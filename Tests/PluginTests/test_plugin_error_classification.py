"""Regression tests for bundled plugin error classification."""

import importlib.util
import json
import sys
import tempfile
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import patch


PLUGIN_DIR = Path(__file__).parent.parent.parent / "Resources" / "BundledPlugins"


def load_plugin(filename: str, module_name: str):
    plugin_dir = str(PLUGIN_DIR)
    if plugin_dir not in sys.path:
        sys.path.insert(0, plugin_dir)
    spec = importlib.util.spec_from_file_location(module_name, PLUGIN_DIR / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_main(module, argv: list[str]) -> dict:
    with patch("sys.argv", argv):
        with patch("sys.stdout", new_callable=StringIO) as output:
            try:
                module.main()
            except SystemExit:
                pass
            return json.loads(output.getvalue())


class TestBundledPluginErrorClassification(unittest.TestCase):
    def assert_usage_parse_failed(self, output: dict):
        self.assertEqual(output, {"error": "用量数据解析失败"})

    def test_tavily_build_error_is_not_reported_as_network_error(self):
        plugin = load_plugin("tavily-usage-plugin.py", "tavily_error_classification")

        with patch.object(plugin, "fetch_usage", return_value={}):
            with patch.object(plugin, "build_items", side_effect=RuntimeError("shape changed")):
                output = run_main(
                    plugin,
                    [
                        "tavily-usage-plugin.py",
                        "--usageboard-param",
                        "API_KEY=fake",
                        "--usageboard-param",
                        "USAGEBOARD_LANGUAGE=zh-Hans",
                    ],
                )

        self.assert_usage_parse_failed(output)

    def test_deepseek_build_error_is_not_reported_as_network_error(self):
        plugin = load_plugin("deepseek-usage-plugin.py", "deepseek_error_classification")

        with patch.object(plugin, "fetch_balance", return_value={}):
            with patch.object(plugin, "build_items", side_effect=RuntimeError("shape changed")):
                output = run_main(
                    plugin,
                    [
                        "deepseek-usage-plugin.py",
                        "--usageboard-param",
                        "API_KEY=fake",
                        "--usageboard-param",
                        "USAGEBOARD_LANGUAGE=zh-Hans",
                    ],
                )

        self.assert_usage_parse_failed(output)

    def test_minimax_build_error_is_not_reported_as_network_error(self):
        plugin = load_plugin("minimax-usage-plugin.py", "minimax_error_classification")

        payload = {"base_resp": {"status_code": 0}}
        with patch.object(plugin, "fetch_remains", return_value=payload):
            with patch.object(plugin, "build_items", side_effect=RuntimeError("shape changed")):
                output = run_main(
                    plugin,
                    [
                        "minimax-usage-plugin.py",
                        "--usageboard-param",
                        "API_KEY=fake",
                        "--usageboard-param",
                        "USAGEBOARD_LANGUAGE=zh-Hans",
                    ],
                )

        self.assert_usage_parse_failed(output)

    def test_glm_build_error_is_not_reported_as_network_error(self):
        plugin = load_plugin("glm-usage-plugin.py", "glm_error_classification")

        with patch.object(plugin, "fetch_limits", return_value={}):
            with patch.object(plugin, "build_items", side_effect=RuntimeError("shape changed")):
                output = run_main(
                    plugin,
                    [
                        "glm-usage-plugin.py",
                        "--usageboard-param",
                        "API_KEY=fake",
                        "--usageboard-param",
                        "USAGEBOARD_LANGUAGE=zh-Hans",
                    ],
                )

        self.assert_usage_parse_failed(output)

    def test_claude_api_parse_error_is_not_reported_as_network_error(self):
        plugin = load_plugin("claude-usage-plugin.py", "claude_error_classification")

        with tempfile.TemporaryDirectory() as data_dir:
            with patch.object(plugin, "load_oauth_token", return_value="token"):
                with patch.object(plugin, "fetch_oauth_usage", return_value=(None, plugin.PARSE_ERROR)):
                    output = run_main(
                        plugin,
                        [
                            "claude-usage-plugin.py",
                            "--usageboard-param",
                            f"DATA_DIR={data_dir}",
                            "--usageboard-param",
                            "USAGEBOARD_LANGUAGE=zh-Hans",
                        ],
                    )

        self.assert_usage_parse_failed(output)

    def test_claude_oauth_timeout_is_reported_as_timeout(self):
        plugin = load_plugin("claude-usage-plugin.py", "claude_timeout_classification")

        with tempfile.TemporaryDirectory() as data_dir:
            with patch.object(plugin, "load_oauth_token", return_value="token"):
                with patch.object(plugin, "fetch_oauth_usage", return_value=(None, plugin.REQUEST_TIMEOUT)):
                    output = run_main(
                        plugin,
                        [
                            "claude-usage-plugin.py",
                            "--usageboard-param",
                            f"DATA_DIR={data_dir}",
                            "--usageboard-param",
                            "USAGEBOARD_LANGUAGE=zh-Hans",
                        ],
                    )

        self.assertEqual(output, {"error": "请求超时，请检查网络"})

    def test_claude_oauth_network_error_is_not_reported_as_http_none(self):
        plugin = load_plugin("claude-usage-plugin.py", "claude_network_classification")

        with tempfile.TemporaryDirectory() as data_dir:
            with patch.object(plugin, "load_oauth_token", return_value="token"):
                with patch.object(plugin, "fetch_oauth_usage", return_value=(None, plugin.NETWORK_ERROR)):
                    output = run_main(
                        plugin,
                        [
                            "claude-usage-plugin.py",
                            "--usageboard-param",
                            f"DATA_DIR={data_dir}",
                            "--usageboard-param",
                            "USAGEBOARD_LANGUAGE=zh-Hans",
                        ],
                    )

        self.assertEqual(output, {"error": "网络连接失败，请检查网络"})


if __name__ == "__main__":
    unittest.main()
