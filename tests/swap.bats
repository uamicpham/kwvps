#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/swap.sh
}

@test "swap size stays within explicit limits" {
  run kw_swap_size_valid 128
  [ "$status" -eq 0 ]
  run kw_swap_size_valid 8192
  [ "$status" -eq 0 ]
  run kw_swap_size_valid 127
  [ "$status" -eq 1 ]
  run kw_swap_size_valid 8193
  [ "$status" -eq 1 ]
  run kw_swap_size_valid '256;id'
  [ "$status" -eq 1 ]
}

@test "swap mutation requires exact confirmation before any write" {
  run kw_swap_change add 256 wrong
  [ "$status" -eq 2 ]
  run kw_swap_change remove '' wrong
  [ "$status" -eq 2 ]
}
