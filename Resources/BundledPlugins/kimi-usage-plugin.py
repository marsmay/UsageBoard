#!/usr/bin/env python3
# UsageBoardPlugin:
# {
#   "schemaVersion": 1,
#   "name": "Kimi",
#   "name@zh-Hans": "Kimi",
#   "name@en": "Kimi",
#   "icon": "icons/light/kimi.png",
#   "description": "查询 Kimi Code 用量",
#   "description@zh-Hans": "查询 Kimi Code 用量",
#   "description@en": "Query Kimi Code usage",
#   "parameters": [
#     {
#       "name": "PLAN",
#       "label": "Subscription Plan",
#       "label@zh-Hans": "订阅计划",
#       "label@en": "Subscription Plan",
#       "type": "choice",
#       "required": false,
#       "defaultValue": "Go",
#       "options": [
#         {"label": "Go", "value": "Go"},
#         {"label": "Plus", "value": "Plus"},
#         {"label": "Pro", "value": "Pro"},
#         {"label": "Max", "value": "Max"}
#       ]
#     },
#     {
#       "name": "API_KEY",
#       "label": "Api Key",
#       "label@zh-Hans": "Api Key",
#       "label@en": "API Key",
#       "type": "secret",
#       "required": true,
#       "placeholder": "Kimi Code API Key"
#     }
#   ]
# }
# /UsageBoardPlugin
"""UsageBoard plugin for Kimi Code quota usage."""

from __future__ import annotations

import os
import sys
from datetime import datetime
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from _common import (  # noqa: E402
    app_language,
    color_for,
    failure,
    fetch_json,
    make_translator,
    numeric,
    parse_usageboard_params,
    require_api_key,
    run_query,
    status_for,
    success,
)


ENDPOINT = "https://api.kimi.com/coding/v1/usages"
# Kimi Code 用量端点面向其 CLI 客户端，保留与 @moonshot-ai/kimi-code 一致的 UA 以兼容服务端校验。
USER_AGENT = "kimi-code/0.27.0"

# Kimi Code 订阅计划 → 徽标颜色。用量 API 已不返回会员等级，套餐仅来自手动配置。
PLAN_BADGE_COLOR = {
    "Go": "gray",
    "Plus": "indigo",
    "Pro": "blue",
    "Max": "orange",
}

TRANSLATIONS = {
    "window_quota":  {"zh-Hans": "{period}用量", "en": "{period} usage"},
    "weekly_quota":  {"zh-Hans": "周用量",       "en": "Weekly usage"},
    "no_quota_items": {"zh-Hans": "未获取到配额数据", "en": "No quota data found."},
}


def window_minutes(duration: float, time_unit: Any) -> float:
    """Normalize a window duration to minutes based on its timeUnit."""
    if time_unit == "TIME_UNIT_HOUR":
        return duration * 60
    if time_unit == "TIME_UNIT_SECOND":
        return duration / 60
    return duration  # TIME_UNIT_MINUTE or unspecified


def window_period(minutes: float, language: str) -> str:
    """Human-readable window length, e.g. "5 小时" / "5 hours"."""
    if minutes >= 60:
        value = max(int(round(minutes / 60)), 1)
        unit = "小时" if language != "en" else "hours"
    else:
        value = max(int(minutes), 1)
        unit = "分钟" if language != "en" else "min"
    return f"{value} {unit}"


def used_total(detail: dict[str, Any]) -> tuple[float, float]:
    """Prefer an explicit `used` field; fall back to limit - remaining."""
    total = numeric(detail.get("limit"))
    # 服务端显式 "used": null 时不遮蔽回退计算（numeric(None) 会得 0）。
    if detail.get("used") is not None:
        return numeric(detail.get("used")), total
    return max(total - numeric(detail.get("remaining")), 0), total


def parse_reset_time(value: Any) -> str | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        # The timezone of naive API timestamps is unverified, and Core rejects
        # offset-less timestamps outright; omit rather than guess a timezone.
        return None
    return dt.isoformat().replace("+00:00", "Z")


def fetch_usage(api_key: str) -> dict[str, Any]:
    return fetch_json(ENDPOINT, headers={
        "Accept": "application/json",
        "Authorization": f"Bearer {api_key}",
        "User-Agent": USER_AGENT,
    }, timeout=10)


def build_items(payload: dict[str, Any], language: str, translate: Any) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []

    # 5-hour rolling windows (shown first)
    limits = payload.get("limits")
    if isinstance(limits, list):
        for entry in limits:
            if not isinstance(entry, dict):
                continue
            window = entry.get("window")
            minutes = 0.0
            if isinstance(window, dict):
                minutes = window_minutes(numeric(window.get("duration")), window.get("timeUnit"))
            detail = entry.get("detail")
            if not isinstance(detail, dict):
                continue
            used, total = used_total(detail)
            if total <= 0:
                continue
            items.append({
                "id": f"kimi-window-{int(minutes)}",
                "name": translate(language, "window_quota", period=window_period(minutes, language)),
                "used": used,
                "limit": total,
                "displayStyle": "percent",
                "resetAt": parse_reset_time(detail.get("resetTime")),
                "status": status_for(used, total),
                "color": color_for(used, total),
            })

    # Weekly / period quota
    usage = payload.get("usage")
    if isinstance(usage, dict):
        used, total = used_total(usage)
        if total > 0:
            items.append({
                "id": "kimi-weekly",
                "name": translate(language, "weekly_quota"),
                "used": used,
                "limit": total,
                "displayStyle": "percent",
                "resetAt": parse_reset_time(usage.get("resetTime")),
                "status": status_for(used, total),
                "color": color_for(used, total),
            })

    return items


def main() -> int:
    params = parse_usageboard_params(sys.argv[1:])
    language = app_language(params)
    translate = make_translator(TRANSLATIONS)

    api_key = require_api_key(params)
    if not api_key:
        return failure(translate(language, "missing_api_key"))

    payload = run_query(lambda: fetch_usage(api_key), translate, language)
    if payload is None:
        return 0

    try:
        items = build_items(payload, language, translate)
    except Exception:
        return failure(translate(language, "usage_parse_failed"))

    if not items:
        return failure(translate(language, "no_quota_items"))

    configured_plan = params.get("PLAN", "").strip()
    badge = configured_plan if configured_plan in PLAN_BADGE_COLOR else None
    return success(items, badge=badge, badgeColor=PLAN_BADGE_COLOR.get(badge))


if __name__ == "__main__":
    sys.exit(main())
