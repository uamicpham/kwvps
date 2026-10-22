#!/usr/bin/env bash
# Snapshot KwVPS-owned domain configuration, not source/DB/certificate private keys.

kw_config_backup_name_valid() {
  [[ ${1:-} =~ ^config-[a-z0-9]{1,29}-[0-9]{8}T[0-9]{6}Z-[[:alnum:]]{8}\.tar\.gz$ ]]
}

kw_config_backup_preflight() {
  local domain=${1,,} file
  ((EUID == 0)) || return 2
  kw_os_supported '' || return 2
  kw_site_lookup "$domain" || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && \
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  for file in "$KW_SITE_META" "$KW_SITE_POOL" "$KW_SITE_VHOST"; do
    [[ -f $file && ! -L $file && $(stat -c %u -- "$file") == 0 ]] || return 2
  done
  [[ -L $KW_SITE_ENABLED && $(readlink -f -- "$KW_SITE_ENABLED") == "$KW_SITE_VHOST" ]] || return 2
  kw_backup_dir_safe /var/backups 0022 || return 2
  if [[ -e $KW_BACKUP_ROOT || -L $KW_BACKUP_ROOT ]]; then
    kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  fi
}

kw_config_backup_locked() (
  local domain=$1 id stamp stage='' archive='' checksum='' final digest
  kw_config_backup_preflight "$domain" || return 2
  if [[ ! -e $KW_BACKUP_ROOT && ! -L $KW_BACKUP_ROOT ]]; then
    install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT" || return 1
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  id=${KW_SITE_OWNER#kw}
  stamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
  stage=$(mktemp -d "$KW_BACKUP_ROOT/.config-stage.XXXXXXXX") || return 1
  trap '[[ -z $archive ]] || rm -f -- "$archive"; [[ -z $checksum ]] || rm -f -- "$checksum"; if [[ -n $stage ]]; then rm -f -- "$stage/site.meta" "$stage/pool.conf" "$stage/vhost.conf"; rmdir -- "$stage" || true; fi' EXIT
  chmod 0700 -- "$stage" || return 1
  install -m 0600 -o root -g root -- "$KW_SITE_META" "$stage/site.meta" || return 1
  install -m 0600 -o root -g root -- "$KW_SITE_POOL" "$stage/pool.conf" || return 1
  install -m 0600 -o root -g root -- "$KW_SITE_VHOST" "$stage/vhost.conf" || return 1
  archive=$(mktemp "$KW_BACKUP_ROOT/.config-archive.XXXXXXXX") || return 1
  chmod 0600 -- "$archive" || return 1
  tar -C "$stage" -czf "$archive" -- site.meta pool.conf vhost.conf || return 1
  [[ -s $archive ]] && tar -tzf "$archive" >/dev/null || return 1
  digest=$(sha256sum -- "$archive") || return 1
  digest=${digest%% *}
  final="$KW_BACKUP_ROOT/config-${id}-${stamp}-${archive##*.}.tar.gz"
  [[ ! -e $final && ! -L $final && ! -e $final.sha256 && ! -L $final.sha256 ]] || return 2
  checksum=$(mktemp "$KW_BACKUP_ROOT/.config-checksum.XXXXXXXX") || return 1
  chmod 0600 -- "$checksum" || return 1
  printf '%s  %s\n' "$digest" "${final##*/}" > "$checksum" || return 1
  mv -T -- "$archive" "$final" || return 1
  archive=''
  mv -T -- "$checksum" "$final.sha256" || return 1
  checksum=''
  printf 'Đã backup cấu hình domain %s: %s\nSHA-256: %s\n' "$domain" "$final" "$digest"
  printf 'Gồm metadata, PHP pool, Nginx vhost. KHÔNG phải gói chuyển VPS: thiếu source, DB, SSL key, ingress, rate limit, Zone ID, token, cron và cấu hình dịch vụ chung.\n'
)

kw_config_backup() (
  local domain=${1,,} confirm=${2:-}
  kw_domain_valid "$domain" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || return 1
  kw_config_backup_locked "$domain"
)

kw_config_backup_interactive() {
  local domain confirm
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  printf 'Backup cấu hình %s chỉ gồm metadata, PHP pool và Nginx vhost; chưa dùng để chuyển VPS.\n' "$domain"
  printf 'Thiếu source, DB, SSL key, ingress, rate limit, Cloudflare token/Zone ID, cron và cấu hình toàn VPS.\n'
  kw_prompt_yes_no_token "Backup cấu hình $domain?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_config_backup "$domain" "${confirm,,}"
}

kw_config_backup_choose() {
  local id=${1:-} file name choice count=0 backup_id domain
  local -a names=()
  ((EUID == 0)) || return 2
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  printf 'Chọn backup cấu hình domain:\n'
  for file in "$KW_BACKUP_ROOT"/config-*.tar.gz; do
    [[ -f $file && ! -L $file ]] || continue
    name=${file##*/}
    kw_config_backup_name_valid "$name" || continue
    [[ -z $id || $name == "config-${id}-"* ]] || continue
    names+=("$name")
    count=$((count + 1))
    backup_id=${name#config-}; backup_id=${backup_id%%-*}
    domain=$(kw_backup_site_label "$backup_id") || return 2
    printf '%2d. %s | %s\n' "$count" "$name" "$domain"
  done
  ((count)) || { printf 'Không có backup cấu hình phù hợp.\n'; return 1; }
  printf ' 0. Quay lại\nChọn số backup: '
  IFS= read -r choice || return 1
  [[ $choice =~ ^[1-9][0-9]*$ ]] && ((choice <= count)) || return 1
  KW_CONFIG_BACKUP_CHOICE=${names[choice-1]}
}

kw_config_backup_verify() {
  local name=$1 path line expected actual listing
  ((EUID == 0)) || return 2
  kw_config_backup_name_valid "$name" || return 2
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  path="$KW_BACKUP_ROOT/$name"
  [[ -f $path && ! -L $path && -f $path.sha256 && ! -L $path.sha256 ]] || return 2
  IFS= read -r line < "$path.sha256" || return 2
  expected=${line%%  *}
  [[ $expected =~ ^[0-9a-f]{64}$ && $line == "$expected  $name" ]] || return 2
  actual=$(sha256sum -- "$path") || return 2
  [[ ${actual%% *} == "$expected" ]] || return 2
  listing=$(tar -tzf "$path") || return 2
  [[ $listing == $'site.meta\npool.conf\nvhost.conf' ]] || return 2
  printf 'Backup cấu hình hợp lệ về checksum và danh sách file: %s\n' "$name"
  printf 'Chưa thực hiện restore; chứng chỉ và dữ liệu ứng dụng nằm ngoài gói này.\n'
}

kw_config_backup_verify_interactive() {
  local name
  kw_config_backup_choose '' || return 0
  name=$KW_CONFIG_BACKUP_CHOICE
  kw_config_backup_verify "$name"
}

kw_config_backup_list() {
  local file name count=0 id domain
  ((EUID == 0)) || return 2
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  printf 'Backup cấu hình domain:\n'
  for file in "$KW_BACKUP_ROOT"/config-*.tar.gz; do
    [[ -f $file && ! -L $file ]] || continue
    name=${file##*/}
    kw_config_backup_name_valid "$name" || continue
    count=$((count + 1))
    id=${name#config-}; id=${id%%-*}
    domain=$(kw_backup_site_label "$id") || return 2
    printf '%2d. %s | %s\n' "$count" "$name" "$domain"
  done
  ((count)) || printf 'Chưa có backup cấu hình.\n'
}

kw_config_restore_locked() (
  local domain=$1 name=$2 id stage='' changed=0 committed=0 old_identity new_identity old_tls=0 new_tls=0
  kw_config_backup_preflight "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  kw_config_backup_name_valid "$name" && [[ $name == "config-${id}-"* ]] || return 2
  kw_config_backup_verify "$name" >/dev/null || return 2
  kw_has php-fpm"$KW_SITE_PHP" && kw_has nginx && kw_has curl || return 2
  stage=$(mktemp -d "$KW_BACKUP_ROOT/.config-restore.XXXXXXXX") || return 1
  chmod 0700 -- "$stage" || return 1
  trap 'if ((changed == 1 && committed == 0)); then install -m 0644 -o root -g root -- "$stage/old.pool" "$KW_SITE_POOL"; install -m 0644 -o root -g root -- "$stage/old.vhost" "$KW_SITE_VHOST"; "php-fpm${KW_SITE_PHP}" -t && nginx -t && systemctl reload "php${KW_SITE_PHP}-fpm" && systemctl reload nginx || kw_log ERROR "Rollback cấu hình cần kiểm tra thủ công: $stage"; fi; if [[ -n $stage ]]; then rm -f -- "$stage/old.pool" "$stage/old.vhost" "$stage/new.meta" "$stage/new.pool" "$stage/new.vhost"; rmdir -- "$stage" || true; fi' EXIT
  install -m 0600 -o root -g root -- "$KW_SITE_POOL" "$stage/old.pool" || return 1
  install -m 0600 -o root -g root -- "$KW_SITE_VHOST" "$stage/old.vhost" || return 1
  tar -xOzf "$KW_BACKUP_ROOT/$name" site.meta > "$stage/new.meta" || return 1
  tar -xOzf "$KW_BACKUP_ROOT/$name" pool.conf > "$stage/new.pool" || return 1
  tar -xOzf "$KW_BACKUP_ROOT/$name" vhost.conf > "$stage/new.vhost" || return 1
  cmp -s -- "$KW_SITE_META" "$stage/new.meta" || {
    kw_log ERROR 'Metadata trong backup khác site hoặc PHP hiện tại; từ chối restore.'; return 2;
  }
  old_identity=$(kw_php_pool_identity "$KW_SITE_POOL") || return 2
  new_identity=$(kw_php_pool_identity "$stage/new.pool") || return 2
  [[ $new_identity == "$old_identity" ]] || {
    kw_log ERROR 'Backup thay đổi user/group/socket/ràng buộc pool; từ chối restore.'; return 2;
  }
  grep -Fxq "# Managed by KwVPS. Site ID: $id" "$stage/new.vhost" || return 2
  grep -Eq "^[[:space:]]*server_name[[:space:]]+${domain//./\.};" "$stage/new.vhost" || return 2
  grep -Fxq "  root /var/www/kwvps/$id/public;" "$stage/new.vhost" || return 2
  grep -Fxq "    fastcgi_pass unix:/run/php/kwvps-$id.sock;" "$stage/new.vhost" || return 2
  grep -Fxq "# KwVPS TLS: Let's Encrypt" "$KW_SITE_VHOST" && old_tls=1
  grep -Fxq "# KwVPS TLS: Let's Encrypt" "$stage/new.vhost" && new_tls=1
  [[ $old_tls == "$new_tls" ]] || {
    kw_log ERROR 'Không chuyển HTTP ↔ HTTPS qua restore cấu hình.'; return 2;
  }
  if cmp -s -- "$KW_SITE_POOL" "$stage/new.pool" && cmp -s -- "$KW_SITE_VHOST" "$stage/new.vhost"; then
    printf 'Cấu hình hiện tại đã khớp backup; không thay đổi.\n'; return 0
  fi
  kw_config_backup_locked "$domain" || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  changed=1
  install -m 0644 -o root -g root -- "$stage/new.pool" "$KW_SITE_POOL" || return 1
  install -m 0644 -o root -g root -- "$stage/new.vhost" "$KW_SITE_VHOST" || return 1
  "php-fpm${KW_SITE_PHP}" -t || return 1
  nginx -t || return 1
  systemctl reload "php${KW_SITE_PHP}-fpm" || return 1
  systemctl reload nginx || return 1
  if ((new_tls)); then
    curl --fail --silent --show-error --max-time 15 --resolve "$domain:443:127.0.0.1" \
      "https://$domain/" -o /dev/null || return 1
  else
    curl --fail --silent --show-error --max-time 15 --resolve "$domain:80:127.0.0.1" \
      "http://$domain/" -o /dev/null || return 1
  fi
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  committed=1
  printf 'Đã khôi phục pool và vhost của %s từ %s. Metadata/SSL/source/DB không thay đổi.\n' "$domain" "$name"
)

kw_config_restore() (
  local domain=${1,,} name=$2 confirm=${3:-}
  kw_domain_valid "$domain" && kw_config_backup_name_valid "$name" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || return 1
  kw_config_restore_locked "$domain" "$name"
)

kw_config_restore_interactive() {
  local domain name confirm
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_config_backup_choose "$(kw_site_id "$domain")" || return 0
  name=$KW_CONFIG_BACKUP_CHOICE
  printf 'Sẽ khôi phục PHP pool và Nginx vhost cho %s từ %s.\n' "$domain" "$name"
  printf 'Chỉ nhận cùng metadata/PHP và cùng chế độ HTTP/HTTPS; tự backup cấu hình hiện tại trước.\n'
  kw_prompt_yes_no_token "Restore cấu hình $domain từ bản đã chọn?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_config_restore "$domain" "$name" "${confirm,,}"
}
