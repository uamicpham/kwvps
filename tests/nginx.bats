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
}
