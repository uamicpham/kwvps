#!/usr/bin/env bash
# Nginx changes are limited to KwVPS-owned files and tested before restart.
readonly KW_NGINX_BASELINE=/etc/nginx/conf.d/kwvps-baseline.conf

kw_nginx_render_baseline() {
  printf '%s\n' \
    '# Managed by KwVPS. Global HTTP baseline.' \
    'server_tokens off;' \
    'client_max_body_size 32m;'
}

kw_nginx_ready() {
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để thay cấu hình Nginx.'; return 2; }
  kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && \
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  kw_has nginx && kw_has systemctl && kw_has flock || return 2
  systemctl is-active --quiet nginx || return 2
}

# Apply an already-staged Nginx configuration. Callers retain their own
# rollback trap; this helper also rejects a restart that reports success but
# leaves the service inactive.
kw_nginx_test_restart() {
  nginx -t || return 1
  systemctl restart nginx || return 1
  systemctl is-active --quiet nginx || {
    kw_log ERROR 'Nginx không active sau khi restart; cần kiểm tra trạng thái và journal.'
    return 1
  }
}

kw_nginx_backup_file() {
  local source=$1 label=$2 timestamp target
  [[ -f $source && ! -L $source && $(stat -c %u "$source") == 0 ]] || return 2
  [[ $label =~ ^[a-z0-9-]{1,60}$ ]] || return 2
  kw_backup_dir_safe /var/backups 0022 || return 2
  if [[ ! -e $KW_BACKUP_ROOT && ! -L $KW_BACKUP_ROOT ]]; then
    install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT" || return 1
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  timestamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
  target="$KW_BACKUP_ROOT/nginx-${label}-${timestamp}-$$.conf"
  [[ ! -e $target && ! -L $target ]] || return 2
  cp -p -- "$source" "$target" || return 1
  chmod 0600 -- "$target" || return 1
  KW_NGINX_BACKUP=$target
}

kw_nginx_restore_plan() {
  local domain=${1,,}
  kw_site_lookup "$domain" || return 2
  [[ -f $KW_SITE_VHOST && ! -L $KW_SITE_VHOST ]] || return 2
  printf 'Phục hồi vhost HTTP nguyên bản của %s tại %s.\n' "$domain" "$KW_SITE_VHOST"
  printf 'Từ chối nếu vhost hiện có SSL. Giữ bản cũ root-only, kiểm tra rồi restart Nginx; rollback nếu lỗi.\n'
  printf 'Không sửa source, PHP, database hoặc cấu hình TLS.\n'
}

kw_nginx_restore_locked() (
  local domain=$1 id expected='' temp='' committed=0 swapped=0 backup=''
  kw_nginx_ready || return 2
  kw_site_lookup "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  [[ -f $KW_SITE_VHOST && ! -L $KW_SITE_VHOST && \
     $(stat -c %u "$KW_SITE_VHOST") == 0 && \
     -L $KW_SITE_ENABLED && $(readlink -f -- "$KW_SITE_ENABLED") == "$KW_SITE_VHOST" ]] || return 2
  grep -Fxq -- "# Managed by KwVPS. Site ID: $id" "$KW_SITE_VHOST" || return 2
  if grep -Eq '(^|[[:space:]])(listen[[:space:]]+.*443|ssl_certificate)' "$KW_SITE_VHOST"; then
    kw_log ERROR 'Vhost có SSL; không ghi đè chứng chỉ bằng mẫu HTTP.'; return 2
  fi
  expected=$(kw_site_render_vhost "$domain" "$id" |
    kw_cf_realip_render_for_site "$domain" "$id") || return 1
  if [[ $(< "$KW_SITE_VHOST") == "$expected" ]]; then
    printf 'Vhost đã đúng mẫu KwVPS; không thay đổi.\n'; return 0
  fi
  kw_nginx_backup_file "$KW_SITE_VHOST" "site-$id" || return 1
  backup=$KW_NGINX_BACKUP
  temp=$(mktemp /etc/nginx/sites-available/.kwvps-restore.XXXXXXXX) || return 1
  trap 'if ((swapped == 1 && committed == 0)); then cp -p -- "$backup" "$KW_SITE_VHOST" && kw_nginx_test_restart || kw_log ERROR "Rollback Nginx cần kiểm tra thủ công: $backup"; fi; [[ -z $temp ]] || rm -f -- "$temp"' EXIT
  printf '%s\n' "$expected" > "$temp" || return 1
  chmod 0644 -- "$temp" || return 1
  mv -T -- "$temp" "$KW_SITE_VHOST" || return 1
  temp=''
  swapped=1
  kw_nginx_test_restart || return 1
  committed=1
  printf 'Đã phục hồi vhost %s; bản trước ở %s\n' "$domain" "$backup"
)

kw_nginx_restore() (
  local domain=${1,,} confirm=${2:-}
  kw_domain_valid "$domain" || return 2
  [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-nginx.lock || return 2
  flock -n 9 || return 1
  kw_nginx_restore_locked "$domain"
)

kw_nginx_restore_interactive() {
  local domain confirm
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_nginx_restore_plan "$domain" || return 2
  kw_prompt_yes_no_token "Phục hồi Nginx cho $domain?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_nginx_restore "$domain" "${confirm,,}"
}

kw_nginx_baseline_plan() {
  printf 'Baseline Nginx toàn cục tại %s:\n' "$KW_NGINX_BASELINE"
  kw_nginx_render_baseline
  printf 'Có thể ảnh hưởng tất cả site trên Nginx. Kiểm tra cú pháp, restart và rollback nếu lỗi.\n'
}

kw_nginx_baseline_locked() (
  local temp='' backup='' committed=0 swapped=0 had_file=0
  kw_nginx_ready || return 2
  nginx -t >/dev/null 2>&1 || { kw_log ERROR 'Nginx hiện đã lỗi; chưa thể áp baseline.'; return 2; }
  [[ -d /etc/nginx/conf.d && ! -L /etc/nginx/conf.d ]] || return 2
  if [[ -e $KW_NGINX_BASELINE || -L $KW_NGINX_BASELINE ]]; then
    [[ -f $KW_NGINX_BASELINE && ! -L $KW_NGINX_BASELINE && \
       $(stat -c %u "$KW_NGINX_BASELINE") == 0 ]] || return 2
    grep -Fxq '# Managed by KwVPS. Global HTTP baseline.' "$KW_NGINX_BASELINE" || return 2
    # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
    had_file=1
    if [[ $(< "$KW_NGINX_BASELINE") == "$(kw_nginx_render_baseline)" ]]; then
      printf 'Baseline đã đúng mẫu; không thay đổi.\n'; return 0
    fi
    kw_nginx_backup_file "$KW_NGINX_BASELINE" baseline || return 1
    backup=$KW_NGINX_BACKUP
  fi
  temp=$(mktemp /etc/nginx/conf.d/.kwvps-baseline.XXXXXXXX) || return 1
  trap 'if ((swapped == 1 && committed == 0)); then if ((had_file)); then cp -p -- "$backup" "$KW_NGINX_BASELINE"; else rm -f -- "$KW_NGINX_BASELINE"; fi; kw_nginx_test_restart || kw_log ERROR "Rollback baseline Nginx cần kiểm tra thủ công: $backup"; fi; [[ -z $temp ]] || rm -f -- "$temp"' EXIT
  kw_nginx_render_baseline > "$temp" || return 1
  chmod 0644 -- "$temp" || return 1
  mv -T -- "$temp" "$KW_NGINX_BASELINE" || return 1
  temp=''
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  swapped=1
  kw_nginx_test_restart || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  committed=1
  printf 'Đã áp baseline Nginx toàn cục.\n'
  [[ -z $backup ]] || printf 'Bản trước: %s\n' "$backup"
)

kw_nginx_baseline() (
  local confirm=${1:-}
  [[ $confirm == APPLY-NGINX-BASELINE ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-nginx.lock || return 2
  flock -n 9 || return 1
  kw_nginx_baseline_locked
)

kw_nginx_baseline_interactive() {
  local confirm
  kw_nginx_baseline_plan
  kw_prompt_yes_no_token 'Áp baseline Nginx toàn cục?' APPLY-NGINX-BASELINE || return 0
  confirm=$KW_PROMPT_VALUE
  kw_nginx_baseline "$confirm"
}

kw_nginx_vhost_identity() {
  local file=$1 domain=$2 id=$3 expected_root=$KW_SITE_PUBLIC laravel=0
  [[ -f $file && ! -L $file ]] || return 2
  [[ $(grep -Fxc -- "# Managed by KwVPS. Site ID: $id" "$file") == 1 ]] || return 2
  if grep -Fxq '# KwVPS Laravel release root' "$file"; then
    [[ $(grep -Fxc '# KwVPS Laravel release root' "$file") == 1 ]] || return 2
    expected_root="$KW_SITE_ROOT/deploy/current/public"
    laravel=1
  fi
  awk -v domain="$domain" -v root="$expected_root" -v acme_root="$KW_SITE_PUBLIC" -v laravel="$laravel" -v socket="$KW_SITE_SOCKET" '
    /^[[:space:]]*#/ { next }
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line == "location ^~ /.well-known/acme-challenge/ {") in_acme = 1
      if (line ~ /^server_name[[:space:]]+/) {
        names++
        if (line != "server_name " domain ";") bad = 1
      } else if (line ~ /^root[[:space:]]+/) {
        if (line == "root " root ";") roots++
        else if (laravel && in_acme && line == "root " acme_root ";") acme_roots++
        else bad = 1
      } else if (line ~ /^fastcgi_pass[[:space:]]+/) {
        sockets++
        if (line != "fastcgi_pass unix:" socket ";") bad = 1
      }
      if (line == "}") in_acme = 0
    }
    END { exit (bad || names < 1 || roots < 1 || sockets < 1 || (laravel && acme_roots < 1)) ? 1 : 0 }
  ' "$file"
}

kw_nginx_vhost_custom_plan() {
  local domain=${1,,}
  kw_site_lookup "$domain" || return 2
  printf 'Sửa bản sao vhost của %s bằng nano: %s\n' "$domain" "$KW_SITE_VHOST"
  printf 'Giữ nguyên marker KwVPS, server_name, root và PHP socket; không sửa site khác.\n'
  printf 'Chỉ áp nếu Nginx kiểm tra cú pháp thành công; restart và kiểm tra trạng thái, rollback nếu lỗi.\n'
  printf 'Có thể gián đoạn ngắn mọi site trên Nginx. Vhost tùy biến có thể không tương thích với đổi domain/SSL tự động.\n'
}

kw_nginx_vhost_custom_locked() (
  local domain=$1 id vhost temp='' backup='' swapped=0 committed=0 restart_attempted=0 mode
  kw_nginx_ready || return 2
  [[ -t 0 && -t 1 ]] || { kw_log ERROR 'nano cần terminal tương tác.'; return 2; }
  kw_has nano || return 2
  kw_site_lookup "$domain" || return 2
  id=${KW_SITE_OWNER#kw}; vhost=$KW_SITE_VHOST
  [[ -f $vhost && ! -L $vhost && $(stat -c %u -- "$vhost") == 0 &&
     -L $KW_SITE_ENABLED && $(readlink -f -- "$KW_SITE_ENABLED") == "$vhost" ]] || return 2
  mode=$(stat -c %a -- "$vhost") || return 2
  [[ $mode =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0022) == 0 )) || return 2
  kw_nginx_vhost_identity "$vhost" "$domain" "$id" || {
    kw_log ERROR 'Vhost hiện tại đã đổi định danh domain/source/socket; không tự sửa.'
    return 2
  }
  nginx -t >/dev/null 2>&1 || { kw_log ERROR 'Nginx hiện đã lỗi; sửa cấu hình hiện tại trước.'; return 2; }
  temp=$(mktemp /etc/nginx/sites-available/.kwvps-edit.XXXXXXXX) || return 1
  trap 'if ((swapped == 1 && committed == 0)); then if install -m 0644 -o root -g root -- "$backup" "$vhost"; then if ((restart_attempted)); then kw_nginx_test_restart || kw_log ERROR "Rollback Nginx cần kiểm tra thủ công: $backup"; else nginx -t || kw_log ERROR "Rollback Nginx cần kiểm tra thủ công: $backup"; fi; else kw_log ERROR "Cần phục hồi vhost thủ công từ $backup"; fi; fi; [[ -z $temp ]] || rm -f -- "$temp"' EXIT
  cp -- "$vhost" "$temp" || return 1
  chmod 0600 -- "$temp" || return 1
  nano "$temp" || return 1
  kw_nginx_vhost_identity "$temp" "$domain" "$id" || {
    kw_log ERROR 'Bản sửa đã đổi server_name, source hoặc PHP socket; vhost gốc được giữ nguyên.'
    return 2
  }
  if cmp -s -- "$vhost" "$temp"; then printf 'Không có thay đổi.\n'; return 0; fi
  kw_nginx_backup_file "$vhost" "custom-$id" || return 1
  backup=$KW_NGINX_BACKUP
  chown -- root:root "$temp" || return 1
  chmod 0644 -- "$temp" || return 1
  mv -T -- "$temp" "$vhost" || return 1
  temp=''
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  swapped=1
  nginx -t || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  restart_attempted=1
  if ! systemctl restart nginx || ! systemctl is-active --quiet nginx; then
    kw_log ERROR 'Nginx không active sau khi áp vhost; đang phục hồi bản trước.'
    return 1
  fi
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  committed=1
  printf 'Đã áp vhost %s, kiểm tra nginx -t và restart Nginx. Bản trước: %s\n' "$domain" "$backup"
)

kw_nginx_vhost_custom() (
  local domain=${1,,} confirm=${2:-}
  kw_domain_valid "$domain" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || { kw_log ERROR 'Một thao tác site khác đang chạy.'; return 1; }
  exec 8>/run/lock/kwvps-nginx.lock || return 2
  flock -n 8 || { kw_log ERROR 'Một thao tác Nginx khác đang chạy.'; return 1; }
  kw_nginx_vhost_custom_locked "$domain"
)

kw_nginx_vhost_custom_interactive() {
  local domain confirm
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_nginx_vhost_custom_plan "$domain" || return 2
  kw_prompt_yes_no_token "Mở bản sao vhost $domain trong nano?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_nginx_vhost_custom "$domain" "${confirm,,}"
}
