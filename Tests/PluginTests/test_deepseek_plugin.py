"""Tests for deepseek-usage-plugin.py — run with: python3 -m unittest discover -s Tests/PluginTests"""

import importlib.util
import json
import sys
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import patch

PLUGIN_PATH = Path(__file__).parent.parent.parent / "Resources" / "BundledPlugins" / "deepseek-usage-plugin.py"


def load_plugin():
    plugin_dir = str(PLUGIN_PATH.parent)
    if plugin_dir not in sys.path:
        sys.path.insert(0, plugin_dir)
    spec = importlib.util.spec_from_file_location("deepseek_plugin", PLUGIN_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


plugin = load_plugin()

FAKE_BALANCE_RESPONSE = {"balance_infos": [{"currency": "CNY", "total_balance": "50.0"}]}


def run_main(argv_extra=None):
    """Run plugin main() with given argv, return parsed stdout JSON."""
    argv = ["deepseek-usage-plugin.py"] + (argv_extra or [])
    with patch("sys.argv", argv):
        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            try:
                plugin.main()
            except SystemExit:
                pass
            return json.loads(mock_out.getvalue())


class TestErrorFormat(unittest.TestCase):
    """Error output must use {"error": "message"} format with no items."""

    def test_missing_api_key_outputs_error_field_not_items(self):
        output = run_main([])
        self.assertIn("error", output)
        self.assertNotIn("items", output)

    def test_missing_api_key_exits_zero(self):
        with patch("sys.argv", ["deepseek-usage-plugin.py"]):
            with patch("sys.stdout", new_callable=StringIO):
                try:
                    plugin.main()
                    exit_code = 0
                except SystemExit as e:
                    exit_code = e.code or 0
        self.assertEqual(exit_code, 0)


class TestColorForBalance(unittest.TestCase):
    """color_for_balance(balance, limit): ratio<=10% red, <=20% orange, <=40% yellow, else blue."""

    def test_zero_balance_is_red(self):
        self.assertEqual(plugin.color_for_balance(0, 100), "red")

    def test_at_10_percent_boundary_is_red(self):
        self.assertEqual(plugin.color_for_balance(10, 100), "red")

    def test_just_above_10_percent_is_orange(self):
        self.assertEqual(plugin.color_for_balance(10.5, 100), "orange")

    def test_at_20_percent_boundary_is_orange(self):
        self.assertEqual(plugin.color_for_balance(20, 100), "orange")

    def test_at_40_percent_boundary_is_yellow(self):
        self.assertEqual(plugin.color_for_balance(40, 100), "yellow")

    def test_above_40_percent_is_blue(self):
        self.assertEqual(plugin.color_for_balance(41, 100), "blue")

    def test_above_limit_is_blue(self):
        self.assertEqual(plugin.color_for_balance(150, 100), "blue")

    def test_custom_limit_scales_thresholds(self):
        # With limit=200, 30 is 15% → orange (was yellow under 100-default before fix)
        self.assertEqual(plugin.color_for_balance(30, 200), "orange")

    def test_zero_limit_returns_none(self):
        self.assertIsNone(plugin.color_for_balance(50, 0))


class TestSchemaVersion(unittest.TestCase):
    """Success output must include schemaVersion."""

    def test_success_output_has_schema_version(self):
        argv = ["deepseek-usage-plugin.py", "--usageboard-param", "API_KEY=fake"]
        with patch("sys.argv", argv):
            with patch.object(plugin, "fetch_balance", return_value=FAKE_BALANCE_RESPONSE):
                with patch("sys.stdout", new_callable=StringIO) as mock_out:
                    try:
                        plugin.main()
                    except SystemExit:
                        pass
                    output = json.loads(mock_out.getvalue())
        self.assertIn("schemaVersion", output)


if __name__ == "__main__":
    unittest.main()
