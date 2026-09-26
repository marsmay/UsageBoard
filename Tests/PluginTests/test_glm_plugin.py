"""Tests for glm-usage-plugin.py — run with: python3 -m unittest discover -s Tests/PluginTests"""

import importlib.util
import json
import sys
import tempfile
import unittest
from datetime import timedelta
from io import StringIO
from pathlib import Path
from unittest.mock import patch

PLUGIN_PATH = Path(__file__).parent.parent.parent / "Resources" / "BundledPlugins" / "glm-usage-plugin.py"


def load_plugin():
    plugin_dir = str(PLUGIN_PATH.parent)
    if plugin_dir not in sys.path:
        sys.path.insert(0, plugin_dir)
    spec = importlib.util.spec_from_file_location("glm_plugin", PLUGIN_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


plugin = load_plugin()


class TestStatsPeriodNone(unittest.TestCase):
    LIMITS_PAYLOAD = {
        "data": {
            "level": "pro",
            "limits": [{"unit": 3, "number": 5, "percentage": 42, "nextResetTime": 1780000000000}],
        }
    }

    def _run_main(self, period, cache_side_effect=None, cache_return=None):
        argv = [
            "glm",
            "--usageboard-param", "API_KEY=test-key",
            "--usageboard-param", f"STAT_PERIOD={period}",
        ]
        with patch.object(sys, "argv", argv), \
             patch.object(plugin, "fetch_limits", return_value=self.LIMITS_PAYLOAD), \
             patch.object(plugin, "maintain_chart_cache", side_effect=cache_side_effect, return_value=cache_return) as cache_mock, \
             patch("sys.stdout", new_callable=StringIO) as out:
            code = plugin.main()
        return code, json.loads(out.getvalue()), cache_mock

    def test_none_period_omits_chart_and_skips_stats_query(self):
        code, output, cache_mock = self._run_main(
            "none",
            cache_side_effect=AssertionError("should not query stats"),
        )

        self.assertEqual(code, 0)
        self.assertNotIn("chart", output)
        self.assertEqual(len(output["items"]), 1)
        cache_mock.assert_not_called()

    def test_default_period_still_builds_chart(self):
        code, output, cache_mock = self._run_main("7d", cache_return={})

        self.assertEqual(code, 0)
        self.assertIn("chart", output)
        cache_mock.assert_called_once()


class TestQuotaKind(unittest.TestCase):
    def test_current_value_shape_is_tool_usage(self):
        kind, label = plugin.quota_kind({"currentValue": 10, "usage": 100}, "en")

        self.assertEqual(kind, "tool")
        self.assertEqual(label, "Tool calls")

    def test_named_token_shape_is_text_usage(self):
        kind, label = plugin.quota_kind({"name": "Token quota"}, "en")

        self.assertEqual(kind, "text")
        self.assertEqual(label, "Text generation")

    def test_unrelated_marker_field_does_not_drive_classification(self):
        kind, label = plugin.quota_kind({"note": "tool migration note"}, "en")

        self.assertEqual(kind, "text")
        self.assertEqual(label, "Text generation")


class TestChartCache(unittest.TestCase):
    def payload(self, dates, values, model="glm-4.5"):
        return {
            "data": {
                "x_time": dates,
                "modelDataList": [
                    {
                        "model": model,
                        "tokensUsage": values,
                    }
                ],
            }
        }

    def test_first_run_fetches_near_30_days(self):
        api_key = "fake-key"
        calls = []

        def fake_fetch(_api_key, start_time, end_time):
            calls.append((start_time, end_time))
            return self.payload([end_time.strftime("%Y-%m-%d")], [42])

        with tempfile.TemporaryDirectory() as cache_dir:
            with patch.object(plugin, "fetch_model_usage", side_effect=fake_fetch):
                daily = plugin.maintain_chart_cache(api_key, "zh-Hans", cache_dir=cache_dir)

        self.assertEqual(len(calls), 1)
        self.assertEqual((calls[0][1].date() - calls[0][0].date()).days, 29)
        self.assertEqual(daily[calls[0][1].strftime("%Y-%m-%d")]["glm-4.5"], 42)

    def test_current_cache_refreshes_today_only(self):
        api_key = "fake-key"
        today = plugin.datetime.now().astimezone().date()
        yesterday = today - timedelta(days=1)
        calls = []

        def fake_fetch(_api_key, start_time, end_time):
            calls.append((start_time, end_time))
            return self.payload([plugin._format_date(today)], [9])

        with tempfile.TemporaryDirectory() as cache_dir:
            plugin.save_chart_cache(api_key, {
                "version": plugin.CACHE_VERSION,
                "last_date": plugin._format_date(today),
                "days": {
                    plugin._format_date(yesterday): {"old-model": 3},
                    plugin._format_date(today): {"glm-4.5": 1},
                },
            }, cache_dir=cache_dir)

            with patch.object(plugin, "fetch_model_usage", side_effect=fake_fetch):
                daily = plugin.maintain_chart_cache(api_key, "zh-Hans", cache_dir=cache_dir)

        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0].date(), today)
        self.assertEqual(calls[0][1].date(), today)
        self.assertEqual(daily[plugin._format_date(yesterday)], {"old-model": 3})
        self.assertEqual(daily[plugin._format_date(today)], {"glm-4.5": 9})

    def test_stale_cache_refetches_last_cached_date(self):
        api_key = "fake-key"
        today = plugin.datetime.now().astimezone().date()
        last_date = today - timedelta(days=3)
        calls = []

        def fake_fetch(_api_key, start_time, end_time):
            calls.append((start_time, end_time))
            return self.payload(
                [plugin._format_date(last_date), plugin._format_date(today)],
                [20, 5],
            )

        with tempfile.TemporaryDirectory() as cache_dir:
            plugin.save_chart_cache(api_key, {
                "version": plugin.CACHE_VERSION,
                "last_date": plugin._format_date(last_date),
                "days": {
                    plugin._format_date(last_date): {"old-model": 7},
                },
            }, cache_dir=cache_dir)

            with patch.object(plugin, "fetch_model_usage", side_effect=fake_fetch):
                daily = plugin.maintain_chart_cache(api_key, "zh-Hans", cache_dir=cache_dir)

        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0].date(), last_date)
        self.assertEqual(calls[0][1].date(), today)
        # The partially cached last day is replaced, not merged with old values.
        self.assertEqual(daily[plugin._format_date(last_date)], {"glm-4.5": 20})
        self.assertEqual(daily[plugin._format_date(today)], {"glm-4.5": 5})

    def test_refetch_with_empty_response_clears_old_day_values(self):
        api_key = "fake-key"
        today = plugin.datetime.now().astimezone().date()
        last_date = today - timedelta(days=1)

        def fake_fetch(_api_key, start_time, end_time):
            return {"data": {"x_time": [], "modelDataList": []}}

        with tempfile.TemporaryDirectory() as cache_dir:
            plugin.save_chart_cache(api_key, {
                "version": plugin.CACHE_VERSION,
                "last_date": plugin._format_date(last_date),
                "days": {
                    plugin._format_date(last_date): {"old-model": 7},
                },
            }, cache_dir=cache_dir)

            with patch.object(plugin, "fetch_model_usage", side_effect=fake_fetch):
                daily = plugin.maintain_chart_cache(api_key, "zh-Hans", cache_dir=cache_dir)

        self.assertEqual(daily[plugin._format_date(last_date)], {})
        self.assertEqual(daily[plugin._format_date(today)], {})

    def test_outdated_cache_version_triggers_full_fetch(self):
        api_key = "fake-key"
        today = plugin.datetime.now().astimezone().date()
        yesterday = today - timedelta(days=1)
        calls = []

        def fake_fetch(_api_key, start_time, end_time):
            calls.append((start_time, end_time))
            return self.payload([end_time.strftime("%Y-%m-%d")], [11])

        with tempfile.TemporaryDirectory() as cache_dir:
            plugin.save_chart_cache(api_key, {
                "version": plugin.CACHE_VERSION - 1,
                "last_date": str(today),
                "days": {str(yesterday): {"old-model": 99}},
            }, cache_dir=cache_dir)

            with patch.object(plugin, "fetch_model_usage", side_effect=fake_fetch):
                daily = plugin.maintain_chart_cache(api_key, "zh-Hans", cache_dir=cache_dir)

        self.assertEqual(len(calls), 1)
        self.assertEqual((calls[0][1].date() - calls[0][0].date()).days, 29)
        self.assertEqual(daily[str(yesterday)], {})

    def test_current_version_cache_discards_dates_outside_window(self):
        today = plugin.datetime.now().astimezone().date()
        expired = today - timedelta(days=30)
        cutoff = today - timedelta(days=29)
        with tempfile.TemporaryDirectory() as cache_dir:
            plugin.save_chart_cache("fake-key", {
                "version": plugin.CACHE_VERSION,
                "last_date": str(today),
                "days": {str(expired): {"model": 99}, str(cutoff): {"model": 7}},
            }, cache_dir=cache_dir)
            with patch.object(plugin, "fetch_model_usage", return_value=self.payload([str(today)], [3])):
                daily = plugin.maintain_chart_cache("fake-key", "en", cache_dir=cache_dir)
        self.assertNotIn(str(expired), daily)
        self.assertEqual(daily[str(cutoff)], {"model": 7})

    def test_new_cache_resumes_incremental_after_full_fetch(self):
        api_key = "fake-key"
        today = plugin.datetime.now().astimezone().date()

        def fake_fetch(_api_key, start_time, end_time):
            calls.append((start_time, end_time))
            return self.payload([end_time.strftime("%Y-%m-%d")], [3])

        with tempfile.TemporaryDirectory() as cache_dir:
            plugin.save_chart_cache(api_key, {
                "version": plugin.CACHE_VERSION - 1,
                "last_date": "2000-01-01",
                "days": {},
            }, cache_dir=cache_dir)

            calls = []
            with patch.object(plugin, "fetch_model_usage", side_effect=fake_fetch):
                plugin.maintain_chart_cache(api_key, "zh-Hans", cache_dir=cache_dir)
            self.assertEqual(len(calls), 1)
            self.assertEqual((calls[0][1].date() - calls[0][0].date()).days, 29)

            calls.clear()
            with patch.object(plugin, "fetch_model_usage", side_effect=fake_fetch):
                daily = plugin.maintain_chart_cache(api_key, "zh-Hans", cache_dir=cache_dir)

        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0].date(), today)
        self.assertEqual(calls[0][1].date(), today)
        self.assertEqual(daily[plugin._format_date(today)], {"glm-4.5": 3})


class TestTotalFallbackLabel(unittest.TestCase):
    def test_fallback_series_uses_localized_total_label(self):
        payload = {"data": {"x_time": ["2026-09-25"], "tokensUsage": [42]}}
        for language, label in (("zh-Hans", "总计"), ("en", "Total")):
            with self.subTest(language=language):
                bucket_values = {"2026-09-25": {}}
                plugin.apply_aligned_model_series(payload, bucket_values, "day", language)
                self.assertEqual(bucket_values["2026-09-25"].get(label), 42)

    def test_model_series_wins_over_total_fallback(self):
        payload = {
            "data": {
                "x_time": ["2026-09-25"],
                "modelDataList": [{"model": "glm-4.5", "tokensUsage": [7]}],
                "tokensUsage": [42],
            }
        }
        bucket_values = {"2026-09-25": {}}
        plugin.apply_aligned_model_series(payload, bucket_values, "day", "zh-Hans")
        self.assertEqual(bucket_values["2026-09-25"], {"glm-4.5": 7})


if __name__ == "__main__":
    unittest.main()
