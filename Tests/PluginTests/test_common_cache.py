import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Resources/BundledPlugins"))
import _common
from _common import (
    fetch_json,
    filter_by_mtime,
    load_json_cache,
    normalize_model_name,
    numeric,
    save_json_cache,
)


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


class TestNormalizeModelName(unittest.TestCase):
    def test_last_slash_segment_wins(self):
        self.assertEqual(normalize_model_name("deepseek/deepseek-v4-flash"), "deepseek-v4-flash")
        self.assertEqual(normalize_model_name("a/b/gpt-5"), "gpt-5")

    def test_plain_name_is_unchanged(self):
        self.assertEqual(normalize_model_name("claude-opus-4-7"), "claude-opus-4-7")
        self.assertEqual(normalize_model_name("  gpt-5  "), "gpt-5")

    def test_trailing_effort_suffix_is_stripped(self):
        self.assertEqual(normalize_model_name("gpt-5(high)"), "gpt-5")
        self.assertEqual(normalize_model_name("gpt-5 (high)"), "gpt-5")
        self.assertEqual(normalize_model_name("claude-opus-4-7（medium）"), "claude-opus-4-7")
        self.assertEqual(normalize_model_name("openai/gpt-5(max)"), "gpt-5")

    def test_unusable_values_return_none(self):
        for value in [None, "", "   ", "deepseek/", "(high)", 123, {"model": "gpt-5"}]:
            self.assertIsNone(normalize_model_name(value))


class TestFilterByMtime(unittest.TestCase):
    def test_keeps_recent_files_and_skips_vanished_ones(self):
        with tempfile.TemporaryDirectory() as directory:
            recent = Path(directory) / "recent.jsonl"
            old = Path(directory) / "old.jsonl"
            recent.write_text("{}")
            old.write_text("{}")
            import os
            cutoff = recent.stat().st_mtime - 1
            import time
            os.utime(old, (cutoff - 100, cutoff - 100))
            # stat 抛 FileNotFoundError 的文件（glob 后被删除）必须跳过而非抛异常。
            vanished = str(Path(directory) / "vanished.jsonl")
            files = [str(recent), vanished, str(old)]
            self.assertEqual(filter_by_mtime(files, cutoff), [str(recent)])

    def test_missing_file_counts_as_not_matching(self):
        self.assertFalse(_common.mtime_at_least("/nonexistent/should-not-raise", 0))


class _FakeResponse:
    def __init__(self, body: bytes):
        self._body = body

    def read(self) -> bytes:
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class TestFetchJson(unittest.TestCase):
    def test_no_redirect_handler_refuses_redirects(self):
        # redirect_request 返回 None 时 urllib 将 30x 作为 HTTPError 抛出，凭证不会转发。
        handler = _common._NoRedirect()
        self.assertIsNone(
            handler.redirect_request(None, None, 302, "Found", {}, "https://evil.example/steal")
        )

    def test_fetch_json_returns_decoded_payload_and_passes_headers(self):
        captured = {}

        class FakeOpener:
            def open(self, request, timeout):
                captured["url"] = request.full_url
                captured["auth"] = request.get_header("Authorization")
                captured["timeout"] = timeout
                return _FakeResponse('{"ok": true}'.encode("utf-8"))

        with patch.object(_common.urllib.request, "build_opener", return_value=FakeOpener()):
            payload = fetch_json(
                "https://api.example.com/v1/usage",
                headers={"Authorization": "Bearer token"},
                timeout=6,
            )
        self.assertEqual(payload, {"ok": True})
        self.assertEqual(captured["url"], "https://api.example.com/v1/usage")
        self.assertEqual(captured["auth"], "Bearer token")
        self.assertEqual(captured["timeout"], 6)

    def test_fetch_json_propagates_decode_errors(self):
        class FakeOpener:
            def open(self, request, timeout):
                return _FakeResponse(b"\xff\xfe not utf-8")

        with patch.object(_common.urllib.request, "build_opener", return_value=FakeOpener()):
            with self.assertRaises(UnicodeDecodeError):
                fetch_json("https://api.example.com/v1/usage")
