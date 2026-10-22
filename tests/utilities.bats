#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/utilities.sh
  source src/menu.sh
}

@test "phpMyAdmin menu has all three actions and no pending placeholder" {
  run kw_catalog utilities
  [ "$status" -eq 0 ]
  [[ "$output" == *'Cài/kiểm tra quyền phpMyAdmin|pma-permissions'* ]]
  [[ "$output" == *'phpMyAdmin theo site|pma-site'* ]]
  [[ "$output" == *'phpMyAdmin admin tất cả DB|pma-admin'* ]]
}

@test "phpMyAdmin is rendered loopback only with an isolated pool" {
  run kw_pma_render_nginx
  [ "$status" -eq 0 ]
  [[ "$output" == *'listen 127.0.0.1:9080;'* ]]
  [[ "$output" != *'listen 0.0.0.0:9080;'* ]]
  run kw_pma_render_pool
  [ "$status" -eq 0 ]
  [[ "$output" == *'[kwvps-phpmyadmin]'* ]]
  [[ "$output" == *'clear_env = yes'* ]]
  run kw_pma_render_security
  [ "$status" -eq 0 ]
  [[ "$output" == *"['AllowRoot'] = false;"* ]]
  [[ "$output" == *"['AllowNoPassword'] = false;"* ]]
}

@test "phpMyAdmin install and admin writes reject missing confirmation" {
  run kw_pma_install wrong
  [ "$status" -eq 2 ]
  run kw_pma_admin_set_password ValidPassword123 create wrong
  [ "$status" -eq 2 ]
}
