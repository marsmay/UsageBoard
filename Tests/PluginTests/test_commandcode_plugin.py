"""Command Code billing contract, fallback, and error regressions (no live keys)."""
import copy
import importlib.util
import json
import os
import sys
import unittest
import urllib.error
from io import StringIO
from pathlib import Path
from unittest.mock import MagicMock, patch

PLUGIN_PATH = Path(__file__).resolve().parents[2] / 'Resources/BundledPlugins/commandcode-usage-plugin.py'
spec = importlib.util.spec_from_file_location('commandcode_plugin', PLUGIN_PATH)
plugin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plugin)

CREDITS = {
    'credits': {'monthlyCredits': 68, 'purchasedCredits': 500},
    'windowLimits': {
        'fiveHour': {'used': 2, 'cap': 14, 'resetAt': 1789852376206},
        'weekly': {'used': 2, 'cap': 35, 'resetAt': 1790439176206},
    },
}
SUBSCRIPTION = {'success': True, 'data': {
    'planId': 'individual-goat', 'status': 'active',
    'currentPeriodEnd': '2026-10-19T16:07:22.000Z',
}}


class CommandCodeTests(unittest.TestCase):
    def run_main(self, responses=None, params=None, env=None):
        argv = [str(PLUGIN_PATH)]
        for key, value in (params if params is not None else {'API_KEY': 'test-key'}).items():
            argv += ['--usageboard-param', f'{key}={value}']
        with patch.object(sys, 'argv', argv), patch.dict(os.environ, env or {}, clear=True), \
             patch.object(plugin, 'fetch_billing', side_effect=responses or [CREDITS, SUBSCRIPTION]) as fetch, \
             patch('sys.stdout', new_callable=StringIO) as out:
            self.assertEqual(plugin.main(), 0)
        return json.loads(out.getvalue()), fetch

    def test_three_windows_monthly_estimate_and_subscription_reset(self):
        output, _ = self.run_main()
        five, week, month = output['items']
        self.assertEqual(output['schemaVersion'], 1)
        self.assertEqual(output['badge'], 'GOAT')
        self.assertEqual([(i['used'], i['limit']) for i in output['items']], [(2, 14), (2, 35), (2, 70)])
        self.assertEqual(five['resetAt'], '2026-09-19T21:12:56.206Z')
        self.assertEqual(week['resetAt'], '2026-09-26T16:12:56.206Z')
        self.assertEqual(month['resetAt'], SUBSCRIPTION['data']['currentPeriodEnd'])
        self.assertTrue(all(i['displayStyle'] == 'percent' for i in output['items']))
        self.assertEqual([i['name'] for i in output['items']], ['5 小时用量', '周用量', '月用量'])
        self.assertEqual(len({i['id'] for i in output['items']}), 3)

    def test_monthly_cap_follows_weekly_not_plan_or_purchased_balance(self):
        data = copy.deepcopy(CREDITS)
        data['windowLimits']['weekly']['cap'] = 50
        data['credits']['monthlyCredits'] = 25
        data['credits']['monthlyCreditsGranted'] = 999
        output, _ = self.run_main([data, SUBSCRIPTION])
        self.assertEqual(output['items'][2]['limit'], 100)
        self.assertEqual(output['items'][2]['used'], 75)
        self.assertEqual(output['items'][2]['status'], 'warning')

    def test_missing_key_does_not_request(self):
        output, fetch = self.run_main(params={})
        self.assertIn('API Key', output['error'])
        fetch.assert_not_called()

    def test_env_fallback_and_parameter_precedence(self):
        for params, expected in [({}, 'env-key'), ({'API_KEY': 'setting-key'}, 'setting-key')]:
            with self.subTest(params=params):
                output, fetch = self.run_main(params=params, env={'COMMAND_API_KEY': 'env-key'})
                self.assertIn('items', output)
                self.assertEqual(fetch.call_args_list[0].args[0], expected)

    def test_english_labels(self):
        output, _ = self.run_main(params={'API_KEY': 'fake', 'USAGEBOARD_LANGUAGE': 'en'})
        self.assertEqual([i['name'] for i in output['items']], ['5-hour usage', 'Weekly usage', 'Monthly usage'])

    def test_subscription_failure_keeps_quotas_without_badge_or_reset(self):
        for response in [TimeoutError(), urllib.error.HTTPError('url', 401, 'no', {}, None),
                         {'success': False, 'data': SUBSCRIPTION['data']}, {'success': True, 'data': None}]:
            with self.subTest(response=type(response).__name__):
                output, _ = self.run_main([CREDITS, response])
                self.assertEqual(len(output['items']), 3)
                self.assertIsNone(output['items'][2]['resetAt'])
                self.assertNotIn('badge', output)

    def test_missing_window_and_monthly_balance_are_not_zero_usage(self):
        data = copy.deepcopy(CREDITS)
        del data['credits']['monthlyCredits']
        del data['windowLimits']['fiveHour']
        output, _ = self.run_main([data, SUBSCRIPTION])
        self.assertEqual([i['id'] for i in output['items']], ['commandcode-weekly'])
        del data['windowLimits']['weekly']
        output, _ = self.run_main([data, SUBSCRIPTION])
        self.assertIn('error', output)

    def test_no_weekly_cap_means_no_estimated_month(self):
        for cap in [0, -1]:
            data = copy.deepcopy(CREDITS)
            data['windowLimits']['weekly']['cap'] = cap
            output, _ = self.run_main([data, SUBSCRIPTION])
            self.assertEqual(len(output['items']), 1)

    def test_invalid_amounts_fail_instead_of_showing_zero(self):
        for bad in [None, True, 'bad', float('nan'), float('inf')]:
            for field in ['used', 'cap']:
                with self.subTest(bad=bad, field=field):
                    data = copy.deepcopy(CREDITS)
                    data['windowLimits']['fiveHour'][field] = bad
                    output, _ = self.run_main([data, SUBSCRIPTION])
                    self.assertEqual(output, {'error': '用量数据解析失败'})

    def test_depletion_and_excess_balance(self):
        for remaining, used in [(0, 70), (-2, 72), (80, 0)]:
            data = copy.deepcopy(CREDITS)
            data['credits']['monthlyCredits'] = remaining
            output, _ = self.run_main([data, SUBSCRIPTION])
            self.assertEqual(output['items'][2]['used'], used)
            if used >= 70:
                self.assertEqual(output['items'][2]['status'], 'critical')

    def test_optional_dates_and_nested_windows(self):
        for value in [None, 'bad', '2026-10-20T00:00:00', True, float('inf'), -1]:
            self.assertIsNone(plugin.reset_time(value))
        self.assertEqual(plugin.reset_time(1789852376), '2026-09-19T21:12:56.000Z')
        data = copy.deepcopy(CREDITS)
        data['credits']['windowLimits'] = data.pop('windowLimits')
        output, _ = self.run_main([data, SUBSCRIPTION])
        self.assertEqual(len(output['items']), 3)

    def test_http_errors_are_redacted_and_classified(self):
        for code in [401, 403, 429, 500, 302]:
            output, fetch = self.run_main([urllib.error.HTTPError('url', code, 'test-key private', {}, None)])
            self.assertIn(str(code), output['error'])
            self.assertNotIn('test-key', output['error'])
            self.assertEqual(fetch.call_count, 1)

    def test_parse_and_network_failures(self):
        for error, expected in [(ValueError(), '用量数据解析失败'),
                                (TimeoutError(), '请求超时，请检查网络'),
                                (urllib.error.URLError('private'), '网络连接失败，请检查网络')]:
            output, _ = self.run_main([error])
            self.assertEqual(output['error'], expected)

    def test_fetch_contract_and_no_redirect(self):
        response = MagicMock()
        response.__enter__.return_value = response
        response.read.return_value = json.dumps(CREDITS).encode()
        opener = MagicMock()
        opener.open.return_value = response
        with patch.object(plugin.urllib.request, 'build_opener', return_value=opener):
            self.assertEqual(plugin.fetch_billing('fake-key', 'credits', 6), CREDITS)
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, 'https://api.commandcode.ai/alpha/billing/credits')
        self.assertEqual(request.get_method(), 'GET')
        self.assertEqual(request.get_header('Authorization'), 'Bearer fake-key')
        self.assertEqual(request.get_header('X-api-key'), 'fake-key')
        self.assertEqual(request.get_header('User-agent'), 'UsageBoard')
        self.assertIsNone(plugin.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://example.com'))
        for invalid in [[], {'success': False}]:
            response.read.return_value = json.dumps(invalid).encode()
            with patch.object(plugin.urllib.request, 'build_opener', return_value=opener), self.assertRaises(ValueError):
                plugin.fetch_billing('fake-key', 'credits', 6)

    def test_metadata_is_in_scanned_header(self):
        header = PLUGIN_PATH.read_text().splitlines()[:80]
        start = header.index('# UsageBoardPlugin:')
        end = header.index('# /UsageBoardPlugin')
        metadata = json.loads('\n'.join(line[2:] for line in header[start+1:end]))
        self.assertEqual(metadata['description'], '查询 Command Code 订阅用量')
        self.assertEqual(metadata['description@en'], 'Query Command Code subscription usage')
        self.assertEqual(metadata['parameters'][0]['type'], 'secret')
        self.assertTrue(metadata['parameters'][0]['required'])
        self.assertEqual(metadata['icon'], 'icons/light/commandcode.png')


if __name__ == '__main__':
    unittest.main()
