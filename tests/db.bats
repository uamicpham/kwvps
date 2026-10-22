#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/sites.sh
  source src/db.sh
}

@test "database names are derived only from validated site IDs" {
  kw_db_names 123456789abc
  [ "$KW_DB_NAME" = kwdb_123456789abc ]
  [ "$KW_DB_USER" = kwu_123456789abc ]
  run kw_db_names '123456789abc;DROP DATABASE mysql'
  [ "$status" -eq 2 ]
}

@test "database SQL validates random hex password" {
  run kw_db_sql_create 123456789abc 0123456789abcdef0123456789abcdef0123456789abcdef
  [ "$status" -eq 0 ]
  [[ "$output" == *'CREATE DATABASE `kwdb_123456789abc`'* ]]
  [[ "$output" == *"'kwu_123456789abc'@'localhost'"* ]]
  run kw_db_sql_create 123456789abc "password'; DROP DATABASE mysql; --"
  [ "$status" -eq 2 ]
}

@test "database create requires exact site confirmation" {
  run kw_db_create example.com wrong.example.com
  [ "$status" -eq 2 ]
  [[ "$output" == *'Xác nhận domain không khớp'* ]]
}

@test "database export requires exact site confirmation" {
  run kw_db_export example.com wrong.example.com
  [ "$status" -eq 2 ]
  [[ "$output" == *'Xác nhận domain không khớp'* ]]
}

@test "database import rejects another site backup before writing" {
  run kw_db_import example.com db-123456789abc-20261021T010203Z-AbCd1234.sql.gz wrong.example.com
  [ "$status" -eq 2 ]
  [[ "$output" == *'Xác nhận domain không khớp'* ]]
  run kw_db_backup_name_valid '../../etc/shadow'
  [ "$status" -eq 1 ]
}

@test "database deletion requires exact site confirmation" {
  run kw_db_drop example.com wrong.example.com
  [ "$status" -eq 2 ]
  [[ "$output" == *'Xác nhận domain không khớp'* ]]
}

@test "remote database tunnel plan rejects unsafe domain and port before touching MariaDB" {
  run kw_db_remote_plan 'example.com;id' 3307
  [ "$status" -eq 2 ]
  run kw_db_remote_plan example.com '3307;id'
  [ "$status" -eq 2 ]
}
