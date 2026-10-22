#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/system.sh
}

@test "only the explicitly supported OS release passes" {
  printf 'ID=ubuntu\nVERSION_ID="24.04"\n' > "$BATS_TEST_TMPDIR/os-release"
  run kw_os_supported "$BATS_TEST_TMPDIR/os-release"
  [ "$status" -eq 0 ]

  printf 'ID=debian\nVERSION_ID="12"\nID_LIKE=ubuntu\n' > "$BATS_TEST_TMPDIR/os-release"
  run kw_os_supported "$BATS_TEST_TMPDIR/os-release"
  [ "$status" -ne 0 ]
}

@test "missing or malformed memory fields never report false zero usage" {
  printf 'MemTotal: 8192 kB\nMemAvailable: 3072 kB\n' > "$BATS_TEST_TMPDIR/mem"
  run kw_memory "$BATS_TEST_TMPDIR/mem"
  [ "$status" -eq 0 ]
  [ "$output" = '5/8 MB | Swap: N/A' ]

  printf 'MemTotal: 8192 kB\nMemAvailable: 9999 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' > "$BATS_TEST_TMPDIR/mem"
  run kw_memory "$BATS_TEST_TMPDIR/mem"
  [ "$output" = 'N/A | Swap: 0/0 MB' ]
}

@test "disk usage reads the root filesystem and rejects malformed df output" {
  kw_read_command() {
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/vda1 104857600 26214400 78643200 25%% /\n'
  }
  run kw_disk_usage /
  [ "$status" -eq 0 ]
  [ "$output" = '25.0/100.0 GB' ]

  kw_read_command() { printf 'unexpected output\n'; }
  run kw_disk_usage /
  [ "$status" -ne 0 ]
}

@test "service status permits known units and blocks injected names" {
  kw_read_command() { printf '%s\n' "$*"; }
  run kw_service_status php8.3-fpm
  [ "$status" -eq 0 ]
  [ "$output" = 'systemctl show --no-pager --property=LoadState,ActiveState,SubState php8.3-fpm.service' ]

  run kw_service_status 'nginx; id'
  [ "$status" -eq 2 ]
  [[ "$output" != *'systemctl show'* ]]
}

@test "tunnel restart refuses missing confirmation without touching service" {
  run kw_tunnel_restart wrong
  [ "$status" -eq 2 ]
}
