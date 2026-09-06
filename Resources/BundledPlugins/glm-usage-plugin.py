#!/usr/bin/env python3
# UsageBoardPlugin:
# {
#   "schemaVersion": 1,
#   "name": "智谱",
#   "name@zh-Hans": "智谱",
#   "name@en": "Zhipu",
#   "icon": "https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/light/zhipu-color.png",
#   "description": "查询智谱 / ZAI Coding Plan 用量和 token 统计",
#   "description@zh-Hans": "查询智谱 / ZAI Coding Plan 用量和 token 统计",
#   "description@en": "Query Zhipu / ZAI Coding Plan usage and token stats",
#   "parameters": [
#     {
#       "name": "API_KEY",
#       "label": "Api Key",
#       "label@zh-Hans": "Api Key",
#       "type": "secret",
#       "required": true,
#       "placeholder": "Coding Plan API Key"
#     },
#     {
#       "name": "STAT_PERIOD",
#       "label": "统计周期",
#       "label@zh-Hans": "统计周期",
#       "label@en": "Stats Period",
#       "type": "choice",
#       "required": true,
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
"""UsageBoard plugin for GLM quota usage."""

from __future__ import annotations

import hashlib
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, time, timedelta, timezone
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from _common import (  # noqa: E402
    load_json_cache,
    save_json_cache,
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


QUOTA_ENDPOINT = "https://open.bigmodel.cn/api/monitor/usage/quota/limit"
MODEL_USAGE_ENDPOINT = "https://bigmodel.cn/api/monitor/usage/model-usage"
CACHE_VERSION = 1
CACHE_FILENAME_PREFIX = "glm-usage-chart-cache"
DEFAULT_CACHE_DIR = "~/Library/Application Support/UsageBoard/plugin-caches"

TRANSLATIONS = {
    "period_5h":       {"zh-Hans": "5小时",     "en": "5 hours"},
    "period_week":     {"zh-Hans": "周",        "en": "week"},
    "period_month":    {"zh-Hans": "月",        "en": "month"},
    "tool_calls":      {"zh-Hans": "工具调用",   "en": "Tool calls"},
    "text_generation": {"zh-Hans": "文本生成",   "en": "Text generation"},
    "five_hour_usage": {"zh-Hans": "5 小时用量", "en": "5-hour usage"},
    "weekly_usage":    {"zh-Hans": "周用量",     "en": "Weekly usage"},
    "mcp_month_usage": {"zh-Hans": "MCP 月用量", "en": "MCP monthly usage"},
    "no_stats_data":   {"zh-Hans": "暂无可用统计数据", "en": "No stats data available"},
    "no_quota_items":  {"zh-Hans": "未获取到配额数据", "en": "No quota data found."},
    "stats_query_failed": {"zh-Hans": "统计数据查询失败", "en": "Failed to query stats data"},
}

translate = make_translator(TRANSLATIONS)

def fetch_limits(api_key: str) -> dict[str, Any]:
    request = urllib.request.Request(
        QUOTA_ENDPOINT,
        headers={
            "Authorization": api_key,
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch_model_usage(api_key: str, start_time: datetime, end_time: datetime) -> dict[str, Any]:
    query = urllib.parse.urlencode(
        {
            "startTime": format_query_time(start_time),
            "endTime": format_query_time(end_time),
        }
    )
    request = urllib.request.Request(
        f"{MODEL_USAGE_ENDPOINT}?{query}",
        headers={
            "Authorization": api_key,
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=8) as response:
        return json.loads(response.read().decode("utf-8"))


def format_query_time(value: datetime) -> str:
    return value.strftime("%Y-%m-%d %H:%M:%S")


def stat_range(period: str) -> tuple[datetime, datetime, list[datetime], str]:
    now = datetime.now().astimezone()
    day_count = {"7d": 7, "15d": 15, "30d": 30}.get(period, 7)
    today = now.date()
    start_date = today - timedelta(days=day_count - 1)
    start, end, buckets = day_window(start_date, today)
    return start, end, buckets, "day"


def day_window(start_date, end_date) -> tuple[datetime, datetime, list[datetime]]:
    now = datetime.now().astimezone()
    start = datetime.combine(start_date, time.min, tzinfo=now.tzinfo)
    end = datetime.combine(end_date, time.max, tzinfo=now.tzinfo).replace(microsecond=0)
    day_count = (end_date - start_date).days + 1
    buckets = [start + timedelta(days=index) for index in range(day_count)]
    return start, end, buckets


def reset_at_iso(limit: dict[str, Any]) -> str | None:
    reset_value = first_present(
        limit,
        (
            "nextResetTime",
            "nextResetTimestamp",
            "resetTime",
            "resetAt",
            "expireTime",
            "expiresAt",
        ),
    )
    timestamp = normalize_timestamp(reset_value)
    if timestamp is None:
        return None
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def first_present(source: dict[str, Any], keys: tuple[str, ...]) -> Any:
    for key in keys:
        value = source.get(key)
        if value not in (None, ""):
            return value
    return None


def normalize_timestamp(value: Any) -> float | None:
    if isinstance(value, str):
        value = value.strip()
        if not value:
            return None
        if value.isdigit():
            value = float(value)
        else:
            try:
                parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
                return parsed.timestamp()
            except ValueError:
                return None

    if not isinstance(value, (int, float)) or value <= 0:
        return None

    # GLM docs describe nextResetTime as milliseconds, but accept seconds too
    # because some quota endpoints return 10-digit Unix timestamps.
    if value > 10_000_000_000:
        return float(value) / 1000
    return float(value)


def usage_from_percentage(limit: dict[str, Any]) -> tuple[float, float]:
    pct = limit.get("percentage", 0)
    if not isinstance(pct, (int, float)):
        pct = 0
    pct = max(0, min(float(pct), 100))
    return pct, 100


def usage_from_current_and_limit(limit: dict[str, Any]) -> tuple[float, float]:
    current = limit.get("currentValue", 0)
    usage_limit = limit.get("usage", 0)
    if not isinstance(current, (int, float)):
        current = 0
    if not isinstance(usage_limit, (int, float)):
        usage_limit = 0
    return max(float(current), 0), max(float(usage_limit), 0)


def period_for(limit: dict[str, Any], language: str) -> tuple[str, str] | None:
    unit = limit.get("unit")
    number = limit.get("number")
    if unit == 3 and number == 5:
        return "5h", translate(language, "period_5h")
    if unit == 6 and number == 1:
        return "week", translate(language, "period_week")
    if unit == 5 and number == 1:
        return "month", translate(language, "period_month")
    return None


def quota_kind(limit: dict[str, Any], language: str) -> tuple[str, str]:
    if "currentValue" in limit or "usage" in limit:
        return "tool", translate(language, "tool_calls")

    text = quota_kind_text(limit)
    tool_markers = ("tool", "工具", "function", "mcp")
    text_markers = ("token", "text", "文本")

    if any(marker in text for marker in tool_markers):
        return "tool", translate(language, "tool_calls")
    if any(marker in text for marker in text_markers):
        return "text", translate(language, "text_generation")
    return "text", translate(language, "text_generation")


def quota_kind_text(limit: dict[str, Any]) -> str:
    keys = (
        "type",
        "kind",
        "category",
        "name",
        "displayName",
        "description",
        "quotaName",
        "quotaType",
        "resource",
        "resourceName",
        "resourceType",
        "service",
        "usageName",
        "usageType",
    )
    values: list[str] = []
    for key in keys:
        value = limit.get(key)
        if isinstance(value, str):
            values.append(value)
    return " ".join(values).lower()


def usage_for(limit: dict[str, Any], kind: str) -> tuple[float, float, str]:
    if kind == "tool" and ("currentValue" in limit or "usage" in limit):
        used, total = usage_from_current_and_limit(limit)
        return used, total, "ratio"
    used, total = usage_from_percentage(limit)
    return used, total, "percent"


def item(
    item_id: str,
    name: str,
    used: float,
    limit: float,
    reset_at: str | None,
    display_style: str = "percent",
) -> dict[str, Any]:
    # status thresholds: 90+ critical, 75+ warning — intentionally stricter than color thresholds
    status = "unknown"
    pct = used / limit * 100 if limit > 0 else 0
    if pct >= 90:
        status = "critical"
    elif pct >= 75:
        status = "warning"
    else:
        status = "normal"

    return {
        "id": item_id,
        "name": name,
        "used": used,
        "limit": limit,
        "displayStyle": display_style,
        "resetAt": reset_at,
        "status": status,
        "color": color_for_pct(pct),
    }


def build_items(payload: dict[str, Any], language: str) -> tuple[list[dict[str, Any]], str | None]:
    data = payload.get("data", {})
    limits = data.get("limits", [])
    if not isinstance(limits, list):
        return [], None

    badge = data.get("level")
    if not isinstance(badge, str):
        badge = None

    output: list[dict[str, Any]] = []

    for limit in limits:
        if not isinstance(limit, dict):
            continue

        period = period_for(limit, language)
        if period is None:
            continue

        period_id, period_label = period
        kind_id, kind_label = quota_kind(limit, language)
        used, total, display_style = usage_for(limit, kind_id)
        if total <= 0:
            continue
        reset_at = reset_at_iso(limit)

        output.append(
            item(
                f"glm-{kind_id}-{period_id}",
                f"{kind_label} ({period_label})",
                used,
                total,
                reset_at,
                display_style=display_style,
            )
        )

    display_names = {
        "glm-text-5h": translate(language, "five_hour_usage"),
        "glm-text-week": translate(language, "weekly_usage"),
        "glm-tool-month": translate(language, "mcp_month_usage"),
    }
    order = {
        "glm-text-5h": 0,
        "glm-text-week": 1,
        "glm-tool-month": 2,
    }
    for entry in output:
        if entry["id"] in display_names:
            entry["name"] = display_names[entry["id"]]
    return sorted(output, key=lambda value: order.get(value["id"], 99)), badge


def build_chart(payload: dict[str, Any], period: str, buckets: list[datetime], bucket_unit: str, language: str) -> dict[str, Any]:
    bucket_values: dict[str, dict[str, float]] = {
        bucket_id(bucket, bucket_unit): {} for bucket in buckets
    }

    apply_aligned_model_series(payload, bucket_values, bucket_unit)

    for record, inherited_model in iter_records(payload):
        model = extract_model(record)
        if model is None:
            model = inherited_model
        tokens = extract_tokens(record)
        timestamp = extract_timestamp(record)
        if not model or tokens is None or tokens <= 0 or timestamp is None:
            continue

        key = bucket_id(timestamp.astimezone(), bucket_unit)
        if key not in bucket_values:
            continue
        bucket_values[key][model] = bucket_values[key].get(model, 0) + tokens

    chart_buckets: list[dict[str, Any]] = []
    for bucket in buckets:
        key = bucket_id(bucket, bucket_unit)
        segments = [
            {"model": model, "tokens": tokens}
            for model, tokens in sorted(bucket_values[key].items())
            if tokens > 0
        ]
        chart_buckets.append(
            {
                "id": key,
                "label": bucket_label(bucket, bucket_unit),
                "segments": segments,
            }
        )

    message = None
    if not any(bucket["segments"] for bucket in chart_buckets):
        message = translate(language, "no_stats_data")

    return {
        "kind": "line",
        "period": period,
        "bucketUnit": bucket_unit,
        "buckets": chart_buckets,
        "message": message,
    }


def cache_key(api_key: str) -> str:
    return hashlib.sha256(api_key.encode("utf-8")).hexdigest()[:16]


def cache_path(api_key: str, cache_dir: str | None = None) -> str:
    root = os.path.expanduser(cache_dir or os.environ.get("USAGEBOARD_CACHE_DIR") or DEFAULT_CACHE_DIR)
    return os.path.join(root, f"{CACHE_FILENAME_PREFIX}-{cache_key(api_key)}.json")


def load_chart_cache(api_key: str, cache_dir: str | None = None) -> dict[str, Any] | None:
    return load_json_cache(cache_path(api_key, cache_dir), CACHE_VERSION)


def save_chart_cache(api_key: str, cache_data: dict[str, Any], cache_dir: str | None = None) -> None:
    save_json_cache(cache_path(api_key, cache_dir), cache_data)


def chart_payload_to_daily(
    payload: dict[str, Any],
    start_date,
    end_date,
    language: str,
) -> dict[str, dict[str, float]]:
    _, _, buckets = day_window(start_date, end_date)
    chart = build_chart(payload, "30d", buckets, "day", language)
    daily: dict[str, dict[str, float]] = {}
    for bucket in chart["buckets"]:
        values: dict[str, float] = {}
        for segment in bucket.get("segments", []):
            model = segment.get("model")
            tokens = numeric_value(segment.get("tokens"))
            if isinstance(model, str) and model and tokens is not None and tokens > 0:
                values[model] = values.get(model, 0) + tokens
        daily[bucket["id"]] = values
    return daily


def maintain_chart_cache(
    api_key: str,
    language: str,
    cache_dir: str | None = None,
) -> dict[str, dict[str, float]]:
    """Build and maintain a 30-day API chart cache. Returns {date: {model: tokens}}."""
    today = datetime.now().astimezone().date()
    cutoff = today - timedelta(days=29)

    cache = load_chart_cache(api_key, cache_dir)

    def fetch_range(start_date, end_date) -> dict[str, dict[str, float]]:
        start_time, end_time, _ = day_window(start_date, end_date)
        payload = fetch_model_usage(api_key, start_time, end_time)
        return chart_payload_to_daily(payload, start_date, end_date, language)

    def full_fetch_and_save() -> dict[str, dict[str, float]]:
        days = fetch_range(cutoff, today)
        save_chart_cache(api_key, {
            "version": CACHE_VERSION,
            "last_date": _format_date(today),
            "days": days,
        }, cache_dir)
        return days

    if cache is None:
        return full_fetch_and_save()

    try:
        last_date = _parse_date(cache.get("last_date", "2000-01-01"))
    except (TypeError, ValueError):
        return full_fetch_and_save()
    gap_days = (today - last_date).days

    if gap_days < 0 or gap_days > 30:
        return full_fetch_and_save()

    # Today is always dirty, so refresh it even when the cache is already current.
    scan_start = today if gap_days == 0 else last_date + timedelta(days=1)
    new_days = fetch_range(scan_start, today)

    merged: dict[str, dict[str, float]] = {}
    for date_key, value in cache.get("days", {}).items():
        try:
            parsed = _parse_date(date_key)
        except (TypeError, ValueError):
            continue
        if cutoff <= parsed < scan_start and isinstance(value, dict):
            merged[date_key] = value

    day_count = (today - scan_start).days + 1
    for index in range(day_count):
        date_key = _format_date(scan_start + timedelta(days=index))
        merged[date_key] = new_days.get(date_key, {})

    save_chart_cache(api_key, {
        "version": CACHE_VERSION,
        "last_date": _format_date(today),
        "days": merged,
    }, cache_dir)
    return merged


def _parse_date(value: str):
    return datetime.strptime(value, "%Y-%m-%d").date()


def _format_date(value) -> str:
    return value.strftime("%Y-%m-%d")


def chart_token_value(value: float) -> float | int:
    return int(value) if value == int(value) else value


def build_chart_from_cache(daily: dict[str, dict[str, float]], period: str, language: str) -> dict[str, Any]:
    day_count = {"7d": 7, "15d": 15, "30d": 30}.get(period, 7)
    today = datetime.now().astimezone().date()
    dates = [_format_date(today - timedelta(days=index)) for index in range(day_count - 1, -1, -1)]

    buckets: list[dict[str, Any]] = []
    for date_key in dates:
        segments = []
        for model, raw_tokens in sorted(daily.get(date_key, {}).items()):
            tokens = numeric_value(raw_tokens)
            if isinstance(model, str) and model and tokens is not None and tokens > 0:
                segments.append({"model": model, "tokens": chart_token_value(tokens)})
        buckets.append({"id": date_key, "label": date_key[5:], "segments": segments})

    message = None
    if not any(bucket["segments"] for bucket in buckets):
        message = translate(language, "no_stats_data")

    return {"kind": "line", "period": period, "bucketUnit": "day", "buckets": buckets, "message": message}


def apply_aligned_model_series(
    payload: dict[str, Any],
    bucket_values: dict[str, dict[str, float]],
    bucket_unit: str,
) -> None:
    data = payload.get("data") if isinstance(payload, dict) else None
    if not isinstance(data, dict):
        return

    times = data.get("x_time")
    if not isinstance(times, list):
        return

    model_entries = data.get("modelDataList")
    if isinstance(model_entries, list):
        for entry in model_entries:
            if not isinstance(entry, dict):
                continue
            model = extract_model(entry)
            values = entry.get("tokensUsage")
            if not model or not isinstance(values, list):
                continue
            apply_aligned_values(times, values, model, bucket_values, bucket_unit)

    total_values = data.get("tokensUsage")
    if isinstance(total_values, list) and not any(bucket_values[key] for key in bucket_values):
        apply_aligned_values(times, total_values, "总计", bucket_values, bucket_unit)


def apply_aligned_values(
    times: list[Any],
    values: list[Any],
    model: str,
    bucket_values: dict[str, dict[str, float]],
    bucket_unit: str,
) -> None:
    for index, time_value in enumerate(times):
        if index >= len(values):
            break
        timestamp = timestamp_from_value(time_value)
        tokens = numeric_value(values[index])
        if timestamp is None or tokens is None or tokens <= 0:
            continue

        key = bucket_id(timestamp.astimezone(), bucket_unit)
        if key not in bucket_values:
            continue
        bucket_values[key][model] = bucket_values[key].get(model, 0) + tokens


def iter_records(value: Any, inherited_model: str | None = None):
    if isinstance(value, dict):
        model = extract_model(value) or inherited_model
        yield value, inherited_model
        for child in value.values():
            yield from iter_records(child, model)
    elif isinstance(value, list):
        if len(value) >= 2 and not isinstance(value[0], (dict, list)) and not isinstance(value[1], (dict, list)):
            yield {"time": value[0], "value": value[1]}, inherited_model
        for child in value:
            yield from iter_records(child, inherited_model)


def extract_model(record: dict[str, Any]) -> str | None:
    value = first_present(
        record,
        (
            "model",
            "modelName",
            "model_name",
            "modelCode",
            "model_code",
            "modelType",
            "model_type",
            "modelId",
            "model_id",
            "modelLabel",
            "model_label",
            "name",
        ),
    )
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def extract_tokens(record: dict[str, Any]) -> float | None:
    token_keys = (
        "tokens",
        "token",
        "totalTokens",
        "total_tokens",
        "totalToken",
        "total_token",
        "totalTokensUsage",
        "total_tokens_usage",
        "totalTokenUsage",
        "total_token_usage",
        "tokensUsage",
        "tokens_usage",
        "tokenCount",
        "token_count",
        "tokensCount",
        "tokens_count",
        "consumeTokens",
        "consume_tokens",
        "consumedTokens",
        "consumed_tokens",
        "usedToken",
        "used_token",
        "tokenUsage",
        "token_usage",
        "usageTokens",
        "usage_tokens",
        "usedTokens",
        "used_tokens",
        "total",
        "value",
    )
    for key in token_keys:
        value = record.get(key)
        number = numeric_value(value)
        if number is not None:
            return number

    usage = record.get("usage")
    if isinstance(usage, dict):
        for key in token_keys:
            number = numeric_value(usage.get(key))
            if number is not None:
                return number
    total_usage = record.get("totalUsage")
    if isinstance(total_usage, dict):
        for key in token_keys:
            number = numeric_value(total_usage.get(key))
            if number is not None:
                return number
    input_tokens = numeric_value(record.get("inputTokens") or record.get("input_tokens"))
    output_tokens = numeric_value(record.get("outputTokens") or record.get("output_tokens"))
    if input_tokens is not None or output_tokens is not None:
        return (input_tokens or 0) + (output_tokens or 0)
    return None


def numeric_value(value: Any) -> float | None:
    if isinstance(value, (int, float)) and value >= 0:
        return float(value)
    if isinstance(value, str):
        normalized = value.strip().replace(",", "")
        if not normalized:
            return None
        try:
            number = float(normalized)
        except ValueError:
            return None
        return number if number >= 0 else None
    return None


def extract_timestamp(record: dict[str, Any]) -> datetime | None:
    value = first_present(
        record,
        (
            "time",
            "date",
            "day",
            "hour",
            "statTime",
            "stat_time",
            "statDate",
            "stat_date",
            "startTime",
            "start_time",
            "timestamp",
            "requestTime",
            "request_time",
            "createdAt",
            "created_at",
            "createTime",
            "create_time",
        ),
    )
    timestamp = normalize_timestamp(value)
    if timestamp is not None:
        return datetime.fromtimestamp(timestamp, tz=timezone.utc)

    if isinstance(value, str):
        return timestamp_from_value(value)
    return None


def timestamp_from_value(value: Any) -> datetime | None:
    timestamp = normalize_timestamp(value)
    if timestamp is not None:
        return datetime.fromtimestamp(timestamp, tz=timezone.utc)

    if isinstance(value, str):
        text = value.strip()
        for pattern in (
            "%Y-%m-%d %H:%M:%S",
            "%Y-%m-%d %H:%M",
            "%Y-%m-%d %H",
            "%Y-%m-%d",
            "%Y/%m/%d %H:%M:%S",
            "%Y/%m/%d %H:%M",
            "%Y/%m/%d",
        ):
            try:
                return datetime.strptime(text, pattern).astimezone()
            except ValueError:
                continue
    return None


def bucket_id(value: datetime, bucket_unit: str) -> str:
    if bucket_unit == "hour":
        return value.strftime("%Y-%m-%dT%H")
    return value.strftime("%Y-%m-%d")


def bucket_label(value: datetime, bucket_unit: str) -> str:
    if bucket_unit == "hour":
        return value.strftime("%H")
    return value.strftime("%m-%d")


def chart_message(message: str, period: str, buckets: list[datetime], bucket_unit: str) -> dict[str, Any]:
    return {
        "kind": "line",
        "period": period,
        "bucketUnit": bucket_unit,
        "buckets": [
            {
                "id": bucket_id(bucket, bucket_unit),
                "label": bucket_label(bucket, bucket_unit),
                "segments": [],
            }
            for bucket in buckets
        ],
        "message": message,
    }


def main() -> int:
    params = parse_usageboard_params(sys.argv[1:])
    api_key = params.get("API_KEY")
    period = params.get("STAT_PERIOD", "7d").lower()
    if period not in ("7d", "15d", "30d"):
        period = "7d"
    language = app_language(params)
    translate = make_translator(TRANSLATIONS)

    if not api_key:
        return failure(translate(language, "missing_api_key"))

    try:
        payload = fetch_limits(api_key)
    except urllib.error.HTTPError as error:
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

    if not items:
        return failure(translate(language, "no_quota_items"))

    _, _, buckets, bucket_unit = stat_range(period)
    try:
        daily = maintain_chart_cache(api_key, language)
        chart = build_chart_from_cache(daily, period, language)
    except Exception:
        chart = chart_message(translate(language, "stats_query_failed"), period, buckets, bucket_unit)
    return success(items, badge=badge, chart=chart)


if __name__ == "__main__":
    sys.exit(main())
