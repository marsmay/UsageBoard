#!/usr/bin/env python3
# UsageBoardPlugin:
# {
#   "name": "Claude",
#   "name@zh-Hans": "Claude",
#   "name@en": "Claude",
#   "icon": "icons/light/claude-color.png",
#   "description": "查询 Claude 订阅用量和统计",
#   "description@zh-Hans": "查询 Claude 订阅用量和统计",
#   "description@en": "Query Claude subscription usage and stats",
#   "parameters": [
#     {
#       "name": "PLAN",
#       "label": "Subscription Plan",
#       "label@zh-Hans": "订阅计划",
#       "label@en": "Subscription Plan",
#       "type": "choice",
#       "required": false,
#       "defaultValue": "pro",
#       "options": [
#         {"label": "None",    "label@zh-Hans": "无",      "label@en": "None",    "value": "none"},
#         {"label": "Pro",     "label@zh-Hans": "Pro",     "label@en": "Pro",     "value": "pro"},
#         {"label": "Max 5X",  "label@zh-Hans": "Max 5X",  "label@en": "Max 5X",  "value": "max5"},
#         {"label": "Max 20X", "label@zh-Hans": "Max 20X", "label@en": "Max 20X", "value": "max20"}
#       ]
#     },
#     {
#       "name": "DATA_DIR",
#       "label": "Data Directory",
#       "label@zh-Hans": "数据目录",
#       "label@en": "Data Directory",
#       "type": "directory",
#       "required": false,
#       "defaultValue": "~/.claude",
#       "placeholder": "~/.claude"
#     },
#     {
#       "name": "STAT_PERIOD",
#       "label": "Stats Period",
#       "label@zh-Hans": "统计周期",
#       "label@en": "Stats Period",
#       "type": "choice",
#       "required": false,
#       "defaultValue": "7d",
#       "options": [
#         {"label": "None",    "label@zh-Hans": "无",      "label@en": "None",     "value": "none"},
#         {"label": "7 days",  "label@zh-Hans": "7 天",  "label@en": "7 days",  "value": "7d"},
#         {"label": "15 days", "label@zh-Hans": "15 天", "label@en": "15 days", "value": "15d"},
#         {"label": "30 days", "label@zh-Hans": "30 天", "label@en": "30 days", "value": "30d"}
#       ]
#     },
#     {
#       "name": "CLAUDE_ONLY",
#       "label": "Claude Models Only",
#       "label@zh-Hans": "仅 Claude 模型",
#       "label@en": "Claude Models Only",
#       "type": "boolean",
#       "required": false,
#       "defaultValue": "false"
#     }
#   ]
# }
# /UsageBoardPlugin

import json
import os
import sys
import glob
import math
import subprocess
import urllib.error
from datetime import datetime, timezone, timedelta
from urllib import request as urllib_request

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from _common import (  # noqa: E402
    load_json_cache,
    save_json_cache,
    app_language as _app_language,
    color_for_pct,
    status_for_pct,
    failure,
    filter_by_mtime,
    make_translator,
    normalize_model_name,
    parse_usageboard_params,
    success,
)

# ─── Constants ────────────────────────────────────────────────────────────────

CACHE_VERSION = 8  # 重建会话工作目录索引，用于发现 classifier 决策日志。
CACHE_FILENAME = ".usageboard-chart-cache.json"
CLASSIFIER_LOG_FILENAME = ".automode_decisions.jsonl"
PARSE_ERROR = "parse_error"
REQUEST_TIMEOUT = "request_timeout"
NETWORK_ERROR = "network_error"

def utc_now():
    return datetime.now(timezone.utc)

def local_today():
    return datetime.now().strftime("%Y-%m-%d")

def is_claude_model(model_name):
    return model_name.startswith("claude-")

def compute_tokens(breakdown):
    i  = breakdown.get("input", 0)
    o  = breakdown.get("output", 0)
    cc = breakdown.get("cache_creation", 0)
    cr = breakdown.get("cache_read", 0)
    return i + o + cc + cr


def _token_number(value):
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value
    return 0


def _cache_creation_tokens(usage):
    cache_creation = usage.get("cache_creation")
    if isinstance(cache_creation, dict):
        return (
            _token_number(cache_creation.get("ephemeral_5m_input_tokens"))
            + _token_number(cache_creation.get("ephemeral_1h_input_tokens"))
        )
    return _token_number(usage.get("cache_creation_input_tokens"))


def _translate(lang):
    return make_translator({
        "five_hour":     {"en": "5-hour usage",                                             "zh-Hans": "5 小时用量"},
        "weekly":        {"en": "Weekly usage",                                              "zh-Hans": "周用量"},
        "no_data_dir":   {"en": "~/.claude not found. Install Claude Code CLI first.",       "zh-Hans": "~/.claude 目录不存在，请先安装 Claude Code CLI"},
        "login_hint":    {"en": "Not signed in. Run claude to sign in.",                     "zh-Hans": "未找到登录凭证，请运行 claude 登录"},
        "api_error":     {"en": "API request failed (HTTP {code})",                   "zh-Hans": "API 请求失败 (HTTP {code})"},
        "api_401":       {"en": "Credentials expired. Sign in again. (HTTP {code})",   "zh-Hans": "登录凭证已失效，请重新登录 (HTTP {code})"},
        "api_5xx":       {"en": "Service unavailable (HTTP {code})",                        "zh-Hans": "服务暂时不可用 (HTTP {code})"},
        "no_stats_data": {"en": "No stats data available",                                   "zh-Hans": "暂无可用统计数据"},
    })

# ─── OAuth ────────────────────────────────────────────────────────────────────

def load_oauth_token():
    try:
        cmd = ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            data = json.loads(result.stdout.strip())
            token = data.get("claudeAiOauth", {}).get("accessToken")
            if token:
                return token
    except Exception:
        pass
    cred_path = os.path.expanduser("~/.claude/.credentials.json")
    if os.path.isfile(cred_path):
        try:
            with open(cred_path) as f:
                data = json.load(f)
            return data.get("claudeAiOauth", {}).get("accessToken")
        except Exception:
            pass
    return None

def fetch_oauth_usage(token):
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "anthropic-beta": "oauth-2025-04-20",
    }
    req = urllib_request.Request(
        "https://api.anthropic.com/api/oauth/usage", headers=headers
    )
    try:
        with urllib_request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read()), None
    except urllib_request.HTTPError as e:
        return None, e.code
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None, PARSE_ERROR
    except TimeoutError:
        return None, REQUEST_TIMEOUT
    except urllib.error.URLError as e:
        if isinstance(e.reason, TimeoutError):
            return None, REQUEST_TIMEOUT
        return None, NETWORK_ERROR
    except Exception:
        return None, NETWORK_ERROR

def build_items_from_oauth(data, lang, translate):
    fh = data.get("five_hour", {})
    sd = data.get("seven_day", {})
    fh_pct = float(fh.get("utilization", 0))
    sd_pct = float(sd.get("utilization", 0))
    fh_resets = fh.get("resets_at")
    sd_resets = sd.get("resets_at")

    return [
        {
            "id": "claude-five-hour",
            "name": translate(lang, "five_hour"),
            "displayStyle": "percent",
            "used": round(min(fh_pct, 100), 1),
            "limit": 100,
            "resetAt": fh_resets,
            "color": color_for_pct(fh_pct),
            "status": status_for_pct(fh_pct),
        },
        {
            "id": "claude-seven-day",
            "name": translate(lang, "weekly"),
            "displayStyle": "percent",
            "used": round(min(sd_pct, 100), 1),
            "limit": 100,
            "resetAt": sd_resets,
            "color": color_for_pct(sd_pct),
            "status": status_for_pct(sd_pct),
        },
    ]

# ─── JSONL scanning ───────────────────────────────────────────────────────────

def all_jsonl_files(data_dir):
    expanded = os.path.expanduser(data_dir)
    return glob.glob(os.path.join(expanded, "projects", "**", "*.jsonl"), recursive=True)

def parse_records(files, start_dt, end_dt, project_dirs=None):
    records_by_id = {}
    for filepath in files:
        try:
            with open(filepath, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    if not isinstance(obj, dict):
                        continue
                    cwd = obj.get("cwd")
                    if project_dirs is not None and isinstance(cwd, str) and os.path.isabs(cwd):
                        project_dirs.add(cwd)
                    if obj.get("type") != "assistant":
                        continue
                    msg = obj.get("message", {})
                    msg_id = msg.get("id")
                    if not msg_id:
                        continue
                    usage = msg.get("usage", {})
                    if not isinstance(usage, dict):
                        continue
                    breakdown = {
                        "input":          _token_number(usage.get("input_tokens")),
                        "output":         _token_number(usage.get("output_tokens")),
                        "cache_creation": _cache_creation_tokens(usage),
                        "cache_read":     _token_number(usage.get("cache_read_input_tokens")),
                    }
                    if compute_tokens(breakdown) <= 0:
                        continue
                    raw_ts = obj.get("timestamp", "")
                    if not raw_ts:
                        continue
                    try:
                        ts = datetime.fromisoformat(raw_ts.replace("Z", "+00:00"))
                    except Exception:
                        continue
                    if ts.tzinfo is None:
                        ts = ts.replace(tzinfo=timezone.utc)

                    model = normalize_model_name(msg.get("model")) or "unknown"
                    existing = records_by_id.get(msg_id)
                    if existing is None:
                        records_by_id[msg_id] = [ts, model, breakdown]
                        continue

                    if ts < existing[0]:
                        existing[0] = ts
                        existing[1] = model
                    for key in ("input", "output", "cache_creation", "cache_read"):
                        existing[2][key] = max(existing[2][key], breakdown[key])
        except Exception:
            continue
    return sorted(
        (tuple(record) for record in records_by_id.values() if start_dt <= record[0] <= end_dt),
        key=lambda record: record[0],
    )

def group_by_local_date(records):
    result = {}
    for ts, model, b in records:
        day = ts.astimezone().strftime("%Y-%m-%d")
        bucket = result.setdefault(day, {}).setdefault(model, {
            "input": 0, "output": 0, "cache_creation": 0, "cache_read": 0,
        })
        for k in ("input", "output", "cache_creation", "cache_read"):
            bucket[k] += b.get(k, 0)
    return result


def classifier_records(project_dirs, start_dt, end_dt):
    """Read optional local auto-mode decisions, independent of the session cache."""
    records = []
    seen_files = set()
    # Read only the exact log name in known session working directories.
    for directory in project_dirs:
        if not isinstance(directory, str) or not os.path.isabs(directory):
            continue
        path = os.path.join(directory, CLASSIFIER_LOG_FILENAME)
        try:
            with open(path, "rb") as stream:
                stat = os.fstat(stream.fileno())
                identity = (stat.st_dev, stat.st_ino)
                if identity in seen_files:
                    continue
                seen_files.add(identity)
                for line in stream:
                    # Claude appends asynchronously; defer an incomplete last line.
                    if not line.endswith(b"\n"):
                        continue
                    try:
                        obj = json.loads(line)
                        if not isinstance(obj, dict):
                            continue
                        # Server-side decisions may already be included in main usage.
                        if obj.get("allowlisted") is not False or obj.get("classifierSource") != "local":
                            continue
                        model = obj.get("classifierModel")
                        if not isinstance(model, str) or not model.strip():
                            continue
                        model = normalize_model_name(model)
                        if not model:
                            continue
                        timestamp = obj.get("ts")
                        if isinstance(timestamp, bool) or not isinstance(timestamp, (int, float)):
                            continue
                        ts = datetime.fromtimestamp(timestamp / 1000, timezone.utc)
                        if not start_dt <= ts <= end_dt:
                            continue
                        breakdown = {}
                        for key, field in (
                            ("input", "inputTokens"), ("output", "outputTokens"),
                            ("cache_creation", "cacheCreationInputTokens"),
                            ("cache_read", "cacheReadInputTokens"),
                        ):
                            value = obj.get(field, 0)
                            if (isinstance(value, bool) or not isinstance(value, (int, float))
                                    or not math.isfinite(value) or value < 0 or value != int(value)):
                                raise ValueError("invalid token count")
                            breakdown[key] = int(value)
                        if compute_tokens(breakdown) > 0:
                            records.append((ts, model, breakdown))
                    except (ValueError, TypeError, OverflowError, OSError):
                        continue
        except (OSError, ValueError):
            continue
    return records


def add_classifier_stats(daily, project_dirs):
    now = utc_now()
    # Include the earliest local date even in UTC+14; build_chart selects its days.
    start = datetime.combine(_parse_date(local_today()) - timedelta(days=29),
                             datetime.min.time(), tzinfo=timezone.utc) - timedelta(hours=14)
    extra = group_by_local_date(classifier_records(project_dirs, start, now))
    merged = {day: {model: dict(tokens) for model, tokens in models.items()}
              for day, models in daily.items()}
    for day, models in extra.items():
        for model, tokens in models.items():
            target = merged.setdefault(day, {}).setdefault(model, {})
            for key, value in tokens.items():
                target[key] = target.get(key, 0) + value
    return merged

# ─── Stats cache ──────────────────────────────────────────────────────────────

def _cache_path(data_dir):
    return os.path.join(os.path.expanduser(data_dir), CACHE_FILENAME)

def load_stats_cache(data_dir):
    return load_json_cache(_cache_path(data_dir), CACHE_VERSION)


def save_stats_cache(data_dir, cache_data):
    save_json_cache(_cache_path(data_dir), cache_data)


def _parse_date(s):
    return datetime.strptime(s, "%Y-%m-%d").date()

def _format_date(d):
    return d.strftime("%Y-%m-%d")

def maintain_cache(data_dir):
    """Cache session usage and cwd discovery; merge live classifier totals on return."""
    today = _parse_date(local_today())
    cutoff = today - timedelta(days=29)

    cache = load_stats_cache(data_dir)
    now = utc_now()

    def full_scan_and_save():
        scan_start_utc = datetime(cutoff.year, cutoff.month, cutoff.day, tzinfo=timezone.utc) - timedelta(hours=14)
        # 全量重建以记录时间为准，导入的日志可能保留与内容不一致的旧 mtime。
        project_dirs = set()
        records = parse_records(all_jsonl_files(data_dir), scan_start_utc, now, project_dirs)
        by_day = group_by_local_date(records)
        days = {d: by_day.get(d, {}) for d in
                (_format_date(cutoff + timedelta(days=i)) for i in range(30))
                if _parse_date(d) <= today}
        save_stats_cache(data_dir, {
            "version": CACHE_VERSION,
            "last_date": _format_date(today),
            "days": days,
            "classifier_dirs": sorted(project_dirs),
        })
        return add_classifier_stats(days, project_dirs)

    if cache is None or not isinstance(cache.get("classifier_dirs", []), list):
        return full_scan_and_save()

    try:
        last_date = _parse_date(cache.get("last_date", "2000-01-01"))
    except (TypeError, ValueError):
        return full_scan_and_save()
    gap_days = (today - last_date).days

    if gap_days < 0 or gap_days > 30:
        return full_scan_and_save()

    # The last cached day is dirty until the next run has crossed midnight.
    scan_start = max(cutoff, last_date)
    scan_start_utc = datetime(scan_start.year, scan_start.month, scan_start.day, tzinfo=timezone.utc) - timedelta(hours=14)
    cutoff_ts = scan_start_utc.timestamp()
    # 会话文件可能在 glob 与 stat 之间被 Claude Code 轮转删除，stat 失败跳过该文件。
    recent_files = filter_by_mtime(all_jsonl_files(data_dir), cutoff_ts)
    project_dirs = {path for path in cache.get("classifier_dirs", [])
                    if isinstance(path, str) and os.path.isabs(path)}
    records = parse_records(recent_files, scan_start_utc, now, project_dirs)
    new_days = group_by_local_date(records)

    merged = {}
    for d, v in cache.get("days", {}).items():
        try:
            parsed = _parse_date(d)
        except (TypeError, ValueError):
            continue
        if cutoff <= parsed < scan_start and isinstance(v, dict):
            merged[d] = v

    day_count = (today - scan_start).days + 1
    for i in range(day_count):
        date_str = _format_date(scan_start + timedelta(days=i))
        merged[date_str] = new_days.get(date_str, {})

    save_stats_cache(data_dir, {
        "version": CACHE_VERSION,
        "last_date": _format_date(today),
        "days": merged,
        "classifier_dirs": sorted(project_dirs),
    })
    return add_classifier_stats(merged, project_dirs)

# ─── Chart ────────────────────────────────────────────────────────────────────

def build_chart(params, daily, lang, translate):
    stat_period = params.get("STAT_PERIOD", "7d")
    claude_only = params.get("CLAUDE_ONLY", "false").lower() == "true"
    stat_days = {"7d": 7, "15d": 15, "30d": 30}.get(stat_period, 7)

    date_list = [
        (datetime.now() - timedelta(days=i)).strftime("%Y-%m-%d")
        for i in range(stat_days - 1, -1, -1)
    ]

    buckets = []
    for date in date_list:
        day_data = daily.get(date, {})
        segments = []
        for model, breakdown in sorted(day_data.items()):
            if claude_only and not is_claude_model(model):
                continue
            tokens = compute_tokens(breakdown)
            if tokens > 0:
                segments.append({"model": model, "tokens": tokens})
        buckets.append({"id": date, "label": date[5:], "segments": segments})

    message = None
    if not any(b["segments"] for b in buckets):
        message = translate(lang, "no_stats_data")

    return {"kind": "line", "period": stat_period, "bucketUnit": "day", "buckets": buckets, "message": message}

# ─── Entry point ──────────────────────────────────────────────────────────────

def main():
    params = parse_usageboard_params(sys.argv[1:])
    lang = _app_language(params)
    translate = _translate(lang)
    # 空 DATA_DIR 不得退化为进程 CWD：显式空串与缺省一样回退 ~/.claude。
    data_dir = os.path.realpath(os.path.expanduser((params.get("DATA_DIR") or "").strip() or "~/.claude"))
    plan = params.get("PLAN", "pro").lower()
    stat_period = params.get("STAT_PERIOD", "7d").lower()
    stats_enabled = stat_period != "none"

    chart = None
    if stats_enabled:
        if not os.path.isdir(os.path.expanduser(data_dir)):
            failure(translate(lang, "no_data_dir"))
            return
        daily = maintain_cache(data_dir)
        chart = build_chart(params, daily, lang, translate)

    if plan == "none":
        success([], chart=chart)
        return

    token = load_oauth_token()
    if not token:
        failure(translate(lang, "login_hint"))
        return

    oauth_data, http_code = fetch_oauth_usage(token)
    if not oauth_data:
        if http_code == 401:
            failure(translate(lang, "api_401", code=http_code))
        elif http_code == PARSE_ERROR:
            failure(translate(lang, "usage_parse_failed"))
        elif http_code == REQUEST_TIMEOUT:
            failure(translate(lang, "request_timeout"))
        elif http_code == NETWORK_ERROR:
            failure(translate(lang, "network_error"))
        elif isinstance(http_code, int) and http_code >= 500:
            failure(translate(lang, "api_5xx", code=http_code))
        else:
            failure(translate(lang, "api_error", code=http_code))
        return

    try:
        items = build_items_from_oauth(oauth_data, lang, translate)
        plan_type = oauth_data.get("plan_type")
        if not isinstance(plan_type, str) or not plan_type.strip():
            # Missing/null/empty server plan falls back to the configured PLAN,
            # then to the default plan.
            plan_type = (params.get("PLAN") or "").strip() or "pro"
        badge = plan_type.strip().capitalize()
    except Exception:
        failure(translate(lang, "usage_parse_failed"))
        return

    success(items, chart=chart, badge=badge)

if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)
