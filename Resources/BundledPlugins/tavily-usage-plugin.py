#!/usr/bin/env python3
# UsageBoardPlugin:
# {
#   "schemaVersion": 1,
#   "name": "Tavily",
#   "name@zh-Hans": "Tavily",
#   "name@en": "Tavily",
#   "icon": "icons/light/tavily-color.png",
#   "description": "查询 Tavily Search 月度用量",
#   "description@zh-Hans": "查询 Tavily Search 月度用量",
#   "description@en": "Query Tavily Search monthly usage",
#   "parameters": [
#     {
#       "name": "API_KEY",
#       "label": "Api Key",
#       "label@zh-Hans": "Api Key",
#       "label@en": "API Key",
#       "type": "secret",
#       "required": true,
#       "placeholder": "Tavily API Key"
#     }
#   ]
# }
# /UsageBoardPlugin
"""UsageBoard plugin for Tavily quota usage."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
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
    utc_now_iso,
)


ENDPOINT = "https://api.tavily.com/usage"


def fetch_usage(api_key: str) -> dict[str, Any]:
    request = urllib.request.Request(ENDPOINT, headers={"Authorization": f"Bearer {api_key}"})
    with urllib.request.urlopen(request, timeout=5) as response:
        return json.loads(response.read().decode("utf-8"))


def next_month_start_iso() -> str:
    now = datetime.now(timezone.utc)
    next_month = now.month + 1 if now.month < 12 else 1
    next_year = now.year if now.month < 12 else now.year + 1
    reset = datetime(next_year, next_month, 1, tzinfo=timezone.utc)
    return reset.isoformat().replace("+00:00", "Z")


def item(item_id: str, name: str, used: float, total: float, color: str = "blue", reset_at: str | None = None) -> dict[str, Any]:
    return {
        "id": item_id,
        "name": name,
        "used": max(used, 0),
        "limit": max(total, 0),
        "displayStyle": "ratio",
        "resetAt": reset_at,
        "status": status_for(used, total),
        "color": color,
    }


def build_items(payload: dict[str, Any], language: str, translate: Any) -> list[dict[str, Any]]:
    account = payload.get("account", {})
    if not isinstance(account, dict):
        return []

    plan_limit = numeric(account.get("plan_limit"))
    if plan_limit <= 0:
        return []

    plan_usage = numeric(account.get("plan_usage"))
    output = [
        item(
            "tavily-total-month",
            translate(language, "total_usage"),
            plan_usage,
            plan_limit,
            color_for(plan_usage, plan_limit),
            next_month_start_iso(),
        )
    ]

    details = [
        ("tavily-search", "search", "search_usage"),
        ("tavily-crawl", "crawl", "crawl_usage"),
        ("tavily-extract", "extract", "extract_usage"),
        ("tavily-map", "map", "map_usage"),
        ("tavily-research", "research", "research_usage"),
    ]
    for item_id, name_key, usage_key in details:
        used = numeric(account.get(usage_key))
        if used > 0:
            output.append(item(item_id, translate(language, name_key), used, plan_usage))

    return output


def main() -> int:
    params = parse_usageboard_params(sys.argv[1:])
    language = app_language(params)
    translate = make_translator({
        "total_usage":  {"zh-Hans": "总用量", "en": "Total usage"},
        "search":       {"zh-Hans": "搜索",   "en": "Search"},
        "crawl":        {"zh-Hans": "爬取",   "en": "Crawl"},
        "extract":      {"zh-Hans": "提取",   "en": "Extract"},
        "map":          {"zh-Hans": "地图",   "en": "Map"},
        "research":     {"zh-Hans": "研究",   "en": "Research"},
        "no_quota_items": {"zh-Hans": "未获取到用量数据", "en": "No usage data found."},
    })

    api_key = params.get("API_KEY")
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
        items = build_items(payload, language, translate)
    except Exception:
        return failure(translate(language, "usage_parse_failed"))

    if not items:
        return failure(translate(language, "no_quota_items"))
    return success(items)


if __name__ == "__main__":
    sys.exit(main())
