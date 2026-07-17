"""Tests for kimi-usage-plugin.py — run with: python3 -m pytest Tests/PluginTests/test_kimi_plugin.py"""

import importlib.util
import json
import sys
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import patch

PLUGIN_PATH = Path(__file__).parent.parent.parent / "Resources" / "BundledPlugins" / "kimi-usage-plugin.py"


def load_plugin():
    plugin_dir = str(PLUGIN_PATH.parent)
    if plugin_dir not in sys.path:
        sys.path.insert(0, plugin_dir)
    spec = importlib.util.spec_from_file_location("kimi_plugin", PLUGIN_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


plugin = load_plugin()

# Mirrors the real https://api.kimi.com/coding/v1/usages response shape.
FAKE_USAGE = {
    "user": {
        "userId": "test-user",
        "membership": {"level": "LEVEL_INTERMEDIATE"},
    },
    "usage": {
        "limit": "100",
        "remaining": "40",
        "resetTime": "2026-07-24T14:16:52Z",
    },
    "limits": [
        {
            "window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
            "detail": {"limit": "100", "used": "1", "remaining": "99", "resetTime": "2026-07-17T19:16:52Z"},
        }
    ],
    "totalQuota": {"limit": "100", "remaining": "99"},
}


def run_main(argv_extra=None, fake_response=None):
    """Run plugin main() with given argv, optionally patching fetch_usage, return parsed stdout JSON."""
    argv = ["kimi-usage-plugin.py"] + (argv_extra or [])
    with patch("sys.argv", argv):
        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            if fake_response is not None:
                with patch.object(plugin, "fetch_usage", return_value=fake_response):
                    try:
                        plugin.main()
                    except SystemExit:
                        pass
            else:
                try:
                    plugin.main()
                except SystemExit:
                    pass
            return json.loads(mock_out.getvalue())


def translate():
    return plugin.make_translator(plugin.TRANSLATIONS)


class TestErrorFormat(unittest.TestCase):
    """Error output must use {"error": "message"} format with no items."""

    def test_missing_api_key_outputs_error_field_not_items(self):
        output = run_main([])
        self.assertIn("error", output)
        self.assertNotIn("items", output)

    def test_missing_api_key_exits_zero(self):
        with patch("sys.argv", ["kimi-usage-plugin.py"]):
            with patch("sys.stdout", new_callable=StringIO):
                try:
                    plugin.main()
                    exit_code = 0
                except SystemExit as e:
                    exit_code = e.code or 0
        self.assertEqual(exit_code, 0)

    def test_empty_payload_outputs_no_quota_error(self):
        output = run_main(["--usageboard-param", "API_KEY=fake"], fake_response={})
        self.assertIn("error", output)
        self.assertNotIn("items", output)


class TestBuildItems(unittest.TestCase):
    """build_items parses the 5-hour window, weekly quota, and total quota."""

    def test_parses_window_and_weekly(self):
        items, badge = plugin.build_items(FAKE_USAGE, "zh-Hans", translate())
        self.assertEqual(badge, "INTERMEDIATE")
        self.assertEqual(len(items), 2)

        window = next(item for item in items if item["id"] == "kimi-window-300")
        # detail.used="1" (explicit) → 1/100 = 1%: normal, blue
        self.assertEqual(window["used"], 1)
        self.assertEqual(window["limit"], 100)
        self.assertEqual(window["status"], "normal")
        self.assertEqual(window["color"], "blue")
        self.assertIn("5 小时", window["name"])
        self.assertEqual(window["resetAt"], "2026-07-17T19:16:52Z")

        weekly = next(item for item in items if item["id"] == "kimi-weekly")
        # limit 100 - remaining 40 = 60 → 60%: normal, yellow
        self.assertEqual(weekly["used"], 60)
        self.assertEqual(weekly["limit"], 100)
        self.assertEqual(weekly["status"], "normal")
        self.assertEqual(weekly["color"], "yellow")
        self.assertEqual(weekly["resetAt"], "2026-07-24T14:16:52Z")

    def test_prefers_detail_used_over_limit_minus_remaining(self):
        payload = {
            "limits": [
                {"window": {"duration": 300}, "detail": {"limit": "100", "used": "5", "remaining": "90"}}
            ]
        }
        items, _ = plugin.build_items(payload, "zh-Hans", translate())
        window = items[0]
        # explicit used=5 wins over 100-90=10
        self.assertEqual(window["used"], 5)

    def test_falls_back_to_limit_minus_remaining_without_used(self):
        payload = {
            "limits": [
                {"window": {"duration": 300}, "detail": {"limit": "100", "remaining": "30"}}
            ]
        }
        items, _ = plugin.build_items(payload, "zh-Hans", translate())
        self.assertEqual(items[0]["used"], 70)

    def test_normalizes_window_timeunit_hour(self):
        payload = {
            "limits": [
                {"window": {"duration": 5, "timeUnit": "TIME_UNIT_HOUR"},
                 "detail": {"limit": "100", "used": "1", "remaining": "99"}}
            ]
        }
        items, _ = plugin.build_items(payload, "zh-Hans", translate())
        # 5 hours normalized to 300 minutes → same id/label as the 300-minute window
        self.assertEqual(items[0]["id"], "kimi-window-300")
        self.assertIn("5 小时", items[0]["name"])

    def test_english_window_label(self):
        items, _ = plugin.build_items(FAKE_USAGE, "en", translate())
        window = next(item for item in items if item["id"] == "kimi-window-300")
        self.assertIn("5 hours", window["name"])

    def test_skips_zero_limit_window(self):
        payload = {"limits": [{"window": {"duration": 300}, "detail": {"limit": 0, "remaining": 0}}]}
        items, badge = plugin.build_items(payload, "zh-Hans", translate())
        self.assertEqual(items, [])
        self.assertIsNone(badge)


class TestExtractPlan(unittest.TestCase):
    """Badge is read from user.membership.level with the LEVEL_ prefix stripped."""

    def test_from_membership_level(self):
        payload = {"user": {"membership": {"level": "LEVEL_ADVANCED"}}}
        self.assertEqual(plugin.extract_plan(payload), "ADVANCED")

    def test_strips_plan_and_type_prefixes(self):
        self.assertEqual(plugin.normalize_plan("PLAN_PRO"), "PRO")
        self.assertEqual(plugin.normalize_plan("TYPE_PURCHASE"), "PURCHASE")
        self.assertEqual(plugin.normalize_plan("Andante"), "Andante")

    def test_falls_back_to_top_level_plan(self):
        self.assertEqual(plugin.extract_plan({"plan": "Andante"}), "Andante")

    def test_returns_none_when_absent(self):
        self.assertIsNone(plugin.extract_plan({}))


class TestMainFlow(unittest.TestCase):
    """main() with patched fetch_usage produces success payload and resolves badge."""

    def test_success_output_has_schema_version_and_badge(self):
        output = run_main(["--usageboard-param", "API_KEY=fake"], fake_response=FAKE_USAGE)
        self.assertIn("schemaVersion", output)
        self.assertEqual(output["badge"], "INTERMEDIATE")
        self.assertNotIn("badgeColor", output)
        self.assertEqual(len(output["items"]), 2)

    def test_manual_plan_keeps_name_with_color(self):
        output = run_main(
            ["--usageboard-param", "API_KEY=fake", "--usageboard-param", "PLAN=Allegro"],
            fake_response=FAKE_USAGE,
        )
        self.assertEqual(output["badge"], "Allegro")
        self.assertEqual(output["badgeColor"], "orange")

    def test_plan_badge_keeps_name_with_color(self):
        cases = {"Andante": "gray", "Moderato": "indigo", "Allegretto": "blue", "Allegro": "orange"}
        for plan, color in cases.items():
            output = run_main(
                ["--usageboard-param", "API_KEY=fake", "--usageboard-param", f"PLAN={plan}"],
                fake_response=FAKE_USAGE,
            )
            self.assertEqual(output["badge"], plan, f"badge text should stay as {plan}")
            self.assertEqual(output["badgeColor"], color, f"PLAN={plan} color")

    def test_empty_plan_value_falls_back_to_auto_badge(self):
        output = run_main(
            ["--usageboard-param", "API_KEY=fake", "--usageboard-param", "PLAN="],
            fake_response=FAKE_USAGE,
        )
        self.assertEqual(output["badge"], "INTERMEDIATE")


if __name__ == "__main__":
    unittest.main()
