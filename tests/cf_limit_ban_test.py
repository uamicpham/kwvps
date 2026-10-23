import importlib.util
import pathlib
import tempfile
import sys
import types
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
if sys.platform == 'win32':
    sys.modules['fcntl'] = types.ModuleType('fcntl')
SPEC = importlib.util.spec_from_file_location('cf_limit_ban', ROOT / 'scripts/cf_limit_ban.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LogParserTests(unittest.TestCase):
    def test_nginx_reject(self):
        line = ('2026/10/22 12:00:00 [error] 10#10: *1 limiting requests, '
                'excess: 2.000 by zone "kwvps_antiddos_5", '
                'client: 198.51.100.7, server: example.com, request: "GET / HTTP/1.1"')
        match = MODULE.REJECT.search(line)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(3), '198.51.100.7')
        self.assertEqual(match.group(4), 'example.com')

    def test_unrelated_error_is_ignored(self):
        self.assertIsNone(MODULE.REJECT.search('client: 1.2.3.4 server: example.com 429'))

    def test_zone_token_overrides_legacy_token(self):
        zone = '0123456789abcdef0123456789abcdef'
        old_base, old_token, old_owned = MODULE.BASE, MODULE.TOKEN, MODULE.owned_file
        with tempfile.TemporaryDirectory() as directory:
            try:
                MODULE.BASE = pathlib.Path(directory)
                MODULE.TOKEN = MODULE.BASE / 'token'
                MODULE.owned_file = lambda path, mode=None: None
                MODULE.TOKEN.write_text('legacy_token_12345678901234567890')
                self.assertEqual(MODULE.token_for_zone(zone), 'legacy_token_12345678901234567890')
                (MODULE.BASE / ('token-' + zone)).write_text('zone_token_1234567890123456789012')
                self.assertEqual(MODULE.token_for_zone(zone), 'zone_token_1234567890123456789012')
            finally:
                MODULE.BASE, MODULE.TOKEN, MODULE.owned_file = old_base, old_token, old_owned


if __name__ == '__main__':
    unittest.main()
