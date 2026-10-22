#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/system.sh
  source src/menu.sh
}

@test "Logs menu exposes cleanup and dispatches its action" {
  run kw_catalog logs
  [ "$status" -eq 0 ]
  [[ "$output" == *'Dọn toàn bộ log|logs-cleanup'* ]]

  kw_logs_cleanup_interactive() { printf 'CLEANUP_CALLED\n'; }
  run kw_action logs-cleanup
  [ "$status" -eq 0 ]
  [ "$output" = 'CLEANUP_CALLED' ]
}

@test "cleanup menu maps choices to web, journal and all without applying on no" {
  kw_logs_cleanup_plan() { printf 'PLAN:%s\n' "$1"; }
  kw_logs_cleanup_apply() { printf 'UNEXPECTED_APPLY:%s\n' "$1"; }

  run kw_logs_cleanup_interactive <<< $'1\nn'
  [ "$status" -eq 0 ]
  [[ "$output" == *'PLAN:web'* ]]
  [[ "$output" != *'UNEXPECTED_APPLY'* ]]

  run kw_logs_cleanup_interactive <<< $'2\nn'
  [ "$status" -eq 0 ]
  [[ "$output" == *'PLAN:journal'* ]]
  [[ "$output" != *'UNEXPECTED_APPLY'* ]]

  run kw_logs_cleanup_interactive <<< $'3\nn'
  [ "$status" -eq 0 ]
  [[ "$output" == *'PLAN:all'* ]]
  [[ "$output" != *'UNEXPECTED_APPLY'* ]]
}

@test "cleanup menu returns on zero or default no, and yes passes the scoped token" {
  kw_logs_cleanup_plan() { printf 'PLAN:%s\n' "$1"; }
  kw_logs_cleanup_apply() {
    printf 'APPLIED:%s:%s\n' "$1" "$2"
    printf 'Đã dọn thư mục: /var/log/nginx\n'
  }

  run kw_logs_cleanup_interactive <<< '0'
  [ "$status" -eq 0 ]
  [[ "$output" != *'PLAN:'* ]]
  [[ "$output" != *'APPLIED:'* ]]

  run kw_logs_cleanup_interactive <<< $'3\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *'PLAN:all'* ]]
  [[ "$output" != *'APPLIED:'* ]]

  run kw_logs_cleanup_interactive <<< $'3\ny'
  [ "$status" -eq 0 ]
  [[ "$output" == *'APPLIED:all:CLEAN-LOGS:all'* ]]
  [[ "$output" == *'Đã dọn thư mục: /var/log/nginx'* ]]
}

@test "cleanup never applies when planning fails or selection is invalid" {
  kw_logs_cleanup_plan() { printf 'PREFLIGHT_FAILED:%s\n' "$1"; return 2; }
  kw_logs_cleanup_apply() { printf 'UNEXPECTED_APPLY\n'; }

  run kw_logs_cleanup_interactive <<< '9'
  [ "$status" -eq 0 ]
  [[ "$output" != *'PREFLIGHT_FAILED'* ]]
  [[ "$output" != *'UNEXPECTED_APPLY'* ]]

  run kw_logs_cleanup_interactive <<< $'3\ny'
  [ "$status" -eq 2 ]
  [[ "$output" == *'PREFLIGHT_FAILED:all'* ]]
  [[ "$output" != *'UNEXPECTED_APPLY'* ]]
}

@test "cleanup apply rejects invalid scope and token before system access" {
  kw_logs_web_scan() { printf 'UNEXPECTED_SCAN\n'; return 99; }
  journalctl() { printf 'UNEXPECTED_JOURNAL\n'; return 99; }
  run kw_logs_cleanup_apply all WRONG
  [ "$status" -eq 2 ]
  [[ "$output" != *'UNEXPECTED_'* ]]
  run kw_logs_cleanup_apply unexpected CLEAN-LOGS:unexpected
  [ "$status" -eq 2 ]
  [[ "$output" != *'UNEXPECTED_'* ]]

  run kw_logs_cleanup_plan unexpected
  [ "$status" -eq 2 ]
  [[ "$output" != *'UNEXPECTED_'* ]]
}

@test "cleanup plan separates KwVPS web logs from system-wide journal" {
  kw_logs_web_scan() {
    KW_LOG_FILES=(/var/log/nginx/kwvps-examplecom.access.log)
    KW_LOG_BYTES=42
    KW_LOG_NGINX_COUNT=1
    KW_LOG_NGINX_BYTES=42
    KW_LOG_PHP_COUNT=0
    KW_LOG_PHP_BYTES=0
  }
  journalctl() { printf 'Archived and active journals take up 8.0M.\n'; }
  command() {
    if [[ ${1:-} == -v && ${2:-} == journalctl ]]; then return 0; fi
    builtin command "$@"
  }

  run kw_logs_cleanup_plan web
  [ "$status" -eq 0 ]
  [[ "$output" == *'/var/log/nginx: 1 file site KwVPS, 42 byte'* ]]
  [[ "$output" == *'/var/log: 0 file PHP-FPM, 0 byte'* ]]
  [[ "$output" == *'Không đụng access.log/error.log Nginx dùng chung'* ]]
  [[ "$output" != *'TOÀN VPS'* ]]

  run kw_logs_cleanup_plan journal
  [ "$status" -eq 0 ]
  [[ "$output" == *'systemd journal TOÀN VPS'* ]]
  [[ "$output" != *'/var/log/nginx: 1 file site KwVPS'* ]]
  [[ "$output" != *'/var/log: 0 file PHP-FPM'* ]]

  run kw_logs_cleanup_plan all
  [ "$status" -eq 0 ]
  [[ "$output" == *'/var/log/nginx: 1 file site KwVPS'* ]]
  [[ "$output" == *'/var/log: 0 file PHP-FPM'* ]]
  [[ "$output" == *'systemd journal TOÀN VPS'* ]]
  [[ "$output" == *'Không thể phục hồi log đã dọn'* ]]
}
