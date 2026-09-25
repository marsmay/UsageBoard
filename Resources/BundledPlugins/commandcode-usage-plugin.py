#!/usr/bin/env python3
# UsageBoardPlugin:
# {
#   "schemaVersion": 1,
#   "name": "Command Code",
#   "name@zh-Hans": "Command Code",
#   "name@en": "Command Code",
#   "icon": "icons/light/commandcode.png",
#   "description": "查询 Command Code 订阅用量",
#   "description@zh-Hans": "查询 Command Code 订阅用量",
#   "description@en": "Query Command Code subscription usage",
#   "parameters": [
#     {
#       "name": "API_KEY",
#       "label": "API Key",
#       "label@zh-Hans": "API Key",
#       "label@en": "API Key",
#       "type": "secret",
#       "required": true,
#       "placeholder": "Command Code API Key"
#     }
#   ]
# }
# /UsageBoardPlugin
"""Command Code subscription usage via its undocumented alpha billing API."""

from __future__ import annotations

import math
import os
import sys
import urllib.error
from datetime import datetime, timezone
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from _common import (  # noqa: E402
    app_language,
    color_for,
    failure,
    fetch_json,
    handle_http_error,
    handle_url_error,
    make_translator,
    parse_usageboard_params,
    status_for,
    success,
)

BASE_URL = "https://api.commandcode.ai/alpha/billing/"
PLAN_BADGE_COLOR = {"GO": "teal", "GOAT": "blue", "MAX": "orange"}
TRANSLATE = make_translator({
    "five_hour": {"zh-Hans": "5 小时用量", "en": "5-hour usage"},
    "weekly": {"zh-Hans": "周用量", "en": "Weekly usage"},
    "monthly": {"zh-Hans": "月用量", "en": "Monthly usage"},
    "no_quota": {"zh-Hans": "未获取到订阅配额数据", "en": "No subscription quota data found."},
})


def fetch_billing(api_key: str, resource: str, timeout: float) -> dict[str, Any]:
    # fetch_json 内置不跟随重定向，凭证不会转发到其他主机。
    payload = fetch_json(BASE_URL + resource, headers={
        "Authorization": f"Bearer {api_key}",
        "x-api-key": api_key,
        "Accept": "application/json",
        "User-Agent": "UsageBoard",
    }, timeout=timeout)
    if not isinstance(payload, dict):
        raise ValueError("Invalid billing response")
    return payload


def number(value: Any) -> float:
    # Missing or malformed amounts must not be rendered as unused quota.
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        raise ValueError("Missing amount")
    result = float(value)
    if not math.isfinite(result):
        raise ValueError("Invalid amount")
    return result


def reset_time(value: Any) -> str | None:
    try:
        if isinstance(value, str) and "T" in value:
            date = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if date.tzinfo is None:
                return None
        else:
            timestamp = number(value)
            if timestamp <= 0:
                return None
            date = datetime.fromtimestamp(timestamp / 1000 if timestamp > 10_000_000_000 else timestamp, timezone.utc)
        return date.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    except (ValueError, OverflowError, OSError):
        return None


def item(key: str, used: float, cap: float, reset: Any, language: str) -> dict[str, Any]:
    used = max(used, 0)
    return {
        "id": f"commandcode-{key}",
        "name": TRANSLATE(language, key),
        "used": used,
        "limit": cap,
        "displayStyle": "percent",
        "resetAt": reset_time(reset),
        "status": status_for(used, cap),
        "color": color_for(used, cap),
    }


def build_items(payload: dict[str, Any], subscription: dict[str, Any], language: str) -> list[dict[str, Any]]:
    credits = payload.get("credits")
    if not isinstance(credits, dict) or payload.get("success") is False:
        raise ValueError("Missing credits")
    windows = payload.get("windowLimits", credits.get("windowLimits", {}))
    if not isinstance(windows, dict):
        raise ValueError("Invalid windows")
    items = []
    weekly_cap = None
    for field, key in (("fiveHour", "five_hour"), ("weekly", "weekly")):
        window = windows.get(field)
        if window is None:
            continue
        if not isinstance(window, dict):
            raise ValueError("Invalid window")
        cap = number(window.get("cap"))
        if cap <= 0:
            continue
        used = number(window.get("used"))
        items.append(item(key, used, cap, window.get("resetAt"), language))
        if field == "weekly":
            weekly_cap = cap
    if weekly_cap is not None and credits.get("monthlyCredits") is not None:
        # Temporary product rule: monthly allowance is twice the weekly cap.
        monthly_cap = number(weekly_cap * 2)
        remaining = number(credits["monthlyCredits"])
        items.append(item("monthly", number(monthly_cap - remaining), monthly_cap,
                          subscription.get("currentPeriodEnd"), language))
    return items


def subscription_badge(subscription: dict[str, Any]) -> str | None:
    plan = subscription.get("planId")
    if not isinstance(plan, str) or not plan.strip():
        return None
    name = plan.removeprefix("individual-")
    return name.upper() if name.upper() in PLAN_BADGE_COLOR else name.replace("-", " ").title()


def main() -> int:
    params = parse_usageboard_params(sys.argv[1:])
    language = app_language(params)
    api_key = (params.get("API_KEY") or os.environ.get("COMMAND_API_KEY", "")).strip()
    if not api_key:
        return failure(TRANSLATE(language, "missing_api_key"))
    try:
        payload = fetch_billing(api_key, "credits", timeout=6)
    except urllib.error.HTTPError as error:
        return handle_http_error(error, TRANSLATE, language)
    except urllib.error.URLError as error:
        return handle_url_error(error, TRANSLATE, language)
    except TimeoutError:
        return failure(TRANSLATE(language, "request_timeout"))
    except (ValueError, UnicodeDecodeError):
        return failure(TRANSLATE(language, "usage_parse_failed"))
    except Exception:
        return failure(TRANSLATE(language, "network_error"))

    # Subscription only enriches the badge and monthly reset. Its failure must
    # not discard usable credits or masquerade as a successful zero-usage result.
    subscription: dict[str, Any] = {}
    try:
        result = fetch_billing(api_key, "subscriptions", timeout=3)
        if result.get("success") is True and isinstance(result.get("data"), dict):
            subscription = result["data"]
    except Exception:
        pass
    try:
        items = build_items(payload, subscription, language)
    except (ValueError, TypeError, OverflowError):
        return failure(TRANSLATE(language, "usage_parse_failed"))
    if not items:
        return failure(TRANSLATE(language, "no_quota"))
    badge = subscription_badge(subscription)
    return success(items, badge=badge, badgeColor=PLAN_BADGE_COLOR.get(badge))


if __name__ == "__main__":
    sys.exit(main())
