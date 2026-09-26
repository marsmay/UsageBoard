"""Tests for kimi-usage-plugin.py — run with: python3 -m unittest discover -s Tests/PluginTests"""

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

# Legacy usage response including membership; current responses can omit user.
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


class TestParseResetTime(unittest.TestCase):
    def test_z_suffix_kept(self):
        self.assertEqual(plugin.parse_reset_time("2026-07-24T14:16:52Z"), "2026-07-24T14:16:52Z")

    def test_explicit_offset_kept(self):
        self.assertEqual(
            plugin.parse_reset_time("2026-07-24T22:16:52+08:00"),
            "2026-07-24T22:16:52+08:00",
        )

    def test_naive_timestamp_omitted(self):
        # Naive timestamps have no verified timezone; they must be omitted
        # rather than passed through (Core would reject the whole output).
        self.assertIsNone(plugin.parse_reset_time("2026-07-24T14:16:52"))

    def test_invalid_and_empty_values_omitted(self):
        for value in ("not-a-time", "", None, 123, {}):
            self.assertIsNone(plugin.parse_reset_time(value), repr(value))

    def test_bad_reset_time_does_not_break_other_items(self):
        payload = {
            "limits": [
                {"window": {"duration": 300, "timeUnit": "min"},
                 "detail": {"limit": "100", "used": "1", "resetTime": "2026-07-17T19:16:52"}}
            ],
            "usage": {"limit": "100", "remaining": "40", "resetTime": "2026-07-24T14:16:52Z"},
        }
        items = plugin.build_items(payload, "zh-Hans", translate())
        window = next(item for item in items if item["id"] == "kimi-window-300")
        weekly = next(item for item in items if item["id"] == "kimi-weekly")
        self.assertIsNone(window["resetAt"])
        self.assertEqual(window["used"], 1)
        self.assertEqual(weekly["resetAt"], "2026-07-24T14:16:52Z")


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
        items = plugin.build_items(FAKE_USAGE, "zh-Hans", translate())
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
        items = plugin.build_items(payload, "zh-Hans", translate())
        window = items[0]
        # explicit used=5 wins over 100-90=10
        self.assertEqual(window["used"], 5)

    def test_falls_back_to_limit_minus_remaining_without_used(self):
        payload = {
            "limits": [
                {"window": {"duration": 300}, "detail": {"limit": "100", "remaining": "30"}}
            ]
        }
        items = plugin.build_items(payload, "zh-Hans", translate())
        self.assertEqual(items[0]["used"], 70)

    def test_null_used_does_not_mask_remaining_fallback(self):
        # 服务端显式 "used": null 不得按 0 处理，需继续走 limit - remaining 回退。
        payload = {
            "limits": [
                {"window": {"duration": 300}, "detail": {"limit": "100", "used": None, "remaining": "40"}}
            ]
        }
        items = plugin.build_items(payload, "zh-Hans", translate())
        self.assertEqual(items[0]["used"], 60)

    def test_normalizes_window_timeunit_hour(self):
        payload = {
            "limits": [
                {"window": {"duration": 5, "timeUnit": "TIME_UNIT_HOUR"},
                 "detail": {"limit": "100", "used": "1", "remaining": "99"}}
            ]
        }
        items = plugin.build_items(payload, "zh-Hans", translate())
        # 5 hours normalized to 300 minutes → same id/label as the 300-minute window
        self.assertEqual(items[0]["id"], "kimi-window-300")
        self.assertIn("5 小时", items[0]["name"])

    def test_english_window_label(self):
        items = plugin.build_items(FAKE_USAGE, "en", translate())
        window = next(item for item in items if item["id"] == "kimi-window-300")
        self.assertIn("5 hours", window["name"])

    def test_skips_zero_limit_window(self):
        payload = {"limits": [{"window": {"duration": 300}, "detail": {"limit": 0, "remaining": 0}}]}
        items = plugin.build_items(payload, "zh-Hans", translate())
        self.assertEqual(items, [])


class TestMainFlow(unittest.TestCase):
    """main() with patched fetch_usage produces success payload and resolves badge."""

    def test_success_output_has_schema_version_and_badge(self):
        output = run_main(["--usageboard-param", "API_KEY=fake",
                           "--usageboard-param", "PLAN=Pro"], fake_response=FAKE_USAGE)
        self.assertIn("schemaVersion", output)
        self.assertEqual(output["badge"], "Pro")
        self.assertEqual(output["badgeColor"], "blue")
        self.assertEqual(len(output["items"]), 2)

    def test_configured_plans_set_badge_with_existing_colors(self):
        # FAKE_USAGE 携带旧版 user.membership 字段，验证响应中的会员等级被完全忽略。
        for plan, color in [("Go", "gray"), ("Plus", "indigo"),
                            ("Pro", "blue"), ("Max", "orange")]:
            with self.subTest(plan=plan):
                output = run_main(["--usageboard-param", "API_KEY=fake",
                                   "--usageboard-param", f"PLAN={plan}"], fake_response=FAKE_USAGE)
                self.assertEqual(output["badge"], plan)
                self.assertEqual(output["badgeColor"], color)
                self.assertEqual(len(output["items"]), 2)

    def test_invalid_configured_plan_omits_badge(self):
        # 旧版套餐名（Andante/Adagio 等）与未知值均视为无效，直接省略徽标。
        for plan in ["", "unknown", "Andante", "Adagio"]:
            output = run_main(["--usageboard-param", "API_KEY=fake",
                               "--usageboard-param", f"PLAN={plan}"], fake_response=FAKE_USAGE)
            self.assertNotIn("badge", output)
            self.assertNotIn("badgeColor", output)

    def test_plan_metadata_exposes_four_choices_in_scanned_header(self):
        lines = PLUGIN_PATH.read_text().splitlines()[:80]
        start = lines.index("# UsageBoardPlugin:")
        end = lines.index("# /UsageBoardPlugin")
        metadata = json.loads("\n".join(line[2:] for line in lines[start + 1:end]))
        plan = metadata["parameters"][0]
        self.assertEqual(plan["name"], "PLAN")
        self.assertEqual(plan["type"], "choice")
        self.assertEqual(plan["defaultValue"], "Go")
        self.assertEqual([o["value"] for o in plan["options"]],
                         ["Go", "Plus", "Pro", "Max"])
        self.assertEqual(metadata["parameters"][1]["name"], "API_KEY")

    def test_response_membership_level_is_ignored(self):
        # 旧版响应即使携带有效 user.membership.level 也不再产生徽标，套餐仅来自手动配置。
        output = run_main(["--usageboard-param", "API_KEY=fake"], fake_response=FAKE_USAGE)
        self.assertEqual(len(output["items"]), 2)
        self.assertNotIn("badge", output)
        self.assertNotIn("badgeColor", output)

    def test_current_usage_response_without_user_keeps_quotas_without_guessing_plan(self):
        payload = dict(FAKE_USAGE)
        del payload["user"]
        payload["usages"] = {"limit_5h": {"used_ratio": 0}, "limit_7d": {"used_ratio": 0.5}}
        payload["booster_wallet"] = {"balance": {"subscriptionId": "not-a-plan"}}
        output = run_main(["--usageboard-param", "API_KEY=fake"], fake_response=payload)
        self.assertEqual(len(output["items"]), 2)
        self.assertNotIn("badge", output)
        self.assertNotIn("badgeColor", output)


if __name__ == "__main__":
    unittest.main()
