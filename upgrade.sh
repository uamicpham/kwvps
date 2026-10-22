#!/usr/bin/env bash
# Upgrade an existing KwVPS test installation without touching site data or services.
set -Eeuo pipefail
if ((BASH_VERSINFO[0] < 5)); then
  printf 'Cần Bash 5 trở lên.\n' >&2
  exit 2
fi
KW_UPGRADE_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly KW_UPGRADE_ROOT
# shellcheck source=src/core.sh
source "$KW_UPGRADE_ROOT/src/core.sh"
# shellcheck source=src/system.sh
source "$KW_UPGRADE_ROOT/src/system.sh"
# shellcheck source=src/updates.sh
source "$KW_UPGRADE_ROOT/src/updates.sh"

upgrade_usage() {
  printf '%s\n' \
    'KwVPS upgrade — chỉ cho bản KwVPS đã cài trên VPS thử nghiệm Ubuntu 24.04.' \
    'bash upgrade.sh --check' \
    'sudo bash upgrade.sh --apply --confirm=UPGRADE-KWVPS' \
    'Giữ nguyên site, /etc/kwvps, backup và service; lưu bản mã cũ tại /opt/kwvps-previous-*.'
}

upgrade_preflight() {
  local file
  command -v runuser >/dev/null 2>&1 || return 2
  kw_os_supported '' || { kw_log ERROR 'Chỉ hỗ trợ Ubuntu 24.04.'; return 2; }
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && \
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || {
    kw_log ERROR 'Không tìm thấy bản KwVPS hợp lệ đã cài.'; return 2;
  }
  [[ -d /opt/kwvps && ! -L /opt/kwvps && \
     -d /opt/kwvps/src && ! -L /opt/kwvps/src && \
     -f /opt/kwvps/kwvps && ! -L /opt/kwvps/kwvps && \
     -f /usr/local/bin/kwvps && ! -L /usr/local/bin/kwvps ]] || {
    kw_log ERROR 'Đường dẫn bản cài không đúng cấu trúc.'; return 2;
  }
  [[ $(stat -c %u -- /opt /opt/kwvps /opt/kwvps/src /usr/local/bin/kwvps) == $'0\n0\n0\n0' ]] || {
    kw_log ERROR 'Bản cài không thuộc sở hữu root.'; return 2;
  }
  for file in kwvps src/core.sh src/system.sh src/updates.sh src/sites.sh src/php.sh src/backups.sh src/config_backups.sh src/db.sh src/db_manage.sh src/rename.sh src/fail2ban.sh src/firewall.sh src/swap.sh src/nginx.sh src/acme.sh src/ssl.sh src/cloudflare.sh src/tunnel.sh src/ssh.sh src/cache.sh src/utilities.sh src/cron.sh src/menu.sh; do
    [[ -f $KW_UPGRADE_ROOT/$file && ! -L $KW_UPGRADE_ROOT/$file ]] || {
      kw_log ERROR "Thiếu hoặc gặp symlink tại mã nguồn $file."; return 2;
    }
    bash -n "$KW_UPGRADE_ROOT/$file" || return 2
  done
  [[ -f $KW_UPGRADE_ROOT/scripts/restore_source.py && ! -L $KW_UPGRADE_ROOT/scripts/restore_source.py ]] || return 2
  command -v python3 >/dev/null 2>&1 || return 2
  python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text())' \
    "$KW_UPGRADE_ROOT/scripts/restore_source.py" || return 2
  bash -n /opt/kwvps/kwvps || return 2
  if ! command -v nginx >/dev/null 2>&1 || ! nginx -t >/dev/null 2>&1; then
    kw_log ERROR 'Nginx hiện tại không vượt qua kiểm tra cấu hình.'; return 2;
  fi
}

upgrade_check() {
  local installed_version
  upgrade_preflight || return 2
  printf 'Bản đang cài: '
  /opt/kwvps/kwvps --version
  printf 'Bản mã mới: '
  bash "$KW_UPGRADE_ROOT/kwvps" --version
  installed_version=$(/opt/kwvps/kwvps --version) || return 2
  installed_version=${installed_version#KwVPS }
  [[ $installed_version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-dev)?$ &&
     $KW_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+(-dev)?$ ]] || return 2
  if ! dpkg --compare-versions "$KW_VERSION" gt "$installed_version"; then
    kw_log ERROR "Gói $KW_VERSION không mới hơn bản đã cài $installed_version; từ chối hạ/cài lại bằng luồng nâng cấp."
    return 2
  fi
  printf 'Chỉ thay bộ mã ở /opt/kwvps; không sửa site, cấu hình Nginx/PHP, database hoặc firewall.\n'
  printf 'Bản cũ sẽ được giữ tại /opt/kwvps-previous-<thời gian>-<ngẫu nhiên>.\n'
}

upgrade_apply_locked() {
  local stage='' previous='' failed='' suffix timestamp file
  upgrade_preflight || return 2
  stage=$(mktemp -d /opt/.kwvps-upgrade.XXXXXXXX) || return 1
  chmod 0755 -- "$stage" || return 1
  install -d -m 0755 -- "$stage/src" "$stage/scripts" || return 1
  install -m 0755 -- "$KW_UPGRADE_ROOT/kwvps" "$stage/kwvps" || return 1
  for file in core.sh system.sh updates.sh sites.sh php.sh backups.sh config_backups.sh db.sh db_manage.sh rename.sh fail2ban.sh firewall.sh swap.sh nginx.sh acme.sh ssl.sh cloudflare.sh tunnel.sh ssh.sh cache.sh utilities.sh cron.sh menu.sh; do
    install -m 0644 -- "$KW_UPGRADE_ROOT/src/$file" "$stage/src/$file" || return 1
  done
  install -m 0644 -- "$KW_UPGRADE_ROOT/scripts/restore_source.py" "$stage/scripts/restore_source.py" || return 1
  install -m 0700 -- "$KW_UPGRADE_ROOT/scripts/cf_limit_ban.py" "$stage/scripts/cf_limit_ban.py" || return 1
  [[ $(bash "$stage/kwvps" --version) == "KwVPS $KW_VERSION" ]] || return 1
  [[ $(runuser -u nobody -- "$stage/kwvps" --version) == "KwVPS $KW_VERSION" ]] || return 1
  bash "$stage/kwvps" --doctor >/dev/null || return 1
  bash "$stage/kwvps" --site-list >/dev/null || return 1
  timestamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
  suffix=${stage##*.}
  previous="/opt/kwvps-previous-${timestamp}-${suffix}"
  failed="/opt/kwvps-failed-${timestamp}-${suffix}"
  [[ ! -e $previous && ! -L $previous && ! -e $failed && ! -L $failed ]] || return 1
  mv -T -- /opt/kwvps "$previous" || return 1
  if ! mv -T -- "$stage" /opt/kwvps; then
    mv -T -- "$previous" /opt/kwvps || kw_log ERROR "Cần khôi phục thủ công từ $previous."
    return 1
  fi
  if ! /opt/kwvps/kwvps --doctor >/dev/null || \
     ! /opt/kwvps/kwvps --site-list >/dev/null || \
     ! runuser -u nobody -- /usr/local/bin/kwvps --version >/dev/null || \
     ! nginx -t >/dev/null 2>&1; then
    kw_log ERROR 'Bản mới không qua kiểm tra; đang trả mã cũ về.'
    if mv -T -- /opt/kwvps "$failed" && mv -T -- "$previous" /opt/kwvps; then
      kw_log WARN "Đã trả mã cũ; mã lỗi giữ tại $failed."
    else
      kw_log ERROR "Rollback không hoàn chỉnh; kiểm tra $previous và $failed ngay."
    fi
    return 1
  fi
  install -m 0644 -- "$KW_UPGRADE_ROOT/scripts/kwvps-cf-limit-ban.service" /etc/systemd/system/kwvps-cf-limit-ban.service || return 1
  install -m 0644 -- "$KW_UPGRADE_ROOT/scripts/kwvps-cf-limit-ban.timer" /etc/systemd/system/kwvps-cf-limit-ban.timer || return 1
  systemctl daemon-reload || return 1
  printf 'Đã nâng cấp: '
  /opt/kwvps/kwvps --version
  printf 'Bản mã trước được giữ tại %s\n' "$previous"
}

upgrade_apply() {
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root.'; return 2; }
  upgrade_check || return 2
  exec 9>/run/lock/kwvps-upgrade.lock || return 2
  flock -n 9 || { kw_log ERROR 'Đang có lần nâng cấp khác.'; return 1; }
  upgrade_apply_locked
}

case "${1:---help}" in
  --help|-h) (($# == 1)) || exit 2; upgrade_usage ;;
  --check) (($# == 1)) || exit 2; upgrade_check ;;
  --apply)
    (($# == 2)) || { upgrade_usage >&2; exit 2; }
    [[ $2 == --confirm=UPGRADE-KWVPS ]] || { kw_log ERROR 'Thiếu xác nhận UPGRADE-KWVPS.'; exit 2; }
    upgrade_apply
    ;;
  *) upgrade_usage >&2; exit 2 ;;
esac
