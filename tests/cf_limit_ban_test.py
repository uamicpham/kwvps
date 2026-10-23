import importlib.util
import contextlib
import hashlib
import io
import pathlib
import sqlite3
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

    def test_site_token_is_bound_to_site_and_zone(self):
        zone = '0123456789abcdef0123456789abcdef'
        domain = 'blog.example.com'
        old_base, old_owned = MODULE.BASE, MODULE.owned_file
        with tempfile.TemporaryDirectory() as directory:
            try:
                MODULE.BASE = pathlib.Path(directory)
                MODULE.owned_file = lambda path, mode=None: None
                (MODULE.BASE / 'token').write_text('legacy_token_12345678901234567890')
                digest = hashlib.sha256(domain.encode('ascii')).hexdigest()
                (MODULE.BASE / ('zone-' + digest + '.id')).write_text(domain + '\n' + zone + '\n')
                with self.assertRaises(FileNotFoundError):
                    MODULE.token_for_site(domain, zone)
                (MODULE.BASE / ('token-' + zone)).write_text('zone_token_1234567890123456789012')
                with self.assertRaises(FileNotFoundError):
                    MODULE.token_for_site(domain, zone)
                (MODULE.BASE / ('site-token-' + digest)).write_text('site_token_1234567890123456789012')
                self.assertEqual(MODULE.token_for_site(domain, zone), 'site_token_1234567890123456789012')
                with self.assertRaises(ValueError):
                    MODULE.token_for_site(domain, 'abcdef0123456789abcdef0123456789')
            finally:
                MODULE.BASE, MODULE.owned_file = old_base, old_owned

    def test_missing_site_token_skips_legacy_push_but_unsafe_token_fails(self):
        zone = '0123456789abcdef0123456789abcdef'
        domain = 'blog.example.com'
        digest = hashlib.sha256(domain.encode('ascii')).hexdigest()
        old_base, old_owned = MODULE.BASE, MODULE.owned_file
        with tempfile.TemporaryDirectory() as directory:
            try:
                MODULE.BASE = pathlib.Path(directory)
                token_path = MODULE.BASE / ('site-token-' + digest)
                (MODULE.BASE / ('zone-' + digest + '.id')).write_text(domain + '\n' + zone + '\n')
                (MODULE.BASE / 'token').write_text('legacy_token_12345678901234567890')
                (MODULE.BASE / ('token-' + zone)).write_text('zone_token_1234567890123456789012')
                MODULE.owned_file = lambda path, mode=None: None
                warning = io.StringIO()
                with contextlib.redirect_stderr(warning):
                    self.assertFalse(MODULE.site_token_configured(domain, zone))
                self.assertIn('no per-site Cloudflare token', warning.getvalue())
                self.assertNotIn('legacy_token_123', warning.getvalue())

                token_path.write_text('site_token_1234567890123456789012')
                self.assertTrue(MODULE.site_token_configured(domain, zone))
                MODULE.owned_file = lambda path, mode=None: (_ for _ in ()).throw(ValueError('Unsafe file'))
                with self.assertRaises(ValueError):
                    MODULE.site_token_configured(domain, zone)
                token_path.unlink()
                try:
                    token_path.symlink_to(MODULE.BASE / 'token')
                except OSError:
                    # Windows may disallow symlinks; Ubuntu CI checks this branch.
                    self.skipTest('symlink creation unavailable on this host')
                self.assertTrue(token_path.is_symlink())
                def reject_symlink(path, mode=None):
                    if path.is_symlink():
                        raise ValueError('Unsafe file')
                MODULE.owned_file = reject_symlink
                with self.assertRaises(ValueError):
                    MODULE.site_token_configured(domain, zone)
            finally:
                MODULE.BASE, MODULE.owned_file = old_base, old_owned

    def test_skipped_site_cannot_replay_prior_hits_to_cloudflare(self):
        old_token = MODULE.token_for_site
        with sqlite3.connect(':memory:') as conn:
            conn.executescript('''CREATE TABLE hits(zone TEXT, domain TEXT, ip TEXT, at INTEGER);
                CREATE TABLE bans(zone TEXT, domain TEXT, ip TEXT, rule_id TEXT, expires INTEGER);''')
            conn.executemany('INSERT INTO hits VALUES(?,?,?,?)',
                             [('0123456789abcdef0123456789abcdef', 'blog.example.com', '8.8.8.8', 100)] * 5)
            try:
                MODULE.token_for_site = lambda domain, zone: (_ for _ in ()).throw(AssertionError('Cloudflare token must not be read'))
                MODULE.ban_candidates(conn, 100, set())
            finally:
                MODULE.token_for_site = old_token
            self.assertEqual(conn.execute('SELECT COUNT(*) FROM bans').fetchone()[0], 0)


if __name__ == '__main__':
    unittest.main()
