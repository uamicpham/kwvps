#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/nginx.sh
}

@test "baseline is a fixed Nginx HTTP context snippet" {
  run kw_nginx_render_baseline
  [ "$status" -eq 0 ]
  [[ "$output" == *'server_tokens off;'* ]]
  [[ "$output" == *'client_max_body_size 32m;'* ]]
  [[ "$output" != *'include'* ]]
}

@test "Nginx changes require exact confirmation before filesystem access" {
  run kw_nginx_restore example.com wrong.example.com
  [ "$status" -eq 2 ]
  run kw_nginx_baseline wrong
  [ "$status" -eq 2 ]
  run kw_nginx_vhost_custom example.com wrong
  [ "$status" -eq 2 ]
}

@test "custom vhost keeps KwVPS site identity" {
  KW_SITE_PUBLIC=/var/www/kwvps/examplecom/public
  KW_SITE_SOCKET=/run/php/kwvps-examplecom.sock
  file="$BATS_TEST_TMPDIR/vhost.conf"
  printf '%s\n' '# Managed by KwVPS. Site ID: examplecom' \
    'server {' 'server_name example.com;' \
    'root /var/www/kwvps/examplecom/public;' \
    'fastcgi_pass unix:/run/php/kwvps-examplecom.sock;' '}' > "$file"
  run kw_nginx_vhost_identity "$file" example.com examplecom
  [ "$status" -eq 0 ]
  printf '%s\n' 'server_name other.example.com;' >> "$file"
  run kw_nginx_vhost_identity "$file" example.com examplecom
  [ "$status" -eq 1 ]
}

@test "Nginx apply tests config, restarts, then checks active state" {
  nginx() { printf 'test\n' >> "$BATS_TEST_TMPDIR/events"; }
  systemctl() { printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/events"; }
  run kw_nginx_test_restart
  [ "$status" -eq 0 ]
  [ "$(< "$BATS_TEST_TMPDIR/events")" = $'test\nrestart nginx\nis-active --quiet nginx' ]
}

@test "Nginx apply never restarts after failed syntax check" {
  nginx() { printf 'test\n' >> "$BATS_TEST_TMPDIR/events"; return 1; }
  systemctl() { printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/events"; }
  run kw_nginx_test_restart
  [ "$status" -eq 1 ]
  [ "$(< "$BATS_TEST_TMPDIR/events")" = test ]
}

@test "Nginx apply fails if restart does not leave service active" {
  nginx() { printf 'test\n' >> "$BATS_TEST_TMPDIR/events"; }
  systemctl() {
    printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/events"
    [[ $1 != is-active ]]
  }
  run kw_nginx_test_restart
  [ "$status" -eq 1 ]
  [ "$(< "$BATS_TEST_TMPDIR/events")" = $'test\nrestart nginx\nis-active --quiet nginx' ]
}
