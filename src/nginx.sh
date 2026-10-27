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
  printf 'Sửa cấu hình Nginx riêng của %s bằng nano: %s\n' "$domain" "$KW_SITE_CUSTOM"
  printf 'Thêm directive cấp server, ví dụ client_max_body_size hoặc location mới. Không sửa server_name, root, PHP socket và TLS.\n'
  printf 'KwVPS sẽ thêm include vào vhost mẫu, kiểm tra nginx -t, restart và rollback nếu lỗi.\n'
  printf 'Vhost đã sửa tay: KwVPS hiện diff với mẫu, yêu cầu bạn chuyển directive cần giữ vào snippet rồi xác nhận thay vhost.\n'
}

kw_nginx_custom_file_safe() {
  local path=$1 mode
  [[ -f $path && ! -L $path && $(stat -c %u -- "$path") == 0 ]] || return 2
  mode=$(stat -c %a -- "$path") || return 2
  [[ $mode =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0022) == 0 )) || return 2
}

kw_nginx_custom_directives_safe() {
  local path=$1
  [[ -f $path && ! -L $path && -s $path ]] || return 2
  # Identity, trust and nested includes remain under KwVPS control.
  ! sed 's/[[:space:]]*#.*$//' "$path" | grep -Eiq '(^|[;{}[:space:]])(include|server|listen|server_name|root|alias|fastcgi_pass|proxy_pass|ssl_certificate|ssl_certificate_key|set_real_ip_from|real_ip_header|real_ip_recursive)([[:space:];{]|$)'
}

kw_nginx_vhost_managed() {
  local domain=$1 id=$2 kind
  if kw_site_vhost_matches "$KW_SITE_VHOST" "$domain" "$id" kw_site_render_vhost "$domain" "$id"; then return 0; fi
  for kind in letsencrypt zerossl paid; do
    if [[ $kind == paid ]]; then
      kw_site_vhost_matches "$KW_SITE_VHOST" "$domain" "$id" kw_ssl_render_paid_vhost "$domain" "$id" && return 0
    else
      kw_site_vhost_matches "$KW_SITE_VHOST" "$domain" "$id" kw_ssl_render_vhost "$domain" "$id" "$kind" && return 0
    fi
  done
  for kind in http letsencrypt zerossl paid; do
    kw_site_vhost_matches "$KW_SITE_VHOST" "$domain" "$id" kw_laravel_render_vhost "$kind" "$domain" "$id" && return 0
  done
  # Cache templates are verified with their own managed zone and snippet.
  kw_cache_state "$domain" >/dev/null 2>&1 && [[ $KW_CACHE_STATE == on ]]
}

kw_nginx_custom_migration_render() {
  local domain=$1 id=$2 kind=http laravel=0
  [[ -f $KW_SITE_VHOST && ! -L $KW_SITE_VHOST ]] || return 2
  kw_nginx_vhost_identity "$KW_SITE_VHOST" "$domain" "$id" || return 2
  if grep -Fq 'include /etc/nginx/kwvps-cache/' "$KW_SITE_VHOST"; then
    kw_log ERROR 'Vhost đang có FastCGI cache; tắt cache và xem lại cấu hình trước khi chuyển.'
    return 2
  fi
  grep -Fxq '# KwVPS Laravel release root' "$KW_SITE_VHOST" && laravel=1
  if grep -Fxq '# KwVPS TLS: Paid' "$KW_SITE_VHOST"; then
    kind=paid
  elif grep -Fxq '# KwVPS TLS: ZeroSSL' "$KW_SITE_VHOST"; then
    kind=zerossl
  elif grep -Fxq "# KwVPS TLS: Let's Encrypt" "$KW_SITE_VHOST"; then
    kind=letsencrypt
  elif grep -Eq '^[[:space:]]*(listen[[:space:]]+.*443|ssl_certificate)' "$KW_SITE_VHOST"; then
    kw_log ERROR 'Vhost HTTPS thiếu marker KwVPS; không tự suy đoán chứng chỉ.'
    return 2
  fi
  if ((laravel)); then
    kw_laravel_render_vhost "$kind" "$domain" "$id"
  else
    case "$kind" in
      http) kw_site_render_vhost "$domain" "$id" ;;
      paid) kw_ssl_render_paid_vhost "$domain" "$id" ;;
      *) kw_ssl_render_vhost "$domain" "$id" "$kind" ;;
    esac
  fi | kw_cf_realip_render_for_site "$domain" "$id"
}

kw_nginx_vhost_custom_locked() (
  local domain=$1 id vhost temp='' vhost_temp='' backup='' old_custom='' swapped=0 committed=0 custom_swapped=0 had_custom=0 migrating=0
  kw_nginx_ready || return 2
  [[ -t 0 && -t 1 ]] || { kw_log ERROR 'nano cần terminal tương tác.'; return 2; }
  kw_has nano || return 2
  kw_site_lookup "$domain" || return 2
  id=${KW_SITE_OWNER#kw}; vhost=$KW_SITE_VHOST
  [[ -f $vhost && ! -L $vhost && $(stat -c %u -- "$vhost") == 0 &&
     -L $KW_SITE_ENABLED && $(readlink -f -- "$KW_SITE_ENABLED") == "$vhost" ]] || return 2
  kw_nginx_vhost_managed "$domain" "$id" || migrating=1
  [[ ! -e /etc/nginx/kwvps-custom && ! -L /etc/nginx/kwvps-custom ]] ||
    [[ -d /etc/nginx/kwvps-custom && ! -L /etc/nginx/kwvps-custom &&
       $(stat -c %u:%a -- /etc/nginx/kwvps-custom) == 0:755 ]] || return 2
  [[ ! -e $KW_SITE_CUSTOM_DIR && ! -L $KW_SITE_CUSTOM_DIR ]] ||
    [[ -d $KW_SITE_CUSTOM_DIR && ! -L $KW_SITE_CUSTOM_DIR &&
       $(stat -c %u:%a -- "$KW_SITE_CUSTOM_DIR") == 0:755 ]] || return 2
  [[ ! -e $KW_SITE_CUSTOM && ! -L $KW_SITE_CUSTOM ]] ||
    kw_nginx_custom_file_safe "$KW_SITE_CUSTOM" || return 2
  nginx -t >/dev/null 2>&1 || { kw_log ERROR 'Nginx hiện đã lỗi; sửa cấu hình hiện tại trước.'; return 2; }
  temp=$(mktemp /etc/nginx/sites-available/.kwvps-custom-edit.XXXXXXXX) || return 1
  trap 'if ((committed == 0)); then if ((swapped)); then install -m 0644 -o root -g root -- "$backup" "$vhost" || kw_log ERROR "Cần phục hồi vhost từ $backup"; fi; if ((custom_swapped)); then if ((had_custom)); then install -m 0644 -o root -g root -- "$old_custom" "$KW_SITE_CUSTOM" || kw_log ERROR "Cần phục hồi snippet từ $old_custom"; else rm -f -- "$KW_SITE_CUSTOM"; fi; fi; if ((swapped || custom_swapped)); then kw_nginx_test_restart || kw_log ERROR "Cần kiểm tra Nginx sau rollback: $domain"; fi; fi; [[ -z $temp ]] || rm -f -- "$temp"; [[ -z $vhost_temp ]] || rm -f -- "$vhost_temp"' EXIT
  if ((migrating)); then
    vhost_temp=$(mktemp /etc/nginx/sites-available/.kwvps-migrate-vhost.XXXXXXXX) || return 1
    kw_nginx_custom_migration_render "$domain" "$id" > "$vhost_temp" || {
      kw_log ERROR 'Không nhận diện được vhost cũ; giữ nguyên để kiểm tra thủ công.'
      return 2
    }
    printf 'Khác biệt giữa vhost hiện tại và mẫu mới (dấu - là dòng sẽ bỏ; dấu + là mẫu KwVPS):\n'
    diff -u --label "Đang chạy: $vhost" --label 'Mẫu KwVPS' "$vhost" "$vhost_temp" || {
      [[ $? == 1 ]] || return 2
    }
    printf 'Hãy đưa các directive cần giữ vào snippet. Bản vhost cũ được lưu root-only.\n'
    kw_prompt_yes_no_token "Đã xem khác biệt và muốn chuyển $domain sang vhost mẫu?" "$domain" || return 0
  fi
  if [[ -f $KW_SITE_CUSTOM ]]; then
    cp -- "$KW_SITE_CUSTOM" "$temp" || return 1
    had_custom=1
  else
    printf '# Nginx tuy chinh cap server; khong sua directive do KwVPS quan ly.\n' > "$temp" || return 1
  fi
  chmod 0600 -- "$temp" || return 1
  nano "$temp" || return 1
  kw_nginx_custom_directives_safe "$temp" || {
    kw_log ERROR 'Snippet chứa directive quản lý bởi KwVPS hoặc rỗng; chưa áp dụng.'
    return 2
  }
  if ((had_custom && !migrating)) && cmp -s -- "$KW_SITE_CUSTOM" "$temp"; then printf 'Không có thay đổi.\n'; return 0; fi
  kw_nginx_backup_file "$vhost" "custom-$id" || return 1
  backup=$KW_NGINX_BACKUP
  if ((had_custom)); then
    kw_nginx_backup_file "$KW_SITE_CUSTOM" "snippet-$id" || return 1
    old_custom=$KW_NGINX_BACKUP
  fi
  install -d -m 0755 -o root -g root -- /etc/nginx/kwvps-custom "$KW_SITE_CUSTOM_DIR" || return 1
  if ((migrating)) || ! grep -Fxq "  include /etc/nginx/kwvps-custom/$id/*.conf;" "$vhost"; then
    if ((!migrating)); then
      vhost_temp=$(mktemp /etc/nginx/sites-available/.kwvps-custom-vhost.XXXXXXXX) || return 1
      awk -v id="$id" '$0 == "  error_log /var/log/nginx/kwvps-" id ".error.log;" { print; print "  include /etc/nginx/kwvps-custom/" id "/*.conf;"; found++; next } {print} END {if (found != 1) exit 2}' "$vhost" > "$vhost_temp" || return 2
    fi
    chmod 0644 -- "$vhost_temp" || return 1
    mv -T -- "$vhost_temp" "$vhost" || return 1
    vhost_temp=''
    # shellcheck disable=SC2034 # EXIT rollback trap reads this marker.
    swapped=1
  fi
  chown -- root:root "$temp" || return 1
  chmod 0644 -- "$temp" || return 1
  mv -T -- "$temp" "$KW_SITE_CUSTOM" || return 1
  temp=''
  # shellcheck disable=SC2034 # EXIT rollback trap reads this marker.
  custom_swapped=1
  kw_nginx_test_restart || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  committed=1
  printf 'Đã áp snippet %s, kiểm tra nginx -t và restart Nginx. Bản vhost trước: %s\n' "$KW_SITE_CUSTOM" "$backup"
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
  kw_prompt_yes_no_token "Mở snippet Nginx của $domain trong nano?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_nginx_vhost_custom "$domain" "${confirm,,}"
}
