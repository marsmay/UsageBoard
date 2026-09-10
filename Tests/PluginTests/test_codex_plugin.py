"""Tests for codex-usage-plugin.py — run with: python3 -m pytest Tests/PluginTests/test_codex_plugin.py"""

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from datetime import date, datetime, time, timedelta
from io import StringIO
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

    def test_build_items_classifies_single_primary_weekly_window_by_duration(self):
        payload = {
            "plan_type": "team",
            "rate_limit": {
                "primary_window": {
                    "used_percent": 0,
                    "limit_window_seconds": 7 * 24 * 60 * 60,
                    "reset_at": 1_800_000_000,
                },
                "secondary_window": None,
            },
        }

        items, badge = plugin.build_items(payload, "zh-Hans")

        self.assertEqual(badge, "team")
        self.assertEqual([item["id"] for item in items], ["codex-weekly"])
        self.assertEqual(items[0]["name"], "周用量")
        self.assertEqual(items[0]["used"], 0)


class TestStatsPeriodNone(unittest.TestCase):
    USAGE_PAYLOAD = {
        "plan_type": "pro",
        "rate_limit": {"primary_window": {"used_percent": 10, "reset_time_ms": 1780000000000}},
    }

    def _run_main(self, extra_params, cache_side_effect=None, cache_return=None):
        argv = ["codex"]
        for key, value in extra_params:
            argv += ["--usageboard-param", f"{key}={value}"]
        with patch.object(sys, "argv", argv), \
             patch.object(plugin, "load_auth", return_value={"tokens": {"access_token": "t", "account_id": "a"}}), \
             patch.object(plugin, "fetch_usage", return_value=self.USAGE_PAYLOAD), \
             patch.object(plugin, "fetch_reset_credits", side_effect=RuntimeError("boom")), \
             patch.object(plugin, "maintain_chart_cache", side_effect=cache_side_effect, return_value=cache_return) as cache_mock, \
             patch("sys.stdout", new_callable=StringIO) as out:
            code = plugin.main()
        return code, json.loads(out.getvalue()), cache_mock

    def test_none_period_skips_stats_and_omits_chart(self):
        code, output, cache_mock = self._run_main(
            [("STAT_PERIOD", "none")],
            cache_side_effect=AssertionError("should not scan"),
        )

        self.assertEqual(code, 0)
        self.assertNotIn("chart", output)
        self.assertEqual(len(output["items"]), 1)
        cache_mock.assert_not_called()

    def test_default_period_still_builds_chart(self):
        code, output, cache_mock = self._run_main([], cache_return={})

        self.assertEqual(code, 0)
        self.assertIn("chart", output)
        cache_mock.assert_called_once()


class TestParseResetCredits(unittest.TestCase):
    def test_keeps_only_available_credits_sorted_by_expiry(self):
        payload = {
            "available_count": 2,
            "credits": [
                {"id": "c-used", "status": "redeemed", "expires_at": "2026-07-01T00:00:00Z"},
                {"id": "c-b", "status": "available", "expires_at": "2026-07-17T00:00:00Z"},
                {"id": "c-a", "status": "available", "expires_at": "2026-07-10T00:00:00Z"},
            ],
        }

        credits = plugin.parse_reset_credits(payload)

        self.assertEqual([c["id"] for c in credits], ["c-a", "c-b"])
        self.assertEqual(credits[0]["expiresAt"], "2026-07-10T00:00:00Z")

    def test_drops_credits_without_parseable_expiry(self):
        payload = {
            "credits": [
                {"id": "c-no-expiry", "status": "available"},
                {"id": "c-bad-expiry", "status": "available", "expires_at": "not-a-date"},
                {"status": "available", "expires_at": "2026-08-01T12:00:00+08:00"},
            ],
        }

        credits = plugin.parse_reset_credits(payload)

        self.assertEqual(len(credits), 1)
        self.assertEqual(credits[0]["id"], "credit-2")
        self.assertEqual(credits[0]["expiresAt"], "2026-08-01T04:00:00Z")

    def test_missing_or_malformed_credits_field_yields_empty_list(self):
        self.assertEqual(plugin.parse_reset_credits({}), [])
        self.assertEqual(plugin.parse_reset_credits({"credits": "nope"}), [])
        self.assertEqual(plugin.parse_reset_credits({"credits": [None, 42]}), [])


class TestCollectSessionFiles(unittest.TestCase):
    """A session file is named after its start date, but entries written after
    local midnight belong to the next day. Incremental scans keyed by the next
    day must still pick up such files, or that day's tokens are undercounted."""

    def _make_session(self, sessions_dir, filename, mtime_date):
        path = os.path.join(sessions_dir, filename)
        open(path, "w", encoding="utf-8").close()
        ts = datetime.combine(mtime_date, time(0, 30)).timestamp()
        os.utime(path, (ts, ts))
        return os.path.basename(path)

    def test_cross_midnight_file_included_by_mtime(self):
        with tempfile.TemporaryDirectory() as tmp:
            sessions = os.path.join(tmp, "sessions")
            os.makedirs(sessions)
            # Named 07-12 but last modified on 07-13 (session spanned midnight).
            cross = self._make_session(sessions, "rollout-2026-07-12T23-50-00-a.jsonl", date(2026, 7, 13))
            # Same-day file.
            same = self._make_session(sessions, "rollout-2026-07-13T09-00-00-c.jsonl", date(2026, 7, 13))
            # Stale file: old name and never touched since — must stay excluded.
            self._make_session(sessions, "rollout-2026-07-01T10-00-00-b.jsonl", date(2026, 7, 1))

            collected = {os.path.basename(f) for f in plugin.collect_session_files(tmp, date(2026, 7, 13), date(2026, 7, 13))}

        self.assertIn(cross, collected)
        self.assertIn(same, collected)
        self.assertEqual(len(collected), 2)

    def test_full_range_uses_filename_dates(self):
        with tempfile.TemporaryDirectory() as tmp:
            sessions = os.path.join(tmp, "sessions")
            os.makedirs(sessions)
            a = self._make_session(sessions, "rollout-2026-07-12T23-50-00-a.jsonl", date(2026, 7, 13))
            b = self._make_session(sessions, "rollout-2026-07-01T10-00-00-b.jsonl", date(2026, 7, 1))
            c = self._make_session(sessions, "rollout-2026-07-13T09-00-00-c.jsonl", date(2026, 7, 13))

            collected = {os.path.basename(f) for f in plugin.collect_session_files(tmp, date(2026, 6, 14), date(2026, 7, 13))}

        self.assertEqual(collected, {a, b, c})


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

    def test_last_cached_day_is_rescanned_after_midnight(self):
        today = plugin.datetime.now().date()
        yesterday = today - timedelta(days=1)
        timestamp = datetime.combine(
            yesterday,
            time(20),
            tzinfo=datetime.now().astimezone().tzinfo,
        ).isoformat()

        with tempfile.TemporaryDirectory() as tmp:
            sessions = Path(tmp) / "sessions" / yesterday.strftime("%Y/%m/%d")
            sessions.mkdir(parents=True)
            session = sessions / f"rollout-{yesterday.isoformat()}T10-00-00-test.jsonl"
            session.write_text(
                json.dumps({"type": "turn_context", "payload": {"model": "gpt-5"}}) + "\n"
                + json.dumps({
                    "type": "event_msg",
                    "payload": {
                        "type": "token_count",
                        "timestamp": timestamp,
                        "info": {"total_token_usage": {"total_tokens": 350}},
                    },
                }) + "\n",
                encoding="utf-8",
            )
            plugin.save_chart_cache(tmp, {
                "version": plugin.CACHE_VERSION,
                "last_date": plugin._format_date(yesterday),
                "days": {plugin._format_date(yesterday): {"gpt-5": 100}},
            })

            daily = plugin.maintain_chart_cache(tmp, "zh-Hans")

        self.assertEqual(daily.get(plugin._format_date(yesterday)), {"gpt-5": 350})


class TestParseSessionsForChart(unittest.TestCase):
    def _parse_events(self, events):
        today = datetime.now().astimezone()
        with tempfile.TemporaryDirectory() as tmp:
            session = Path(tmp) / "rollout.jsonl"
            session.write_text(
                "\n".join(json.dumps(event) for event in events) + "\n",
                encoding="utf-8",
            )
            result = plugin.parse_sessions_for_chart(
                [str(session)],
                [today],
                "day",
                "7d",
                "en",
            )
        return sum(segment["tokens"] for segment in result["buckets"][0]["segments"])

    def _token_event(self, total_usage, last_usage=None):
        info = {"total_token_usage": total_usage}
        if last_usage is not None:
            info["last_token_usage"] = last_usage
        return {
            "type": "event_msg",
            "payload": {
                "type": "token_count",
                "timestamp": datetime.now().astimezone().isoformat(),
                "info": info,
            },
        }

    def test_repeated_last_usage_does_not_recount_unchanged_cumulative_total(self):
        events = [
            {"type": "turn_context", "payload": {"model": "gpt-5"}},
            self._token_event({"total_tokens": 120}, {"total_tokens": 120}),
            self._token_event({"total_tokens": 120}, {"total_tokens": 120}),
        ]

        self.assertEqual(self._parse_events(events), 120)

    def test_invalid_last_usage_is_ignored_when_cumulative_total_is_zero(self):
        events = [
            {"type": "turn_context", "payload": {"model": "gpt-5"}},
            self._token_event(
                {
                    "input_tokens": 0,
                    "cached_input_tokens": 0,
                    "output_tokens": 0,
                    "reasoning_output_tokens": 0,
                    "total_tokens": 0,
                },
                {"total_tokens": 22440},
            ),
        ]

        self.assertEqual(self._parse_events(events), 0)

    def test_total_tokens_does_not_double_count_cached_or_reasoning_subsets(self):
        events = [
            {"type": "turn_context", "payload": {"model": "gpt-5"}},
            self._token_event({
                "input_tokens": 100,
                "cached_input_tokens": 80,
                "output_tokens": 20,
                "reasoning_output_tokens": 10,
                "total_tokens": 120,
            }),
        ]

        self.assertEqual(self._parse_events(events), 120)


if __name__ == "__main__":
    unittest.main()
