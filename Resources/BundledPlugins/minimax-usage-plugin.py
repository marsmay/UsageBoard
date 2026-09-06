#!/usr/bin/env python3
# UsageBoardPlugin:
# {
#   "schemaVersion": 1,
#   "name": "MiniMax",
#   "name@zh-Hans": "MiniMax",
#   "name@en": "MiniMax",
#   "icon": "icons/light/minimax-color.png",
#   "description": "查询 MiniMax Coding Plan 用量",
#   "description@zh-Hans": "查询 MiniMax Coding Plan 用量",
#   "description@en": "Query MiniMax Coding Plan usage",
#   "parameters": [
#     {
#       "name": "API_KEY",
#       "label": "Api Key",
#       "label@zh-Hans": "Api Key",
#       "label@en": "API Key",
#       "type": "secret",
#       "required": true,
#       "placeholder": "MiniMax API Key"
#     },
#     {
#       "name": "PLAN",
#       "label": "Subscription Plan",
#       "label@zh-Hans": "订阅计划",
#       "label@en": "Subscription Plan",
#       "type": "choice",
#       "required": false,
#       "defaultValue": "plus",
#       "options": [
#         {"label": "None",  "label@zh-Hans": "无",    "label@en": "None",  "value": "none"},
#         {"label": "Plus",  "label@zh-Hans": "Plus",  "label@en": "Plus",  "value": "plus"},
#         {"label": "Max",   "label@zh-Hans": "Max",   "label@en": "Max",   "value": "max"},
#         {"label": "Ultra", "label@zh-Hans": "Ultra", "label@en": "Ultra", "value": "ultra"}
#       ]
#     }
#   ]
# }
# /UsageBoardPlugin
"""UsageBoard plugin for MiniMax Coding Plan quota usage."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from _common import (  # noqa: E402
    app_language,
    color_for_pct,
    failure,
    handle_http_error,
    handle_url_error,
    make_translator,
    numeric,
    parse_usageboard_params,
    status_for,
    success,
)


ENDPOINT = "https://www.minimaxi.com/v1/token_plan/remains"

# model_name 返回的是大分类，映射到 translate 字典的 key。未登记的按原名展示。
KNOWN_MODELS = {"general", "video"}


def fetch_remains(api_key: str) -> dict[str, Any]:
    request = urllib.request.Request(
        ENDPOINT,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def reset_at_from_remaining_ms(value: Any) -> str | None:
    remaining_ms = numeric(value)
    if remaining_ms <= 0:
        return None
    reset_at = datetime.now(timezone.utc) + timedelta(milliseconds=remaining_ms)
    return reset_at.isoformat().replace("+00:00", "Z")


def interval_label_key(model: dict[str, Any]) -> str:
    time_diff_ms = numeric(model.get("end_time")) - numeric(model.get("start_time"))
    hours_diff = time_diff_ms / 1000 / 3600
    if hours_diff <= 5.1:
        return "period_5h"
    if hours_diff <= 24.1:
        return "period_day"
    if hours_diff <= 168.1:
        return "period_week"
    return "period_generic"


def pct_item(item_id: str, name: str, used_pct: float, reset_at: str | None) -> dict[str, Any]:
    used = min(max(used_pct, 0), 100)
    return {
        "id": item_id,
        "name": name,
        "used": used,
        "limit": 100,
        "displayStyle": "percent",
        "resetAt": reset_at,
        "status": status_for(used, 100),
        "color": color_for_pct(used),
    }


def build_items(payload: dict[str, Any], language: str, translate: Any) -> list[dict[str, Any]]:
    models = payload.get("model_remains", [])
    if not isinstance(models, list):
        return []

    output: list[dict[str, Any]] = []
    for model in models:
        if not isinstance(model, dict):
            continue

        raw_name = str(model.get("model_name", "unknown"))
        name = translate(language, f"model_{raw_name}") if raw_name in KNOWN_MODELS else raw_name
        slug = raw_name.replace(" ", "-").replace("/", "-").lower()

        interval_pct = model.get("current_interval_remaining_percent")
        if interval_pct is not None:
            period_key = interval_label_key(model)
            output.append(pct_item(
                f"minimax-{slug}-interval",
                f"{name} ({translate(language, period_key)})",
                100 - numeric(interval_pct),
                reset_at_from_remaining_ms(model.get("remains_time")),
            ))

        weekly_pct = model.get("current_weekly_remaining_percent")
        if weekly_pct is not None:
            output.append(pct_item(
                f"minimax-{slug}-week",
                f"{name} ({translate(language, 'period_week')})",
                100 - numeric(weekly_pct),
                reset_at_from_remaining_ms(model.get("weekly_remains_time")),
            ))

    return output


def plan_badge(params: dict[str, str]) -> str | None:
    plan = params.get("PLAN", "plus").lower()
    if plan == "none":
        return None
    return plan.capitalize()


def main() -> int:
    params = parse_usageboard_params(sys.argv[1:])
    language = app_language(params)
    translate = make_translator({
        "model_general":   {"zh-Hans": "文本",  "en": "Text"},
        "model_video":     {"zh-Hans": "视频",  "en": "Video"},
        "period_5h":       {"zh-Hans": "5小时", "en": "5 hours"},
        "period_day":      {"zh-Hans": "天",    "en": "day"},
        "period_week":     {"zh-Hans": "周",    "en": "week"},
        "period_generic":  {"zh-Hans": "周期",  "en": "period"},
        "no_quota_items":  {"zh-Hans": "未获取到配额数据", "en": "No quota data found."},
        "invalid_api_key": {"zh-Hans": "API Key 无效，请检查配置", "en": "Invalid API Key. Check your settings."},
    })

    api_key = params.get("API_KEY")
    if not api_key:
        return failure(translate(language, "missing_api_key"))

    try:
        payload = fetch_remains(api_key)
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
        status_code = payload.get("base_resp", {}).get("status_code", 0)
        if status_code != 0:
            if status_code == 2049:
                return failure(translate(language, "invalid_api_key"))
            status_msg = payload.get("base_resp", {}).get("status_msg", "")
            return failure(f"{status_msg} ({status_code})" if status_msg else str(status_code))
        items = build_items(payload, language, translate)
    except Exception:
        return failure(translate(language, "usage_parse_failed"))

    if not items:
        return failure(translate(language, "no_quota_items"))
    return success(items, badge=plan_badge(params))


if __name__ == "__main__":
    sys.exit(main())
