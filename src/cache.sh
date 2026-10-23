#!/usr/bin/env bash
# Redis service controls; never issue FLUSHALL/FLUSHDB across sites.

kw_cache_redis_installed() {
  [[ $(dpkg-query -W -f='${db:Status-Status}' redis-server 2>/dev/null) == installed ]]
}

kw_cache_redis_status() {
  if ! kw_cache_redis_installed; then
    printf 'Redis server chưa cài. Chỉ cài khi bạn chọn; KwVPS không mở cổng Redis.\n'
    return 0
  fi
  printf 'Redis package: '
  dpkg-query -W -f='${Version}\n' redis-server || return 1
  kw_service_status redis-server || return 1
  if kw_has redis-cli; then
    local ping
    ping=$(timeout 3 redis-cli -h 127.0.0.1 -p 6379 ping 2>&1) || {
      printf 'Không PING được Redis local; có thể đang tắt hoặc cần xác thực.\n'; return 0;
    }
    [[ $ping == PONG ]] && printf 'Redis local: PONG\n' || printf 'Redis local: phản hồi khác PONG; kiểm tra xác thực/cấu hình.\n'
  fi
  printf 'Không thực hiện FLUSHALL/FLUSHDB vì Redis có thể dùng chung nhiều site.\n'
}

kw_cache_redis_loopback_only() {
  local sockets line address found=0
  sockets=$(ss -H -ltn '( sport = :6379 )') || return 2
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    address=$(awk '{print $4}' <<< "$line")
    case "$address" in 127.0.0.1:6379|'[::1]:6379') found=1 ;; *) return 2 ;; esac
  done <<< "$sockets"
  ((found))
}

kw_cache_redis_install_plan() {
  local data
  kw_os_supported '' || return 2
  if kw_cache_redis_installed; then printf 'Redis đã cài.\n'; return 0; fi
  data=$(LC_ALL=C apt-get -s --no-remove install --no-install-recommends redis-server 2>&1) || return 2
  [[ $data != *$'\nRemv '* && $data != Remv\ * && $data != *$'\nPurg '* && $data != Purg\ * ]] || return 2
  printf 'Kế hoạch apt (chưa cài):\n%s\n' "$data"
  printf 'Sau cài sẽ xác minh Redis chỉ nghe 127.0.0.1/::1 và PING local. Không mở firewall.\n'
}

kw_cache_redis_install() (
  local confirm=${1:-}
  [[ $confirm == INSTALL-REDIS ]] || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  kw_has apt-get && kw_has flock && kw_has ss || return 2
  exec 9>/run/lock/kwvps-redis.lock || return 2
  flock -n 9 || return 1
  kw_cache_redis_installed && { printf 'Redis đã cài.\n'; return 0; }
  kw_cache_redis_install_plan || return 2
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove --no-install-recommends redis-server || return 1
  if ! kw_has redis-cli || ! systemctl is-active --quiet redis-server || ! kw_cache_redis_loopback_only ||
     [[ $(timeout 3 redis-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null) != PONG ]]; then
    systemctl stop redis-server || kw_log ERROR 'Không dừng được Redis; kiểm tra ngay.'
    kw_log ERROR 'Redis đã cài nhưng không đạt kiểm tra local-only/PING; service đã được yêu cầu dừng.'
    return 1
  fi
  printf 'Đã cài Redis và xác minh chỉ nghe loopback, PING local thành công.\n'
)

kw_cache_redis_restart() (
  local confirm=${1:-}
  [[ $confirm == RESTART-REDIS ]] || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  if ! kw_cache_redis_installed || ! kw_has systemctl || ! kw_has flock; then
    kw_log ERROR 'Redis server chưa cài hoặc thiếu công cụ quản lý.'; return 2;
  fi
  systemctl is-active --quiet redis-server || {
    kw_log ERROR 'Redis không active; xem journal trước khi restart.'; return 2;
  }
  exec 9>/run/lock/kwvps-redis.lock || return 2
  flock -n 9 || return 1
  systemctl restart redis-server || return 1
  systemctl is-active --quiet redis-server || return 1
  printf 'Redis đã restart và service active. Kiểm tra ứng dụng dùng cache sau thao tác.\n'
)

kw_cache_redis_interactive() {
  local choice
  kw_cache_redis_status || return 1
  if ! kw_cache_redis_installed; then
    printf '1. Cài Redis từ package Ubuntu\n0. Quay lại\nChọn: '
    IFS= read -r choice || return 0
    [[ $choice == 1 ]] || return 0
    kw_cache_redis_install_plan || return 2
    kw_prompt_yes_no_token 'Cài Redis trên VPS?' INSTALL-REDIS || return 0
    kw_cache_redis_install "$KW_PROMPT_VALUE"
    return $?
  fi
  printf '1. Restart Redis\n0. Quay lại\nChọn: '
  IFS= read -r choice || return 0
  [[ $choice == 1 ]] || return 0
  kw_prompt_yes_no_token 'Restart Redis? Kết nối cache có thể gián đoạn ngắn.' RESTART-REDIS || return 0
  kw_cache_redis_restart "$KW_PROMPT_VALUE"
}

# Domain cache is Nginx FastCGI cache, isolated by KwVPS site ID. It never
# touches Redis data or application-specific cache directories.
kw_cache_paths() {
  local id=$1
  kw_site_id_valid "$id" || return 2
  KW_CACHE_DIR="/var/cache/nginx/kwvps/$id"
  KW_CACHE_ZONE="/etc/nginx/conf.d/kwvps-fcgi-$id.conf"
  KW_CACHE_SNIPPET="/etc/nginx/kwvps-cache/$id.conf"
  KW_CACHE_MAP=/etc/nginx/conf.d/kwvps-fcgi-map.conf
}

kw_cache_render_zone() {
  local id=$1
  kw_cache_paths "$id" || return 2
  printf '# Managed by KwVPS. FastCGI cache for site %s.\n' "$id"
  printf 'fastcgi_cache_path %s levels=1:2 keys_zone=kwvps_%s:16m max_size=256m inactive=30m use_temp_path=off;\n' \
    "$KW_CACHE_DIR" "$id"
}

kw_cache_render_snippet() {
  local id=$1
  kw_cache_paths "$id" || return 2
  cat <<EOF
# Managed by KwVPS. Only anonymous GET/HEAD without query string may cache.
fastcgi_cache kwvps_${id};
fastcgi_cache_key "\$scheme|\$request_method|\$host|\$request_uri";
fastcgi_cache_bypass \$kwvps_cache_skip;
fastcgi_no_cache \$kwvps_cache_skip;
fastcgi_cache_valid 200 5m;
add_header X-KwVPS-Cache \$upstream_cache_status always;
EOF
}

kw_cache_render_map() {
  cat <<'EOF'
# Managed by KwVPS. Cache only GET/HEAD without query, Cookie or Authorization.
map "$request_method|$query_string|$http_cookie|$http_authorization" $kwvps_cache_skip {
  default 1;
  ~^(GET|HEAD)\|\|\|$ 0;
}
EOF
}

kw_cache_map_ready() {
  [[ -f /etc/nginx/conf.d/kwvps-fcgi-map.conf &&
     ! -L /etc/nginx/conf.d/kwvps-fcgi-map.conf &&
     $(stat -c %u -- /etc/nginx/conf.d/kwvps-fcgi-map.conf) == 0 &&
     $(< /etc/nginx/conf.d/kwvps-fcgi-map.conf) == "$(kw_cache_render_map)" ]]
}

kw_cache_base_vhost() {
  local domain=$1 id=$2 vhost=$3
  kw_domain_valid "$domain" && kw_site_id_valid "$id" || return 2
  [[ -f $vhost && ! -L $vhost ]] || return 2
  if grep -Fxq '# KwVPS TLS: Paid' "$vhost"; then
    kw_ssl_render_paid_vhost "$domain" "$id"
  elif grep -Fxq '# KwVPS TLS: ZeroSSL' "$vhost"; then
    kw_ssl_render_vhost "$domain" "$id" zerossl
  elif grep -Fxq "# KwVPS TLS: Let's Encrypt" "$vhost"; then
    kw_ssl_render_vhost "$domain" "$id" letsencrypt
  else
    kw_site_render_vhost "$domain" "$id"
  fi
}

kw_cache_render_vhost() {
  local domain=$1 id=$2 vhost=$3 base
  base=$(kw_cache_base_vhost "$domain" "$id" "$vhost") || return 2
  [[ $(grep -Ec 'fastcgi_pass unix:/run/php/kwvps-[a-z0-9]+\.sock;' <<< "$base") == 1 ]] || return 2
  awk -v id="$id" '
    /fastcgi_pass unix:\/run\/php\/kwvps-[a-z0-9]+\.sock;/ {
      print "    include /etc/nginx/kwvps-cache/" id ".conf;"
    }
    { print }
  ' <<< "$base"
}

kw_cache_state() {
  local domain=${1,,} id base expected
  kw_site_lookup "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  kw_cache_paths "$id" || return 2
  [[ -f $KW_SITE_VHOST && ! -L $KW_SITE_VHOST &&
     $(stat -c %u -- "$KW_SITE_VHOST") == 0 ]] || return 2
  base=$(kw_cache_base_vhost "$domain" "$id" "$KW_SITE_VHOST") || return 2
  if [[ $(< "$KW_SITE_VHOST") == "$base" ]]; then
    [[ ! -e $KW_CACHE_ZONE && ! -L $KW_CACHE_ZONE &&
       ! -e $KW_CACHE_SNIPPET && ! -L $KW_CACHE_SNIPPET ]] || return 2
    if [[ -e $KW_CACHE_DIR || -L $KW_CACHE_DIR ]]; then
      [[ -d $KW_CACHE_DIR && ! -L $KW_CACHE_DIR &&
         $(stat -c %U -- "$KW_CACHE_DIR") == www-data ]] || return 2
    fi
    KW_CACHE_STATE=off
  else
    expected=$(kw_cache_render_vhost "$domain" "$id" "$KW_SITE_VHOST") || return 2
    [[ $(< "$KW_SITE_VHOST") == "$expected" ]] || {
      kw_log ERROR 'Vhost tùy biến; không sửa FastCGI cache tự động.'
      return 2
    }
    [[ -f $KW_CACHE_ZONE && ! -L $KW_CACHE_ZONE &&
       -f $KW_CACHE_SNIPPET && ! -L $KW_CACHE_SNIPPET ]] || return 2
    [[ $(< "$KW_CACHE_ZONE") == "$(kw_cache_render_zone "$id")" &&
       $(< "$KW_CACHE_SNIPPET") == "$(kw_cache_render_snippet "$id")" ]] &&
      kw_cache_map_ready || return 2
    KW_CACHE_STATE=on
  fi
}

kw_cache_status() {
  local domain
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_cache_state "$domain" || return 2
  printf 'FastCGI cache %s: %s\n' "$domain" "$KW_CACHE_STATE"
  if [[ -d $KW_CACHE_DIR && ! -L $KW_CACHE_DIR ]]; then
    du -shx -- "$KW_CACHE_DIR" || return 1
  fi
  printf 'Chỉ cache phản hồi PHP 200 của GET/HEAD ẩn danh, không cookie/auth/query; Nginx vẫn tôn trọng Set-Cookie và Cache-Control.\n'
  printf 'Không áp dụng cho Redis hoặc cache ứng dụng bên trong source.\n'
}

kw_cache_enable_locked() (
  local domain=$1 id backup vhost_tmp='' zone_tmp='' snippet_tmp='' map_tmp='' made_cache_root=0 made_parent=0 made_dir=0 made_snipdir=0 made_zone=0 made_snippet=0 made_map=0 swapped=0 committed=0
  kw_nginx_ready || return 2
  kw_cache_state "$domain" || return 2
  [[ $KW_CACHE_STATE == off ]] || { printf 'FastCGI cache đã bật.\n'; return 0; }
  id=${KW_SITE_OWNER#kw}
  [[ ! -e $KW_CACHE_ZONE && ! -L $KW_CACHE_ZONE &&
     ! -e $KW_CACHE_SNIPPET && ! -L $KW_CACHE_SNIPPET ]] || return 2
  if [[ -e $KW_CACHE_MAP || -L $KW_CACHE_MAP ]]; then
    kw_cache_map_ready || return 2
  fi
  nginx -t >/dev/null 2>&1 || return 2
  kw_nginx_backup_file "$KW_SITE_VHOST" "cache-$id" || return 1
  backup=$KW_NGINX_BACKUP
  trap 'if ((committed == 0)); then if ((swapped)); then cp -p -- "$backup" "$KW_SITE_VHOST"; fi; if ((made_zone)); then rm -f -- "$KW_CACHE_ZONE"; fi; if ((made_snippet)); then rm -f -- "$KW_CACHE_SNIPPET"; fi; if ((made_map)); then rm -f -- "$KW_CACHE_MAP"; fi; if ((swapped || made_zone || made_snippet || made_map)); then kw_nginx_test_restart || kw_log ERROR "Cần phục hồi Nginx bằng $backup"; fi; if ((made_dir)); then rmdir -- "$KW_CACHE_DIR" 2>/dev/null || true; fi; if ((made_parent)); then rmdir -- /var/cache/nginx/kwvps 2>/dev/null || true; fi; if ((made_cache_root)); then rmdir -- /var/cache/nginx 2>/dev/null || true; fi; if ((made_snipdir)); then rmdir -- /etc/nginx/kwvps-cache 2>/dev/null || true; fi; fi; [[ -z $vhost_tmp ]] || rm -f -- "$vhost_tmp"; [[ -z $zone_tmp ]] || rm -f -- "$zone_tmp"; [[ -z $snippet_tmp ]] || rm -f -- "$snippet_tmp"; [[ -z $map_tmp ]] || rm -f -- "$map_tmp"' EXIT
  if [[ ! -e /var/cache/nginx && ! -L /var/cache/nginx ]]; then
    install -d -m 0755 -o root -g root /var/cache/nginx || return 1
    # shellcheck disable=SC2034 # Read by EXIT rollback trap.
    made_cache_root=1
  fi
  [[ -d /var/cache/nginx && ! -L /var/cache/nginx &&
     $(stat -c %u -- /var/cache/nginx) == 0 ]] || return 2
  if [[ ! -e /var/cache/nginx/kwvps && ! -L /var/cache/nginx/kwvps ]]; then
    install -d -m 0755 -o root -g root /var/cache/nginx/kwvps || return 1
    # shellcheck disable=SC2034 # Read by EXIT rollback trap.
    made_parent=1
  fi
  [[ -d /var/cache/nginx/kwvps && ! -L /var/cache/nginx/kwvps &&
     $(stat -c %u -- /var/cache/nginx/kwvps) == 0 ]] || return 2
  if [[ ! -e $KW_CACHE_DIR && ! -L $KW_CACHE_DIR ]]; then
    install -d -m 0700 -o www-data -g www-data -- "$KW_CACHE_DIR" || return 1
    # shellcheck disable=SC2034 # Read by EXIT rollback trap.
    made_dir=1
  fi
  [[ $(stat -c %U -- "$KW_CACHE_DIR") == www-data ]] || return 2
  if [[ ! -e /etc/nginx/kwvps-cache && ! -L /etc/nginx/kwvps-cache ]]; then
    install -d -m 0755 -o root -g root /etc/nginx/kwvps-cache || return 1
    # shellcheck disable=SC2034 # Read by EXIT rollback trap.
    made_snipdir=1
  fi
  [[ -d /etc/nginx/kwvps-cache && ! -L /etc/nginx/kwvps-cache &&
     $(stat -c %u -- /etc/nginx/kwvps-cache) == 0 ]] || return 2
  zone_tmp=$(mktemp /etc/nginx/conf.d/.kwvps-fcgi.XXXXXXXX) || return 1
  snippet_tmp=$(mktemp /etc/nginx/kwvps-cache/.kwvps-fcgi.XXXXXXXX) || return 1
  vhost_tmp=$(mktemp /etc/nginx/sites-available/.kwvps-fcgi.XXXXXXXX) || return 1
  if [[ ! -e $KW_CACHE_MAP && ! -L $KW_CACHE_MAP ]]; then
    map_tmp=$(mktemp /etc/nginx/conf.d/.kwvps-fcgi-map.XXXXXXXX) || return 1
    kw_cache_render_map > "$map_tmp" || return 1
    chmod 0644 -- "$map_tmp" || return 1
    mv -T -- "$map_tmp" "$KW_CACHE_MAP" || return 1
    map_tmp=''
    # shellcheck disable=SC2034 # Read by EXIT rollback trap.
    made_map=1
  fi
  kw_cache_render_zone "$id" > "$zone_tmp" || return 1
  kw_cache_render_snippet "$id" > "$snippet_tmp" || return 1
  kw_cache_render_vhost "$domain" "$id" "$KW_SITE_VHOST" > "$vhost_tmp" || return 1
  chmod 0644 -- "$zone_tmp" "$snippet_tmp" "$vhost_tmp" || return 1
  mv -T -- "$zone_tmp" "$KW_CACHE_ZONE" || return 1
  zone_tmp=''
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  made_zone=1
  mv -T -- "$snippet_tmp" "$KW_CACHE_SNIPPET" || return 1
  snippet_tmp=''
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  made_snippet=1
  mv -T -- "$vhost_tmp" "$KW_SITE_VHOST" || return 1
  vhost_tmp=''
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  swapped=1
  kw_nginx_test_restart || return 1
  kw_cache_state "$domain" && [[ $KW_CACHE_STATE == on ]] || return 1
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  committed=1
  printf 'Đã bật FastCGI cache cho %s; backup vhost: %s\n' "$domain" "$backup"
)

kw_cache_enable() (
  local domain=${1,,} confirm=${2:-}
  kw_domain_valid "$domain" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-nginx.lock || return 2
  flock -n 9 || return 1
  kw_cache_enable_locked "$domain"
)

kw_cache_clear_locked() (
  local domain=$1 id file count=0
  kw_nginx_ready || return 2
  kw_cache_state "$domain" || return 2
  [[ -d $KW_CACHE_DIR && ! -L $KW_CACHE_DIR ]] || {
    printf 'Không có file FastCGI cache cho %s.\n' "$domain"; return 0;
  }
  id=${KW_SITE_OWNER#kw}
  [[ $KW_CACHE_DIR == "/var/cache/nginx/kwvps/$id" &&
     -d $KW_CACHE_DIR && ! -L $KW_CACHE_DIR &&
     $(stat -c %U -- "$KW_CACHE_DIR") == www-data ]] || return 2
  while IFS= read -r -d '' file; do
    [[ $file == "$KW_CACHE_DIR"/* && -f $file && ! -L $file ]] || return 2
    rm -- "$file" || return 1
    count=$((count + 1))
  done < <(find "$KW_CACHE_DIR" -xdev -type f -print0)
  printf 'Đã xóa %d file FastCGI cache của %s. Không đụng Redis hoặc source.\n' "$count" "$domain"
)

kw_cache_clear() (
  local domain=${1,,} confirm=${2:-}
  kw_domain_valid "$domain" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-nginx.lock || return 2
  flock -n 9 || return 1
  kw_cache_clear_locked "$domain"
)

kw_cache_clear_interactive() {
  local domain
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_cache_state "$domain" || return 2
  [[ -d $KW_CACHE_DIR && ! -L $KW_CACHE_DIR ]] || {
    printf 'Không có file FastCGI cache cho %s.\n' "$domain"; return 0;
  }
  kw_prompt_yes_no_token "Xóa file FastCGI cache của $domain?" "$domain" || return 0
  kw_cache_clear "$domain" "$KW_PROMPT_VALUE"
}

kw_cache_disable_locked() (
  local domain=$1 id backup temp='' swapped=0 removed_zone=0 removed_snippet=0 committed=0
  kw_nginx_ready || return 2
  kw_cache_state "$domain" || return 2
  [[ $KW_CACHE_STATE == on ]] || { printf 'FastCGI cache đã tắt.\n'; return 0; }
  id=${KW_SITE_OWNER#kw}
  [[ $(stat -c %u -- "$KW_CACHE_ZONE" "$KW_CACHE_SNIPPET") == $'0\n0' ]] || return 2
  kw_nginx_backup_file "$KW_SITE_VHOST" "cache-off-$id" || return 1
  backup=$KW_NGINX_BACKUP
  temp=$(mktemp /etc/nginx/sites-available/.kwvps-cache-off.XXXXXXXX) || return 1
  trap 'if ((committed == 0)); then if ((swapped)); then cp -p -- "$backup" "$KW_SITE_VHOST"; fi; if ((removed_zone)); then kw_cache_render_zone "$id" > "$KW_CACHE_ZONE"; chmod 0644 -- "$KW_CACHE_ZONE"; fi; if ((removed_snippet)); then kw_cache_render_snippet "$id" > "$KW_CACHE_SNIPPET"; chmod 0644 -- "$KW_CACHE_SNIPPET"; fi; if ((swapped || removed_zone || removed_snippet)); then kw_nginx_test_restart || kw_log ERROR "Cần phục hồi Nginx bằng $backup"; fi; fi; [[ -z $temp ]] || rm -f -- "$temp"' EXIT
  kw_cache_base_vhost "$domain" "$id" "$KW_SITE_VHOST" > "$temp" || return 1
  chmod 0644 -- "$temp" || return 1
  mv -T -- "$temp" "$KW_SITE_VHOST" || return 1
  temp=''
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  swapped=1
  rm -- "$KW_CACHE_SNIPPET" || return 1
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  removed_snippet=1
  rm -- "$KW_CACHE_ZONE" || return 1
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  removed_zone=1
  kw_nginx_test_restart || return 1
  # Retain cache files for explicit clear; do not silently delete data.
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  committed=1
  printf 'Đã tắt FastCGI cache của %s; file cache còn tại %s. Backup vhost: %s\n' \
    "$domain" "$KW_CACHE_DIR" "$backup"
)

kw_cache_disable() (
  local domain=${1,,} confirm=${2:-}
  kw_domain_valid "$domain" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-nginx.lock || return 2
  flock -n 9 || return 1
  kw_cache_disable_locked "$domain"
)

kw_cache_manage_interactive() {
  local domain choice
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_cache_state "$domain" || return 2
  printf 'FastCGI cache %s: %s\n' "$domain" "$KW_CACHE_STATE"
  if [[ $KW_CACHE_STATE == off ]]; then
    printf '1. Bật FastCGI cache\n0. Quay lại\nChọn: '
    IFS= read -r choice || return 0
    [[ $choice == 1 ]] || return 0
    kw_prompt_yes_no_token "Bật FastCGI cache cho $domain?" "$domain" || return 0
    kw_cache_enable "$domain" "$KW_PROMPT_VALUE"
  else
    printf '1. Tắt FastCGI cache\n2. Xóa file cache domain\n0. Quay lại\nChọn: '
    IFS= read -r choice || return 0
    case "$choice" in
      1)
        kw_prompt_yes_no_token "Tắt FastCGI cache của $domain?" "$domain" || return 0
        kw_cache_disable "$domain" "$KW_PROMPT_VALUE" ;;
      2)
        kw_prompt_yes_no_token "Xóa file FastCGI cache của $domain?" "$domain" || return 0
        kw_cache_clear "$domain" "$KW_PROMPT_VALUE" ;;
      *) return 0 ;;
    esac
  fi
}
