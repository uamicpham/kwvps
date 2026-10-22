#!/usr/bin/env python3
"""Optional Nginx limit_req -> Cloudflare zone IP Access rule bridge.

Never reads request headers. Only KwVPS-owned, root-controlled Nginx error logs
and explicit per-site opt-in files are accepted. The timer starts at EOF so an
old log cannot trigger a mass ban when this feature is enabled.
"""
import fcntl
import datetime
import ipaddress
import json
import os
import re
import sqlite3
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = Path('/etc/kwvps/cloudflare')
STATE = BASE / 'antiddos'
DB = BASE / 'limit-ban.sqlite3'
TOKEN = BASE / 'token'
REALIP = Path('/etc/nginx/conf.d/kwvps-cloudflare-realip.conf')
LOCK = Path('/run/lock/kwvps-cf-limit-ban.lock')
DOMAIN = re.compile(r'^[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$')
SITE_ID = re.compile(r'^[a-z0-9]{1,29}$')
ZONE = re.compile(r'^[0-9a-fA-F]{32}$')
REJECT = re.compile(r'^(\d{4}/\d\d/\d\d \d\d:\d\d:\d\d) \[error\] [^\n]*? limiting requests, excess: [0-9.]+ by zone "kwvps_antiddos_(5|10|20|50)", client: ([0-9a-fA-F:.]+), server: ([a-z0-9.-]+),')
TTL = 900
WINDOW = 60
THRESHOLD = 5
MAX_NEW_PER_RUN = 5
MAX_ACTIVE_PER_ZONE = 100


def owned_file(path, mode=None):
    st = path.lstat()
    if not stat.S_ISREG(st.st_mode) or st.st_uid != 0 or (mode is not None and st.st_mode & 0o777 != mode):
        raise ValueError(f'Unsafe file: {path}')


def api(token, method, path, payload=None):
    data = None if payload is None else json.dumps(payload).encode('utf-8')
    req = urllib.request.Request('https://api.cloudflare.com/client/v4/' + path,
                                 data=data, method=method,
                                 headers={'Authorization': 'Bearer ' + token,
                                          'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            result = json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f'Cloudflare HTTP {error.code}') from None
    if result.get('success') is not True:
        raise RuntimeError('Cloudflare API rejected request')
    return result.get('result')


def trusted_edges():
    owned_file(REALIP)
    networks = []
    for line in REALIP.read_text().splitlines():
        match = re.fullmatch(r'\s*set_real_ip_from\s+([^;\s]+);\s*', line)
        if match:
            net = ipaddress.ip_network(match.group(1), strict=True)
            # Never trust a blanket or local network as a Cloudflare edge.
            if net.prefixlen == 0 or net.is_private or net.is_loopback:
                raise ValueError('Unsafe Real IP proxy range')
            networks.append(net)
    if len(networks) < 10 or 'real_ip_header CF-Connecting-IP;' not in REALIP.read_text():
        raise ValueError('Cloudflare Real IP configuration incomplete')
    return networks


def configs():
    result = []
    for cfg in sorted(STATE.glob('*.push')):
        owned_file(cfg, 0o600)
        domain = cfg.name[:-5]
        if not DOMAIN.fullmatch(domain):
            raise ValueError('Invalid domain in push state')
        parts = cfg.read_text().splitlines()
        if len(parts) != 2 or not SITE_ID.fullmatch(parts[0]) or not ZONE.fullmatch(parts[1]):
            raise ValueError('Invalid push state')
        site, zone = parts
        rate = STATE / (domain + '.rate')
        owned_file(rate, 0o600)
        if rate.read_text().strip() not in ('5', '10', '20', '50'):
            raise ValueError('Nginx limit disabled or invalid')
        meta = Path('/etc/kwvps/sites') / (site + '.site')
        owned_file(meta)
        if 'domain=' + domain not in meta.read_text().splitlines():
            raise ValueError('Site/domain mismatch')
        ingress = Path('/etc/kwvps/ingress') / (domain + '.mode')
        if ingress.exists():
            owned_file(ingress, 0o600)
            if ingress.read_text().strip() != 'dns':
                continue
        elif subprocess.run(['systemctl', 'is-active', '--quiet', 'cloudflared.service'],
                            check=False).returncode == 0:
            # Unclassified site on a VPS with an active connector is unsafe.
            continue
        result.append((domain, site, zone))
    return result


def scan(conn, domain, site, zone, edges, now):
    log = Path('/var/log/nginx') / ('kwvps-' + site + '.error.log')
    if not log.exists():
        return
    owned_file(log)
    st = log.stat()
    row = conn.execute('SELECT inode, offset FROM offsets WHERE site=?', (site,)).fetchone()
    # New or rotated log: begin at EOF. Never replay historical traffic.
    offset = row[1] if row and row[0] == st.st_ino and row[1] <= st.st_size else st.st_size
    if st.st_size - offset > 2_000_000:
        offset = st.st_size
    with log.open('rb') as stream:
        stream.seek(offset)
        for raw in stream:
            if len(raw) > 8192:
                continue
            match = REJECT.search(raw.decode('utf-8', 'replace'))
            if not match or match.group(4) != domain:
                continue
            try:
                event = int(datetime.datetime.strptime(match.group(1), '%Y/%m/%d %H:%M:%S').timestamp())
            except ValueError:
                continue
            if not now - WINDOW <= event <= now + 5:
                continue
            try:
                ip = ipaddress.ip_address(match.group(3))
            except ValueError:
                continue
            if not ip.is_global or any(ip in net for net in edges):
                continue
            conn.execute('INSERT INTO hits(zone, ip, at) VALUES(?,?,?)', (zone, str(ip), event))
        end = stream.tell()
    conn.execute('INSERT OR REPLACE INTO offsets(site,inode,offset) VALUES(?,?,?)', (site, st.st_ino, end))


def reconcile(conn, token, now):
    for zone, ip, rule_id in conn.execute('SELECT zone,ip,rule_id FROM bans WHERE expires<=?', (now,)).fetchall():
        try:
            api(token, 'DELETE', f'zones/{zone}/firewall/access_rules/rules/{rule_id}')
        except RuntimeError as error:
            print(f'Could not expire ban {ip}: {error}', file=sys.stderr)
            continue
        conn.execute('DELETE FROM bans WHERE zone=? AND ip=?', (zone, ip))
    conn.execute('DELETE FROM hits WHERE at<?', (now - WINDOW,))


def ban_candidates(conn, token, now):
    candidates = conn.execute('''SELECT zone,ip,COUNT(*) AS n FROM hits
        WHERE at>=? GROUP BY zone,ip HAVING n>=? ORDER BY n DESC LIMIT ?''',
        (now - WINDOW, THRESHOLD, MAX_NEW_PER_RUN)).fetchall()
    for zone, ip, count in candidates:
        if conn.execute('SELECT 1 FROM bans WHERE zone=? AND ip=?', (zone, ip)).fetchone():
            continue
        if conn.execute('SELECT COUNT(*) FROM bans WHERE zone=?', (zone,)).fetchone()[0] >= MAX_ACTIVE_PER_ZONE:
            continue
        # Do not overwrite somebody else's access rule for this IP.
        existing = api(token, 'GET', f'zones/{zone}/firewall/access_rules/rules?configuration.value={ip}')
        if existing:
            continue
        result = api(token, 'POST', f'zones/{zone}/firewall/access_rules/rules', {
            'mode': 'block', 'configuration': {'target': 'ip' if ':' not in ip else 'ip6', 'value': ip},
            'notes': f'KwVPS Nginx limit; {count} rejects/60s; expires {now + TTL}'})
        rule_id = result.get('id') if isinstance(result, dict) else None
        if not isinstance(rule_id, str) or not ZONE.fullmatch(rule_id):
            raise RuntimeError('Cloudflare created a rule but did not return a valid ID; inspect dashboard')
        conn.execute('INSERT INTO bans(zone,ip,rule_id,expires) VALUES(?,?,?,?)', (zone, ip, rule_id, now + TTL))
        conn.execute('DELETE FROM hits WHERE zone=? AND ip=?', (zone, ip))
        print(f'Cloudflare blocked {ip} in zone {zone} for {TTL}s')


def main():
    if os.geteuid() != 0:
        raise ValueError('root required')
    owned_file(TOKEN, 0o600)
    token = TOKEN.read_text().strip()
    if not re.fullmatch(r'[A-Za-z0-9._-]{20,256}', token):
        raise ValueError('Invalid Cloudflare token')
    if len(sys.argv) == 3 and sys.argv[1] == '--check-zone':
        zone = sys.argv[2]
        if not ZONE.fullmatch(zone):
            raise ValueError('Invalid Zone ID')
        api(token, 'GET', f'zones/{zone}/firewall/access_rules/rules?per_page=1')
        print('Cloudflare IP Access read OK; write permission still requires a live trial')
        return
    if len(sys.argv) != 1:
        raise ValueError('Invalid arguments')
    edges = trusted_edges()
    active = configs()
    if not active and not DB.exists():
        return
    with LOCK.open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if DB.exists():
            owned_file(DB, 0o600)
        with sqlite3.connect(DB) as conn:
            os.chmod(DB, 0o600)
            conn.executescript('''CREATE TABLE IF NOT EXISTS offsets(site TEXT PRIMARY KEY,inode INTEGER,offset INTEGER);
                CREATE TABLE IF NOT EXISTS hits(zone TEXT,ip TEXT,at INTEGER);
                CREATE TABLE IF NOT EXISTS bans(zone TEXT,ip TEXT,rule_id TEXT,expires INTEGER,
                PRIMARY KEY(zone,ip));''')
            now = int(time.time())
            for domain, site, zone in active:
                scan(conn, domain, site, zone, edges, now)
            reconcile(conn, token, now)
            ban_candidates(conn, token, now)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, RuntimeError, sqlite3.Error) as error:
        print(f'KwVPS CF limit bridge: {error}', file=sys.stderr)
        sys.exit(1)
