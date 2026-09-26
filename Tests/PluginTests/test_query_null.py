import contextlib
import importlib.util
import io
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


class NullQueryTests(unittest.TestCase):
    def test_json_null_returns_error_document_for_all_query_clients(self):
        plugins = Path(__file__).resolve().parents[2] / "Resources/BundledPlugins"
        for name, fetch in [("kimi", "fetch_usage"), ("minimax", "fetch_remains"),
                            ("deepseek", "fetch_balance"), ("glm", "fetch_limits"),
                            ("tavily", "fetch_usage")]:
            with self.subTest(plugin=name):
                spec = importlib.util.spec_from_file_location(name, plugins / f"{name}-usage-plugin.py")
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                output = io.StringIO()
                with patch.object(sys, "argv", [name, "--usageboard-param", "API_KEY=fake"]), \
                     patch.object(module, fetch, return_value=json.loads("null")), \
                     contextlib.redirect_stdout(output):
                    self.assertEqual(module.main(), 0)
                self.assertTrue(json.loads(output.getvalue())["error"])
