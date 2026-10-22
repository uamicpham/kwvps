#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/sites.sh
  source src/backups.sh
  source src/config_backups.sh
}

@test "configuration backup names are narrowly validated" {
  kw_config_backup_name_valid config-123456789abc-20261021T120000Z-Ab12Cd34.tar.gz
  ! kw_config_backup_name_valid ../../etc/shadow
  ! kw_config_backup_name_valid config-123456789abc-20261021T120000Z-Ab12Cd34.tar.gz/../x
}

@test "configuration backup requires exact domain confirmation" {
  run kw_config_backup example.com wrong.example.com
  [ "$status" -eq 2 ]
}

@test "configuration restore requires exact domain and valid archive name" {
  run kw_config_restore example.com config-123456789abc-20261021T120000Z-Ab12Cd34.tar.gz wrong.example.com
  [ "$status" -eq 2 ]
  run kw_config_restore example.com ../../etc/shadow example.com
  [ "$status" -eq 2 ]
}
