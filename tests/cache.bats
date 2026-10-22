#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/system.sh
  source src/sites.sh
  source src/cache.sh
  source src/menu.sh
}

@test "Redis restart requires exact confirmation before service access" {
  run kw_cache_redis_restart WRONG
  [ "$status" -eq 2 ]
}

@test "Redis install requires exact internal confirmation before apt access" {
  run kw_cache_redis_install WRONG
  [ "$status" -eq 2 ]
}

@test "Redis listener parser rejects non-loopback socket" {
  ss() { printf 'LISTEN 0 511 0.0.0.0:6379 0.0.0.0:*\n'; }
  run kw_cache_redis_loopback_only
  [ "$status" -eq 2 ]
}

@test "Redis listener parser accepts IPv4 and IPv6 loopback sockets" {
  ss() { printf 'LISTEN 0 511 127.0.0.1:6379 0.0.0.0:*\nLISTEN 0 511 [::1]:6379 [::]:*\n'; }
  run kw_cache_redis_loopback_only
  [ "$status" -eq 0 ]
}

@test "Redis menu reports missing package without installing or flushing" {
  kw_cache_redis_installed() { return 1; }
  run kw_cache_redis_interactive </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *'chưa cài'* ]]
  [[ "$output" != *'Restart Redis'* ]]
}

@test "FastCGI cache paths reject unsafe site IDs" {
  kw_cache_paths kwvpskenhgameztop
  [ "$KW_CACHE_DIR" = /var/cache/nginx/kwvps/kwvpskenhgameztop ]
  ! kw_cache_paths '../etc/passwd'
}

@test "FastCGI config is scoped to one site and anonymous GET or HEAD" {
  run kw_cache_render_zone kwvpskenhgameztop
  [ "$status" -eq 0 ]
  [[ "$output" == *'keys_zone=kwvps_kwvpskenhgameztop:16m'* ]]
  run kw_cache_render_map
  [ "$status" -eq 0 ]
  [[ "$output" == *'~^(GET|HEAD)'* ]]
  [[ "$output" == *'$http_cookie'* ]]
  [[ "$output" == *'$http_authorization'* ]]
}

@test "FastCGI mutations reject missing confirmation" {
  run kw_cache_enable example.com wrong
  [ "$status" -eq 2 ]
  run kw_cache_disable example.com wrong
  [ "$status" -eq 2 ]
  run kw_cache_clear example.com wrong
  [ "$status" -eq 2 ]
}

@test "cache menu separates clear, status, Redis and FastCGI controls" {
  run kw_catalog cache
  [ "$status" -eq 0 ]
  [[ "$output" == *'Xóa cache domain|cache-clear'* ]]
  [[ "$output" == *'Quản lý cache domain|cache-status'* ]]
  [[ "$output" == *'Quản lý Redis|cache-redis'* ]]
  [[ "$output" == *'Quản lý FastCGI|cache-fcgi'* ]]
}
