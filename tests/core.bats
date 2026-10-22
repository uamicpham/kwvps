#!/usr/bin/env bats
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/system.sh
}

@test "help works without Linux or root" {
  run bash kwvps --help
  [ "$status" -eq 0 ]
  [[ "$output" == *'--preview'* ]]
}

@test "port and domain reject shell injection" {
  run kw_port_valid '22; id'
  [ "$status" -ne 0 ]
  run kw_domain_valid 'example.com;id'
  [ "$status" -ne 0 ]
}

@test "os release is data and not shell code" {
  printf 'ID="$(touch %s/pwned)"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/os-release"
  run kw_os_field ID "$BATS_TEST_TMPDIR/os-release"
  [ "$status" -eq 0 ]
  [[ "$output" == '$('* ]]
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}

@test "memory uses MemAvailable and zero swap" {
  printf 'MemTotal: 8192 kB\nMemAvailable: 3072 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' > "$BATS_TEST_TMPDIR/mem"
  run kw_memory "$BATS_TEST_TMPDIR/mem"
  [ "$output" = '5/8 MB | Swap: 0/0 MB' ]
}

@test "preview navigates submenu and exits cleanly" {
  run bash -c 'printf "1\n0\n0\n" | bash kwvps --preview'
  [ "$status" -eq 0 ]
  [[ "$output" == *'Nhân bản site'* ]]
}

@test "preview accepts quick menu path 1.4" {
  run bash -c 'printf "1.4\n\n0\n" | bash kwvps --preview'
  [ "$status" -eq 0 ]
  [[ "$output" == *'PREVIEW: không thực thi truy vấn quản trị.'* ]]
}

@test "yes/no confirmation declines by default and returns the required API token on yes" {
  run kw_prompt_yes_no_token 'Apply?' example.com <<< ''
  [ "$status" -eq 1 ]
  result=$(kw_prompt_yes_no_token 'Apply?' example.com <<< 'y' && printf '%s' "$KW_PROMPT_VALUE")
  [[ "$result" == *'example.com' ]]
}

@test "full portable smoke suite" {
  run bash tests/smoke.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *'PASS:'* ]]
}
