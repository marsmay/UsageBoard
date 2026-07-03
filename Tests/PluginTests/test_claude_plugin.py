"""Tests for claude-usage-plugin.py — run with: python3 -m pytest Tests/PluginTests/test_claude_plugin.py"""

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from io import StringIO
from unittest.mock import patch

PLUGIN_PATH = Path(__file__).parent.parent.parent / "Resources" / "BundledPlugins" / "claude-usage-plugin.py"


def load_plugin():
    plugin_dir = str(PLUGIN_PATH.parent)
    if plugin_dir not in sys.path:
        sys.path.insert(0, plugin_dir)
    spec = importlib.util.spec_from_file_location("claude_plugin", PLUGIN_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


plugin = load_plugin()


class TestTranslateSignature(unittest.TestCase):
    """translate(language, key) — language first, key second (matches all other plugins)."""

    def test_language_first_zh(self):
        translate = plugin._translate("zh-Hans")
        result = translate("zh-Hans", "five_hour")
        self.assertEqual(result, "5 小时用量")

    def test_language_first_en(self):
        translate = plugin._translate("en")
        result = translate("en", "five_hour")
        self.assertEqual(result, "5-hour usage")

    def test_unknown_key_returns_key(self):
        translate = plugin._translate("en")
        result = translate("en", "nonexistent_key")
        self.assertEqual(result, "nonexistent_key")


class TestColorThresholds(unittest.TestCase):
    """color_for thresholds should match other plugins: ≥90 red, ≥80 orange, ≥60 yellow, <60 blue."""

    def test_90_is_red(self):
        self.assertEqual(plugin.color_for_pct(90), "red")

    def test_80_is_orange(self):
        self.assertEqual(plugin.color_for_pct(80), "orange")

    def test_79_is_yellow(self):
        self.assertEqual(plugin.color_for_pct(79), "yellow")

    def test_60_is_yellow(self):
        self.assertEqual(plugin.color_for_pct(60), "yellow")

    def test_59_is_blue(self):
        self.assertEqual(plugin.color_for_pct(59), "blue")


class TestStatusThresholds(unittest.TestCase):
    """status_for thresholds should match other plugins: ≥90 critical, ≥75 warning, else normal."""

    def test_90_is_critical(self):
        self.assertEqual(plugin.status_for(90), "critical")

    def test_75_is_warning(self):
        self.assertEqual(plugin.status_for(75), "warning")

    def test_74_is_normal(self):
        self.assertEqual(plugin.status_for(74), "normal")

    def test_0_is_normal(self):
        self.assertEqual(plugin.status_for(0), "normal")


class TestSuccessSchemaVersion(unittest.TestCase):
    """success() output must include schemaVersion field."""

    def test_success_has_schema_version(self):
        items = [{"id": "x", "name": "x", "used": 0, "limit": 1, "displayStyle": "percent", "status": "normal"}]
        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            plugin.success(items)
            output = json.loads(mock_out.getvalue())
        self.assertIn("schemaVersion", output)
        self.assertEqual(output["schemaVersion"], 1)


class TestFailureFormat(unittest.TestCase):
    """failure() must output {"error": "message"} with no items."""

    def test_failure_has_error_field(self):
        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            plugin.failure("test error")
            output = json.loads(mock_out.getvalue())
        self.assertIn("error", output)
        self.assertEqual(output["error"], "test error")

    def test_failure_has_no_items(self):
        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            plugin.failure("test error")
            output = json.loads(mock_out.getvalue())
        self.assertNotIn("items", output)


class TestFetchOauthUsageErrors(unittest.TestCase):
    def test_timeout_error_returns_timeout_code(self):
        with patch.object(plugin.urllib_request, "urlopen", side_effect=TimeoutError):
            data, code = plugin.fetch_oauth_usage("token")

        self.assertIsNone(data)
        self.assertEqual(code, plugin.REQUEST_TIMEOUT)

    def test_url_error_returns_network_error_code(self):
        error = plugin.urllib.error.URLError("offline")
        with patch.object(plugin.urllib_request, "urlopen", side_effect=error):
            data, code = plugin.fetch_oauth_usage("token")

        self.assertIsNone(data)
        self.assertEqual(code, plugin.NETWORK_ERROR)


class TestBuildItemsFromOauth(unittest.TestCase):
    """OAuth usage payload should produce UsageBoard items for five_hour and seven_day."""

    def test_produces_two_items_with_correct_fields(self):
        payload = {
            "five_hour": {"utilization": 12.34, "resets_at": "2026-05-09T10:00:00Z"},
            "seven_day": {"utilization": 56.78, "resets_at": "2026-05-10T00:00:00Z"},
        }

        translate = plugin._translate("zh-Hans")
        items = plugin.build_items_from_oauth(payload, "zh-Hans", translate)

        self.assertEqual(len(items), 2)
        self.assertEqual([item["id"] for item in items], ["claude-five-hour", "claude-seven-day"])

        fh = items[0]
        self.assertEqual(fh["name"], "5 小时用量")
        self.assertEqual(fh["used"], 12.3)
        self.assertEqual(fh["limit"], 100)
        self.assertEqual(fh["displayStyle"], "percent")
        self.assertEqual(fh["resetAt"], "2026-05-09T10:00:00Z")
        self.assertEqual(fh["status"], "normal")
        self.assertEqual(fh["color"], "blue")

        sd = items[1]
        self.assertEqual(sd["name"], "周用量")
        self.assertEqual(sd["used"], 56.8)
        self.assertEqual(sd["color"], "blue")

    def test_ignores_unknown_fields_in_payload(self):
        payload = {
            "five_hour": {"utilization": 50, "resets_at": "2026-05-09T10:00:00Z"},
            "seven_day": {"utilization": 80, "resets_at": "2026-05-10T00:00:00Z"},
            "seven_day_omelette": {"utilization": 91.2, "resets_at": "2026-05-11T00:00:00Z"},
        }

        translate = plugin._translate("en")
        items = plugin.build_items_from_oauth(payload, "en", translate)

        self.assertEqual([item["id"] for item in items], ["claude-five-hour", "claude-seven-day"])


class TestMaintainCacheRefreshesToday(unittest.TestCase):
    """maintain_cache must re-scan today's data on subsequent runs (gap_days == 0).

    Regression test for bug: previously, `if gap_days <= 0: return cache` froze today's
    data after the first scan of the day, so usage that happened later wouldn't show up.
    """

    def _write_jsonl(self, path, ts_iso, model, tokens):
        record = {
            "type": "assistant",
            "timestamp": ts_iso,
            "message": {
                "id": f"msg-{ts_iso}-{tokens}",
                "model": model,
                "usage": {"input_tokens": 0, "output_tokens": tokens, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0},
            },
        }
        with open(path, "a") as f:
            f.write(json.dumps(record) + "\n")

    def test_today_is_rescanned_when_gap_days_is_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            projects = os.path.join(tmp, "projects", "p1")
            os.makedirs(projects)
            jsonl = os.path.join(projects, "session.jsonl")

            today_str = datetime.now().strftime("%Y-%m-%d")
            now = datetime.now().astimezone()
            start_today = now.replace(hour=0, minute=0, second=0, microsecond=0)
            elapsed_today = now - start_today
            earlier = start_today + (elapsed_today / 3)
            later = start_today + (elapsed_today * 2 / 3)

            # First run: today has 100 tokens
            self._write_jsonl(jsonl, earlier.isoformat(), "claude-sonnet", 100)
            result1 = plugin.maintain_cache(tmp)
            self.assertEqual(result1.get(today_str, {}).get("claude-sonnet", {}).get("output", 0), 100)

            # Append more usage in the same day — simulate user activity since first run
            self._write_jsonl(jsonl, later.isoformat(), "claude-sonnet", 250)

            # Second run (same day, gap_days == 0) — must pick up the 250 new tokens
            result2 = plugin.maintain_cache(tmp)
            self.assertEqual(
                result2.get(today_str, {}).get("claude-sonnet", {}).get("output", 0),
                350,
                "Today's data must be re-scanned on subsequent runs, not returned from cache as-is",
            )


class TestMaintainCacheRecovery(unittest.TestCase):
    def test_invalid_last_date_rebuilds_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache_path = os.path.join(tmp, plugin.CACHE_FILENAME)
            with open(cache_path, "w") as f:
                json.dump({"version": plugin.CACHE_VERSION, "last_date": "bad-date", "days": {}}, f)

            result = plugin.maintain_cache(tmp)

        self.assertIsInstance(result, dict)

    def test_invalid_cached_day_key_is_skipped(self):
        today = plugin._parse_date(plugin.local_today())
        yesterday = today - timedelta(days=1)

        with tempfile.TemporaryDirectory() as tmp:
            plugin.save_stats_cache(tmp, {
                "version": plugin.CACHE_VERSION,
                "last_date": plugin._format_date(today),
                "days": {
                    "bad-date": {"stale": {"input": 1, "output": 0, "cache_creation": 0, "cache_read": 0}},
                    plugin._format_date(yesterday): {"old-model": {"input": 2, "output": 0, "cache_creation": 0, "cache_read": 0}},
                },
            })

            result = plugin.maintain_cache(tmp)

        self.assertNotIn("bad-date", result)
        self.assertEqual(
            result.get(plugin._format_date(yesterday)),
            {"old-model": {"input": 2, "output": 0, "cache_creation": 0, "cache_read": 0}},
        )


class TestComputeTokens(unittest.TestCase):
    """compute_tokens supports both billing-weighted and actual modes."""

    def test_actual_sums_all_four(self):
        b = {"input": 100, "output": 50, "cache_creation": 200, "cache_read": 9999}
        self.assertEqual(plugin.compute_tokens(b, "actual"), 100 + 50 + 200 + 9999)

    def test_billable_applies_ratios(self):
        b = {"input": 100, "output": 50, "cache_creation": 200, "cache_read": 9999}
        # 100*1 + 50*5 + 200*1.25 + 9999*0.1 = 100 + 250 + 250 + 999.9 = 1599.9 → 1600
        self.assertEqual(plugin.compute_tokens(b, "billable"), 1600)

    def test_unknown_mode_defaults_to_billable(self):
        b = {"input": 100, "output": 50, "cache_creation": 200, "cache_read": 9999}
        self.assertEqual(plugin.compute_tokens(b, "unknown"), 1600)


class TestParseRecordsReturnsBreakdown(unittest.TestCase):
    """parse_records returns raw 4-field breakdown, not pre-summed total."""

    def test_breakdown_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            jsonl = os.path.join(tmp, "session.jsonl")
            with open(jsonl, "w") as f:
                f.write(json.dumps({
                    "type": "assistant",
                    "timestamp": "2026-05-15T10:00:00Z",
                    "message": {
                        "id": "msg-1",
                        "model": "claude-opus-4-7",
                        "usage": {
                            "input_tokens": 100,
                            "output_tokens": 50,
                            "cache_creation_input_tokens": 200,
                            "cache_read_input_tokens": 9999,
                        },
                    },
                }) + "\n")
            start = datetime(2026, 5, 14, tzinfo=timezone.utc)
            end = datetime(2026, 5, 16, tzinfo=timezone.utc)
            records = plugin.parse_records([jsonl], start, end)
            self.assertEqual(len(records), 1)
            _, _, breakdown = records[0]
            self.assertEqual(breakdown, {
                "input": 100, "output": 50, "cache_creation": 200, "cache_read": 9999,
            })


if __name__ == "__main__":
    unittest.main()
