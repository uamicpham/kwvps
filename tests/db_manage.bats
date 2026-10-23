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

@test "DB create and change password prompts show typed characters" {
  kw_site_prompt_domain() { KW_SITE_CHOICE=example.com; }
  kw_db_choose_managed() { KW_DB_MANAGED_CHOICE=demo_db; }
  kw_db_select_meta() { KW_DB_SELECTED_USER=demo_user; }
  kw_prompt_validated() {
    if [[ $1 == Mật\ khẩu* ]]; then
      [[ $1 == *'hiển thị khi nhập'* && $4 == plain ]] || return 2
      KW_PROMPT_VALUE=ValidPass_123!
    elif [[ $1 == Tên\ database* ]]; then KW_PROMPT_VALUE=demo_db
    elif [[ $1 == Tên\ user* ]]; then KW_PROMPT_VALUE=demo_user
    else return 2; fi
  }
  kw_prompt_yes_no_token() { KW_PROMPT_VALUE=$2; }
  kw_db_custom_create() { printf 'CREATED\n'; }
  kw_db_password_change() { printf 'CHANGED\n'; }
  run kw_db_custom_create_interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *CREATED* && "$output" != *ValidPass_123!* ]]
  run kw_db_password_change_interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *CHANGED* && "$output" != *ValidPass_123!* ]]
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

@test "named DB import warns about existing tables and never auto-exports" {
  kw_db_choose_upload() { KW_DB_UPLOAD_CHOICE=existing.sql.gz; }
  kw_db_choose_managed() { KW_DB_MANAGED_CHOICE=demo_db; }
  mariadb() { printf '3\n'; }
  kw_prompt_yes_no_token() { KW_PROMPT_VALUE=$2; }
  kw_db_import_uploaded() { printf 'IMPORTED:%s:%s\n' "$1" "$2"; }
  run kw_db_import_uploaded_interactive <<< '1'
  [ "$status" -eq 0 ]
  [[ "$output" == *'đã có 3 bảng'* ]]
  [[ "$output" == *'Import không tự export hiện trạng'* ]]
  [[ "$output" == *'IMPORTED:existing.sql.gz:demo_db'* ]]
  local function_body
  function_body=$(declare -f kw_db_import_uploaded_locked)
  [[ "$function_body" != *'kw_db_export_named_locked'* ]]
  function_body=$(declare -f kw_db_export_named_locked)
  [[ "$function_body" != *'sha256sum'* ]]
}
