import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Resources/BundledPlugins"))
from _common import load_json_cache, numeric, save_json_cache


class TestCommonCache(unittest.TestCase):
    def test_invalid_cache_shapes_are_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cache.json"
            for payload in [None, [], 1, {"version": 1, "days": []}, {"version": 2, "days": {}}]:
                path.write_text(json.dumps(payload))
                self.assertIsNone(load_json_cache(str(path), 1))

    def test_failed_publish_keeps_previous_cache_and_cleans_temporary_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cache.json"
            old = {"version": 1, "days": {"2026-09-01": {"tokens": 12}}}
            save_json_cache(str(path), old)
            with patch("_common.os.replace", side_effect=OSError("disk full")):
                save_json_cache(str(path), {"version": 1, "days": {}})
            self.assertEqual(load_json_cache(str(path), 1), old)
            self.assertEqual(list(Path(directory).iterdir()), [path])
            save_json_cache(str(path), {"version": 1, "days": {}})
            self.assertEqual(load_json_cache(str(path), 1)["days"], {})

    def test_numeric_rejects_non_finite_and_overflow(self):
        for value in [float("nan"), float("inf"), "-Infinity", "1e999", 10**1000]:
            self.assertEqual(numeric(value), 0)
        self.assertEqual(numeric("12.5"), 12.5)
