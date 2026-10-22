#!/usr/bin/env bash
# Installer for a CLEAN Ubuntu 24.04 VPS. A release bundle may carry its
# public GitHub owner/repo; no token or secret is embedded in the bundle.
set -Eeuo pipefail
if ((BASH_VERSINFO[0] < 5)); then
  printf 'Cần Bash 5 trở lên.\n' >&2
  exit 2
fi
KW_INSTALL_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly KW_INSTALL_ROOT
# shellcheck source=src/core.sh
source "$KW_INSTALL_ROOT/src/core.sh"
# shellcheck source=src/system.sh
source "$KW_INSTALL_ROOT/src/system.sh"
# shellcheck source=src/updates.sh
source "$KW_INSTALL_ROOT/src/updates.sh"
# shellcheck source=src/php.sh
source "$KW_INSTALL_ROOT/src/php.sh"
readonly -a KW_INSTALL_MODULES=(
  core.sh system.sh updates.sh sites.sh php.sh backups.sh config_backups.sh
  db.sh db_manage.sh rename.sh fail2ban.sh firewall.sh swap.sh nginx.sh
  acme.sh ssl.sh cloudflare.sh tunnel.sh ssh.sh cache.sh utilities.sh
  cron.sh menu.sh
)

install_usage() {
  printf '%s\n' \
    'KwVPS installer — chỉ cho VPS Ubuntu Server 24.04 LTS sạch.' \
    'bash install.sh --check   Kiểm tra điều kiện (không thay đổi máy)' \
    'sudo bash install.sh --apply   Cài package nền tảng và lệnh kwvps' \
    'Bản release GitHub được tải và kiểm tra SHA-256 trước khi gọi bộ cài.'
}

install_existing_panel() {
  local tool path
  for tool in larvps aapanel bt; do
    if command -v "$tool" >/dev/null 2>&1; then return 0; fi
  done
  for path in /etc/larvps /opt/larvps /www/server/panel /usr/local/lsws; do
    [[ ! -e $path && ! -L $path ]] || return 0
  done
  return 1
}

install_source_preflight() {
  local file release_repo
  for file in kwvps scripts/kwvps-launcher scripts/restore_source.py \
    scripts/cf_limit_ban.py scripts/kwvps-cf-limit-ban.service \
    scripts/kwvps-cf-limit-ban.timer; do
    [[ -f $KW_INSTALL_ROOT/$file && ! -L $KW_INSTALL_ROOT/$file ]] || {
      printf '[STOP] Thiếu hoặc có symlink: %s\n' "$file" >&2
      return 2
    }
  done
  for file in "${KW_INSTALL_MODULES[@]}"; do
    file="$KW_INSTALL_ROOT/src/$file"
    [[ -f $file && ! -L $file ]] && bash -n "$file" || return 2
  done
  bash -n "$KW_INSTALL_ROOT/kwvps" || return 2
  if [[ -e $KW_INSTALL_ROOT/release-repo || -L $KW_INSTALL_ROOT/release-repo ]]; then
    [[ -f $KW_INSTALL_ROOT/release-repo && ! -L $KW_INSTALL_ROOT/release-repo ]] || return 2
    IFS= read -r release_repo < "$KW_INSTALL_ROOT/release-repo" || return 2
    kw_github_repo_valid "$release_repo" || return 2
  fi
}

install_preflight() {
  local failed=0
  kw_os_show
  if kw_os_supported ''; then printf '[OK] Ubuntu 24.04\n';
  else printf '[STOP] Cần Ubuntu 24.04\n'; failed=1; fi
  if [[ $(uname -m) == x86_64 ]]; then printf '[OK] x86_64\n';
  else printf '[STOP] Kiến trúc này chưa được hỗ trợ; cần x86_64.\n'; failed=1; fi
  if [[ -d /run/systemd/system ]]; then printf '[OK] systemd\n';
  else printf '[STOP] systemd chưa chạy\n'; failed=1; fi
  if install_existing_panel; then
    printf '[STOP] Phát hiện control panel có sẵn.\n'
    failed=1
  fi
  if [[ -f /etc/kwvps/install-id ]]; then
    if [[ $(< /etc/kwvps/install-id) == kwvps-v1 ]]; then
      if ((failed == 0)) && [[ -x /usr/local/bin/kwvps && -x /opt/kwvps/kwvps ]]; then
        printf '[OK] KwVPS đã được cài; không cài lại.\n'
        return 10
      fi
      printf '[STOP] Cài đặt KwVPS chưa hoàn chỉnh hoặc có xung đột.\n'
      return 1
    fi
    printf '[STOP] Marker cài đặt không hợp lệ.\n'
    failed=1
  fi
  if [[ -e /usr/local/bin/kwvps || -L /usr/local/bin/kwvps || -e /opt/kwvps || -L /opt/kwvps ]]; then
    printf '[STOP] Đích cài KwVPS đã tồn tại.\n'
    failed=1
  fi
  if [[ -e /etc/nginx || -L /etc/nginx ]] || command -v nginx >/dev/null 2>&1 || \
     command -v apache2 >/dev/null 2>&1 || [[ -e /var/www/html ]]; then
    printf '[STOP] Phát hiện web stack hoặc dữ liệu web hiện có; cần VPS thử nghiệm mới.\n'
    failed=1
  fi
  if command -v apt-get >/dev/null 2>&1; then printf '[OK] apt-get\n';
  else printf '[STOP] Thiếu apt-get\n'; failed=1; fi
  if install_source_preflight; then printf '[OK] Bộ mã cài đặt đầy đủ\n';
  else printf '[STOP] Bộ mã cài đặt thiếu/hỏng\n'; failed=1; fi
  return "$failed"
}

install_apply() {
  local result=0 phrase file candidate release_repo
  ((EUID == 0)) || { printf 'Cần sudo/root để cài.\n' >&2; return 2; }
  install_preflight || result=$?
  if ((result == 10)); then return 0; fi
  ((result == 0)) || return 2
  printf '\nSẽ cài Nginx, PHP 8.3 FPM, MariaDB, Fail2ban, UFW, cron, nano, curl và KwVPS. Không bật UFW, cấu hình DNS hay SSL.\n'
  printf 'Nhập INSTALL KWVPS để xác nhận: '
  [[ -r /dev/tty ]] || { printf 'Cần terminal tương tác.\n' >&2; return 2; }
  IFS= read -r phrase < /dev/tty || return 2
  [[ $phrase == 'INSTALL KWVPS' ]] || { printf 'Đã hủy cài đặt.\n'; return 130; }
  apt-get update || { printf 'ERROR: apt-get update thất bại; chưa cài package.\n' >&2; return 1; }
  candidate=$(kw_apt_candidate php8.3-fpm) || {
    printf 'ERROR: Không đọc được bản PHP 8.3 ứng viên từ APT; chưa cài package.\n' >&2
    return 1
  }
  if ! kw_php_package_version_safe 8.3 "$candidate"; then
    printf 'DỪNG: PHP 8.3 ứng viên (%s) chưa có bản vá RCE được xác minh. Cần gói Ubuntu 24.04 .13 trở lên hoặc upstream 8.3.36 trở lên.\n' "$candidate" >&2
    return 2
  fi
  apt-get install -y nginx php8.3-fpm mariadb-server fail2ban ufw cron nano curl || {
    printf 'ERROR: Cài package thất bại; cần kiểm tra APT trước khi chạy lại KwVPS.\n' >&2
    return 1
  }
  kw_php_security_ready 8.3 || return 2
  systemctl enable --now nginx php8.3-fpm mariadb fail2ban cron || return 1
  install -d -m 0755 /opt/kwvps /opt/kwvps/src /opt/kwvps/scripts /var/www/kwvps || return 1
  install -d -m 0755 /etc/kwvps /etc/kwvps/sites || return 1
  install -m 0755 "$KW_INSTALL_ROOT/kwvps" /opt/kwvps/kwvps || return 1
  for file in "${KW_INSTALL_MODULES[@]}"; do
    install -m 0644 "$KW_INSTALL_ROOT/src/$file" "/opt/kwvps/src/$file" || return 1
  done
  install -m 0644 "$KW_INSTALL_ROOT/scripts/restore_source.py" /opt/kwvps/scripts/restore_source.py || return 1
  install -m 0700 "$KW_INSTALL_ROOT/scripts/cf_limit_ban.py" /opt/kwvps/scripts/cf_limit_ban.py || return 1
  install -m 0644 "$KW_INSTALL_ROOT/scripts/kwvps-cf-limit-ban.service" /etc/systemd/system/kwvps-cf-limit-ban.service || return 1
  install -m 0644 "$KW_INSTALL_ROOT/scripts/kwvps-cf-limit-ban.timer" /etc/systemd/system/kwvps-cf-limit-ban.timer || return 1
  if [[ -f $KW_INSTALL_ROOT/release-repo && ! -L $KW_INSTALL_ROOT/release-repo ]]; then
    IFS= read -r release_repo < "$KW_INSTALL_ROOT/release-repo" || return 2
    kw_github_repo_valid "$release_repo" || return 2
    install -m 0600 "$KW_INSTALL_ROOT/release-repo" /etc/kwvps/github-repo || return 1
  fi
  systemctl daemon-reload || return 1
  nginx -t || return 1
  install -m 0755 "$KW_INSTALL_ROOT/scripts/kwvps-launcher" /usr/local/bin/kwvps || return 1
  printf 'kwvps-v1\n' > /etc/kwvps/install-id || return 1
  chmod 0644 /etc/kwvps/install-id || return 1
  printf 'Cài xong. Chạy kwvps --doctor rồi mở menu bằng kwvps.\n'
}

case "${1:---help}" in
  --help|-h) (($# == 1)) || exit 2; install_usage ;;
  --check)
    (($# == 1)) || exit 2
    result=0
    install_preflight || result=$?
    ((result == 10)) && result=0
    exit "$result"
    ;;
  --apply) (($# == 1)) || exit 2; install_apply ;;
  *) install_usage >&2; exit 2 ;;
esac
