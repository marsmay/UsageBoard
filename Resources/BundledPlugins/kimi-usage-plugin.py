#!/usr/bin/env python3
# UsageBoardPlugin:
# {
#   "schemaVersion": 1,
#   "name": "Kimi",
#   "name@zh-Hans": "Kimi",
#   "name@en": "Kimi",
#   "icon": "https://raw.githubusercontent.com/lobehub/lobe-icons/refs/heads/master/packages/static-png/light/kimi.png",
#   "description": "查询 Kimi Code 用量",
#   "description@zh-Hans": "查询 Kimi Code 用量",
#   "description@en": "Query Kimi Code usage",
#   "parameters": [
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

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from _common import (  # noqa: E402
    app_language,
    color_for,
    failure,
    handle_http_error,
    handle_url_error,
    make_translator,
    numeric,
    parse_usageboard_params,
    status_for,
    success,
)


ENDPOINT = "https://api.kimi.com/coding/v1/usages"
# Kimi Code 用量端点面向其 CLI 客户端，保留与 @moonshot-ai/kimi-code 一致的 UA 以兼容服务端校验。
USER_AGENT = "kimi-code/0.27.0"

# Kimi 商品配置中的会员等级 → 订阅计划。
MEMBERSHIP_PLAN = {
    "LEVEL_FREE": "Adagio",
    "LEVEL_TRIAL": "Andante",
    "LEVEL_BASIC": "Moderato",
    "LEVEL_INTERMEDIATE": "Allegretto",
    "LEVEL_ADVANCED": "Allegro",
}

# Kimi Code 订阅计划 → 徽标颜色。
PLAN_BADGE_COLOR = {
    "Adagio": "gray",
    "Andante": "gray",
    "Moderato": "indigo",
    "Allegretto": "blue",
    "Allegro": "orange",
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
    if "used" in detail:
        return numeric(detail.get("used")), total
    return max(total - numeric(detail.get("remaining")), 0), total


def parse_reset_time(value: Any) -> str | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt.isoformat().replace("+00:00", "Z")


def fetch_usage(api_key: str) -> dict[str, Any]:
    request = urllib.request.Request(
        ENDPOINT,
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {api_key}",
            "User-Agent": USER_AGENT,
        },
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def extract_plan(payload: dict[str, Any]) -> str | None:
    """Map the usage API membership level to its configured product title."""
    user = payload.get("user")
    if not isinstance(user, dict):
        return None
    membership = user.get("membership")
    if not isinstance(membership, dict):
        return None
    level = membership.get("level")
    if not isinstance(level, str):
        return None
    return MEMBERSHIP_PLAN.get(level)


def build_items(payload: dict[str, Any], language: str, translate: Any) -> tuple[list[dict[str, Any]], str | None]:
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

    return items, extract_plan(payload)


def main() -> int:
    params = parse_usageboard_params(sys.argv[1:])
    language = app_language(params)
    translate = make_translator(TRANSLATIONS)

    api_key = params.get("API_KEY", "")
    if not api_key:
        return failure(translate(language, "missing_api_key"))

    try:
        payload = fetch_usage(api_key)
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
        items, auto_badge = build_items(payload, language, translate)
    except Exception:
        return failure(translate(language, "usage_parse_failed"))

    if not items:
        return failure(translate(language, "no_quota_items"))

    return success(items, badge=auto_badge, badgeColor=PLAN_BADGE_COLOR.get(auto_badge))


if __name__ == "__main__":
    sys.exit(main())
