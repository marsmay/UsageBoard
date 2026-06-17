"""Tests for codex-usage-plugin.py — run with: python3 -m pytest Tests/PluginTests/test_codex_plugin.py"""

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

PLUGIN_PATH = Path(__file__).parent.parent.parent / "Resources" / "BundledPlugins" / "codex-usage-plugin.py"


def load_plugin():
    plugin_dir = str(PLUGIN_PATH.parent)
    if plugin_dir not in sys.path:
        sys.path.insert(0, plugin_dir)
    spec = importlib.util.spec_from_file_location("codex_plugin", PLUGIN_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


plugin = load_plugin()


class TestAuthCredentials(unittest.TestCase):
    def test_reads_credentials_from_tokens_object(self):
        auth = {
            "tokens": {
                "access_token": "nested-token",
                "account_id": "nested-account",
            }
        }

        self.assertEqual(
            plugin.extract_auth_credentials(auth),
            ("nested-token", "nested-account"),
        )

    def test_reads_credentials_from_top_level_fields(self):
        auth = {
            "access_token": "top-token",
            "account_id": "top-account",
        }

        self.assertEqual(
            plugin.extract_auth_credentials(auth),
            ("top-token", "top-account"),
        )

    def test_falls_back_per_field_when_tokens_object_is_partial(self):
        auth = {
            "tokens": {"access_token": "nested-token"},
            "account_id": "top-account",
        }

        self.assertEqual(
            plugin.extract_auth_credentials(auth),
            ("nested-token", "top-account"),
        )

    def test_rejects_blank_credentials(self):
        auth = {
            "access_token": " ",
            "account_id": "",
        }

        self.assertEqual(plugin.extract_auth_credentials(auth), (None, None))


class TestBuildItems(unittest.TestCase):
    def test_build_items_reads_current_rate_limit_payload(self):
        payload = {
            "plan_type": "plus",
            "rate_limit": {
                "primary_window": {
                    "used_percent": 25,
                    "reset_at": 1_800_000_000,
                },
                "secondary_window": {
                    "used_percent": 40,
                    "reset_at": 1_800_010_000,
                },
            },
        }

        items, badge = plugin.build_items(payload, "zh-Hans")

        self.assertEqual(badge, "plus")
        self.assertEqual([item["id"] for item in items], ["codex-five-hour", "codex-weekly"])
        self.assertEqual(items[0]["name"], "5 小时用量")
        self.assertEqual(items[0]["used"], 25)
        self.assertEqual(items[1]["name"], "周用量")
        self.assertEqual(items[1]["used"], 40)


class TestChartCacheRecovery(unittest.TestCase):
    def _empty_chart(self, _files, buckets, bucket_unit, _period, _language):
        return {
            "buckets": [
                {"id": plugin.bucket_id(bucket, bucket_unit), "segments": []}
                for bucket in buckets
            ]
        }

    def test_invalid_last_date_rebuilds_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache_path = Path(tmp) / plugin.CACHE_FILENAME
            cache_path.write_text(
                json.dumps({"version": plugin.CACHE_VERSION, "last_date": "bad-date", "days": {}}),
                encoding="utf-8",
            )

            with patch.object(plugin, "collect_session_files", return_value=[]), \
                 patch.object(plugin, "parse_sessions_for_chart", side_effect=self._empty_chart):
                daily = plugin.maintain_chart_cache(tmp, "zh-Hans")

        self.assertIsInstance(daily, dict)

    def test_invalid_cached_day_key_is_skipped(self):
        today = plugin.datetime.now().date()
        yesterday = today - plugin.timedelta(days=1)

        with tempfile.TemporaryDirectory() as tmp:
            cache_path = Path(tmp) / plugin.CACHE_FILENAME
            cache_path.write_text(
                json.dumps({
                    "version": plugin.CACHE_VERSION,
                    "last_date": plugin._format_date(today),
                    "days": {
                        "bad-date": {"stale": 1},
                        plugin._format_date(yesterday): {"old-model": 2},
                    },
                }),
                encoding="utf-8",
            )

            with patch.object(plugin, "collect_session_files", return_value=[]), \
                 patch.object(plugin, "parse_sessions_for_chart", side_effect=self._empty_chart):
                daily = plugin.maintain_chart_cache(tmp, "zh-Hans")

        self.assertNotIn("bad-date", daily)
        self.assertEqual(daily.get(plugin._format_date(yesterday)), {"old-model": 2})


if __name__ == "__main__":
    unittest.main()
