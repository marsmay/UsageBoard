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

import json
import os
import sys
import urllib.error
import urllib.request
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from _common import (  # noqa: E402
    failure,
    handle_http_error,
    handle_url_error,
    make_translator,
    parse_usageboard_params,
    success,
    utc_now_iso,
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
    request = urllib.request.Request(
        ENDPOINT,
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        if response.status != 200:
            raise ValueError(f"Unexpected HTTP {response.status}")
        body = response.read()
        return json.loads(body)


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
    language = params.get("USAGEBOARD_LANGUAGE", "en")
    language = "en" if language == "en" else "zh-Hans"
    translate = make_translator({
        "balance": {"zh-Hans": "余额", "en": "Balance"},
    })

    api_key = params.get("API_KEY", "")
    if not api_key:
        return failure(translate(language, "missing_api_key"))
    limit_amount = parse_limit(params.get("LIMIT", ""))

    try:
        payload = fetch_balance(api_key)
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
        items = build_items(payload, language, limit_amount, translate)
    except Exception:
        return failure(translate(language, "usage_parse_failed"))

    return success(items)


if __name__ == "__main__":
    sys.exit(main())
