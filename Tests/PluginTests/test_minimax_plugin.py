"""Tests for minimax-usage-plugin.py across supported Python interpreters."""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import patch


PLUGIN_PATH = Path(__file__).parent.parent.parent / "Resources" / "BundledPlugins" / "minimax-usage-plugin.py"
HOMEBREW_PREFIX = os.environ.get("HOMEBREW_PREFIX")
HOMEBREW_PYTHON = Path(HOMEBREW_PREFIX) / "bin/python3" if HOMEBREW_PREFIX else None
HOMEBREW_ENVIRONMENT = {
    "HOMEBREW_PREFIX": HOMEBREW_PREFIX or "",
    "HOMEBREW_CELLAR": os.environ.get("HOMEBREW_CELLAR", str(Path(HOMEBREW_PREFIX) / "Cellar")) if HOMEBREW_PREFIX else "",
    "HOMEBREW_REPOSITORY": os.environ.get("HOMEBREW_REPOSITORY", HOMEBREW_PREFIX or ""),
}


def expected_interpreters():
    interpreters = [Path("/usr/bin/python3")]
    if HOMEBREW_PYTHON is not None:
        interpreters.append(HOMEBREW_PYTHON)
    return interpreters


def available_interpreters():
    for interpreter in expected_interpreters():
        if interpreter.exists():
            yield interpreter


def run_plugin_with_interpreter(interpreter: Path) -> dict:
    payload = {
        "base_resp": {"status_code": 0},
        "model_remains": [
            {
                "model_name": "general",
                "start_time": 0,
                "end_time": 5 * 60 * 60 * 1000,
                "remains_time": 1,
                "weekly_start_time": 0,
                "weekly_end_time": 7 * 24 * 60 * 60 * 1000,
                "weekly_remains_time": 2,
                "current_interval_remaining_percent": 98,
                "current_weekly_remaining_percent": 99,
            },
            {
                "model_name": "video",
                "start_time": 0,
                "end_time": 24 * 60 * 60 * 1000,
                "remains_time": 3,
                "weekly_start_time": 0,
                "weekly_end_time": 7 * 24 * 60 * 60 * 1000,
                "weekly_remains_time": 4,
                "current_interval_remaining_percent": 100,
                "current_weekly_remaining_percent": 100,
            },
        ],
    }
    wrapper = textwrap.dedent(
        f"""
        import importlib.util
        import sys
        from pathlib import Path

        plugin_path = {str(PLUGIN_PATH)!r}
        plugin_dir = str(Path(plugin_path).parent)
        if plugin_dir not in sys.path:
            sys.path.insert(0, plugin_dir)
        payload = {payload!r}

        spec = importlib.util.spec_from_file_location("minimax_plugin", plugin_path)
        plugin = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(plugin)
        plugin.fetch_remains = lambda api_key: payload
        sys.argv = ["minimax-usage-plugin.py", "--usageboard-param", "API_KEY=fake"]
        raise SystemExit(plugin.main())
        """
    )

    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False, encoding="utf-8") as file:
        file.write(wrapper)
        wrapper_path = file.name

    try:
        env = os.environ.copy()
        env.update({
            "PYTHONIOENCODING": "utf-8",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
        })
        if HOMEBREW_PYTHON is not None and interpreter == HOMEBREW_PYTHON:
            env.update(HOMEBREW_ENVIRONMENT)
        result = subprocess.run(
            [str(interpreter), wrapper_path],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            env=env,
        )
    finally:
        os.unlink(wrapper_path)

    return json.loads(result.stdout)


class TestMiniMaxInterpreterCompatibility(unittest.TestCase):
    def test_output_decodes_with_expected_interpreters(self):
        interpreters = list(available_interpreters())
        if not interpreters:
            self.skipTest("No configured Python interpreters are available")

        for interpreter in interpreters:
            with self.subTest(interpreter=str(interpreter)):
                output = run_plugin_with_interpreter(interpreter)
                self.assertEqual(output["schemaVersion"], 1)
                self.assertEqual(output["badge"], "Plus")
                self.assertEqual(len(output["items"]), 4)
                first = output["items"][0]
                self.assertEqual(first["displayStyle"], "percent")
                self.assertEqual(first["limit"], 100)
                self.assertEqual(first["used"], 2)
                self.assertEqual(first["status"], "normal")
                self.assertIn(".", first["resetAt"])
                self.assertTrue(first["resetAt"].endswith("Z"))


def load_plugin():
    plugin_dir = str(PLUGIN_PATH.parent)
    if plugin_dir not in sys.path:
        sys.path.insert(0, plugin_dir)
    spec = importlib.util.spec_from_file_location("minimax_plugin_main", PLUGIN_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


VALID_REMAINS = {
    "model_remains": [
        {
            "model_name": "general",
            "start_time": 0,
            "end_time": 5 * 60 * 60 * 1000,
            "remains_time": 1,
            "weekly_start_time": 0,
            "weekly_end_time": 7 * 24 * 60 * 60 * 1000,
            "weekly_remains_time": 2,
            "current_interval_remaining_percent": 98,
            "current_weekly_remaining_percent": 99,
        },
    ],
}


class TestBaseRespHandling(unittest.TestCase):
    plugin = load_plugin()

    def _run_main(self, payload):
        argv = ["minimax-usage-plugin.py", "--usageboard-param", "API_KEY=fake"]
        with patch.object(sys, "argv", argv), \
             patch.object(self.plugin, "fetch_remains", return_value=payload), \
             patch("sys.stdout", new_callable=StringIO) as out:
            self.plugin.main()
        return json.loads(out.getvalue())

    def test_success_with_base_resp(self):
        output = self._run_main({"base_resp": {"status_code": 0}, **VALID_REMAINS})
        self.assertNotIn("error", output)
        self.assertEqual(len(output["items"]), 2)

    def test_null_base_resp_with_usage_is_parse_failure(self):
        output = self._run_main({"base_resp": None, **VALID_REMAINS})
        self.assertIn("error", output)

    def test_missing_base_resp_with_usage_succeeds(self):
        output = self._run_main(dict(VALID_REMAINS))
        self.assertNotIn("error", output)
        self.assertEqual(len(output["items"]), 2)

    def test_null_base_resp_without_usage_is_not_fake_success(self):
        output = self._run_main({"base_resp": None})
        self.assertIn("error", output)

    def test_error_code_2049_reports_invalid_key(self):
        output = self._run_main({"base_resp": {"status_code": 2049}, **VALID_REMAINS})
        self.assertIn("error", output)

    def test_error_code_with_message(self):
        output = self._run_main(
            {"base_resp": {"status_code": 1002, "status_msg": "rate limited"}, **VALID_REMAINS}
        )
        self.assertEqual(output["error"], "rate limited (1002)")

    def test_non_dict_base_resp_is_parse_failure(self):
        output = self._run_main({"base_resp": "oops", **VALID_REMAINS})
        self.assertIn("error", output)


if __name__ == "__main__":
    unittest.main()
