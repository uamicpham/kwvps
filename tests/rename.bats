#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/sites.sh
  source src/rename.sh
  source src/menu.sh
}

@test "site rename is reachable from the third Sites menu entry" {
  run kw_catalog sites
  [ "$status" -eq 0 ]
  [[ "$output" == *'Đổi tên miền|site-rename'* ]]
}

@test "site rename rejects missing confirmation and unsafe domains before filesystem access" {
  run kw_site_rename old.example.com new.example.com no
  [ "$status" -eq 2 ]
  run kw_site_rename 'old.example.com;id' new.example.com yes
  [ "$status" -eq 2 ]
  run kw_site_rename old.example.com old.example.com yes
  [ "$status" -eq 2 ]
}
