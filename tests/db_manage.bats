#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/system.sh
  source src/sites.sh
  source src/backups.sh
  source src/db.sh
  source src/db_manage.sh
  source src/menu.sh
}

@test "DB menu has seven requested actions in order" {
  output=$(kw_catalog db)
  [[ "$output" == $'Danh sách DB|db-managed-list\nDanh sách User DB|db-users-list\nĐổi Pass Database (User DB)|db-password\nTạo DB|db-custom-create\nXóa DB|db-drop-named\nImport DB|db-import-upload\nExport DB|db-export-named' ]]
}

@test "custom DB identifiers and password reject SQL injection" {
  kw_db_identifier_valid kenhgamez5
  kw_db_user_valid kenhgamez_user
  kw_db_password_valid 'Safe-pass_123!'
  ! kw_db_identifier_valid 'name;DROP'
  ! kw_db_identifier_valid '1database'
  ! kw_db_user_valid 'user@host'
  ! kw_db_password_valid "abc' OR 1=1 --"
  ! kw_db_password_valid short
}

@test "uploaded SQL filenames reject traversal and other types" {
  [ "$KW_DB_UPLOAD_DIR" = "$KW_BACKUP_ROOT" ]
  kw_db_upload_valid kenhgamez5_full.sql
  kw_db_upload_valid kenhgamez5.sql.gz
  ! kw_db_upload_valid ../../etc/passwd
  ! kw_db_upload_valid bad..sql
  ! kw_db_upload_valid archive.zip
  ! kw_db_upload_valid 'a;touch.sql'
}

@test "DB and user lists contain only numbered names" {
  kw_db_ready() { return 0; }
  kw_db_managed_names() { printf 'db_one\ndb_two\n'; }
  kw_db_select_meta() { KW_DB_SELECTED_USER="user_${1#db_}"; return 0; }
  run kw_db_managed_list
  [ "$status" -eq 0 ]
  [ "$output" = $'1. db_one\n2. db_two' ]
  run kw_db_users_list
  [ "$status" -eq 0 ]
  [ "$output" = $'1. user_one\n2. user_two' ]
}

@test "DB chooser can filter by site without another import implementation" {
  kw_db_ready() { return 0; }
  kw_db_managed_names() { printf 'db_one\ndb_two\n'; }
  kw_db_select_meta() {
    if [[ $1 == db_one ]]; then KW_DB_SELECTED_DOMAIN=one.example.com
    else KW_DB_SELECTED_DOMAIN=two.example.com; fi
  }
  run kw_db_choose_managed one.example.com < <(printf '1\n')
  [ "$status" -eq 0 ]
  [[ "$output" == *'1. db_one'* ]]
  [[ "$output" != *'db_two'* ]]
}

@test "DB creation retries an invalid password without restarting site and name selection" {
  kw_site_prompt_domain() { KW_SITE_CHOICE=example.com; }
  kw_db_custom_create() { printf 'CREATED:%s:%s\n' "$2" "$3"; }
  run kw_db_custom_create_interactive <<< $'demo_db\ndemo_user\nshort\nValidPass_123!\ny'
  [ "$status" -eq 0 ]
  [[ "$output" == *'Giá trị không hợp lệ: Mật khẩu'* ]]
  [[ "$output" == *'CREATED:demo_db:demo_user'* ]]
}

@test "destructive DB APIs require confirmation before system access" {
  run kw_db_drop_named kenhgamez5 NO
  [ "$status" -eq 2 ]
  run kw_db_password_change kenhgamez5 Safe-pass_123! wrong
  [ "$status" -eq 2 ]
  run kw_db_import_uploaded kenhgamez5.sql kenhgamez5 wrong
  [ "$status" -eq 2 ]
  run kw_db_custom_create example.com kenhgamez5 kenhgamez_user Safe-pass_123! wrong
  [ "$status" -eq 2 ]
}
