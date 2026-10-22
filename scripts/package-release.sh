#!/usr/bin/env bash
# Build a small, reproducible release archive from an explicit allowlist.
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$root"
repo=${1:-}
[[ $repo =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}/[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$ && $repo != *..* ]] || {
  printf 'Dùng: bash scripts/package-release.sh owner/repo\n' >&2
  exit 2
}
version=$(bash kwvps --version)
version=${version#KwVPS }
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'Chỉ đóng gói phiên bản chính thức dạng x.y.z; hiện tại: %s\n' "$version" >&2
  exit 2
}
stage=$(mktemp -d /tmp/kwvps-package.XXXXXXXX)
[[ $stage == /tmp/kwvps-package.* && -d $stage && ! -L $stage ]] || exit 2
trap 'rm -rf -- "$stage"' EXIT
install -d -m 0755 "$stage/kwvps/src" "$stage/kwvps/scripts" "$root/dist"
install -m 0755 install.sh upgrade.sh kwvps "$stage/kwvps/"
install -m 0755 scripts/kwvps-launcher scripts/cf_limit_ban.py "$stage/kwvps/scripts/"
install -m 0644 scripts/restore_source.py scripts/kwvps-cf-limit-ban.service \
  scripts/kwvps-cf-limit-ban.timer "$stage/kwvps/scripts/"
for file in core.sh system.sh updates.sh sites.sh php.sh backups.sh config_backups.sh \
  db.sh db_manage.sh rename.sh fail2ban.sh firewall.sh swap.sh nginx.sh acme.sh \
  ssl.sh cloudflare.sh tunnel.sh ssh.sh cache.sh utilities.sh cron.sh menu.sh; do
  install -m 0644 "src/$file" "$stage/kwvps/src/$file"
done
printf '%s\n' "$repo" > "$stage/kwvps/release-repo"
chmod 0644 "$stage/kwvps/release-repo"
bash -n "$stage/kwvps/install.sh" "$stage/kwvps/upgrade.sh" "$stage/kwvps/kwvps"
for file in "$stage"/kwvps/src/*.sh; do bash -n "$file"; done
archive="$root/dist/kwvps-$version.tar.gz"
[[ ! -e $archive && ! -L $archive ]] || {
  printf 'Gói %s đã tồn tại; không ghi đè.\n' "$archive" >&2
  exit 2
}
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -czf "$archive" -C "$stage" kwvps
sha256sum "$archive" > "$archive.sha256"
printf 'Đã tạo %s và checksum. Tạo GitHub release tag v%s, tải đúng gói này lên, rồi đối chiếu SHA-256.\n' "$archive" "$version"
