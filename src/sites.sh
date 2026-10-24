#!/usr/bin/env bash
# KwVPS-owned sites on a prepared Ubuntu 24.04 VPS.
# The renderer is pure; site creation is isolated from read-only site queries.

kw_site_php_valid() {
  case "${1:-}" in 8.5|8.4|8.3|7.4) return 0 ;; *) return 1 ;; esac
}

kw_site_id_valid() {
  [[ ${1:-} =~ ^[a-z0-9]{1,29}$ ]]
}

kw_site_id() {
  local domain=${1,,} slug legacy
  kw_domain_valid "$domain" || return 2
  slug=${domain//[!a-z0-9]/}
  # Keep old hash-based sites manageable until they are explicitly retired.
  legacy=$(printf '%s' "$domain" | sha256sum) || return 2
  legacy=${legacy:0:12}
  if [[ -f /etc/kwvps/sites/$legacy.site && ! -L /etc/kwvps/sites/$legacy.site ]] &&
     grep -Fxq "domain=$domain" "/etc/kwvps/sites/$legacy.site"; then
    printf '%s' "$legacy"
  else
    if [[ ! $slug =~ ^[a-z0-9]{1,29}$ ]]; then
      kw_log ERROR 'Tên miền sau khi bỏ dấu chấm/gạch phải dài tối đa 29 ký tự.'
      return 2
    fi
    printf '%s' "$slug"
  fi
}

kw_site_new_domain_valid() {
  local id domain=${1,,}
  id=$(kw_site_id "$domain") || return 1
  [[ ! -e /etc/kwvps/sites/$id.site && ! -L /etc/kwvps/sites/$id.site ]]
}

kw_site_id_matches_domain() {
  local id=$1 domain=${2,,} slug legacy
  kw_site_id_valid "$id" && kw_domain_valid "$domain" || return 1
  slug=${domain//[!a-z0-9]/}
  [[ $id == "$slug" ]] && return 0
  legacy=$(printf '%s' "$domain" | sha256sum) || return 1
  [[ $id == "${legacy:0:12}" ]]
}

kw_site_paths() {
  local id=$1 php=$2
  KW_SITE_PHP="$php"
  KW_SITE_OWNER="kw${id}"
  KW_SITE_ROOT="/var/www/kwvps/${id}"
  KW_SITE_PUBLIC="${KW_SITE_ROOT}/public"
  KW_SITE_POOL="/etc/php/${php}/fpm/pool.d/kwvps-${id}.conf"
  KW_SITE_VHOST="/etc/nginx/sites-available/kwvps-${id}.conf"
  KW_SITE_ENABLED="/etc/nginx/sites-enabled/kwvps-${id}.conf"
  KW_SITE_META="/etc/kwvps/sites/${id}.site"
  KW_SITE_SOCKET="/run/php/kwvps-${id}.sock"
}

kw_site_plan() {
  local domain=${1,,} php=${2:-} id
  kw_domain_valid "$domain" || { kw_log ERROR 'Tên miền không hợp lệ.'; return 2; }
  kw_site_php_valid "$php" || { kw_log ERROR 'Chỉ hỗ trợ PHP 8.5, 8.4, 8.3 hoặc 7.4.'; return 2; }
  id=$(kw_site_id "$domain") || return 2
  kw_site_paths "$id" "$php"
  printf 'Kế hoạch thêm site (chưa thay đổi hệ thống):\n'
  printf '  Domain: %s\n  PHP-FPM: %s\n  Site ID: %s\n' "$domain" "$php" "$id"
  printf '  User: %s\n  Source: %s\n' "$KW_SITE_OWNER" "$KW_SITE_PUBLIC"
  printf '  Pool: %s\n  Vhost: %s\n' "$KW_SITE_POOL" "$KW_SITE_VHOST"
  printf '  HTTP: cổng 80; chưa có SSL, DNS, DB, cache hoặc firewall rule.\n'
  printf '  Tạo user riêng, trang chào và cấu hình Nginx/PHP-FPM rồi health check loopback.\n'
}

kw_site_render_pool() {
  local id=$1 user=$2
  cat <<EOF
[kwvps-${id}]
user = ${user}
group = ${user}
listen = /run/php/kwvps-${id}.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = ondemand
pm.max_children = 5
pm.process_idle_timeout = 10s
pm.max_requests = 500
clear_env = yes
security.limit_extensions = .php
EOF
}

kw_site_render_vhost() {
  local domain=$1 id=$2
  cat <<EOF
# Managed by KwVPS. Site ID: ${id}
server {
  listen 80;
  listen [::]:80;
  server_name ${domain};
  root /var/www/kwvps/${id}/public;
  index index.php index.html;

  access_log /var/log/nginx/kwvps-${id}.access.log;
  error_log /var/log/nginx/kwvps-${id}.error.log;

  location / {
    try_files \$uri \$uri/ /index.php?\$args;
  }
  location ^~ /.well-known/acme-challenge/ {
    default_type text/plain;
    try_files \$uri =404;
  }
  location ~ /\. {
    deny all;
  }
  location ~ \.php\$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/kwvps-${id}.sock;
  }
}
EOF
}

# Compare an exact KwVPS template while allowing only KwVPS's managed Tunnel
# Real-IP overlay. Custom Nginx directives still make the comparison fail.
kw_site_vhost_matches() {
  local file=$1 domain=$2 id=$3 normalized expected
  shift 3
  [[ -f $file && ! -L $file ]] || return 2
  cmp -s -- "$file" <("$@") && return 0
  grep -Fq '# KwVPS Tunnel Real IP (managed)' -- "$file" || return 1
  # Sentinels preserve trailing newlines in command substitution; a failed
  # overlay must never be mistaken for an empty/valid template.
  normalized=$(kw_cf_realip_vhost_overlay dns "$domain" "$id" "$file" && printf '\001') || return 2
  expected=$("$@" && printf '\001') || return 2
  [[ $normalized == "$expected" ]]
}

kw_site_list() {
  local file domain php id key value found=0
  if [[ -e /etc/kwvps/sites && ! -r /etc/kwvps/sites ]]; then
    kw_log ERROR 'Không có quyền đọc registry site.'
    return 1
  fi
  printf '%-30s %-8s %s\n' 'DOMAIN' 'PHP' 'SITE ID'
  for file in /etc/kwvps/sites/*.site; do
    [[ -f $file && ! -L $file ]] || continue
    if [[ ! -r $file ]]; then
      kw_log ERROR "Không có quyền đọc metadata site: $file"
      return 1
    fi
    domain=''; php=''; id=''
    while IFS='=' read -r key value; do
      case "$key" in
        domain) domain=$value ;;
        php_version) php=$value ;;
        site_id) id=$value ;;
      esac
    done < "$file"
    if kw_domain_valid "$domain" && kw_site_php_valid "$php" && kw_site_id_valid "$id" &&
       [[ $id == "$(kw_site_id "$domain")" ]]; then
      printf '%-30s %-8s %s\n' "$domain" "$php" "$id"
      found=1
    else
      kw_log WARN "Metadata site lỗi hoặc không đọc được: $file"
    fi
  done
  ((found)) || printf 'Chưa có site do KwVPS quản lý.\n'
}

kw_site_lookup() {
  local domain=${1,,} id file key value meta_domain='' meta_id='' meta_php='' meta_owner=''
  kw_domain_valid "$domain" || return 2
  id=$(kw_site_id "$domain") || return 2
  file="/etc/kwvps/sites/${id}.site"
  [[ -f $file && ! -L $file && -r $file ]] || {
    kw_log ERROR 'Không tìm thấy metadata site KwVPS hoặc không có quyền đọc.'
    return 2
  }
  while IFS='=' read -r key value; do
    case "$key" in
      domain) meta_domain=$value ;;
      site_id) meta_id=$value ;;
      php_version) meta_php=$value ;;
      owner) meta_owner=$value ;;
    esac
  done < "$file"
  [[ $meta_domain == "$domain" && $meta_id == "$id" ]] || return 2
  kw_site_php_valid "$meta_php" || return 2
  kw_site_paths "$id" "$meta_php"
  [[ $meta_owner == "$KW_SITE_OWNER" ]] || return 2
  [[ -d $KW_SITE_ROOT && ! -L $KW_SITE_ROOT && \
     -d $KW_SITE_PUBLIC && ! -L $KW_SITE_PUBLIC ]] || return 2
}

kw_site_disk() {
  local domain=$1
  kw_site_lookup "$domain" || return 2
  printf 'Source của %s:\n' "${domain,,}"
  kw_read_command du -shx -- "$KW_SITE_PUBLIC" || return 1
  printf 'Filesystem chứa source:\n'
  kw_read_command df -h -- "$KW_SITE_PUBLIC"
}

kw_site_large_files() (
  local domain=$1 threshold=${2:-100} listing entry bytes path count=0 size_mib
  [[ $threshold =~ ^[1-9][0-9]{0,5}$ ]] || {
    kw_log ERROR 'Ngưỡng phải từ 1 đến 999999 MiB.'; return 2;
  }
  kw_site_lookup "$domain" || return 2
  printf 'Tối đa 20 file trên %s lớn hơn %s MiB:\n' "${domain,,}" "$threshold"
  listing=$(mktemp) || return 1
  trap 'rm -f -- "$listing"' EXIT
  # NUL records preserve filenames with tabs/newlines. find does not follow links.
  if ! kw_read_command find "$KW_SITE_PUBLIC" -xdev -type f \
    -size "+${threshold}M" -printf '%s\t%p\0' > "$listing"; then
    return 1
  fi
  if [[ ! -s $listing ]]; then
    printf 'Không tìm thấy file phù hợp.\n'
    return 0
  fi
  if ! LC_ALL=C sort -z -nr -o "$listing" -- "$listing"; then
    return 1
  fi
  while IFS= read -r -d '' entry; do
    bytes=${entry%%$'\t'*}
    path=${entry#*$'\t'}
    size_mib=$(awk -v b="$bytes" 'BEGIN { printf "%.1f", b/1048576 }')
    printf '%s MiB\t%q\n' "$size_mib" "$path"
    count=$((count + 1))
    ((count < 20)) || break
  done < "$listing"
)

kw_site_log() {
  local domain=$1 kind=$2 path
  kw_site_lookup "$domain" || return 2
  case "$kind" in
    access|error) path="/var/log/nginx/kwvps-${KW_SITE_OWNER#kw}.${kind}.log" ;;
    *) kw_log ERROR 'Chỉ hỗ trợ access hoặc error log.'; return 2 ;;
  esac
  [[ -f $path && ! -L $path && -r $path ]] || {
    kw_log ERROR "Log chưa tồn tại hoặc không có quyền đọc: $path"; return 1;
  }
  printf '100 dòng cuối của %s (có thể chứa dữ liệu riêng):\n' "$path"
  kw_read_command tail -n 100 -- "$path"
}

kw_site_prompt_domain() {
  local file key value domain id php choice count=0
  local -a domains=()
  printf 'Chọn site KwVPS:\n'
  for file in /etc/kwvps/sites/*.site; do
    [[ -f $file && ! -L $file && -r $file ]] || continue
    domain=''; id=''; php=''
    while IFS='=' read -r key value; do
      case "$key" in
        domain) domain=$value ;;
        site_id) id=$value ;;
        php_version) php=$value ;;
      esac
    done < "$file"
    if ! kw_domain_valid "$domain" || ! kw_site_php_valid "$php" || \
       [[ $id != "$(kw_site_id "$domain")" || $file != "/etc/kwvps/sites/${id}.site" ]]; then
      continue
    fi
    domains+=("$domain")
    count=$((count + 1))
    printf '%d. %s\n' "$count" "$domain"
  done
  if ((count == 0)); then printf 'Chưa có site KwVPS.\n'; return 1; fi
  printf ' 0. Quay lại\n'
  while :; do
    printf 'Chọn số site: '
    IFS= read -r choice || return 1
    [[ $choice != 0 ]] || return 1
    [[ $choice =~ ^[1-9][0-9]*$ ]] && ((choice <= count)) && break
    printf 'Số site không hợp lệ; nhập lại.\n'
  done
  KW_SITE_CHOICE=${domains[choice-1]}
}

kw_site_disk_interactive() {
  kw_site_prompt_domain || return 0
  kw_site_disk "$KW_SITE_CHOICE"
}

kw_site_large_interactive() {
  local threshold
  kw_site_prompt_domain || return 0
  printf 'Ngưỡng MiB (Enter = 100): '
  IFS= read -r threshold || return 0
  kw_site_large_files "$KW_SITE_CHOICE" "${threshold:-100}"
}

kw_site_log_interactive() {
  local kind
  kw_site_prompt_domain || return 0
  printf 'Loại log (access/error): '
  IFS= read -r kind || return 0
  kw_site_log "$KW_SITE_CHOICE" "$kind"
}

kw_site_php_pool_info() {
  local domain=$1
  kw_site_lookup "$domain" || return 2
  [[ -f $KW_SITE_POOL && ! -L $KW_SITE_POOL && -r $KW_SITE_POOL ]] || {
    kw_log ERROR 'Không đọc được PHP-FPM pool của site.'; return 1;
  }
  printf 'Domain: %s\nPHP-FPM: %s\nPool: %s\nSocket: %s\n' \
    "${domain,,}" "$KW_SITE_PHP" "$KW_SITE_POOL" "$KW_SITE_SOCKET"
  printf 'Các tham số pool đang lưu (chỉ đọc):\n'
  LC_ALL=C awk -F= '
    /^[[:space:]]*[#;]/ { next }
    NF < 2 { next }
    {
      key=$1; value=$2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (key ~ /^(user|group|listen|listen\.owner|listen\.group|listen\.mode|pm|pm\.max_children|pm\.process_idle_timeout|pm\.max_requests|clear_env|security\.limit_extensions)$/)
        printf "  %s = %s\n", key, value
    }
  ' "$KW_SITE_POOL" || return 1
  printf 'Trạng thái service (không chứng minh ứng dụng PHP hoạt động):\n'
  kw_service_status "php${KW_SITE_PHP}-fpm"
}

kw_site_php_log() {
  local domain=$1
  kw_site_lookup "$domain" || return 2
  printf '100 dòng journal của php%s-fpm; dùng chung cho mọi site cùng PHP version.\n' "$KW_SITE_PHP"
  printf 'Log có thể chứa dữ liệu riêng; che thông tin trước khi chia sẻ.\n'
  kw_read_command journalctl --no-pager -n 100 -u "php${KW_SITE_PHP}-fpm.service"
}

kw_site_php_pool_interactive() {
  kw_site_prompt_domain || return 0
  kw_site_php_pool_info "$KW_SITE_CHOICE"
}

kw_site_php_log_interactive() {
  kw_site_prompt_domain || return 0
  kw_site_php_log "$KW_SITE_CHOICE"
}

kw_site_preflight() {
  local domain=$1 php=$2 id=$3 dump path cmd nginx_conflict=0
  kw_os_supported '' || {
    kw_log ERROR 'Chỉ hỗ trợ tạo site trên Ubuntu 24.04.'; return 2;
  }
  ((EUID == 0)) || { kw_log ERROR 'Cần quyền root để tạo site.'; return 2; }
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id ]] || {
    kw_log ERROR 'VPS chưa được chuẩn bị bằng bộ cài KwVPS.'; return 2;
  }
  [[ $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  for cmd in nginx "php-fpm${php}" systemctl useradd userdel install flock curl getent sha256sum; do
    kw_has "$cmd" || { kw_log ERROR "Thiếu $cmd."; return 2; }
  done
  kw_php_site_ready "$php" || return 2
  [[ -r /etc/nginx/snippets/fastcgi-php.conf ]] || return 2
  if ! systemctl is-active --quiet nginx ||
    ! systemctl is-active --quiet "php${php}-fpm"; then
    kw_log ERROR 'Nginx hoặc PHP-FPM chưa chạy.'; return 2;
  fi
  kw_site_paths "$id" "$php"
  local parent owner mode
  for parent in /etc/kwvps /etc/kwvps/sites /var/www/kwvps \
    "/etc/php/${php}/fpm/pool.d" /etc/nginx/sites-available /etc/nginx/sites-enabled; do
    [[ -d $parent && ! -L $parent ]] || {
      kw_log ERROR "Thư mục đích không hợp lệ: $parent"; return 2;
    }
    owner=$(stat -c %u -- "$parent") || return 2
    mode=$(stat -c %a -- "$parent") || return 2
    [[ $owner == 0 && $mode =~ ^[0-7]{3,4}$ ]] || return 2
    (( (8#$mode & 0022) == 0 )) || {
      kw_log ERROR "Thư mục có quyền ghi không an toàn: $parent"; return 2;
    }
  done
  if [[ -e $KW_SITE_META || -L $KW_SITE_META ]]; then
    kw_log ERROR "Domain đã tồn tại hoặc tạo cùng site ID ($id): $domain"
    return 2
  fi
  for path in "$KW_SITE_ROOT" "$KW_SITE_POOL" "$KW_SITE_VHOST" "$KW_SITE_ENABLED" "$KW_SITE_META" "$KW_SITE_SOCKET"; do
    [[ ! -e $path && ! -L $path ]] || {
      if [[ $path == "$KW_SITE_META" ]]; then
        kw_log ERROR "Domain đã tồn tại hoặc tạo cùng site ID ($id): $domain"
      else
        kw_log ERROR "Đích đã tồn tại: $path"
      fi
      return 2;
    }
  done
  if getent passwd "$KW_SITE_OWNER" >/dev/null; then
    kw_log ERROR 'User site đã tồn tại.'; return 2
  fi
  dump=$(nginx -T 2>&1) || { kw_log ERROR 'Cấu hình Nginx hiện tại không hợp lệ.'; return 2; }
  kw_nginx_server_name_taken "$domain" <<< "$dump" || nginx_conflict=$?
  case $nginx_conflict in
    0) kw_log ERROR 'Domain đã xuất hiện trong server_name của Nginx; cần kiểm tra thủ công.'; return 2 ;;
    1) ;;
    *) kw_log ERROR 'Nginx có server_name dạng regex hoặc không đọc được danh sách tên miền; cần kiểm tra thủ công.'; return 2 ;;
  esac
}

# Nginx -T includes certificate paths and longer hostnames, so search only
# server_name directive arguments. Return 2 for regex names that cannot be
# checked safely against a specific hostname without Nginx's PCRE engine.
kw_nginx_server_name_taken() {
  local domain=${1,,}
  kw_domain_valid "$domain" || return 2
  awk -v host="$domain" '
    function ends_with(value, suffix) {
      return length(value) >= length(suffix) &&
        substr(value, length(value) - length(suffix) + 1) == suffix
    }
    function matches(name, base, prefix) {
      name = tolower(name)
      if (name ~ /^".*"$/) name = substr(name, 2, length(name) - 2)
      if (substr(name, 1, 1) == "~") { regex = 1; return 0 }
      if (name == host) return 1
      if (substr(name, 1, 2) == "*.") {
        base = substr(name, 3)
        return ends_with(host, "." base)
      }
      if (substr(name, 1, 1) == ".") {
        base = substr(name, 2)
        return host == base || ends_with(host, "." base)
      }
      if (substr(name, length(name) - 1) == ".*") {
        prefix = substr(name, 1, length(name) - 1)
        return length(host) > length(prefix) && substr(host, 1, length(prefix)) == prefix
      }
      return 0
    }
    function check(segment, words, count, first, i) {
      sub(/^[[:space:]]+/, "", segment)
      if (segment == "") return
      count = split(segment, words, /[[:space:]]+/)
      if (!reading) {
        if (words[1] != "server_name") return
        reading = 1
        first = 2
      } else first = 1
      for (i = first; i <= count; i++) {
        if (words[i] != "" && matches(words[i])) found = 1
      }
    }
    {
      line = $0
      sub(/#.*/, "", line)
      while (match(line, /[;{}]/)) {
        position = RSTART
        check(substr(line, 1, position - 1))
        reading = 0
        line = substr(line, position + 1)
      }
      check(line)
    }
    END { exit(found ? 0 : (regex ? 2 : 1)) }
  '
}

kw_site_rollback() {
  # Only paths derived from a validated domain and owned by this transaction.
  ((KW_SITE_DONE == 0)) || return 0
  if ((KW_SITE_LINK_CREATED)); then rm -f -- "$KW_SITE_ENABLED"; fi
  if ((KW_SITE_VHOST_CREATED)); then rm -f -- "$KW_SITE_VHOST"; fi
  if ((KW_SITE_POOL_CREATED)); then rm -f -- "$KW_SITE_POOL"; fi
  if ((KW_SITE_META_CREATED)); then rm -f -- "$KW_SITE_META"; fi
  if [[ -n ${KW_SITE_STAGE:-} && -d $KW_SITE_STAGE ]]; then
    rm -f -- "$KW_SITE_STAGE/pool.conf" "$KW_SITE_STAGE/vhost.conf" "$KW_SITE_STAGE/site.meta"
    rmdir -- "$KW_SITE_STAGE" 2>/dev/null || \
      kw_log WARN "Giữ staging tại $KW_SITE_STAGE để kiểm tra thủ công."
  fi
  if ((KW_SITE_ROOT_CREATED)); then
    rm -f -- "$KW_SITE_PUBLIC/index.html"
    rmdir -- "$KW_SITE_PUBLIC" "$KW_SITE_ROOT" 2>/dev/null || \
      kw_log WARN "Giữ dữ liệu tại $KW_SITE_ROOT để kiểm tra thủ công."
  fi
  if ((KW_SITE_USER_CREATED)) && [[ ! -d $KW_SITE_ROOT ]]; then
    userdel -- "$KW_SITE_OWNER" 2>/dev/null || \
      kw_log WARN "User $KW_SITE_OWNER còn tồn tại; cần kiểm tra thủ công."
  fi
  if ((KW_SITE_LINK_CREATED || KW_SITE_VHOST_CREATED)); then
    if ! nginx -t >/dev/null 2>&1 || \
       ! systemctl restart nginx >/dev/null 2>&1 || \
       ! systemctl is-active --quiet nginx; then
      kw_log WARN 'Cần kiểm tra Nginx sau rollback.'
    fi
  fi
  if ((KW_SITE_POOL_CREATED)); then
    if ! "php-fpm${KW_SITE_PHP}" -t >/dev/null 2>&1 || \
       ! systemctl restart "php${KW_SITE_PHP}-fpm" >/dev/null 2>&1 || \
       ! systemctl is-active --quiet "php${KW_SITE_PHP}-fpm"; then
      kw_log WARN 'Cần kiểm tra PHP-FPM sau rollback.'
    fi
  fi
}

# Re-apply and verify the ownership of only the files this transaction just
# created. The shared parent and Nginx/PHP configuration must remain root-owned.
kw_site_initial_permissions() {
  local file
  [[ -d $KW_SITE_ROOT && ! -L $KW_SITE_ROOT &&
     -d $KW_SITE_PUBLIC && ! -L $KW_SITE_PUBLIC &&
     -f $KW_SITE_PUBLIC/index.html && ! -L $KW_SITE_PUBLIC/index.html ]] || return 2
  for file in "$KW_SITE_POOL" "$KW_SITE_VHOST" "$KW_SITE_META"; do
    [[ -f $file && ! -L $file ]] || return 2
  done
  chown -- "$KW_SITE_OWNER:www-data" "$KW_SITE_ROOT" "$KW_SITE_PUBLIC" \
    "$KW_SITE_PUBLIC/index.html" || return 1
  chmod 0750 -- "$KW_SITE_ROOT" "$KW_SITE_PUBLIC" || return 1
  chmod 0640 -- "$KW_SITE_PUBLIC/index.html" || return 1
  chown -- root:root "$KW_SITE_POOL" "$KW_SITE_VHOST" "$KW_SITE_META" || return 1
  chmod 0644 -- "$KW_SITE_POOL" "$KW_SITE_VHOST" "$KW_SITE_META" || return 1
  [[ $(stat -c '%U:%G:%a' -- "$KW_SITE_ROOT" "$KW_SITE_PUBLIC" "$KW_SITE_PUBLIC/index.html") == \
     "$KW_SITE_OWNER:www-data:750"$'\n'"$KW_SITE_OWNER:www-data:750"$'\n'"$KW_SITE_OWNER:www-data:640" ]] || return 1
  [[ $(stat -c '%U:%G:%a' -- "$KW_SITE_POOL" "$KW_SITE_VHOST" "$KW_SITE_META") == \
     $'root:root:644\nroot:root:644\nroot:root:644' ]] || return 1
}

kw_site_apply_locked() (
  local domain=$1 php=$2 id=$3
  local KW_SITE_DONE=0 KW_SITE_LINK_CREATED=0 KW_SITE_VHOST_CREATED=0
  local KW_SITE_POOL_CREATED=0 KW_SITE_META_CREATED=0 KW_SITE_ROOT_CREATED=0
  # shellcheck disable=SC2030 # This variable belongs to the site-create subshell.
  local KW_SITE_USER_CREATED=0 KW_SITE_PHP=$php KW_SITE_STAGE=''
  kw_site_preflight "$domain" "$php" "$id" || return 2
  trap kw_site_rollback EXIT
  KW_SITE_STAGE=$(mktemp -d /etc/kwvps/.site-stage.XXXXXXXX) || return 1
  chmod 0700 "$KW_SITE_STAGE" || return 1
  kw_site_render_pool "$id" "$KW_SITE_OWNER" > "$KW_SITE_STAGE/pool.conf" || return 1
  kw_site_render_vhost "$domain" "$id" > "$KW_SITE_STAGE/vhost.conf" || return 1
  printf 'domain=%s\nsite_id=%s\nphp_version=%s\nowner=%s\n' \
    "$domain" "$id" "$php" "$KW_SITE_OWNER" > "$KW_SITE_STAGE/site.meta" || return 1
  useradd --system --user-group --no-create-home --home-dir "$KW_SITE_ROOT" \
    --shell /usr/sbin/nologin -- "$KW_SITE_OWNER" || return 1
  KW_SITE_USER_CREATED=1
  install -d -m 0750 -o "$KW_SITE_OWNER" -g www-data -- "$KW_SITE_ROOT" || return 1
  KW_SITE_ROOT_CREATED=1
  install -d -m 0750 -o "$KW_SITE_OWNER" -g www-data -- "$KW_SITE_PUBLIC" || return 1
  printf '<!doctype html><meta charset="utf-8"><title>KwVPS</title><h1>Site ready</h1>\n' \
    > "$KW_SITE_PUBLIC/index.html" || return 1
  chown "$KW_SITE_OWNER:www-data" "$KW_SITE_PUBLIC/index.html" || return 1
  chmod 0640 "$KW_SITE_PUBLIC/index.html" || return 1
  install -m 0644 -o root -g root -- "$KW_SITE_STAGE/pool.conf" "$KW_SITE_POOL" || return 1
  KW_SITE_POOL_CREATED=1
  "php-fpm${php}" -t >/dev/null || return 1
  install -m 0644 -o root -g root -- "$KW_SITE_STAGE/vhost.conf" "$KW_SITE_VHOST" || return 1
  KW_SITE_VHOST_CREATED=1
  ln -s -- "$KW_SITE_VHOST" "$KW_SITE_ENABLED" || return 1
  KW_SITE_LINK_CREATED=1
  nginx -t || return 1
  systemctl restart "php${php}-fpm" || return 1
  systemctl is-active --quiet "php${php}-fpm" || return 1
  systemctl restart nginx || return 1
  systemctl is-active --quiet nginx || return 1
  curl --silent --show-error --fail --noproxy '*' --max-time 8 -H "Host: $domain" \
    'http://127.0.0.1/' >/dev/null || return 1
  # This record contains public site routing metadata only, never credentials.
  install -m 0644 -o root -g root -- "$KW_SITE_STAGE/site.meta" "$KW_SITE_META" || return 1
  KW_SITE_META_CREATED=1
  kw_site_initial_permissions || {
    kw_log ERROR 'Không áp/xác minh được quyền của site mới; đang hoàn tác.'
    return 1
  }
  rm -f -- "$KW_SITE_STAGE/pool.conf" "$KW_SITE_STAGE/vhost.conf" "$KW_SITE_STAGE/site.meta" || return 1
  rmdir -- "$KW_SITE_STAGE" || return 1
  KW_SITE_DONE=1
  printf 'Đã tạo site %s với PHP-FPM %s. Source thuộc %s:www-data; pool/vhost/metadata thuộc root. Cần cấu hình DNS và SSL riêng.\n' "$domain" "$php" "$KW_SITE_OWNER"
)

kw_site_create() (
  local domain=${1,,} php=$2 confirm=${3:-} id
  kw_domain_valid "$domain" && kw_site_php_valid "$php" || return 2
  [[ $confirm == "$domain" ]] || { kw_log ERROR 'Xác nhận domain không khớp.'; return 2; }
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để tạo site.'; return 2; }
  id=$(kw_site_id "$domain") || return 2
  kw_has flock || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || { kw_log ERROR 'Một phiên quản lý site khác đang chạy.'; return 1; }
  kw_site_apply_locked "$domain" "$php" "$id"
)

kw_site_add_interactive() {
  # shellcheck disable=SC2034 # Read by the nested site preflight to require EOL acknowledgement.
  local domain php confirm choice name index KW_PHP_EOL_SITE_ACK=0
  kw_prompt_validated 'Domain/subdomain: ' kw_site_new_domain_valid \
    'Domain không hợp lệ, quá dài hoặc đã tồn tại/trùng site ID' plain || return 0
  domain=${KW_PROMPT_VALUE,,}
  kw_site_find_retired "$domain" || return 2
  if ((${#KW_RETIRED_MATCHES[@]})); then
    printf 'Site %s đang trong vùng giữ (%d bản).\n' "$domain" "${#KW_RETIRED_MATCHES[@]}"
    printf '1. Phục hồi site đang giữ %s\n' "$domain"
    printf '2. Xóa site đang giữ và thêm mới %s\n' "$domain"
    printf '0. Quay lại\n'
    while :; do
      printf 'Chọn: '
      IFS= read -r choice || return 0
      case "$choice" in 1|2) break ;; 0|'') return 0 ;; *) printf 'Lựa chọn không hợp lệ.\n' ;; esac
    done
    if [[ $choice == 1 ]]; then
      if ((${#KW_RETIRED_MATCHES[@]} == 1)); then
        name=${KW_RETIRED_MATCHES[0]}
      else
        printf 'Chọn bản cần phục hồi:\n'
        for index in "${!KW_RETIRED_MATCHES[@]}"; do
          printf '%d. %s\n' "$((index+1))" "${KW_RETIRED_MATCHES[index]}"
        done
        printf '0. Quay lại\n'
        while :; do
          printf 'Chọn: '
          IFS= read -r choice || return 0
          [[ $choice != 0 ]] || return 0
          [[ $choice =~ ^[1-9][0-9]*$ ]] && ((choice <= ${#KW_RETIRED_MATCHES[@]})) && break
          printf 'Lựa chọn không hợp lệ.\n'
        done
        name=${KW_RETIRED_MATCHES[choice-1]}
      fi
      kw_site_retired_plan "$domain" "$name" || return 2
      kw_prompt_yes_no_token "Phục hồi site $domain từ $name?" "$domain" || return 0
      kw_site_retired_restore "$domain" "$name" "${KW_PROMPT_VALUE,,}"
      return $?
    fi
  fi
  kw_php_choose_version || return 0
  php=$KW_PHP_CHOICE
  kw_site_plan "$domain" "$php" || return 2
  if ((${#KW_RETIRED_MATCHES[@]})); then
    printf 'Sẽ xóa VĨNH VIỄN %d gói site đã giữ của %s rồi tạo site HTTP mới. DB, backup độc lập và chứng chỉ không bị xóa.\n' \
      "${#KW_RETIRED_MATCHES[@]}" "$domain"
    kw_prompt_confirm_domain "$domain" 'Nhập lại đúng domain để XÓA bản giữ và thêm mới: ' || return 0
    confirm=$KW_PROMPT_VALUE
    kw_site_replace_retired "$domain" "$php" "${confirm,,}"
  else
    kw_prompt_yes_no_token "Tạo site $domain với PHP $php?" "$domain" || return 0
    confirm=$KW_PROMPT_VALUE
    kw_site_create "$domain" "$php" "${confirm,,}"
  fi
}

kw_site_find_retired() {
  local domain=${1,,} dir name archive_id key value found_domain='' found_id=''
  KW_RETIRED_MATCHES=()
  kw_domain_valid "$domain" || return 2
  [[ -d $KW_BACKUP_ROOT/retired && ! -L $KW_BACKUP_ROOT/retired ]] || return 0
  kw_backup_dir_safe "$KW_BACKUP_ROOT/retired" 0077 || return 2
  for dir in "$KW_BACKUP_ROOT"/retired/*; do
    [[ -d $dir && ! -L $dir && -f $dir/site.meta && ! -L $dir/site.meta ]] || continue
    name=${dir##*/}; found_domain=''; found_id=''
    [[ $name =~ ^([a-z0-9]{1,29})-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$ ]] || continue
    archive_id=${BASH_REMATCH[1]}
    while IFS='=' read -r key value; do
      case "$key" in domain) found_domain=$value ;; site_id) found_id=$value ;; esac
    done < "$dir/site.meta"
    [[ $found_domain == "$domain" && $found_id == "$archive_id" ]] || continue
    kw_site_id_matches_domain "$archive_id" "$domain" || continue
    KW_RETIRED_MATCHES+=("$name")
  done
}

kw_site_replace_retired() (
  local domain=${1,,} php=$2 confirm=${3:-} id name archive_id path dump
  kw_domain_valid "$domain" && kw_site_php_valid "$php" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || return 2
  id=$(kw_site_id "$domain") || return 2
  [[ ! -e /etc/kwvps/sites/$id.site && ! -L /etc/kwvps/sites/$id.site ]] || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || return 1
  kw_site_find_retired "$domain" || return 2
  ((${#KW_RETIRED_MATCHES[@]})) || return 2
  for name in "${KW_RETIRED_MATCHES[@]}"; do
    kw_site_purge_preflight "$domain" "$name" || return 2
  done
  # Reject obvious creation failures before any retained copy is destroyed.
  kw_site_paths "$id" "$php"
  for path in "$KW_SITE_ROOT" "$KW_SITE_POOL" "$KW_SITE_VHOST" "$KW_SITE_ENABLED" "$KW_SITE_META" "$KW_SITE_SOCKET"; do
    [[ ! -e $path && ! -L $path ]] || { kw_log ERROR "Đích đã tồn tại: $path"; return 2; }
  done
  kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  systemctl is-active --quiet nginx && systemctl is-active --quiet "php${php}-fpm" || return 2
  dump=$(nginx -T 2>&1) || return 2
  [[ $dump != *"$domain"* ]] || { kw_log ERROR 'Domain còn trong cấu hình Nginx khác.'; return 2; }
  for name in "${KW_RETIRED_MATCHES[@]}"; do
    kw_site_purge_preflight "$domain" "$name" || return 2
    rm -rf --one-file-system -- "$KW_PURGE_DIR" || return 1
  done
  for name in "${KW_RETIRED_MATCHES[@]}"; do
    archive_id=${name%%-*}
    kw_site_cleanup_orphan_user "$archive_id" || return 1
  done
  kw_site_cleanup_orphan_user "$id" || return 1
  kw_site_apply_locked "$domain" "$php" "$id"
)

kw_site_cleanup_orphan_user() {
  local id=$1 owner="kw${1}" dir
  kw_site_id_valid "$id" || return 2
  [[ ! -e /etc/kwvps/sites/$id.site && ! -L /etc/kwvps/sites/$id.site ]] || return 0
  for dir in "$KW_BACKUP_ROOT"/retired/"$id"-*; do
    [[ -f $dir/site.meta && ! -L $dir/site.meta ]] && return 0
  done
  getent passwd "$owner" >/dev/null || return 0
  userdel -- "$owner" || { kw_log ERROR "Site đã xóa nhưng chưa xóa được user $owner; cần xử lý thủ công."; return 1; }
}

kw_site_clone_plan() {
  local source=${1,,} destination=${2,,} php
  kw_site_lookup "$source" || return 2
  kw_site_new_domain_valid "$destination" || return 2
  # shellcheck disable=SC2031 # kw_site_lookup sets this in the current shell.
  php=$KW_SITE_PHP
  printf 'Nhân bản %s sang %s (PHP %s).\n' "$source" "$destination" "$php"
  printf 'Sao chép source/code an toàn; tạo user, pool và vhost HTTP riêng.\n'
  printf 'Không sao chép DB, mật khẩu, SSL, DNS hay cron. Ứng dụng động có thể cần cấu hình lại.\n'
}

kw_site_clone_rollback() {
  ((KW_CLONE_COMMITTED == 0)) || return 0
  if ((KW_CLONE_CREATED)); then
    if ((KW_CLONE_COPIED)) && [[ -d $KW_SITE_PUBLIC ]]; then
      mv -T -- "$KW_SITE_PUBLIC" "$KW_CLONE_TEMP/copied-public" ||
        kw_log ERROR "Cần kiểm tra source clone: $KW_SITE_PUBLIC"
    fi
    if ((KW_CLONE_DEFAULT_MOVED)) && [[ -d $KW_CLONE_TEMP/default-public ]]; then
      mv -T -- "$KW_CLONE_TEMP/default-public" "$KW_SITE_PUBLIC" ||
        kw_log ERROR "Cần phục hồi trang mặc định: $KW_SITE_PUBLIC"
    fi
    kw_site_remove_apply_locked "$KW_CLONE_DESTINATION" ||
      kw_log ERROR "Không thể tự đưa site clone lỗi ra khỏi phục vụ: $KW_CLONE_DESTINATION"
  fi
  [[ -z $KW_CLONE_TEMP ]] || kw_log WARN "Giữ staging clone để kiểm tra: $KW_CLONE_TEMP"
}

kw_site_clone_apply_locked() (
  local source=$1 destination=$2 source_root php id helper archive
  local KW_CLONE_COMMITTED=0 KW_CLONE_CREATED=0 KW_CLONE_DEFAULT_MOVED=0 KW_CLONE_COPIED=0
  local KW_CLONE_TEMP='' KW_CLONE_DESTINATION=$destination
  kw_site_lookup "$source" || return 2
  source_root=$KW_SITE_ROOT
  # shellcheck disable=SC2031 # kw_site_lookup sets this in the current shell.
  php=$KW_SITE_PHP
  id=$(kw_site_id "$destination") || return 2
  kw_site_preflight "$destination" "$php" "$id" || return 2
  kw_backup_source_preflight "$source" || return 2
  if [[ ! -e $KW_BACKUP_ROOT && ! -L $KW_BACKUP_ROOT ]]; then
    install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT" || return 1
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  KW_CLONE_TEMP=$(mktemp -d "$KW_BACKUP_ROOT/.clone.XXXXXXXX") || return 1
  chmod 0700 -- "$KW_CLONE_TEMP" || return 1
  trap kw_site_clone_rollback EXIT
  archive="$KW_CLONE_TEMP/source.tar.gz"
  kw_backup_archive_create "$source_root" "$archive" || return 1
  install -d -m 0700 -- "$KW_CLONE_TEMP/extract" || return 1
  helper=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../scripts" && pwd -P)/restore_source.py || return 1
  python3 "$helper" "$archive" "$KW_CLONE_TEMP/extract" || return 1
  kw_site_apply_locked "$destination" "$php" "$id" || return 1
  KW_CLONE_CREATED=1
  kw_site_paths "$id" "$php"
  chown -R -- "kw${id}:www-data" "$KW_CLONE_TEMP/extract/public" || return 1
  mv -T -- "$KW_SITE_PUBLIC" "$KW_CLONE_TEMP/default-public" || return 1
  KW_CLONE_DEFAULT_MOVED=1
  mv -T -- "$KW_CLONE_TEMP/extract/public" "$KW_SITE_PUBLIC" || return 1
  KW_CLONE_COPIED=1
  [[ -d $KW_SITE_PUBLIC && ! -L $KW_SITE_PUBLIC ]] || return 1
  nginx -t >/dev/null || return 1
  KW_CLONE_COMMITTED=1
  rm -f -- "$KW_CLONE_TEMP/default-public/index.html" "$archive"
  rmdir -- "$KW_CLONE_TEMP/default-public" "$KW_CLONE_TEMP/extract" "$KW_CLONE_TEMP" ||
    kw_log WARN "Còn file staging clone tại $KW_CLONE_TEMP"
  printf 'Đã nhân bản source/code %s sang %s. Hãy cấu hình DB, DNS và SSL riêng.\n' "$source" "$destination"
)

kw_site_clone() (
  local source=${1,,} destination=${2,,} confirm=${3:-}
  kw_domain_valid "$source" && kw_site_new_domain_valid "$destination" && [[ $source != "$destination" ]] || return 2
  [[ $confirm == yes ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || { kw_log ERROR 'Một thao tác site khác đang chạy.'; return 1; }
  kw_site_clone_apply_locked "$source" "$destination"
)

kw_site_clone_interactive() {
  # shellcheck disable=SC2034 # Read by the nested clone/site preflight.
  local source destination answer KW_PHP_EOL_SITE_ACK=0
  printf 'Quản lý Sites / Nhân bản site / Chọn site nguồn để nhân bản\n'
  kw_site_prompt_domain || return 0
  source=$KW_SITE_CHOICE
  # shellcheck disable=SC2031 # kw_site_lookup sets site metadata in this current shell.
  kw_site_lookup "$source" || return 2
  # shellcheck disable=SC2031 # Value was set by kw_site_lookup above, not a subshell.
  if [[ $KW_SITE_PHP == 7.4 ]]; then
    printf 'CẢNH BÁO: site nguồn dùng PHP 7.4 đã hết hỗ trợ; site clone cũng sẽ dùng phiên bản EOL này.\n'
    kw_prompt_yes_no_token 'Tôi hiểu rủi ro EOL và vẫn muốn nhân bản site bằng PHP 7.4?' 'CLONE-EOL-PHP:7.4' || return 0
    # shellcheck disable=SC2034 # Read by the nested clone/site preflight.
    KW_PHP_EOL_SITE_ACK=1
  fi
  # shellcheck disable=SC2016 # Backticks are literal menu typography.
  printf 'Nhập `0` để quay lại hoặc Ctrl+C để thoát.\n'
  while :; do
    printf 'Domain đích: '
    IFS= read -r destination || return 0
    [[ $destination != 0 && -n $destination ]] || return 0
    destination=${destination,,}
    kw_site_new_domain_valid "$destination" && [[ $destination != "$source" ]] && break
    printf 'Domain không hợp lệ, quá dài hoặc đã tồn tại/trùng site ID. Nhập lại.\n'
  done
  kw_site_clone_plan "$source" "$destination" || return 2
  while :; do
    printf 'Nhân bản %s sang %s? [Y/n]: ' "$source" "$destination"
    IFS= read -r answer || return 0
    case "$answer" in
      ''|y|Y|yes|YES) kw_site_clone "$source" "$destination" yes; return $? ;;
      n|N|no|NO|0) return 0 ;;
      *) printf 'Nhập Y hoặc n.\n' ;;
    esac
  done
}

kw_site_permissions_plan() {
  local domain=${1,,}
  kw_site_lookup "$domain" || return 2
  printf 'Phân lại quyền sở hữu source của %s:\n' "$domain"
  printf '  Đường dẫn: %s\n  Chủ sở hữu: %s:www-data\n' "$KW_SITE_ROOT" "$KW_SITE_OWNER"
  printf '  Hỗ trợ symlink nội bộ (Laravel/Node); từ chối symlink trỏ ngoài site hoặc hardlink.\n'
  printf '  Ghi manifest owner/group cũ vào %s.\n' "$KW_BACKUP_ROOT"
}

kw_site_permissions_apply_locked() (
  local domain=$1 id manifest temp
  kw_site_lookup "$domain" || return 2
  kw_backup_source_preflight "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  [[ ! -L $KW_SITE_ROOT ]] || return 2
  if [[ -n $(find -P "$KW_SITE_ROOT" -xdev -type f -links +1 -print -quit) ]]; then
    kw_log ERROR 'Source có hardlink; từ chối đổi owner hàng loạt để tránh ảnh hưởng ngoài site.'; return 2;
  fi
  local safe_symlinks=0
  if python3 - "$KW_SITE_ROOT" <<'PY'
import os, sys
site_root = os.path.realpath(sys.argv[1])
sep = os.sep
prefix = site_root if site_root.endswith(sep) else site_root + sep
for dirpath, dirnames, filenames in os.walk(site_root, followlinks=False):
    for name in dirnames + filenames:
        p = os.path.join(dirpath, name)
        if os.path.islink(p):
            target = os.path.realpath(p)
            if target != site_root and not target.startswith(prefix):
                sys.exit(1)
PY
  then
    safe_symlinks=1
  fi
  ((safe_symlinks)) || {
    kw_log ERROR 'Source có symlink trỏ ra ngoài thư mục site; từ chối đổi owner hàng loạt.'
    return 2
  }
  if [[ ! -e $KW_BACKUP_ROOT && ! -L $KW_BACKUP_ROOT ]]; then
    install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT" || return 1
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  temp=$(mktemp "$KW_BACKUP_ROOT/.permissions-${id}.XXXXXXXX") || return 1
  chmod 0600 -- "$temp" || return 1
  find -P "$KW_SITE_ROOT" -xdev -printf '%P\0%U:%G\0' > "$temp" || return 1
  manifest="$KW_BACKUP_ROOT/permissions-${id}-$(date -u +%Y%m%dT%H%M%SZ)-${temp##*.}.manifest"
  [[ ! -e $manifest ]] || return 1
  mv -T -- "$temp" "$manifest" || return 1
  find -P "$KW_SITE_ROOT" -xdev -exec chown -h -- "$KW_SITE_OWNER:www-data" '{}' + || {
    kw_log ERROR "Đổi owner chưa hoàn tất; manifest để đối chiếu: $manifest"; return 1;
  }
  if [[ -f $KW_SITE_ROOT/deploy/shared/.env && ! -L $KW_SITE_ROOT/deploy/shared/.env ]]; then
    chmod 0600 -- "$KW_SITE_ROOT/deploy/shared/.env" || return 1
    chown -- "$KW_SITE_OWNER:$KW_SITE_OWNER" "$KW_SITE_ROOT/deploy/shared/.env" || return 1
  fi
  if [[ -d $KW_SITE_ROOT/deploy/shared/storage && ! -L $KW_SITE_ROOT/deploy/shared/storage ]]; then
    find -P "$KW_SITE_ROOT/deploy/shared/storage" -type d -exec chmod 0750 '{}' + || return 1
    find -P "$KW_SITE_ROOT/deploy/shared/storage" -type f -exec chmod 0660 '{}' + || return 1
  fi
  printf 'Đã phân lại chủ sở hữu source %s; manifest cũ: %s\n' "$domain" "$manifest"
)

kw_site_permissions() (
  local domain=${1,,} confirm=${2:-}
  kw_domain_valid "$domain" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || return 1
  kw_site_permissions_apply_locked "$domain"
)

kw_site_permissions_interactive() {
  local domain
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_site_permissions_plan "$domain" || return 2
  kw_prompt_yes_no_token "Phân lại quyền sở hữu source $domain?" "$domain" || return 0
  kw_site_permissions "$domain" "${KW_PROMPT_VALUE,,}"
}

kw_site_laravel_plan() {
  local domain=${1,,}
  kw_site_lookup "$domain" || return 2
  printf 'Chuẩn bị thư mục Laravel cho %s:\n' "$domain"
  printf '  Git source: %s/source\n' "$KW_SITE_ROOT"
  printf '  Release:    %s/deploy/releases\n' "$KW_SITE_ROOT"
  printf '  Dùng chung: %s/deploy/shared/storage\n' "$KW_SITE_ROOT"
  printf 'Sau bước này dùng menu Laravel của KwVPS để clone Git, sửa .env, pull và deploy.\n'
  printf 'Bước chuẩn bị chỉ tạo thư mục rỗng; không clone Git, tạo .env/current, sửa Nginx hoặc DB.\n'
  printf 'Nếu source/deploy hoặc cấu trúc cũ có tiền tố đã tồn tại, KwVPS dừng và không ghi đè.\n'
}

kw_site_laravel_create_layout() (
  # shellcheck disable=SC2034 # status is read by the EXIT cleanup trap.
  local root=$1 owner=$2 source deploy path index status expected_mode
  local -a created=() web_paths=()
  [[ $owner =~ ^kw[a-z0-9]{1,29}$ && -d $root && ! -L $root ]] || return 2
  source="$root/source"
  deploy="$root/deploy"
  for path in "$source" "$deploy"; do
    [[ ! -e $path && ! -L $path ]] || {
      kw_log ERROR "Thư mục đã tồn tại; không thay đổi: $path"
      return 2
    }
  done
  for path in "$root"/*-source "$root"/*-deploy; do
    [[ ! -e $path && ! -L $path ]] || {
      kw_log ERROR "Site đã có cấu trúc deploy cũ; không tạo thêm: $path"
      return 2
    }
  done
  trap 'status=$?; if ((status != 0)); then for ((index=${#created[@]}-1; index>=0; index--)); do rmdir -- "${created[index]}" 2>/dev/null || kw_log WARN "Giữ thư mục không rỗng: ${created[index]}"; done; fi' EXIT
  for path in \
    "$source" "$deploy" "$deploy/releases" "$deploy/shared" \
    "$deploy/shared/storage" "$deploy/shared/storage/app" \
    "$deploy/shared/storage/app/public" "$deploy/shared/storage/app/private" \
    "$deploy/shared/storage/logs" "$deploy/shared/storage/framework" \
    "$deploy/shared/storage/framework/cache" "$deploy/shared/storage/framework/cache/data" \
    "$deploy/shared/storage/framework/sessions" "$deploy/shared/storage/framework/views"; do
    runuser -u "$owner" -- mkdir -m 0750 -- "$path" || return 1
    created+=("$path")
  done
  web_paths=("$deploy" "$deploy/releases" "$deploy/shared" "$deploy/shared/storage" \
    "$deploy/shared/storage/app" "$deploy/shared/storage/app/public")
  for path in "${web_paths[@]}"; do
    [[ -d $path && ! -L $path ]] || return 2
    chown -h -- "$owner:www-data" "$path" || return 1
  done
  # chmod by an unprivileged user silently clears setgid if its effective group
  # does not match the directory's group. Run only this chmod with www-data as
  # the primary group, keeping the site UID and avoiding root following a raced link.
  [[ -d $deploy/shared/storage/app/public && ! -L $deploy/shared/storage/app/public &&
     $(stat -c '%U:%G' -- "$deploy/shared/storage/app/public") == "$owner:www-data" ]] || return 2
  runuser -u "$owner" -g www-data -- chmod 2750 -- "$deploy/shared/storage/app/public" || return 1
  for path in "${created[@]}"; do
    expected_mode=750
    [[ $path != "$deploy/shared/storage/app/public" ]] || expected_mode=2750
    [[ -d $path && ! -L $path &&
       $(stat -c '%U:%a' -- "$path") == "$owner:$expected_mode" ]] || {
      kw_log ERROR "Quyền thư mục Laravel không đúng; chưa hoàn tất: $path"
      return 1
    }
  done
  for path in "${web_paths[@]}"; do
    [[ $(stat -c %G -- "$path") == www-data ]] || {
      kw_log ERROR "Nhóm truy cập Nginx không đúng; chưa hoàn tất: $path"
      return 1
    }
  done
  trap - EXIT
  printf 'Đã chuẩn bị %s và %s. Chưa clone code hoặc đổi website.\n' "$source" "$deploy"
)

kw_site_laravel_prepare() (
  local domain=${1,,} confirm=${2:-} command
  kw_domain_valid "$domain" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || { kw_log ERROR 'Cần root để chuẩn bị Laravel.'; return 2; }
  for command in flock runuser mkdir chown chmod stat rmdir; do
    kw_has "$command" || { kw_log ERROR "Thiếu công cụ $command."; return 2; }
  done
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || return 1
  kw_site_lookup "$domain" || return 2
  [[ $(stat -c '%U:%G' -- "$KW_SITE_ROOT") == "$KW_SITE_OWNER:www-data" ]] || {
    kw_log ERROR 'Owner/group của thư mục site chưa đúng; kiểm tra quyền trước khi tiếp tục.'
    return 2
  }
  runuser -u www-data -- test -x "$KW_SITE_ROOT" || {
    kw_log ERROR 'Nginx không thể truy cập thư mục site; kiểm tra quyền trước khi tiếp tục.'
    return 2
  }
  kw_site_laravel_create_layout "$KW_SITE_ROOT" "$KW_SITE_OWNER"
)

kw_site_laravel_interactive() {
  local domain
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_site_laravel_plan "$domain" || return 2
  kw_prompt_yes_no_token "Tạo thư mục Laravel cho $domain?" "$domain" || return 0
  kw_site_laravel_prepare "$domain" "${KW_PROMPT_VALUE,,}"
}

kw_site_remove_plan() {
  local domain=${1,,} php id file key value name user
  kw_site_lookup "$domain" || return 2
  php=${KW_SITE_POOL#/etc/php/}; php=${php%%/*}
  id=${KW_SITE_OWNER#kw}
  printf 'Tài nguyên của site %s:\n' "$domain"
  printf '  Source/code: %s (%s)\n' "$KW_SITE_ROOT" "$(du -shx -- "$KW_SITE_ROOT" | awk '{print $1}')"
  printf '  User Linux: %s\n  PHP-FPM: %s\n  Pool: %s\n' "$KW_SITE_OWNER" "$php" "$KW_SITE_POOL"
  printf '  Nginx: %s\n  Metadata: %s\n' "$KW_SITE_VHOST" "$KW_SITE_META"
  if [[ -f /etc/letsencrypt/renewal/$domain.conf ]]; then
    printf '  SSL/renewal: %s (chứng chỉ sẽ giữ nguyên)\n' "/etc/letsencrypt/renewal/$domain.conf"
  fi
  if [[ -f /etc/kwvps/certs/$id/fullchain.pem && -f $KW_SITE_VHOST ]] &&
     grep -Fxq '# KwVPS TLS: Paid' "$KW_SITE_VHOST"; then
    printf '  Paid SSL: /etc/kwvps/certs/%s (chứng chỉ/private key sẽ giữ nguyên)\n' "$id"
  fi
  printf '  Database KwVPS gắn domain:\n'
  local found=0
  for file in /etc/kwvps/db-custom/*.db; do
    [[ -f $file && ! -L $file ]] || continue
    name=''; user=''; value=''
    while IFS='=' read -r key value; do
      case "$key" in database) name=$value ;; user) user=$value ;; domain) [[ $value != "$domain" ]] || found=1 ;; esac
    done < "$file"
    if ((found)); then printf '    %s (user: %s)\n' "$name" "$user"; found=0; fi
  done
  [[ ! -f /etc/kwvps/db/$id.db ]] || printf '    kwdb_%s (legacy)\n' "$id"
  printf '  DB, user DB, log và chứng chỉ KHÔNG bị xóa ngầm.\n'
  printf '  1. Xóa site và GIỮ vùng phục hồi (source/cấu hình)\n'
  printf '  2. Xóa SẠCH site, KHÔNG giữ vùng phục hồi\n'
  printf '  DB, chứng chỉ và backup độc lập vẫn giữ. Xóa sạch còn xóa user Linux của site nếu không có bản giữ khác.\n'
  printf '  0. Quay lại\n'
}

kw_site_remove_preflight() {
  local domain=$1 id php renew mode=${2:-keep}
  [[ $mode == keep || $mode == purge ]] || return 2
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để gỡ site.'; return 2; }
  kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && \
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  kw_site_lookup "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  php=${KW_SITE_POOL#/etc/php/}; php=${php%%/*}
  KW_REMOVE_PHP=$php
  [[ -f $KW_SITE_POOL && ! -L $KW_SITE_POOL && \
     -f $KW_SITE_VHOST && ! -L $KW_SITE_VHOST && \
     -L $KW_SITE_ENABLED && $(readlink -- "$KW_SITE_ENABLED") == "$KW_SITE_VHOST" ]] || return 2
  cmp -s -- "$KW_SITE_POOL" <(kw_site_render_pool "$id" "$KW_SITE_OWNER") || {
    kw_log ERROR 'Pool đã tùy chỉnh; không tự gỡ.'; return 2;
  }
  KW_REMOVE_RENEWAL=''
  if ! kw_site_vhost_matches "$KW_SITE_VHOST" "$domain" "$id" kw_site_render_vhost "$domain" "$id" &&
     ! kw_site_vhost_matches "$KW_SITE_VHOST" "$domain" "$id" kw_laravel_render_vhost http "$domain" "$id"; then
    if kw_site_vhost_matches "$KW_SITE_VHOST" "$domain" "$id" kw_ssl_render_paid_vhost "$domain" "$id" ||
       kw_site_vhost_matches "$KW_SITE_VHOST" "$domain" "$id" kw_laravel_render_vhost paid "$domain" "$id"; then
      [[ -d /etc/kwvps/certs/$id && ! -L /etc/kwvps/certs/$id && \
         -f /etc/kwvps/certs/$id/fullchain.pem && ! -L /etc/kwvps/certs/$id/fullchain.pem && \
         -f /etc/kwvps/certs/$id/privkey.pem && ! -L /etc/kwvps/certs/$id/privkey.pem ]] || return 2
    else
      if ! kw_site_vhost_matches "$KW_SITE_VHOST" "$domain" "$id" kw_ssl_render_vhost "$domain" "$id" &&
         ! kw_site_vhost_matches "$KW_SITE_VHOST" "$domain" "$id" kw_ssl_render_vhost "$domain" "$id" zerossl &&
         ! kw_site_vhost_matches "$KW_SITE_VHOST" "$domain" "$id" kw_laravel_render_vhost letsencrypt "$domain" "$id" &&
         ! kw_site_vhost_matches "$KW_SITE_VHOST" "$domain" "$id" kw_laravel_render_vhost zerossl "$domain" "$id"; then
        kw_log ERROR 'Vhost đã tùy chỉnh; không tự gỡ.'; return 2
      fi
      renew="/etc/letsencrypt/renewal/${domain}.conf"
      [[ -f $renew && ! -L $renew && $(stat -c %u -- "$renew") == 0 ]] || return 2
      grep -Fq "/var/www/kwvps/${id}/public" "$renew" || return 2
      KW_REMOVE_RENEWAL=$renew
    fi
  fi
  "php-fpm${php}" -t >/dev/null 2>&1 && nginx -t >/dev/null 2>&1 || return 2
}

kw_site_remove_rollback() {
  ((KW_REMOVE_DONE == 0)) || return 0
  local name source target
  for name in root meta pool vhost enabled renewal; do
    case "$name" in
      root) source="$KW_REMOVE_DIR/site-root"; target=$KW_SITE_ROOT ;;
      meta) source="$KW_REMOVE_DIR/site.meta"; target=$KW_SITE_META ;;
      pool) source="$KW_REMOVE_DIR/pool.conf"; target=$KW_SITE_POOL ;;
      vhost) source="$KW_REMOVE_DIR/vhost.conf"; target=$KW_SITE_VHOST ;;
      enabled) source="$KW_REMOVE_DIR/enabled.conf"; target=$KW_SITE_ENABLED ;;
      renewal) source="$KW_REMOVE_DIR/renewal.conf"; target=$KW_REMOVE_RENEWAL ;;
    esac
    [[ -n $target ]] || continue
    if [[ -e $source || -L $source ]]; then
      if [[ ! -e $target && ! -L $target ]]; then
        mv -T -- "$source" "$target" || kw_log ERROR "Cần phục hồi thủ công $source."
      fi
    fi
  done
  if ((KW_REMOVE_NGINX_CHANGED)); then
    if ! nginx -t >/dev/null 2>&1 || ! systemctl restart nginx >/dev/null 2>&1 || \
       ! systemctl is-active --quiet nginx; then
      kw_log WARN 'Cần kiểm tra Nginx sau rollback.'
    fi
  fi
  if ((KW_REMOVE_FPM_CHANGED)); then
    if ! "php-fpm${KW_REMOVE_PHP}" -t >/dev/null 2>&1 || \
       ! systemctl restart "php${KW_REMOVE_PHP}-fpm" >/dev/null 2>&1 || \
       ! systemctl is-active --quiet "php${KW_REMOVE_PHP}-fpm"; then
      kw_log WARN 'Cần kiểm tra PHP-FPM sau rollback.'
    fi
  fi
}

kw_site_remove_apply_locked() (
  local domain=$1 mode=${2:-keep} id timestamp suffix
  local KW_REMOVE_DONE=0 KW_REMOVE_DIR='' KW_REMOVE_PHP='' KW_REMOVE_RENEWAL=''
  # shellcheck disable=SC2034 # Rollback trap reads these mutation markers.
  local KW_REMOVE_NGINX_CHANGED=0 KW_REMOVE_FPM_CHANGED=0
  kw_site_remove_preflight "$domain" "$mode" || return 2
  install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT/retired" || return 1
  kw_backup_dir_safe "$KW_BACKUP_ROOT/retired" 0077 || return 2
  id=${KW_SITE_OWNER#kw}
  timestamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
  suffix=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n') || return 1
  KW_REMOVE_DIR="$KW_BACKUP_ROOT/retired/${id}-${timestamp}-${suffix}"
  [[ ! -e $KW_REMOVE_DIR && ! -L $KW_REMOVE_DIR ]] || return 2
  install -d -m 0700 -o root -g root -- "$KW_REMOVE_DIR" || return 1
  trap kw_site_remove_rollback EXIT
  # shellcheck disable=SC2034 # A move can partially mutate the service configuration.
  KW_REMOVE_NGINX_CHANGED=1
  mv -T -- "$KW_SITE_ENABLED" "$KW_REMOVE_DIR/enabled.conf" || return 1
  mv -T -- "$KW_SITE_VHOST" "$KW_REMOVE_DIR/vhost.conf" || return 1
  # shellcheck disable=SC2034 # A move can partially mutate the service configuration.
  KW_REMOVE_FPM_CHANGED=1
  mv -T -- "$KW_SITE_POOL" "$KW_REMOVE_DIR/pool.conf" || return 1
  mv -T -- "$KW_SITE_META" "$KW_REMOVE_DIR/site.meta" || return 1
  mv -T -- "$KW_SITE_ROOT" "$KW_REMOVE_DIR/site-root" || return 1
  if [[ -n $KW_REMOVE_RENEWAL ]]; then
    mv -T -- "$KW_REMOVE_RENEWAL" "$KW_REMOVE_DIR/renewal.conf" || return 1
  fi
  nginx -t >/dev/null || return 1
  "php-fpm${KW_REMOVE_PHP}" -t >/dev/null || return 1
  systemctl restart "php${KW_REMOVE_PHP}-fpm" || return 1
  systemctl is-active --quiet "php${KW_REMOVE_PHP}-fpm" || return 1
  systemctl restart nginx || return 1
  systemctl is-active --quiet nginx || return 1
  KW_REMOVE_DONE=1
  if [[ $mode == purge ]]; then
    kw_site_purge_preflight "$domain" "${KW_REMOVE_DIR##*/}" || {
      kw_log ERROR "Site đã gỡ nhưng vẫn còn trong vùng giữ: $KW_REMOVE_DIR"; return 1;
    }
    rm -rf --one-file-system -- "$KW_REMOVE_DIR" || {
      kw_log ERROR "Site đã gỡ nhưng chưa xóa hết vùng giữ: $KW_REMOVE_DIR"; return 1;
    }
    [[ ! -e $KW_REMOVE_DIR && ! -L $KW_REMOVE_DIR ]] || return 1
    kw_site_cleanup_orphan_user "$id" || return 1
    printf 'Đã xóa sạch site %s; không giữ vùng phục hồi.\n' "$domain"
  else
    printf 'Đã đưa %s ra khỏi phục vụ. Tài nguyên giữ tại %s\n' "$domain" "$KW_REMOVE_DIR"
  fi
  printf 'DB, log và chứng chỉ không bị xóa.\n'
)

kw_site_remove() (
  local domain=${1,,} confirm=${2:-} mode=${3:-keep}
  kw_domain_valid "$domain" || return 2
  [[ $mode == keep || $mode == purge ]] || return 2
  [[ $confirm == "$domain" ]] || { kw_log ERROR 'Xác nhận domain không khớp.'; return 2; }
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || { kw_log ERROR 'Một thao tác site khác đang chạy.'; return 1; }
  kw_site_remove_apply_locked "$domain" "$mode"
)

kw_site_remove_interactive() {
  local domain confirm choice mode
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_site_remove_plan "$domain" || return 2
  while :; do
    printf 'Chọn: '
    IFS= read -r choice || return 0
    case "$choice" in 1) mode=keep; break ;; 2) mode=purge; break ;; 0|'') return 0 ;; *) printf 'Lựa chọn không hợp lệ.\n' ;; esac
  done
  kw_prompt_confirm_domain "$domain" 'Nhập lại đúng domain để XÓA site: ' || return 0
  confirm=$KW_PROMPT_VALUE
  kw_site_remove "$domain" "${confirm,,}" "$mode"
}

kw_site_retired_list() {
  local dir name
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để xem site đang giữ.'; return 2; }
  [[ -d $KW_BACKUP_ROOT/retired && ! -L $KW_BACKUP_ROOT/retired ]] || {
    printf 'Chưa có site KwVPS trong vùng giữ.\n'; return 0;
  }
  kw_backup_dir_safe "$KW_BACKUP_ROOT/retired" 0077 || return 2
  for dir in "$KW_BACKUP_ROOT"/retired/*; do
    [[ -d $dir && ! -L $dir ]] || continue
    name=${dir##*/}
    [[ $name =~ ^[a-z0-9]{1,29}-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$ ]] || continue
    printf '%s\n' "$name"
  done
}

kw_site_retired_preflight() {
  local domain=${1,,} name=$2 id dir key value meta_domain='' meta_id='' meta_php='' meta_owner='' path dump
  ((EUID == 0)) || return 2
  kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && \
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  kw_domain_valid "$domain" || return 2
  [[ $name =~ ^[a-z0-9]{1,29}-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$ ]] || return 2
  id=${name%%-*}
  kw_site_id_valid "$id" || return 2
  # A retired legacy site no longer has its registry entry for kw_site_id to discover.
  kw_site_id_matches_domain "$id" "$domain" || return 2
  kw_backup_dir_safe "$KW_BACKUP_ROOT/retired" 0077 || return 2
  dir="$KW_BACKUP_ROOT/retired/$name"
  kw_backup_dir_safe "$dir" 0077 || return 2
  [[ -f $dir/site.meta && ! -L $dir/site.meta ]] || return 2
  while IFS='=' read -r key value; do
    case "$key" in
      domain) meta_domain=$value ;;
      site_id) meta_id=$value ;;
      php_version) meta_php=$value ;;
      owner) meta_owner=$value ;;
    esac
  done < "$dir/site.meta"
  [[ $meta_domain == "$domain" && $meta_id == "$id" ]] || return 2
  kw_site_php_valid "$meta_php" || return 2
  kw_site_paths "$id" "$meta_php"
  [[ $meta_owner == "$KW_SITE_OWNER" ]] || return 2
  KW_RETIRED_PHP=$meta_php
  KW_RETIRED_DIR=$dir
  getent passwd "$KW_SITE_OWNER" >/dev/null || return 2
  [[ -d $dir/site-root && ! -L $dir/site-root && \
     -d $dir/site-root/public && ! -L $dir/site-root/public && \
     -f $dir/pool.conf && ! -L $dir/pool.conf && \
     -f $dir/vhost.conf && ! -L $dir/vhost.conf && \
     -L $dir/enabled.conf && $(readlink -- "$dir/enabled.conf") == "$KW_SITE_VHOST" ]] || return 2
  cmp -s -- "$dir/pool.conf" <(kw_site_render_pool "$id" "$KW_SITE_OWNER") || return 2
  KW_RETIRED_RENEWAL=''
  if ! kw_site_vhost_matches "$dir/vhost.conf" "$domain" "$id" kw_site_render_vhost "$domain" "$id" &&
     ! kw_site_vhost_matches "$dir/vhost.conf" "$domain" "$id" kw_laravel_render_vhost http "$domain" "$id"; then
    if kw_site_vhost_matches "$dir/vhost.conf" "$domain" "$id" kw_ssl_render_paid_vhost "$domain" "$id" ||
       kw_site_vhost_matches "$dir/vhost.conf" "$domain" "$id" kw_laravel_render_vhost paid "$domain" "$id"; then
      [[ -f /etc/kwvps/certs/$id/fullchain.pem && -f /etc/kwvps/certs/$id/privkey.pem ]] || return 2
    else
      if ! kw_site_vhost_matches "$dir/vhost.conf" "$domain" "$id" kw_ssl_render_vhost "$domain" "$id" &&
         ! kw_site_vhost_matches "$dir/vhost.conf" "$domain" "$id" kw_ssl_render_vhost "$domain" "$id" zerossl &&
         ! kw_site_vhost_matches "$dir/vhost.conf" "$domain" "$id" kw_laravel_render_vhost letsencrypt "$domain" "$id" &&
         ! kw_site_vhost_matches "$dir/vhost.conf" "$domain" "$id" kw_laravel_render_vhost zerossl "$domain" "$id"; then
        return 2
      fi
      [[ -f $dir/renewal.conf && ! -L $dir/renewal.conf ]] || return 2
      [[ -f /etc/letsencrypt/live/$domain/fullchain.pem && \
         -f /etc/letsencrypt/live/$domain/privkey.pem ]] || return 2
      KW_RETIRED_RENEWAL="/etc/letsencrypt/renewal/$domain.conf"
      [[ ! -e $KW_RETIRED_RENEWAL && ! -L $KW_RETIRED_RENEWAL ]] || return 2
    fi
  fi
  for path in "$KW_SITE_ROOT" "$KW_SITE_META" "$KW_SITE_POOL" "$KW_SITE_VHOST" "$KW_SITE_ENABLED" "$KW_SITE_SOCKET"; do
    [[ ! -e $path && ! -L $path ]] || { kw_log ERROR "Đích đã tồn tại: $path"; return 2; }
  done
  dump=$(nginx -T 2>&1) || return 2
  [[ $dump != *"$domain"* ]] || { kw_log ERROR 'Domain đang được Nginx sử dụng.'; return 2; }
  systemctl is-active --quiet nginx || return 2
  systemctl is-active --quiet "php${meta_php}-fpm" || return 2
}

kw_site_retired_plan() {
  local domain=$1 name=$2 KW_RETIRED_PHP='' KW_RETIRED_DIR='' KW_RETIRED_RENEWAL=''
  kw_site_retired_preflight "$domain" "$name" || return 2
  printf 'Kế hoạch phục hồi site đã giữ:\n'
  printf '  Domain: %s\n  Vùng giữ: %s\n  PHP-FPM: %s\n' \
    "${domain,,}" "$KW_RETIRED_DIR" "$KW_RETIRED_PHP"
  printf '  Trả source, metadata, pool và vhost về đường dẫn cũ; kiểm tra cấu hình rồi khởi động lại dịch vụ.\n'
  printf '  Không khôi phục DB, SSL, log hoặc thay đổi bên ngoài KwVPS.\n'
}

kw_site_retired_rollback() {
  ((KW_RETIRED_DONE == 0)) || return 0
  local name source target
  for name in renewal enabled vhost pool meta root; do
    case "$name" in
      renewal) source=$KW_RETIRED_RENEWAL; target="$KW_RETIRED_DIR/renewal.conf" ;;
      enabled) source=$KW_SITE_ENABLED; target="$KW_RETIRED_DIR/enabled.conf" ;;
      vhost) source=$KW_SITE_VHOST; target="$KW_RETIRED_DIR/vhost.conf" ;;
      pool) source=$KW_SITE_POOL; target="$KW_RETIRED_DIR/pool.conf" ;;
      meta) source=$KW_SITE_META; target="$KW_RETIRED_DIR/site.meta" ;;
      root) source=$KW_SITE_ROOT; target="$KW_RETIRED_DIR/site-root" ;;
    esac
    [[ -n $source ]] || continue
    if [[ -e $source || -L $source ]]; then
      if [[ ! -e $target && ! -L $target ]]; then
        mv -T -- "$source" "$target" || kw_log ERROR "Cần trả thủ công $source."
      fi
    fi
  done
  if ((KW_RETIRED_NGINX_CHANGED)); then
    if ! nginx -t >/dev/null 2>&1 || ! systemctl restart nginx >/dev/null 2>&1 || \
       ! systemctl is-active --quiet nginx; then
      kw_log WARN 'Cần kiểm tra Nginx sau rollback.'
    fi
  fi
  if ((KW_RETIRED_FPM_CHANGED)); then
    if ! "php-fpm${KW_RETIRED_PHP}" -t >/dev/null 2>&1 || \
       ! systemctl restart "php${KW_RETIRED_PHP}-fpm" >/dev/null 2>&1 || \
       ! systemctl is-active --quiet "php${KW_RETIRED_PHP}-fpm"; then
      kw_log WARN 'Cần kiểm tra PHP-FPM sau rollback.'
    fi
  fi
}

kw_site_retired_apply_locked() (
  local domain=$1 name=$2
  local KW_RETIRED_PHP='' KW_RETIRED_DIR='' KW_RETIRED_RENEWAL='' KW_RETIRED_DONE=0
  # shellcheck disable=SC2034 # Rollback trap reads these mutation markers.
  local KW_RETIRED_NGINX_CHANGED=0 KW_RETIRED_FPM_CHANGED=0
  kw_site_retired_preflight "$domain" "$name" || return 2
  trap kw_site_retired_rollback EXIT
  mv -T -- "$KW_RETIRED_DIR/site-root" "$KW_SITE_ROOT" || return 1
  mv -T -- "$KW_RETIRED_DIR/site.meta" "$KW_SITE_META" || return 1
  # shellcheck disable=SC2034 # A move can partially mutate the service configuration.
  KW_RETIRED_FPM_CHANGED=1
  mv -T -- "$KW_RETIRED_DIR/pool.conf" "$KW_SITE_POOL" || return 1
  # shellcheck disable=SC2034 # A move can partially mutate the service configuration.
  KW_RETIRED_NGINX_CHANGED=1
  mv -T -- "$KW_RETIRED_DIR/vhost.conf" "$KW_SITE_VHOST" || return 1
  mv -T -- "$KW_RETIRED_DIR/enabled.conf" "$KW_SITE_ENABLED" || return 1
  if [[ -n $KW_RETIRED_RENEWAL ]]; then
    mv -T -- "$KW_RETIRED_DIR/renewal.conf" "$KW_RETIRED_RENEWAL" || return 1
  fi
  nginx -t >/dev/null || return 1
  "php-fpm${KW_RETIRED_PHP}" -t >/dev/null || return 1
  systemctl restart "php${KW_RETIRED_PHP}-fpm" || return 1
  systemctl is-active --quiet "php${KW_RETIRED_PHP}-fpm" || return 1
  systemctl restart nginx || return 1
  systemctl is-active --quiet nginx || return 1
  KW_RETIRED_DONE=1
  rmdir -- "$KW_RETIRED_DIR" 2>/dev/null || \
    kw_log WARN "Vùng giữ đã phục hồi nhưng còn thư mục trống/khác: $KW_RETIRED_DIR"
  printf 'Đã phục hồi site %s; hãy kiểm tra HTTP/PHP và dữ liệu ứng dụng.\n' "$domain"
)

kw_site_retired_restore() (
  local domain=${1,,} name=$2 confirm=${3:-}
  kw_domain_valid "$domain" || return 2
  [[ $confirm == "$domain" ]] || { kw_log ERROR 'Xác nhận domain không khớp.'; return 2; }
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || return 1
  kw_site_retired_apply_locked "$domain" "$name"
)

kw_site_retired_interactive() {
  local domain name confirm dir key value id choice count=0
  local -a domains=() names=()
  ((EUID == 0)) || return 2
  if [[ ! -d $KW_BACKUP_ROOT/retired ]]; then
    printf 'Chưa có site KwVPS trong vùng giữ.\n'; return 0
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT/retired" 0077 || return 2
  printf 'Chọn site đã giữ:\n'
  for dir in "$KW_BACKUP_ROOT"/retired/*; do
    [[ -d $dir && ! -L $dir && -f $dir/site.meta && ! -L $dir/site.meta ]] || continue
    name=${dir##*/}
    [[ $name =~ ^[a-z0-9]{1,29}-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$ ]] || continue
    domain=''; id=''
    while IFS='=' read -r key value; do
      case "$key" in domain) domain=$value ;; site_id) id=$value ;; esac
    done < "$dir/site.meta"
    kw_domain_valid "$domain" || continue
    [[ $name == "$id-"* ]] || continue
    kw_site_id_matches_domain "$id" "$domain" || continue
    domains+=("$domain"); names+=("$name")
    count=$((count + 1))
    printf '%2d. %-30s %s\n' "$count" "$domain" "$name"
  done
  if ((count == 0)); then printf 'Chưa có site hợp lệ trong vùng giữ.\n'; return 0; fi
  printf ' 0. Quay lại\nChọn số site: '
  IFS= read -r choice || return 0
  [[ $choice =~ ^[1-9][0-9]*$ ]] && ((choice <= count)) || return 0
  domain=${domains[choice-1]}; name=${names[choice-1]}
  kw_site_retired_plan "$domain" "$name" || return 2
  kw_prompt_yes_no_token "Phục hồi site $domain từ vùng giữ?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_site_retired_restore "$domain" "$name" "${confirm,,}"
}

kw_site_purge_preflight() {
  local domain=${1,,} name=$2 id dir key value found_domain='' found_id=''
  ((EUID == 0)) || return 2
  kw_domain_valid "$domain" || return 2
  [[ $name =~ ^([a-z0-9]{1,29})-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$ ]] || return 2
  id=${BASH_REMATCH[1]}
  kw_site_id_matches_domain "$id" "$domain" || return 2
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  kw_backup_dir_safe "$KW_BACKUP_ROOT/retired" 0077 || return 2
  dir="$KW_BACKUP_ROOT/retired/$name"
  kw_backup_dir_safe "$dir" 0077 || return 2
  [[ -f $dir/site.meta && ! -L $dir/site.meta && -d $dir/site-root && ! -L $dir/site-root ]] || return 2
  while IFS='=' read -r key value; do
    case "$key" in domain) found_domain=$value ;; site_id) found_id=$value ;; esac
  done < "$dir/site.meta"
  [[ $found_domain == "$domain" && $found_id == "$id" ]] || return 2
  [[ -f $dir/pool.conf && ! -L $dir/pool.conf && -f $dir/vhost.conf && ! -L $dir/vhost.conf ]] || return 2
  [[ -L $dir/enabled.conf ]] || return 2
  [[ $(readlink -- "$dir/enabled.conf") == "/etc/nginx/sites-available/kwvps-${id}.conf" ]] || return 2
  local entry base
  for entry in "$dir"/*; do
    [[ -e $entry || -L $entry ]] || continue
    base=${entry##*/}
    case "$base" in site.meta|site-root|pool.conf|vhost.conf|enabled.conf|renewal.conf) ;; *) kw_log ERROR "Gói giữ có mục lạ: $base"; return 2 ;; esac
  done
  KW_PURGE_DIR=$dir
}

kw_site_purge() (
  local domain=${1,,} name=$2 confirm=${3:-} dir
  [[ $confirm == "$domain" ]] || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || return 1
  kw_site_purge_preflight "$domain" "$name" || return 2
  dir=$KW_PURGE_DIR
  printf 'Xóa vĩnh viễn gói site đã giữ: %s\n' "$dir"
  rm -rf --one-file-system -- "$dir" || return 1
  [[ ! -e $dir && ! -L $dir ]] || return 1
  kw_site_cleanup_orphan_user "${name%%-*}" || return 1
  printf 'Đã xóa sạch gói giữ %s. Không xóa DB, backup độc lập hay chứng chỉ.\n' "$name"
)

kw_site_purge_interactive() {
  local domain='' id='' name='' dir key value choice count=0
  local -a domains=() names=()
  ((EUID == 0)) || return 2
  kw_backup_dir_safe "$KW_BACKUP_ROOT/retired" 0077 || return 2
  printf 'Chọn site đã giữ để xóa sạch:\n'
  for dir in "$KW_BACKUP_ROOT"/retired/*; do
    [[ -d $dir && ! -L $dir && -f $dir/site.meta && ! -L $dir/site.meta ]] || continue
    name=${dir##*/}; domain=''; id=''
    while IFS='=' read -r key value; do
      case "$key" in domain) domain=$value ;; site_id) id=$value ;; esac
    done < "$dir/site.meta"
    kw_domain_valid "$domain" || continue
    [[ $name == "$id-"* ]] || continue
    domains+=("$domain"); names+=("$name")
    count=$((count + 1)); printf '%d. %s (%s)\n' "$count" "$domain" "$name"
  done
  ((count)) || { printf 'Không có site đã giữ.\n'; return 0; }
  printf '0. Quay lại\n'
  while :; do
    printf 'Chọn: '
    IFS= read -r choice || return 0
    [[ $choice != 0 ]] || return 0
    [[ $choice =~ ^[1-9][0-9]*$ ]] && ((choice <= count)) && break
    printf 'Số site không hợp lệ.\n'
  done
  domain=${domains[choice-1]}; name=${names[choice-1]}
  kw_site_purge_preflight "$domain" "$name" || return 2
  printf 'Sẽ xóa vĩnh viễn source/code và cấu hình trong %s. Không thể phục hồi từ gói này.\n' "$KW_PURGE_DIR"
  printf 'DB, backup độc lập, user Linux và chứng chỉ không thuộc phạm vi xóa.\n'
  kw_prompt_confirm_domain "$domain" 'Nhập lại đúng domain để XÓA SẠCH: ' || return 0
  kw_site_purge "$domain" "$name" "${KW_PROMPT_VALUE,,}"
}
