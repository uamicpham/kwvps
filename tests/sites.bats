#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/sites.sh
  source src/php.sh
}

@test "Nginx conflict checks server_name, not substrings in subdomains or certificate paths" {
  run kw_nginx_server_name_taken kenhgamez.top <<< $'server_name kwvps.kenhgamez.top;\nssl_certificate /etc/letsencrypt/live/kwvps.kenhgamez.top/fullchain.pem;'
  [ "$status" -eq 1 ]
  run kw_nginx_server_name_taken kenhgamez.top <<< 'server_name kenhgamez.top;'
  [ "$status" -eq 0 ]
  run kw_nginx_server_name_taken kenhgamez.top <<< 'server_name www.kenhgamez.top kenhgamez.top;'
  [ "$status" -eq 0 ]
  run kw_nginx_server_name_taken kenhgamez.top <<< 'server_name kwvps.kenhgamez.top; root /var/www/kenhgamez.top;'
  [ "$status" -eq 1 ]
  run kw_nginx_server_name_taken kenhgamez.top <<< 'server_name kwvps.kenhgamez.top; server_name kenhgamez.top;'
  [ "$status" -eq 0 ]
  run kw_nginx_server_name_taken kenhgamez.top <<< 'server { listen 80; server_name "KENHGAMEZ.TOP"; }'
  [ "$status" -eq 0 ]
  run kw_nginx_server_name_taken kenhgamez.top <<< $'server_name\n  kwvps.kenhgamez.top\n  kenhgamez.top;'
  [ "$status" -eq 0 ]
  run kw_nginx_server_name_taken foo.example.com <<< 'server_name *.example.com;'
  [ "$status" -eq 0 ]
  run kw_nginx_server_name_taken example.com <<< 'server_name *.example.com;'
  [ "$status" -eq 1 ]
  run kw_nginx_server_name_taken foo.example.com <<< 'server_name .example.com;'
  [ "$status" -eq 0 ]
  run kw_nginx_server_name_taken example.com <<< 'server_name .example.com;'
  [ "$status" -eq 0 ]
  run kw_nginx_server_name_taken xfoo.example.com <<< 'server_name .foo.example.com;'
  [ "$status" -eq 1 ]
  run kw_nginx_server_name_taken mail.example.com <<< 'server_name mail.*;'
  [ "$status" -eq 0 ]
  run kw_nginx_server_name_taken mailer.example.com <<< 'server_name mail.*;'
  [ "$status" -eq 1 ]
  run kw_nginx_server_name_taken kenhgamez.top <<< '# server_name kenhgamez.top;'
  [ "$status" -eq 1 ]
  run kw_nginx_server_name_taken example.com <<< 'server_name ~^example[.]com$;'
  [ "$status" -eq 2 ]
}

@test "site ID is stable for a domain regardless of letter case" {
  lower=$(kw_site_id example.com)
  upper=$(kw_site_id EXAMPLE.COM)
  [ "$lower" = "$upper" ]
  [ "$lower" = examplecom ]
  kw_site_id_matches_domain kwvpskenhgameztop kwvps.kenhgamez.top
  [ "$(kw_site_id a-b.example.com)" = abexamplecom ]
  ! kw_site_id_valid 'a.b'
}

@test "site ID rejects a normalized domain longer than a Linux owner name permits" {
  run kw_site_id longlonglonglonglonglonglonglong.example.com
  [ "$status" -eq 2 ]
}

@test "site plan canonicalizes the domain and shows isolated paths" {
  id=$(kw_site_id example.com)
  run kw_site_plan EXAMPLE.COM 8.3
  [ "$status" -eq 0 ]
  [[ "$output" == *'Domain: example.com'* ]]
  [[ "$output" == *"Site ID: $id"* ]]
  [[ "$output" == *"User: kw$id"* ]]
  [[ "$output" == *"Pool: /etc/php/8.3/fpm/pool.d/kwvps-$id.conf"* ]]
  [[ "$output" == *"Vhost: /etc/nginx/sites-available/kwvps-$id.conf"* ]]
  [[ "$output" == *'Chế độ kết nối: DNS thông thường mặc định'* ]]
}

@test "site plan rejects unsafe domain and PHP version" {
  run kw_site_plan 'example.com;id' 8.3
  [ "$status" -eq 2 ]
  [[ "$output" != *'Kế hoạch thêm site'* ]]
  run kw_site_plan example.com '8.3;id'
  [ "$status" -eq 2 ]
  [[ "$output" != *'Kế hoạch thêm site'* ]]
}

@test "adding a site retries an invalid domain without leaving the form" {
  kw_site_find_retired() { KW_RETIRED_MATCHES=(); }
  kw_php_choose_version() { KW_PHP_CHOICE=8.3; }
  kw_site_create() { printf 'CREATED:%s:%s\n' "$1" "$2"; }
  run kw_site_add_interactive <<< $'bad domain\nexample.com\ny'
  [ "$status" -eq 0 ]
  [[ "$output" == *'Giá trị không hợp lệ: Domain'* ]]
  [[ "$output" == *'CREATED:example.com:8.3'* ]]
}

@test "adding a retained domain offers restoration by number" {
  kw_site_new_domain_valid() { kw_domain_valid "$1"; }
  kw_site_find_retired() { KW_RETIRED_MATCHES=(examplecom-20261021T010203Z-abcdef12); }
  kw_site_retired_plan() { printf 'PLAN:%s\n' "$1"; }
  kw_site_retired_restore() { printf 'RESTORED:%s:%s\n' "$1" "$2"; }
  run kw_site_add_interactive <<< $'example.com\n1\ny'
  [ "$status" -eq 0 ]
  [[ "$output" == *'Site example.com đang trong vùng giữ'* ]]
  [[ "$output" == *'1. Phục hồi site đang giữ example.com'* ]]
  [[ "$output" == *'RESTORED:example.com:examplecom-20261021T010203Z-abcdef12'* ]]
}

@test "adding a retained domain offers purge then new site with domain confirmation" {
  kw_site_new_domain_valid() { kw_domain_valid "$1"; }
  kw_site_find_retired() { KW_RETIRED_MATCHES=(examplecom-20261021T010203Z-abcdef12); }
  kw_php_choose_version() { KW_PHP_CHOICE=8.3; }
  kw_site_replace_retired() { printf 'REPLACED:%s:%s:%s\n' "$1" "$2" "$3"; }
  run kw_site_add_interactive <<< $'example.com\n2\nexample.com'
  [ "$status" -eq 0 ]
  [[ "$output" == *'2. Xóa site đang giữ và thêm mới example.com'* ]]
  [[ "$output" == *'REPLACED:example.com:8.3:example.com'* ]]
}

@test "supported PHP choices and pool limits reject unsafe values" {
  for version in 8.5 8.4 8.3 7.4; do kw_php_version_supported "$version"; done
  ! kw_php_version_supported '8.3;id'
  kw_php_pool_value_valid pm.max_children 128
  ! kw_php_pool_value_valid pm.max_children 129
  kw_php_pool_value_valid pm.max_requests 10000
  ! kw_php_pool_value_valid pm.max_requests 10001
  run kw_php_switch example.com 8.4 wrong.example.com
  [ "$status" -eq 2 ]
}

@test "custom pool guard detects a changed socket identity" {
  id=$(kw_site_id example.com)
  original="$BATS_TEST_TMPDIR/original.conf"
  changed="$BATS_TEST_TMPDIR/changed.conf"
  kw_site_render_pool "$id" "kw$id" > "$original"
  cp "$original" "$changed"
  before=$(kw_php_pool_identity "$original")
  [ -n "$before" ]
  sed -i 's@listen = /run/php/@listen = /tmp/@' "$changed"
  after=$(kw_php_pool_identity "$changed")
  [ "$before" != "$after" ]
}

@test "PHP pool runs as isolated site user with private socket" {
  id=$(kw_site_id example.com)
  output=$(kw_site_render_pool "$id" "kw$id")
  [[ "$output" == *"[kwvps-$id]"* ]]
  [[ "$output" == *"user = kw$id"* ]]
  [[ "$output" == *"listen = /run/php/kwvps-$id.sock"* ]]
  [[ "$output" == *'clear_env = yes'* ]]
  [[ "$output" == *'security.limit_extensions = .php'* ]]
}

@test "Nginx vhost routes to matching pool and blocks dotfiles before PHP" {
  id=$(kw_site_id example.com)
  output=$(kw_site_render_vhost example.com "$id")
  [[ "$output" == *'server_name example.com;'* ]]
  [[ "$output" == *"root /var/www/kwvps/$id/public;"* ]]
  [[ "$output" == *"fastcgi_pass unix:/run/php/kwvps-$id.sock;"* ]]
  [[ "$output" == *'try_files $uri $uri/ /index.php?$args;'* ]]
  dot_line=$(printf '%s\n' "$output" | grep -n 'deny all;' | head -n 1)
  php_line=$(printf '%s\n' "$output" | grep -n 'fastcgi_pass' | head -n 1)
  [ "${dot_line%%:*}" -lt "${php_line%%:*}" ]
}

@test "PHP pool view reports site-specific version and socket" {
  kw_site_lookup() {
    KW_SITE_PHP=8.3
    KW_SITE_POOL="$BATS_TEST_TMPDIR/pool.conf"
    KW_SITE_SOCKET=/run/php/kwvps-123456789abc.sock
  }
  kw_service_status() { printf 'ActiveState=active\n'; }
  printf '[kwvps-123456789abc]\npm.max_children = 5\n' > "$BATS_TEST_TMPDIR/pool.conf"
  run kw_site_php_pool_info example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *'PHP-FPM: 8.3'* ]]
  [[ "$output" == *'pm.max_children = 5'* ]]
  [[ "$output" == *'kwvps-123456789abc.sock'* ]]
}

@test "site removal requires exact domain confirmation" {
  run kw_site_remove example.com wrong.example.com
  [ "$status" -eq 2 ]
  [[ "$output" == *'Xác nhận domain không khớp'* ]]
}

@test "site removal mode rejects unknown values before accessing system" {
  run kw_site_remove example.com example.com invalid
  [ "$status" -eq 2 ]
}

@test "purge requires exact domain confirmation before filesystem access" {
  run kw_site_purge example.com examplecom-20261021T010203Z-abcdef12 wrong.example.com
  [ "$status" -eq 2 ]
}

@test "site removal plan says data is retained" {
  kw_site_lookup() {
    KW_SITE_PHP=8.3
    KW_SITE_ROOT=/var/www/kwvps/123456789abc
  }
  run kw_site_remove_plan example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *'Xóa site và GIỮ vùng phục hồi'* ]]
  [[ "$output" == *'Xóa SẠCH site, KHÔNG giữ vùng phục hồi'* ]]
  [[ "$output" == *'DB, user DB, log và chứng chỉ KHÔNG bị xóa ngầm'* ]]
}

@test "clone prompt lists source by number, retries destination and accepts default Y" {
  kw_site_prompt_domain() { printf '1. example.com\n0. Quay lại\n'; KW_SITE_CHOICE=example.com; }
  kw_site_new_domain_valid() { kw_domain_valid "$1"; }
  kw_site_lookup() { KW_SITE_PHP=8.3; }
  kw_site_clone() { printf 'CLONED:%s:%s:%s\n' "$1" "$2" "$3"; }
  run kw_site_clone_interactive <<< $'0bad\ndestination.example\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *'Quản lý Sites / Nhân bản site / Chọn site nguồn'* ]]
  [[ "$output" == *'Domain không hợp lệ'* ]]
  [[ "$output" == *'CLONED:example.com:destination.example:yes'* ]]
}

@test "clone cancellation never creates a destination" {
  kw_site_prompt_domain() { KW_SITE_CHOICE=example.com; }
  kw_site_new_domain_valid() { kw_domain_valid "$1"; }
  kw_site_lookup() { KW_SITE_PHP=8.3; }
  kw_site_clone() { printf 'UNEXPECTED\n'; return 1; }
  run kw_site_clone_interactive <<< $'destination.example\nn'
  [ "$status" -eq 0 ]
  [[ "$output" != *'UNEXPECTED'* ]]
}

@test "permission reset requires exact domain confirmation" {
  run kw_site_permissions example.com wrong.example.com
  [ "$status" -eq 2 ]
}

@test "retired site restoration requires exact domain confirmation" {
  run kw_site_retired_restore example.com 123456789abc-20261021T010203Z-abcdef12 wrong.example.com
  [ "$status" -eq 2 ]
  [[ "$output" == *'Xác nhận domain không khớp'* ]]
}

@test "new site ownership is applied to source and root-owned config" {
  KW_SITE_OWNER=kwexamplecom
  KW_SITE_ROOT="$BATS_TEST_TMPDIR/site"
  KW_SITE_PUBLIC="$KW_SITE_ROOT/public"
  KW_SITE_POOL="$BATS_TEST_TMPDIR/pool.conf"
  KW_SITE_VHOST="$BATS_TEST_TMPDIR/vhost.conf"
  KW_SITE_META="$BATS_TEST_TMPDIR/site.meta"
  mkdir -p "$KW_SITE_PUBLIC"
  touch "$KW_SITE_PUBLIC/index.html" "$KW_SITE_POOL" "$KW_SITE_VHOST" "$KW_SITE_META"
  chown() { printf 'chown:%s\n' "$*" >> "$BATS_TEST_TMPDIR/events"; }
  chmod() { printf 'chmod:%s\n' "$*" >> "$BATS_TEST_TMPDIR/events"; }
  stat() {
    [[ $1 == -c && $2 == '%U:%G:%a' && $3 == -- ]] || return 1
    shift 3
    local file
    for file in "$@"; do
      case "$file" in
        "$KW_SITE_ROOT"|"$KW_SITE_PUBLIC") printf 'kwexamplecom:www-data:750\n' ;;
        "$KW_SITE_PUBLIC/index.html") printf 'kwexamplecom:www-data:640\n' ;;
        *) printf 'root:root:644\n' ;;
      esac
    done
  }
  run kw_site_initial_permissions
  [ "$status" -eq 0 ]
  grep -Fq 'chown:-- kwexamplecom:www-data' "$BATS_TEST_TMPDIR/events"
  grep -Fq 'chown:-- root:root' "$BATS_TEST_TMPDIR/events"
  grep -Fq 'chmod:0750 --' "$BATS_TEST_TMPDIR/events"
  grep -Fq 'chmod:0644 --' "$BATS_TEST_TMPDIR/events"
}
