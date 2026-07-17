"""Shared utilities for UsageBoard bundled plugins."""
from __future__ import annotations

import json
import ssl
import socket
import sys
import urllib.error
from datetime import datetime, timezone
from typing import Any

SCHEMA_VERSION = 1


# ─── Parameter parsing ─────────────────────────────────────────────────────────

def parse_usageboard_params(argv: list[str]) -> dict[str, str]:
    values: dict[str, str] = {}
    index = 0
    while index < len(argv):
        if argv[index] == "--usageboard-param" and index + 1 < len(argv):
            key_value = argv[index + 1]
            if "=" in key_value:
                key, value = key_value.split("=", 1)
                if key:
                    values[key] = value
            index += 2
        else:
            index += 1
    return values


def app_language(params: dict[str, str]) -> str:
    return "en" if params.get("USAGEBOARD_LANGUAGE") == "en" else "zh-Hans"


# ─── Translation ────────────────────────────────────────────────────────────────

COMMON_TRANSLATIONS: dict[str, dict[str, str]] = {
    "missing_api_key":  {"zh-Hans": "请在插件设置中配置 API Key",          "en": "Configure API Key in plugin settings"},
    "request_timeout":  {"zh-Hans": "请求超时，请检查网络",                  "en": "Request timed out. Check your network."},
    "http_401":         {"zh-Hans": "API Key 无效，请检查配置 (HTTP {code})",         "en": "Invalid API Key. Check your settings. (HTTP {code})"},
    "http_403":         {"zh-Hans": "账号无权限访问 (HTTP {code})",                    "en": "Access denied. Check your plan. (HTTP {code})"},
    "http_429":         {"zh-Hans": "请求频率超限，请稍后重试 (HTTP {code})",           "en": "Rate limited. Try again later. (HTTP {code})"},
    "http_5xx":         {"zh-Hans": "服务暂时不可用 (HTTP {code})",         "en": "Service unavailable (HTTP {code})"},
    "http_other":       {"zh-Hans": "请求失败 (HTTP {code})",              "en": "Request failed (HTTP {code})"},
    "network_error":    {"zh-Hans": "网络连接失败，请检查网络",               "en": "Network error. Check your connection."},
    "usage_parse_failed": {"zh-Hans": "用量数据解析失败",                    "en": "Failed to parse usage data"},
    "ssl_error":        {"zh-Hans": "SSL 证书验证失败，请检查网络环境",       "en": "SSL certificate error. Check your network."},
    "connection_error":  {"zh-Hans": "无法连接服务器，请检查网络",             "en": "Cannot reach server. Check your connection."},
}


def make_translator(translations: dict[str, dict[str, str]]) -> Any:
    """Return a translate function that merges COMMON_TRANSLATIONS with plugin-specific ones."""
    merged = {**COMMON_TRANSLATIONS, **translations}

    def translate(language: str, key: str, **kwargs) -> str:
        values = merged.get(key, {})
        text = values.get(language) or values.get("zh-Hans") or key
        return text.format(**kwargs) if kwargs else text

    return translate


# ─── Time utilities ─────────────────────────────────────────────────────────────

def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


# ─── Output ─────────────────────────────────────────────────────────────────────

def success(items: list[dict[str, Any]], badge: str | None = None, chart: dict[str, Any] | None = None, badgeColor: str | None = None) -> int:
    result: dict[str, Any] = {"schemaVersion": SCHEMA_VERSION, "updatedAt": utc_now_iso(), "items": items}
    if badge:
        result["badge"] = badge
    if chart:
        result["chart"] = chart
    if badgeColor:
        result["badgeColor"] = badgeColor
    print(json.dumps(result, ensure_ascii=False))
    return 0


def failure(message: str) -> int:
    print(json.dumps({"error": message}, ensure_ascii=False))
    return 0


# ─── Status / color helpers ─────────────────────────────────────────────────────

def numeric(value: Any) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return 0
    return 0


def status_for(used: float, total: float) -> str:
    pct = used / total * 100 if total > 0 else 0
    if pct >= 90:
        return "critical"
    if pct >= 75:
        return "warning"
    return "normal"


def color_for(used: float, total: float) -> str:
    pct = used / total * 100 if total > 0 else 0
    if pct >= 90:
        return "red"
    if pct >= 80:
        return "orange"
    if pct >= 60:
        return "yellow"
    return "blue"


def color_for_pct(pct: float) -> str:
    if pct >= 90:
        return "red"
    if pct >= 80:
        return "orange"
    if pct >= 60:
        return "yellow"
    return "blue"


# ─── HTTP error handling ────────────────────────────────────────────────────────

def handle_http_error(error: urllib.error.HTTPError, translate: Any, language: str) -> int:
    if error.code == 401:
        return failure(translate(language, "http_401", code=error.code))
    if error.code == 403:
        return failure(translate(language, "http_403", code=error.code))
    if error.code == 429:
        return failure(translate(language, "http_429", code=error.code))
    if error.code >= 500:
        return failure(translate(language, "http_5xx", code=error.code))
    return failure(translate(language, "http_other", code=error.code))


def handle_url_error(error: urllib.error.URLError, translate: Any, language: str) -> int:
    reason = error.reason
    if isinstance(reason, ssl.SSLCertVerificationError):
        return failure(translate(language, "ssl_error"))
    if isinstance(reason, ssl.SSLError):
        return failure(translate(language, "ssl_error"))
    if isinstance(reason, (socket.timeout, TimeoutError)):
        return failure(translate(language, "request_timeout"))
    if isinstance(reason, ConnectionRefusedError):
        return failure(translate(language, "connection_error"))
    if isinstance(reason, OSError):
        return failure(translate(language, "connection_error"))
    return failure(translate(language, "network_error"))
