#!/usr/bin/env python3
# UsageBoardPlugin:
# {
#   "schemaVersion": 1,
#   "name": "Codex",
#   "name@zh-Hans": "Codex",
#   "name@en": "Codex",
#   "icon": "https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/light/codex-color.png",
#   "description": "查询 OpenAI Codex CLI 用量和统计",
#   "description@zh-Hans": "查询 OpenAI Codex CLI 用量和统计",
#   "description@en": "Query OpenAI Codex CLI usage and stats",
#   "parameters": [
#     {
#       "name": "AUTH_FILE",
#       "label": "认证文件",
#       "label@zh-Hans": "认证文件",
#       "label@en": "Auth File",
#       "type": "file",
#       "required": false,
#       "defaultValue": "~/.codex/auth.json",
#       "placeholder": "~/.codex/auth.json"
#     },
#     {
#       "name": "DATA_DIR",
#       "label": "数据目录",
#       "label@zh-Hans": "数据目录",
#       "label@en": "Data Directory",
#       "type": "directory",
#       "required": false,
#       "defaultValue": "~/.codex",
#       "placeholder": "~/.codex"
#     },
#     {
#       "name": "ENABLE_STATS",
#       "label": "统计",
#       "label@zh-Hans": "统计",
#       "label@en": "Statistics",
#       "type": "boolean",
#       "required": false,
#       "defaultValue": "true"
#     },
#     {
#       "name": "STAT_PERIOD",
#       "label": "统计周期",
#       "label@zh-Hans": "统计周期",
#       "label@en": "Stats Period",
#       "type": "choice",
#       "required": false,
#       "defaultValue": "7d",
#       "options": [
#         {"label": "7 天",  "label@zh-Hans": "7 天",  "label@en": "7 days",  "value": "7d"},
#         {"label": "15 天", "label@zh-Hans": "15 天", "label@en": "15 days", "value": "15d"},
#         {"label": "30 天", "label@zh-Hans": "30 天", "label@en": "30 days", "value": "30d"}
#       ]
#     }
#   ]
# }
# /UsageBoardPlugin
"""UsageBoard plugin for OpenAI Codex CLI quota usage."""

from __future__ import annotations

import glob
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, time, timedelta, timezone
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from _common import (  # noqa: E402
    app_language,
    color_for_pct,
    failure,
    handle_http_error,
    handle_url_error,
    make_translator,
    parse_usageboard_params,
    success,
    utc_now_iso,
)


ENDPOINT = "https://chatgpt.com/backend-api/wham/usage"
CACHE_VERSION = 1
CACHE_FILENAME = ".usageboard-chart-cache.json"

TRANSLATIONS = {
    "no_stats_data":        {"zh-Hans": "暂无可用统计数据",                              "en": "No stats data available"},
    "five_hour_usage":      {"zh-Hans": "5 小时用量",                                   "en": "5-hour usage"},
    "weekly_usage":         {"zh-Hans": "周用量",                                       "en": "Weekly usage"},
    "auth_file_not_found":  {"zh-Hans": "未找到认证文件，请先登录 Codex（{path}）",      "en": "Auth file not found. Sign in to Codex first. ({path})"},
    "auth_token_missing":   {"zh-Hans": "认证信息不完整，请重新登录 Codex",               "en": "Incomplete auth. Sign in to Codex again."},
    "token_expired":        {"zh-Hans": "登录已过期，请重新运行 codex auth",              "en": "Session expired. Run codex auth again."},
    "unauthorized":         {"zh-Hans": "账号无权限访问",                                "en": "Access denied. Check your plan."},
    "usage_parse_failed":   {"zh-Hans": "用量数据解析失败",                               "en": "Failed to parse usage data"},
    "stats_parse_failed":   {"zh-Hans": "统计数据解析失败",                               "en": "Failed to parse stats data"},
    "no_quota_data":        {"zh-Hans": "未获取到配额数据，账号可能不支持此 API",          "en": "No quota data. Account may not support this API."},
}
translate = make_translator(TRANSLATIONS)


def load_auth(auth_path: str) -> dict[str, Any] | None:
    expanded = os.path.expanduser(auth_path)
    if not os.path.isfile(expanded):
        return None
    try:
        with open(expanded, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return None


def extract_auth_credentials(auth: dict[str, Any]) -> tuple[str | None, str | None]:
    tokens = auth.get("tokens") if isinstance(auth.get("tokens"), dict) else {}
    access_token = tokens.get("access_token") or auth.get("access_token")
    account_id = tokens.get("account_id") or auth.get("account_id")

    if not isinstance(access_token, str) or not access_token.strip():
        access_token = None
    if not isinstance(account_id, str) or not account_id.strip():
        account_id = None

    return access_token, account_id


def fetch_usage(access_token: str, account_id: str) -> dict[str, Any]:
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/json",
        "ChatGPT-Account-Id": account_id,
        "Origin": "https://chatgpt.com",
        "Referer": "https://chatgpt.com/",
        "User-Agent": "Mozilla/5.0",
    }
    request = urllib.request.Request(ENDPOINT, headers=headers)
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read().decode("utf-8"))


def epoch_ms_to_iso(value: Any) -> str | None:
    if value is None:
        return None
    try:
        raw = int(value)
    except (TypeError, ValueError):
        return None
    timestamp = raw / 1000 if raw > 10**11 else raw
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def get_percent_left(window: dict[str, Any]) -> float | None:
    for key in ("percent_left", "remaining_percent"):
        value = window.get(key)
        if value is not None:
            try:
                return float(value)
            except (TypeError, ValueError):
                pass
    used = window.get("used_percent")
    if used is not None:
        try:
            return max(0, 100 - float(used))
        except (TypeError, ValueError):
            pass
    return None


def get_reset_at(window: dict[str, Any]) -> str | None:
    for key in ("reset_time_ms", "reset_at"):
        value = window.get(key)
        if value is not None:
            return epoch_ms_to_iso(value)
    nested = window.get("primary_window")
    if isinstance(nested, dict):
        return get_reset_at(nested)
    return None


def stat_range(period: str) -> tuple[datetime, datetime, list[datetime], str]:
    now = datetime.now().astimezone()
    day_count = {"7d": 7, "15d": 15, "30d": 30}.get(period, 7)
    today = now.date()
    start_date = today - timedelta(days=day_count - 1)
    start = datetime.combine(start_date, time.min, tzinfo=now.tzinfo)
    end = datetime.combine(today, time.max, tzinfo=now.tzinfo).replace(microsecond=0)
    buckets = [start + timedelta(days=i) for i in range(day_count)]
    return start, end, buckets, "day"


def bucket_id(dt: datetime, unit: str) -> str:
    return dt.strftime("%Y-%m-%d")


def bucket_label(dt: datetime, unit: str) -> str:
    return dt.strftime("%m-%d")


def chart_message(msg: str, period: str, buckets: list[datetime], unit: str) -> dict[str, Any]:
    return {
        "kind": "line",
        "period": period,
        "bucketUnit": unit,
        "buckets": [
            {"id": bucket_id(b, unit), "label": bucket_label(b, unit), "segments": []}
            for b in buckets
        ],
        "message": msg,
    }


def _cache_path(data_dir: str) -> str:
    return os.path.join(os.path.expanduser(data_dir), CACHE_FILENAME)


def _parse_date(s: str) -> ...:
    return datetime.strptime(s, "%Y-%m-%d").date()


def _format_date(d) -> str:
    return d.strftime("%Y-%m-%d")


def load_chart_cache(data_dir: str) -> dict[str, Any] | None:
    path = _cache_path(data_dir)
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if data.get("version") != CACHE_VERSION:
            return None
        return data
    except (OSError, json.JSONDecodeError):
        return None


def save_chart_cache(data_dir: str, cache_data: dict[str, Any]) -> None:
    path = _cache_path(data_dir)
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(cache_data, f)
    except OSError:
        pass


def maintain_chart_cache(data_dir: str, language: str) -> dict[str, dict[str, float]]:
    """Build and maintain a 30-day chart cache. Returns {date: {model: tokens}}."""
    today = datetime.now().date()
    cutoff = today - timedelta(days=29)

    cache = load_chart_cache(data_dir)

    def full_scan_and_save():
        buckets = [cutoff + timedelta(days=i) for i in range(30) if cutoff + timedelta(days=i) <= today]
        files = collect_session_files(data_dir, cutoff, today)
        result = parse_sessions_for_chart(files, buckets, "day", "30d", language)
        days = {}
        for b in result["buckets"]:
            if b["segments"]:
                days[b["id"]] = {s["model"]: s["tokens"] for s in b["segments"]}
        save_chart_cache(data_dir, {
            "version": CACHE_VERSION,
            "last_date": _format_date(today),
            "days": days,
        })
        return days

    if cache is None:
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
    day_count = (today - scan_start).days + 1
    scan_dates = [scan_start + timedelta(days=i) for i in range(day_count)]
    files = collect_session_files(data_dir, scan_start, today)
    result = parse_sessions_for_chart(files, scan_dates, "day", "30d", language)
    new_days = {}
    for b in result["buckets"]:
        if b["segments"]:
            new_days[b["id"]] = {s["model"]: s["tokens"] for s in b["segments"]}

    merged = {}
    for d, v in cache.get("days", {}).items():
        try:
            parsed = _parse_date(d)
        except (TypeError, ValueError):
            continue
        if cutoff <= parsed < scan_start and isinstance(v, dict):
            merged[d] = v

    for i in range(day_count):
        date_str = _format_date(scan_start + timedelta(days=i))
        merged[date_str] = new_days.get(date_str, {})

    save_chart_cache(data_dir, {
        "version": CACHE_VERSION,
        "last_date": _format_date(today),
        "days": merged,
    })
    return merged


def build_chart_from_cache(daily: dict[str, dict[str, float]], period: str, language: str) -> dict[str, Any]:
    """Build chart output from cached daily data for the requested period."""
    day_count = {"7d": 7, "15d": 15, "30d": 30}.get(period, 7)
    today = datetime.now().date()
    date_list = [_format_date(today - timedelta(days=i)) for i in range(day_count - 1, -1, -1)]

    model_totals: dict[str, float] = {}
    for date in date_list:
        for model, tokens in daily.get(date, {}).items():
            model_totals[model] = model_totals.get(model, 0) + tokens
    sorted_models = [m for m, _ in sorted(model_totals.items(), key=lambda x: -x[1])]

    buckets: list[dict[str, Any]] = []
    for date in date_list:
        day_data = daily.get(date, {})
        segments = [
            {"model": m, "tokens": int(day_data.get(m, 0))}
            for m in sorted_models
            if day_data.get(m, 0) > 0
        ]
        buckets.append({"id": date, "label": date[5:], "segments": segments})

    message = None
    if not any(b["segments"] for b in buckets):
        message = translate(language, "no_stats_data")

    return {"kind": "line", "period": period, "bucketUnit": "day", "buckets": buckets, "message": message}


_FILENAME_DATE = re.compile(r"rollout-(\d{4}-\d{2}-\d{2})T")


def parse_date_from_filename(filename: str) -> str | None:
    m = _FILENAME_DATE.search(os.path.basename(filename))
    return m.group(1) if m else None


def collect_session_files(data_dir: str, start_date, end_date) -> list[str]:
    expanded = os.path.expanduser(data_dir)
    files: list[str] = []
    for pattern in (
        os.path.join(expanded, "sessions", "**", "*.jsonl"),
        os.path.join(expanded, "archived_sessions", "*.jsonl"),
    ):
        files.extend(glob.glob(pattern, recursive=True))
    start_str = start_date.strftime("%Y-%m-%d") if isinstance(start_date, datetime) else str(start_date)
    end_str = end_date.strftime("%Y-%m-%d") if isinstance(end_date, datetime) else str(end_date)
    # A session file is named after its start date, but entries written after
    # local midnight carry the next day's timestamp. Include any file modified on
    # or after start_date (by mtime) so a session that spans midnight is not
    # dropped when its filename date falls before the incremental scan range.
    # Bucketing in parse_sessions_for_chart is authoritative, so extra files
    # never cause double counting.
    try:
        start_mtime: float | None = datetime.combine(_parse_date(start_str), time.min).timestamp()
    except (TypeError, ValueError):
        start_mtime = None
    result: list[str] = []
    for f in files:
        file_date = parse_date_from_filename(f)
        if file_date and start_str <= file_date <= end_str:
            result.append(f)
            continue
        if start_mtime is not None:
            try:
                if os.path.getmtime(f) >= start_mtime:
                    result.append(f)
            except OSError:
                pass
    return result


def parse_sessions_for_chart(
    files: list[str],
    buckets: list[datetime],
    bucket_unit: str,
    period: str,
    language: str,
) -> dict[str, Any]:
    bucket_keys = {bucket_id(b, bucket_unit): {} for b in buckets}
    model_totals: dict[str, float] = {}

    for filepath in files:
        current_model: str | None = None
        prev_usage: dict[str, float] = {}
        try:
            with open(filepath, encoding="utf-8") as fh:
                for line in fh:
                    if '"turn_context"' not in line and '"token_count"' not in line:
                        continue
                    try:
                        event = json.loads(line)
                    except (json.JSONDecodeError, ValueError):
                        continue

                    kind = event.get("type")
                    payload = event.get("payload")
                    if not isinstance(payload, dict):
                        continue

                    if kind == "turn_context":
                        model = payload.get("model")
                        if isinstance(model, str) and model.strip():
                            current_model = model.strip()

                    if payload.get("type") == "token_count":
                        info = payload.get("info")
                        if not isinstance(info, dict):
                            continue
                        total_usage = info.get("total_token_usage")
                        if not isinstance(total_usage, dict):
                            continue
                        total_tokens = total_usage.get("total_tokens")
                        if not isinstance(total_tokens, (int, float)):
                            continue
                        total_tokens = float(total_tokens)

                        delta = max(total_tokens - prev_usage.get("total_tokens", 0), 0)
                        if not prev_usage:
                            delta = total_tokens
                        prev_usage["total_tokens"] = total_tokens

                        model = current_model or "unknown"
                        ts = payload.get("timestamp") or event.get("timestamp")
                        if ts and delta > 0:
                            try:
                                dt = datetime.fromisoformat(str(ts).replace("Z", "+00:00")).astimezone()
                            except (ValueError, TypeError):
                                continue
                            key = bucket_id(dt, bucket_unit)
                            if key in bucket_keys:
                                bucket_keys[key][model] = bucket_keys[key].get(model, 0) + delta
                                model_totals[model] = model_totals.get(model, 0) + delta
        except (OSError, UnicodeDecodeError):
            continue

    sorted_models = [m for m, _ in sorted(model_totals.items(), key=lambda x: -x[1])]

    chart_buckets: list[dict[str, Any]] = []
    for b in buckets:
        key = bucket_id(b, bucket_unit)
        segments = [
            {"model": m, "tokens": int(bucket_keys[key].get(m, 0))}
            for m in sorted_models
            if bucket_keys[key].get(m, 0) > 0
        ]
        chart_buckets.append({"id": key, "label": bucket_label(b, bucket_unit), "segments": segments})

    message = None
    if not any(b["segments"] for b in chart_buckets):
        message = translate(language, "no_stats_data")

    return {"kind": "line", "period": period, "bucketUnit": bucket_unit, "buckets": chart_buckets, "message": message}


def parse_window(data: dict[str, Any], *keys: str) -> dict[str, Any] | None:
    for key in keys:
        value = data.get(key)
        if isinstance(value, dict):
            return value
    return None


def get_window_duration_seconds(window: dict[str, Any]) -> int | None:
    value = window.get("limit_window_seconds")
    try:
        return int(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def build_items(payload: dict[str, Any], language: str) -> tuple[list[dict[str, Any]], str | None]:
    rate_limits = parse_window(payload, "rate_limit", "rate_limits")
    if not rate_limits:
        return [], None

    badge = payload.get("plan_type")
    if not isinstance(badge, str):
        badge = None

    items: list[dict[str, Any]] = []

    five_hour = parse_window(rate_limits, "five_hour", "five_hour_limit", "five_hour_rate_limit", "primary")
    weekly = parse_window(rate_limits, "weekly", "weekly_limit", "weekly_rate_limit", "secondary")

    primary_window = parse_window(rate_limits, "primary_window")
    secondary_window = parse_window(rate_limits, "secondary_window")
    for window in (primary_window, secondary_window):
        if not window:
            continue
        duration = get_window_duration_seconds(window)
        if duration == 5 * 60 * 60 and not five_hour:
            five_hour = window
        elif duration == 7 * 24 * 60 * 60 and not weekly:
            weekly = window

    if not five_hour and primary_window is not weekly:
        five_hour = primary_window
    if not weekly and secondary_window is not five_hour:
        weekly = secondary_window

    if five_hour:
        pct = get_percent_left(five_hour)
        if pct is not None:
            used = 100 - pct
            items.append({
                "id": "codex-five-hour",
                "name": translate(language, "five_hour_usage"),
                "used": round(used, 1),
                "limit": 100,
                "displayStyle": "percent",
                "resetAt": get_reset_at(five_hour),
                "status": "critical" if used >= 90 else "warning" if used >= 75 else "normal",
                "color": color_for_pct(used),
            })

    if weekly:
        pct = get_percent_left(weekly)
        if pct is not None:
            used = 100 - pct
            items.append({
                "id": "codex-weekly",
                "name": translate(language, "weekly_usage"),
                "used": round(used, 1),
                "limit": 100,
                "displayStyle": "percent",
                "resetAt": get_reset_at(weekly),
                "status": "critical" if used >= 90 else "warning" if used >= 75 else "normal",
                "color": color_for_pct(used),
            })

    return items, badge


def main() -> int:
    params = parse_usageboard_params(sys.argv[1:])
    language = app_language(params)
    auth_file = params.get("AUTH_FILE", "") or "~/.codex/auth.json"
    data_dir = os.path.realpath(os.path.expanduser(params.get("DATA_DIR", "") or "~/.codex"))
    enable_stats = params.get("ENABLE_STATS", "true").lower() != "false"
    period = params.get("STAT_PERIOD", "7d").lower()
    if period not in ("7d", "15d", "30d"):
        period = "7d"

    auth = load_auth(auth_file)
    if not auth:
        return failure(translate(language, "auth_file_not_found", path=os.path.expanduser(auth_file)))

    access_token, account_id = extract_auth_credentials(auth)
    if not access_token or not account_id:
        return failure(translate(language, "auth_token_missing"))

    items: list[dict[str, Any]] = []
    badge: str | None = None
    try:
        payload = fetch_usage(access_token, account_id)
    except urllib.error.HTTPError as error:
        if error.code == 401:
            return failure(translate(language, "token_expired"))
        if error.code == 403:
            return failure(translate(language, "unauthorized"))
        return handle_http_error(error, translate, language)
    except urllib.error.URLError as error:
        return handle_url_error(error, translate, language)
    except TimeoutError:
        return failure(translate(language, "request_timeout"))
    except json.JSONDecodeError:
        return failure(translate(language, "usage_parse_failed"))
    except Exception:
        return failure(translate(language, "network_error"))

    try:
        items, badge = build_items(payload, language)
    except Exception:
        return failure(translate(language, "usage_parse_failed"))

    chart = None
    if enable_stats:
        try:
            daily = maintain_chart_cache(data_dir, language)
            chart = build_chart_from_cache(daily, period, language)
        except Exception:
            _, _, buckets, bucket_unit = stat_range(period)
            chart = chart_message(translate(language, "stats_parse_failed"), period, buckets, bucket_unit)

    if not items:
        return failure(translate(language, "no_quota_data"))
    return success(items, badge=badge, chart=chart)


if __name__ == "__main__":
    sys.exit(main())
