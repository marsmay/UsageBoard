#!/usr/bin/env python3
# UsageBoardPlugin:
# {
#   "schemaVersion": 1,
#   "name": "DeepSeek",
#   "name@zh-Hans": "DeepSeek",
#   "name@en": "DeepSeek",
#   "icon": "icons/light/deepseek-color.png",
#   "description": "查询 DeepSeek API 余额",
#   "description@zh-Hans": "查询 DeepSeek API 余额",
#   "description@en": "Query DeepSeek API balance",
#   "parameters": [
#     {
#       "name": "API_KEY",
#       "label": "Api Key",
#       "label@zh-Hans": "Api Key",
#       "label@en": "API Key",
#       "type": "secret",
#       "required": true,
#       "placeholder": "DeepSeek API Key"
#     },
#     {
#       "name": "LIMIT",
#       "label": "Amount Limit",
#       "label@zh-Hans": "金额上限",
#       "label@en": "Amount Limit",
#       "type": "integer",
#       "required": false,
#       "defaultValue": "100",
#       "placeholder": "100"
#     }
#   ]
# }
# /UsageBoardPlugin
"""UsageBoard plugin for DeepSeek API balance."""

from __future__ import annotations

import os
import sys
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from _common import (  # noqa: E402
    app_language,
    failure,
    fetch_json,
    make_translator,
    parse_usageboard_params,
    require_api_key,
    run_query,
    success,
)


ENDPOINT = "https://api.deepseek.com/user/balance"
DEFAULT_LIMIT = 100.0


def color_for_balance(balance: float, limit: float) -> str | None:
    if limit <= 0:
        return None
    ratio = balance / limit
    if ratio <= 0.10:
        return "red"
    if ratio <= 0.20:
        return "orange"
    if ratio <= 0.40:
        return "yellow"
    return "blue"


def parse_limit(raw: str) -> float:
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return DEFAULT_LIMIT
    return value if value > 0 else DEFAULT_LIMIT


def fetch_balance(api_key: str) -> dict[str, Any]:
    # 4xx/5xx 由 fetch_json 抛 HTTPError；2xx 中非 200 的罕见响应按正常 JSON 解析处理。
    return fetch_json(ENDPOINT, headers={
        "Accept": "application/json",
        "Authorization": f"Bearer {api_key}",
    }, timeout=10)


def build_items(data: dict[str, Any], language: str, limit_amount: float, translate: Any) -> list[dict[str, Any]]:
    items: list[dict] = []
    for info in data.get("balance_infos", []):
        currency = info.get("currency", "CNY")
        total_balance = float(info.get("total_balance", "0"))
        suffix = f" ({currency})" if currency != "CNY" else ""
        items.append({
            "id": f"balance-{currency}",
            "name": f"{translate(language, 'balance')}{suffix}",
            "used": round(total_balance, 2),
            "limit": round(limit_amount, 2),
            "displayStyle": "ratio",
            "status": "normal",
            "color": color_for_balance(total_balance, limit_amount),
        })
    return items


def main() -> int:
    params = parse_usageboard_params(sys.argv[1:])
    language = app_language(params)
    translate = make_translator({
        "balance": {"zh-Hans": "余额", "en": "Balance"},
    })

    api_key = require_api_key(params)
    if not api_key:
        return failure(translate(language, "missing_api_key"))
    limit_amount = parse_limit(params.get("LIMIT", ""))

    payload = run_query(lambda: fetch_balance(api_key), translate, language)
    if payload is None:
        return 0

    try:
        items = build_items(payload, language, limit_amount, translate)
    except Exception:
        return failure(translate(language, "usage_parse_failed"))

    return success(items)


if __name__ == "__main__":
    sys.exit(main())
