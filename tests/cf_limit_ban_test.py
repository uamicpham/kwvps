import importlib.util
import pathlib
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


if __name__ == '__main__':
    unittest.main()
