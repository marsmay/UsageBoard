"""Tests for claude-usage-plugin.py — run with: python3 -m pytest Tests/PluginTests/test_claude_plugin.py"""

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, time, timedelta, timezone
from pathlib import Path
from io import StringIO
from unittest.mock import patch

PLUGIN_PATH = Path(__file__).parent.parent.parent / "Resources" / "BundledPlugins" / "claude-usage-plugin.py"


def load_plugin():
    plugin_dir = str(PLUGIN_PATH.parent)
    if plugin_dir not in sys.path:
        sys.path.insert(0, plugin_dir)
    spec = importlib.util.spec_from_file_location("claude_plugin", PLUGIN_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


plugin = load_plugin()


class TestPlanAndStatsNone(unittest.TestCase):
    def _run_main(self, params, isdir=True, cache_return=None, cache_side_effect=None):
        argv = ["claude"]
        for key, value in params:
            argv += ["--usageboard-param", f"{key}={value}"]
        with patch.object(sys, "argv", argv), \
             patch.object(plugin.os.path, "isdir", return_value=isdir), \
             patch.object(plugin, "maintain_cache", side_effect=cache_side_effect, return_value=cache_return) as cache_mock, \
             patch("sys.stdout", new_callable=StringIO) as out:
            plugin.main()
        return json.loads(out.getvalue()), cache_mock

    def test_plan_and_stats_none_returns_no_content(self):
        output, cache_mock = self._run_main(
            [("PLAN", "none"), ("STAT_PERIOD", "none")],
            isdir=False,  # data dir is not required when stats are off
            cache_side_effect=AssertionError("should not scan"),
        )

        self.assertEqual(output["items"], [])
        self.assertNotIn("chart", output)
        cache_mock.assert_not_called()

    def test_plan_none_with_stats_keeps_chart_only(self):
        output, cache_mock = self._run_main(
            [("PLAN", "none"), ("STAT_PERIOD", "7d")],
            cache_return={},
        )

        self.assertEqual(output["items"], [])
        self.assertIn("chart", output)

    def test_empty_data_dir_param_falls_back_to_default(self):
        # 空 DATA_DIR 不得退化为进程 CWD，应与缺省一样解析到 ~/.claude。
        _, cache_mock = self._run_main(
            [("PLAN", "none"), ("STAT_PERIOD", "7d"), ("DATA_DIR", "")],
            cache_return={},
        )
        expected = plugin.os.path.realpath(plugin.os.path.expanduser("~/.claude"))
        self.assertEqual(cache_mock.call_args.args[0], expected)

    def test_whitespace_data_dir_param_falls_back_to_default(self):
        _, cache_mock = self._run_main(
            [("PLAN", "none"), ("STAT_PERIOD", "7d"), ("DATA_DIR", "  ")],
            cache_return={},
        )
        expected = plugin.os.path.realpath(plugin.os.path.expanduser("~/.claude"))
        self.assertEqual(cache_mock.call_args.args[0], expected)
        cache_mock.assert_called_once()


class TestBadgePlanFallback(unittest.TestCase):
    def _run_main(self, params, oauth_data):
        argv = ["claude", "--usageboard-param", "STAT_PERIOD=none"]
        for key, value in params:
            argv += ["--usageboard-param", f"{key}={value}"]
        with patch.object(sys, "argv", argv), \
             patch.object(plugin, "load_oauth_token", return_value="token"), \
             patch.object(plugin, "fetch_oauth_usage", return_value=(oauth_data, 200)), \
             patch("sys.stdout", new_callable=StringIO) as out:
            plugin.main()
        return json.loads(out.getvalue())

    def test_valid_server_plan_type_wins(self):
        output = self._run_main([("PLAN", "pro")], {"plan_type": "max"})

        self.assertEqual(output["badge"], "Max")

    def test_null_plan_type_falls_back_to_configured_plan(self):
        output = self._run_main([("PLAN", "max")], {"plan_type": None})

        self.assertEqual(output["badge"], "Max")

    def test_missing_plan_type_falls_back_to_configured_plan(self):
        output = self._run_main([("PLAN", "max")], {"five_hour": {"utilization": 10}})

        self.assertEqual(output["badge"], "Max")

    def test_empty_plan_type_falls_back_to_configured_plan(self):
        output = self._run_main([("PLAN", "max")], {"plan_type": "  "})

        self.assertEqual(output["badge"], "Max")

    def test_null_plan_type_without_plan_param_falls_back_to_default(self):
        output = self._run_main([], {"plan_type": None})

        self.assertEqual(output["badge"], "Pro")

    def test_null_plan_type_with_empty_plan_param_falls_back_to_default(self):
        output = self._run_main([("PLAN", "")], {"plan_type": None})

        self.assertEqual(output["badge"], "Pro")

    def test_null_plan_type_with_whitespace_plan_falls_back_to_default(self):
        output = self._run_main([("PLAN", "  ")], {"plan_type": None})

        self.assertEqual(output["badge"], "Pro")


class TestTranslateSignature(unittest.TestCase):
    """translate(language, key) — language first, key second (matches all other plugins)."""

    def test_language_first_zh(self):
        translate = plugin._translate("zh-Hans")
        result = translate("zh-Hans", "five_hour")
        self.assertEqual(result, "5 小时用量")

    def test_language_first_en(self):
        translate = plugin._translate("en")
        result = translate("en", "five_hour")
        self.assertEqual(result, "5-hour usage")

    def test_unknown_key_returns_key(self):
        translate = plugin._translate("en")
        result = translate("en", "nonexistent_key")
        self.assertEqual(result, "nonexistent_key")


class TestColorThresholds(unittest.TestCase):
    """color_for thresholds should match other plugins: ≥90 red, ≥80 orange, ≥60 yellow, <60 blue."""

    def test_90_is_red(self):
        self.assertEqual(plugin.color_for_pct(90), "red")

    def test_80_is_orange(self):
        self.assertEqual(plugin.color_for_pct(80), "orange")

    def test_79_is_yellow(self):
        self.assertEqual(plugin.color_for_pct(79), "yellow")

    def test_60_is_yellow(self):
        self.assertEqual(plugin.color_for_pct(60), "yellow")

    def test_59_is_blue(self):
        self.assertEqual(plugin.color_for_pct(59), "blue")


class TestStatusThresholds(unittest.TestCase):
    """status_for thresholds should match other plugins: ≥90 critical, ≥75 warning, else normal."""

    def test_90_is_critical(self):
        self.assertEqual(plugin.status_for_pct(90), "critical")

    def test_75_is_warning(self):
        self.assertEqual(plugin.status_for_pct(75), "warning")

    def test_74_is_normal(self):
        self.assertEqual(plugin.status_for_pct(74), "normal")

    def test_0_is_normal(self):
        self.assertEqual(plugin.status_for_pct(0), "normal")


class TestSuccessSchemaVersion(unittest.TestCase):
    """success() output must include schemaVersion field."""

    def test_success_has_schema_version(self):
        items = [{"id": "x", "name": "x", "used": 0, "limit": 1, "displayStyle": "percent", "status": "normal"}]
        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            plugin.success(items)
            output = json.loads(mock_out.getvalue())
        self.assertIn("schemaVersion", output)
        self.assertEqual(output["schemaVersion"], 1)


class TestFailureFormat(unittest.TestCase):
    """failure() must output {"error": "message"} with no items."""

    def test_failure_has_error_field(self):
        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            plugin.failure("test error")
            output = json.loads(mock_out.getvalue())
        self.assertIn("error", output)
        self.assertEqual(output["error"], "test error")

    def test_failure_has_no_items(self):
        with patch("sys.stdout", new_callable=StringIO) as mock_out:
            plugin.failure("test error")
            output = json.loads(mock_out.getvalue())
        self.assertNotIn("items", output)


class TestFetchOauthUsageErrors(unittest.TestCase):
    def test_timeout_error_returns_timeout_code(self):
        with patch.object(plugin.urllib_request, "urlopen", side_effect=TimeoutError):
            data, code = plugin.fetch_oauth_usage("token")

        self.assertIsNone(data)
        self.assertEqual(code, plugin.REQUEST_TIMEOUT)

    def test_url_error_returns_network_error_code(self):
        error = plugin.urllib.error.URLError("offline")
        with patch.object(plugin.urllib_request, "urlopen", side_effect=error):
            data, code = plugin.fetch_oauth_usage("token")

        self.assertIsNone(data)
        self.assertEqual(code, plugin.NETWORK_ERROR)


class TestBuildItemsFromOauth(unittest.TestCase):
    """OAuth usage payload should produce UsageBoard items for five_hour and seven_day."""

    def test_produces_two_items_with_correct_fields(self):
        payload = {
            "five_hour": {"utilization": 12.34, "resets_at": "2026-05-09T10:00:00Z"},
            "seven_day": {"utilization": 56.78, "resets_at": "2026-05-10T00:00:00Z"},
        }

        translate = plugin._translate("zh-Hans")
        items = plugin.build_items_from_oauth(payload, "zh-Hans", translate)

        self.assertEqual(len(items), 2)
        self.assertEqual([item["id"] for item in items], ["claude-five-hour", "claude-seven-day"])

        fh = items[0]
        self.assertEqual(fh["name"], "5 小时用量")
        self.assertEqual(fh["used"], 12.3)
        self.assertEqual(fh["limit"], 100)
        self.assertEqual(fh["displayStyle"], "percent")
        self.assertEqual(fh["resetAt"], "2026-05-09T10:00:00Z")
        self.assertEqual(fh["status"], "normal")
        self.assertEqual(fh["color"], "blue")

        sd = items[1]
        self.assertEqual(sd["name"], "周用量")
        self.assertEqual(sd["used"], 56.8)
        self.assertEqual(sd["color"], "blue")

    def test_ignores_unknown_fields_in_payload(self):
        payload = {
            "five_hour": {"utilization": 50, "resets_at": "2026-05-09T10:00:00Z"},
            "seven_day": {"utilization": 80, "resets_at": "2026-05-10T00:00:00Z"},
            "seven_day_omelette": {"utilization": 91.2, "resets_at": "2026-05-11T00:00:00Z"},
        }

        translate = plugin._translate("en")
        items = plugin.build_items_from_oauth(payload, "en", translate)

        self.assertEqual([item["id"] for item in items], ["claude-five-hour", "claude-seven-day"])


class TestMaintainCacheRefreshesToday(unittest.TestCase):
    """maintain_cache must re-scan today's data on subsequent runs (gap_days == 0).

    Regression test for bug: previously, `if gap_days <= 0: return cache` froze today's
    data after the first scan of the day, so usage that happened later wouldn't show up.
    """

    def _write_jsonl(self, path, ts_iso, model, tokens):
        record = {
            "type": "assistant",
            "timestamp": ts_iso,
            "message": {
                "id": f"msg-{ts_iso}-{tokens}",
                "model": model,
                "usage": {"input_tokens": 0, "output_tokens": tokens, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0},
            },
        }
        with open(path, "a") as f:
            f.write(json.dumps(record) + "\n")

    def test_full_scan_keeps_recent_records_regardless_of_mtime(self):
        # 全量扫描以记录时间为准，旧 mtime 不能遮蔽近期记录。
        with tempfile.TemporaryDirectory() as tmp:
            projects = os.path.join(tmp, "projects", "p1")
            os.makedirs(projects)
            recent = os.path.join(projects, "recent.jsonl")
            stale = os.path.join(projects, "stale.jsonl")
            now = datetime.now().astimezone()
            self._write_jsonl(recent, now.isoformat(), "claude-sonnet", 33)
            # 导入后保留旧 mtime 的近期记录仍应计入统计。
            self._write_jsonl(stale, now.isoformat(), "claude-sonnet", 500)
            import time as _time
            old_ts = _time.time() - 40 * 86400
            os.utime(stale, (old_ts, old_ts))

            result = plugin.maintain_cache(tmp)  # 无缓存 → 全量路径
            today_str = datetime.now().strftime("%Y-%m-%d")
            self.assertEqual(result.get(today_str, {}).get("claude-sonnet", {}).get("output", 0), 533)

    def test_previous_cache_version_rebuilds_records_with_old_mtime(self):
        with tempfile.TemporaryDirectory() as tmp:
            projects = os.path.join(tmp, "projects", "p1")
            os.makedirs(projects)
            path = os.path.join(projects, "imported.jsonl")
            yesterday = datetime.now().astimezone() - timedelta(days=1)
            self._write_jsonl(path, yesterday.isoformat(), "claude-sonnet", 500)
            old_ts = (yesterday - timedelta(days=40)).timestamp()
            os.utime(path, (old_ts, old_ts))
            plugin.save_stats_cache(tmp, {
                "version": 6, "last_date": datetime.now().strftime("%Y-%m-%d"), "days": {}
            })
            result = plugin.maintain_cache(tmp)
            self.assertEqual(result[yesterday.strftime("%Y-%m-%d")]["claude-sonnet"]["output"], 500)
            self.assertEqual(plugin.load_stats_cache(tmp)["version"], plugin.CACHE_VERSION)

    def test_vanished_files_are_skipped_during_incremental_scan(self):
        # glob 与 getmtime 之间被 Claude Code 轮转删除的文件必须跳过，不得让整个插件失败。
        with tempfile.TemporaryDirectory() as tmp:
            projects = os.path.join(tmp, "projects", "p1")
            os.makedirs(projects)
            jsonl = os.path.join(projects, "session.jsonl")
            now = datetime.now().astimezone()
            self._write_jsonl(jsonl, now.isoformat(), "claude-sonnet", 80)
            plugin.maintain_cache(tmp)  # 生成缓存，使下一次走增量路径

            original = plugin.all_jsonl_files
            vanished = os.path.join(tmp, "projects", "p1", "rotated-away.jsonl")
            with patch.object(plugin, "all_jsonl_files", return_value=[vanished, jsonl]):
                result = plugin.maintain_cache(tmp)  # 不得抛 FileNotFoundError
            today_str = datetime.now().strftime("%Y-%m-%d")
            self.assertEqual(result.get(today_str, {}).get("claude-sonnet", {}).get("output", 0), 80)

    def test_today_is_rescanned_when_gap_days_is_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            projects = os.path.join(tmp, "projects", "p1")
            os.makedirs(projects)
            jsonl = os.path.join(projects, "session.jsonl")

            today_str = datetime.now().strftime("%Y-%m-%d")
            now = datetime.now().astimezone()
            start_today = now.replace(hour=0, minute=0, second=0, microsecond=0)
            elapsed_today = now - start_today
            earlier = start_today + (elapsed_today / 3)
            later = start_today + (elapsed_today * 2 / 3)

            # First run: today has 100 tokens
            self._write_jsonl(jsonl, earlier.isoformat(), "claude-sonnet", 100)
            result1 = plugin.maintain_cache(tmp)
            self.assertEqual(result1.get(today_str, {}).get("claude-sonnet", {}).get("output", 0), 100)

            # Append more usage in the same day — simulate user activity since first run
            self._write_jsonl(jsonl, later.isoformat(), "claude-sonnet", 250)

            # Second run (same day, gap_days == 0) — must pick up the 250 new tokens
            result2 = plugin.maintain_cache(tmp)
            self.assertEqual(
                result2.get(today_str, {}).get("claude-sonnet", {}).get("output", 0),
                350,
                "Today's data must be re-scanned on subsequent runs, not returned from cache as-is",
            )

    def test_last_cached_day_is_rescanned_after_midnight(self):
        today = plugin._parse_date(plugin.local_today())
        yesterday = today - timedelta(days=1)
        local_tz = datetime.now().astimezone().tzinfo

        with tempfile.TemporaryDirectory() as tmp:
            projects = os.path.join(tmp, "projects", "p1")
            os.makedirs(projects)
            jsonl = os.path.join(projects, "session.jsonl")
            first = datetime.combine(yesterday, time(10), tzinfo=local_tz)
            second = datetime.combine(yesterday, time(20), tzinfo=local_tz)
            self._write_jsonl(jsonl, first.isoformat(), "claude-sonnet", 100)
            self._write_jsonl(jsonl, second.isoformat(), "claude-sonnet", 250)

            plugin.save_stats_cache(tmp, {
                "version": plugin.CACHE_VERSION,
                "last_date": plugin._format_date(yesterday),
                "days": {
                    plugin._format_date(yesterday): {
                        "claude-sonnet": {
                            "input": 0,
                            "output": 100,
                            "cache_creation": 0,
                            "cache_read": 0,
                        }
                    }
                },
            })

            result = plugin.maintain_cache(tmp)

        self.assertEqual(
            result.get(plugin._format_date(yesterday), {}).get("claude-sonnet", {}).get("output"),
            350,
        )


class TestMaintainCacheRecovery(unittest.TestCase):
    def test_invalid_last_date_rebuilds_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache_path = os.path.join(tmp, plugin.CACHE_FILENAME)
            with open(cache_path, "w") as f:
                json.dump({"version": plugin.CACHE_VERSION, "last_date": "bad-date", "days": {}}, f)

            result = plugin.maintain_cache(tmp)

        self.assertIsInstance(result, dict)

    def test_invalid_cached_day_key_is_skipped(self):
        today = plugin._parse_date(plugin.local_today())
        yesterday = today - timedelta(days=1)

        with tempfile.TemporaryDirectory() as tmp:
            plugin.save_stats_cache(tmp, {
                "version": plugin.CACHE_VERSION,
                "last_date": plugin._format_date(today),
                "days": {
                    "bad-date": {"stale": {"input": 1, "output": 0, "cache_creation": 0, "cache_read": 0}},
                    plugin._format_date(yesterday): {"old-model": {"input": 2, "output": 0, "cache_creation": 0, "cache_read": 0}},
                },
            })

            result = plugin.maintain_cache(tmp)

        self.assertNotIn("bad-date", result)
        self.assertEqual(
            result.get(plugin._format_date(yesterday)),
            {"old-model": {"input": 2, "output": 0, "cache_creation": 0, "cache_read": 0}},
        )


class TestModelNameNormalization(unittest.TestCase):
    """Routed model names carry a provider prefix (`deepseek/deepseek-v4-flash`); the last
    `/`-separated segment is the display key, so plain and prefixed names merge."""

    def _write_record(self, path, ts_iso, model, tokens):
        record = {
            "type": "assistant",
            "timestamp": ts_iso,
            "message": {
                "id": f"msg-{ts_iso}-{model}",
                "model": model,
                "usage": {"input_tokens": 0, "output_tokens": tokens, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0},
            },
        }
        with open(path, "a") as f:
            f.write(json.dumps(record) + "\n")

    def test_prefixed_and_plain_model_names_merge(self):
        with tempfile.TemporaryDirectory() as tmp:
            projects = os.path.join(tmp, "projects", "p1")
            os.makedirs(projects)
            jsonl = os.path.join(projects, "session.jsonl")

            ts = datetime.now().astimezone().replace(microsecond=0).isoformat()
            today_str = datetime.now().strftime("%Y-%m-%d")
            self._write_record(jsonl, ts, "deepseek/deepseek-v4-flash", 100)
            self._write_record(jsonl, ts, "deepseek-v4-flash", 50)
            self._write_record(jsonl, ts, "claude-opus-4-7", 7)

            daily = plugin.maintain_cache(tmp)

        day = daily.get(today_str, {})
        self.assertEqual(
            day.get("deepseek-v4-flash", {}).get("output", 0),
            150,
            "provider-prefixed and plain model names must aggregate into one entry",
        )
        self.assertNotIn("deepseek/deepseek-v4-flash", day)
        self.assertEqual(day.get("claude-opus-4-7", {}).get("output", 0), 7)


class TestComputeTokens(unittest.TestCase):
    """compute_tokens always reports the actual total across all token categories."""

    def test_sums_all_four(self):
        b = {"input": 100, "output": 50, "cache_creation": 200, "cache_read": 9999}
        self.assertEqual(plugin.compute_tokens(b), 100 + 50 + 200 + 9999)

    def test_chart_uses_actual_total_with_legacy_calc_mode_value(self):
        today = datetime.now().strftime("%Y-%m-%d")
        daily = {
            today: {
                "claude-sonnet": {
                    "input": 100,
                    "output": 50,
                    "cache_creation": 200,
                    "cache_read": 9999,
                }
            }
        }

        chart = plugin.build_chart(
            {"STAT_PERIOD": "7d", "CALC_MODE": "billable"},
            daily,
            "en",
            plugin._translate("en"),
        )

        self.assertEqual(chart["buckets"][-1]["segments"][0]["tokens"], 100 + 50 + 200 + 9999)


class TestParseRecordsReturnsBreakdown(unittest.TestCase):
    """parse_records returns raw 4-field breakdown, not pre-summed total."""

    def test_breakdown_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            jsonl = os.path.join(tmp, "session.jsonl")
            with open(jsonl, "w") as f:
                f.write(json.dumps({
                    "type": "assistant",
                    "timestamp": "2026-05-15T10:00:00Z",
                    "message": {
                        "id": "msg-1",
                        "model": "claude-opus-4-7",
                        "usage": {
                            "input_tokens": 100,
                            "output_tokens": 50,
                            "cache_creation_input_tokens": 200,
                            "cache_read_input_tokens": 9999,
                        },
                    },
                }) + "\n")
            start = datetime(2026, 5, 14, tzinfo=timezone.utc)
            end = datetime(2026, 5, 16, tzinfo=timezone.utc)
            records = plugin.parse_records([jsonl], start, end)
            self.assertEqual(len(records), 1)
            _, _, breakdown = records[0]
            self.assertEqual(breakdown, {
                "input": 100, "output": 50, "cache_creation": 200, "cache_read": 9999,
            })

    def test_streaming_frames_merge_valid_usage_by_field(self):
        with tempfile.TemporaryDirectory() as tmp:
            jsonl = os.path.join(tmp, "session.jsonl")
            frames = [
                {
                    "type": "assistant",
                    "timestamp": "2026-05-15T10:00:00Z",
                    "message": {
                        "id": "msg-stream",
                        "model": "claude-sonnet-4-5",
                        "usage": {
                            "input_tokens": 0,
                            "output_tokens": 0,
                            "cache_creation_input_tokens": 0,
                            "cache_read_input_tokens": 0,
                        },
                    },
                },
                {
                    "type": "assistant",
                    "timestamp": "2026-05-15T10:01:00Z",
                    "message": {
                        "id": "msg-stream",
                        "model": "claude-sonnet-4-5",
                        "usage": {
                            "input_tokens": 100,
                            "output_tokens": 10,
                            "cache_creation_input_tokens": 5,
                            "cache_read_input_tokens": 0,
                        },
                    },
                },
                {
                    "type": "assistant",
                    "timestamp": "2026-05-15T10:02:00Z",
                    "message": {
                        "id": "msg-stream",
                        "model": "claude-sonnet-4-5",
                        "usage": {
                            "input_tokens": 80,
                            "output_tokens": 50,
                            "cache_creation_input_tokens": 999,
                            "cache_creation": {
                                "ephemeral_5m_input_tokens": 7,
                                "ephemeral_1h_input_tokens": 3,
                            },
                            "cache_read_input_tokens": 20,
                        },
                    },
                },
            ]
            with open(jsonl, "w") as f:
                for frame in frames:
                    f.write(json.dumps(frame) + "\n")

            start = datetime(2026, 5, 14, tzinfo=timezone.utc)
            end = datetime(2026, 5, 16, tzinfo=timezone.utc)
            records = plugin.parse_records([jsonl], start, end)

        self.assertEqual(len(records), 1)
        timestamp, model, breakdown = records[0]
        self.assertEqual(timestamp, datetime(2026, 5, 15, 10, 1, tzinfo=timezone.utc))
        self.assertEqual(model, "claude-sonnet-4-5")
        self.assertEqual(breakdown, {
            "input": 100,
            "output": 50,
            "cache_creation": 10,
            "cache_read": 20,
        })


class TestClassifierStats(unittest.TestCase):
    def setUp(self):
        self.start = datetime(2026, 5, 14, tzinfo=timezone.utc)
        self.end = datetime(2026, 5, 16, tzinfo=timezone.utc)
        self.record = {
            "ts": datetime(2026, 5, 15, 10, tzinfo=timezone.utc).timestamp() * 1000,
            "tool": "Bash", "allowlisted": False, "decision": "allowed",
            "classifierSource": "local", "classifierModel": "provider/claude-sonnet-4-5(high)",
            "inputTokens": 100, "outputTokens": 7,
            "cacheReadInputTokens": 900, "cacheCreationInputTokens": 50,
            "stage": "fast",
        }

    def write_log(self, directory, records):
        os.makedirs(directory, exist_ok=True)
        path = Path(directory) / plugin.CLASSIFIER_LOG_FILENAME
        path.write_text("".join(json.dumps(record) + "\n" for record in records))
        return path

    def test_actual_usage_and_two_stage_total_counted_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.write_log(tmp, [self.record, {**self.record, "stage": "thinking", "inputTokens": 300}])
            records = plugin.classifier_records([tmp], self.start, self.end)
        self.assertEqual(len(records), 2)
        self.assertEqual(records[0][1], "claude-sonnet-4-5")
        self.assertEqual(records[0][2], {"input": 100, "output": 7, "cache_creation": 50, "cache_read": 900})
        self.assertEqual(sum(plugin.compute_tokens(r[2]) for r in records), 2314)

    def test_invalid_lines_do_not_hide_later_usage_and_partial_line_is_deferred(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.write_log(tmp, [None, [], {**self.record, "ts": "bad"},
                                        {**self.record, "inputTokens": -1},
                                        {**self.record, "inputTokens": True},
                                        {**self.record, "inputTokens": float("nan")},
                                        {**self.record, "inputTokens": float("inf")},
                                        {**self.record, "inputTokens": 1.5},
                                        {**self.record, "ts": float("inf")}])
            with path.open("ab") as f:
                f.write(b'{"bad":\xff}\nnot-json\n')
                f.write((json.dumps(self.record) + "\n").encode())
                f.write(json.dumps(self.record).encode())
            self.assertEqual(len(plugin.classifier_records([tmp], self.start, self.end)), 1)
            with path.open("ab") as f:
                f.write(b"\n")
            self.assertEqual(len(plugin.classifier_records([tmp], self.start, self.end)), 2)

    def test_skips_server_allowlist_unknown_source_and_outside_window(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.write_log(tmp, [
                {**self.record, "classifierSource": "server"},
                {**self.record, "classifierSource": None},
                {**self.record, "allowlisted": True},
                {**self.record, "classifierModel": ""},
                {**self.record, "ts": 0},
                {**self.record, "ts": self.end.timestamp() * 1000 + 1},
                {**self.record, "decision": "blocked"},
            ])
            records = plugin.classifier_records([tmp], self.start, self.end)
        self.assertEqual(len(records), 1)  # Blocked decisions still consume tokens.

    def test_known_directories_and_file_aliases_count_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            first = self.write_log(os.path.join(tmp, "project1"), [self.record, self.record])
            second = self.write_log(os.path.join(tmp, "project2"), [self.record])
            aliases = Path(tmp) / "aliases"
            aliases.mkdir()
            os.link(first, aliases / plugin.CLASSIFIER_LOG_FILENAME)
            symlink = Path(tmp) / "symlink"
            symlink.mkdir()
            (symlink / plugin.CLASSIFIER_LOG_FILENAME).symlink_to(second)
            (Path(tmp) / "cycle").symlink_to(tmp, target_is_directory=True)
            self.write_log(os.path.join(tmp, "node_modules", "ignored"), [self.record])
            records = plugin.classifier_records(
                [str(first.parent), str(second.parent), str(aliases), str(symlink), str(first.parent)],
                self.start, self.end)
        # No request ID: equal records may be separate legitimate calls; preserve them.
        self.assertEqual(len(records), 3)

    def test_merge_by_model_is_repeatable_and_does_not_pollute_session_cache(self):
        now = datetime.now(timezone.utc) - timedelta(seconds=1)
        day = now.astimezone().strftime("%Y-%m-%d")
        daily = {day: {"claude-sonnet-4-5": {"input": 10, "output": 2, "cache_read": 0, "cache_creation": 0}}}
        with tempfile.TemporaryDirectory() as tmp:
            self.write_log(tmp, [{**self.record, "ts": now.timestamp() * 1000}])
            merged = plugin.add_classifier_stats(daily, [tmp])
            self.assertEqual(merged, plugin.add_classifier_stats(daily, [tmp]))
            self.assertEqual(list(merged[day]), ["claude-sonnet-4-5"])
            self.assertEqual(merged[day]["claude-sonnet-4-5"]["input"], 110)
            self.assertEqual(daily[day]["claude-sonnet-4-5"]["input"], 10)
            self.assertEqual(plugin.add_classifier_stats(daily, []), daily)
            chart = plugin.build_chart({"CLAUDE_ONLY": "true"}, merged, "en", plugin._translate("en"))
            self.assertEqual(sum(s["tokens"] for b in chart["buckets"] for s in b["segments"]), 1069)

    def test_cwd_discovery_cache_refresh_and_no_cache_pollution(self):
        now = datetime.now(timezone.utc) - timedelta(seconds=1)
        day = now.astimezone().strftime("%Y-%m-%d")
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp) / "data"
            sessions = data / "projects" / "project"
            sessions.mkdir(parents=True)
            project = Path(tmp) / "work"
            log = self.write_log(project, [{**self.record, "ts": now.timestamp() * 1000}])
            session = sessions / "session.jsonl"
            # cwd discovery must not depend on assistant usage or record timestamp.
            session.write_text(json.dumps({"type": "user", "cwd": str(project)}) + "\n")
            cold = plugin.maintain_cache(str(data))
            self.assertEqual(cold[day]["claude-sonnet-4-5"]["input"], 100)
            cache = plugin.load_stats_cache(str(data))
            self.assertEqual(cache["classifier_dirs"], [str(project)])
            self.assertEqual(cache["days"][day], {})
            # Session mtime may be old; the persisted cwd still locates new decisions.
            os.utime(session, (0, 0))
            with log.open("a") as f:
                f.write(json.dumps({**self.record, "ts": now.timestamp() * 1000}) + "\n")
            warm = plugin.maintain_cache(str(data))
            self.assertEqual(warm[day]["claude-sonnet-4-5"]["input"], 200)
            self.assertEqual(plugin.maintain_cache(str(data)), warm)
            self.assertEqual(plugin.load_stats_cache(str(data))["days"][day], {})
            log.unlink()
            self.assertEqual(plugin.maintain_cache(str(data))[day], {})

    def test_new_cwd_is_discovered_during_incremental_scan(self):
        now = datetime.now(timezone.utc) - timedelta(seconds=1)
        day = now.astimezone().strftime("%Y-%m-%d")
        with tempfile.TemporaryDirectory() as tmp:
            sessions = Path(tmp) / "data" / "projects" / "project"
            sessions.mkdir(parents=True)
            data = str(sessions.parent.parent)
            plugin.maintain_cache(data)
            project = Path(tmp) / "work"
            self.write_log(project, [{**self.record, "ts": now.timestamp() * 1000}])
            (sessions / "session.jsonl").write_text(
                json.dumps({"type": "user", "cwd": str(project)}) + "\n")
            self.assertEqual(plugin.maintain_cache(data)[day]["claude-sonnet-4-5"]["input"], 100)

    def test_none_does_not_scan_classifier_logs(self):
        with patch.object(plugin, "classifier_records", side_effect=AssertionError("must not scan")):
            TestPlanAndStatsNone()._run_main([("PLAN", "none"), ("STAT_PERIOD", "none")])

    def test_previous_cache_rebuild_discovers_cwd_with_old_mtime(self):
        now = datetime.now(timezone.utc) - timedelta(seconds=1)
        day = now.astimezone().strftime("%Y-%m-%d")
        with tempfile.TemporaryDirectory() as tmp:
            sessions = Path(tmp) / "data" / "projects" / "project"
            sessions.mkdir(parents=True)
            data = str(sessions.parent.parent)
            project = Path(tmp) / "work"
            self.write_log(project, [{**self.record, "ts": now.timestamp() * 1000}])
            session = sessions / "session.jsonl"
            session.write_text(json.dumps({"type": "user", "cwd": str(project)}) + "\n")
            os.utime(session, (0, 0))
            plugin.save_stats_cache(data, {"version": 7, "last_date": day, "days": {}})
            daily = plugin.maintain_cache(data)
            self.assertEqual(daily[day]["claude-sonnet-4-5"]["input"], 100)
            self.assertEqual(plugin.load_stats_cache(data)["version"], 8)

    def test_date_boundaries_and_unreadable_directories(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.write_log(tmp, [
                {**self.record, "ts": self.start.timestamp() * 1000},
                {**self.record, "ts": self.end.timestamp() * 1000},
                {**self.record, "ts": self.start.timestamp() * 1000 - 1},
            ])
            records = plugin.classifier_records(
                ["relative", "\x00/invalid", "/missing-usageboard-test-directory", tmp], self.start, self.end)
            self.assertEqual(len(records), 2)
            grouped = plugin.group_by_local_date(records)
            self.assertEqual(set(grouped), {ts.astimezone().strftime("%Y-%m-%d") for ts in (self.start, self.end)})


if __name__ == "__main__":
    unittest.main()
