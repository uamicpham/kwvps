#!/usr/bin/env bash
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
source src/core.sh
source src/system.sh

checks=0
check() {
  "$@" || { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
  checks=$((checks + 1))
}
reject() {
  if "$@"; then printf 'UNEXPECTED SUCCESS: %s\n' "$*" >&2; exit 1; fi
  checks=$((checks + 1))
}

check kw_os_supported <(printf 'ID=ubuntu\nVERSION_ID="24.04"\n')
reject kw_os_supported <(printf 'ID=debian\nVERSION_ID="12"\nID_LIKE=ubuntu\n')

result=$(kw_memory <(printf 'MemTotal: 8192 kB\nMemAvailable: 3072 kB\n'))
check test "$result" = '5/8 MB | Swap: N/A'
result=$(kw_memory <(printf 'MemTotal: 8192 kB\nMemAvailable: 9999 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n'))
check test "$result" = 'N/A | Swap: 0/0 MB'

check kw_service_unit php8.3-fpm
reject kw_service_unit 'nginx; id'

test_disk_fixture() (
  kw_read_command() {
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/vda1 104857600 26214400 78643200 25%% /\n'
  }
  local result
  result=$(kw_disk_usage /)
  [[ $result == '25.0/100.0 GB' ]]
)
test_bad_disk_fixture() (
  kw_read_command() { printf 'unexpected output\n'; }
  ! kw_disk_usage / >/dev/null
)
test_service_fixture() (
  kw_read_command() { printf '%s\n' "$*"; }
  local result
  result=$(kw_service_status php8.3-fpm)
  [[ $result == 'systemctl show --no-pager --property=LoadState,ActiveState,SubState php8.3-fpm.service' ]]
)
check test_disk_fixture
check test_bad_disk_fixture
check test_service_fixture

printf 'PASS: %d system checks\n' "$checks"
