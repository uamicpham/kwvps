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

@test "phpMyAdmin admin DB password prompt shows typed characters" {
  kw_pma_ready() { return 0; }
  kw_db_ready() { return 0; }
  kw_pma_admin_exists() { return 1; }
  kw_prompt_validated() {
    [[ $1 == *'hiển thị khi nhập'* && $4 == plain ]] || return 2
    KW_PROMPT_VALUE=ValidPassword123
  }
  kw_prompt_yes_no_token() { KW_PROMPT_VALUE=$2; }
  kw_pma_admin_set_password() { printf 'CREATED\n'; }
  kw_pma_tunnel_guide() { :; }
  run kw_pma_admin_interactive <<< '1'
  [ "$status" -eq 0 ]
  [[ "$output" == *CREATED* && "$output" != *ValidPassword123* ]]
}
