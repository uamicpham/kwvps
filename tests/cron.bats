#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/cron.sh
}

@test "root cron editor requires explicit confirmation before any writes" {
  run kw_cron_nano wrong
  [ "$status" -eq 2 ]
}

@test "cron plan states privilege and backup scope" {
  run kw_cron_nano_plan
  [ "$status" -eq 0 ]
  [[ "$output" == *'root'* ]]
  [[ "$output" == *'/var/backups/kwvps'* ]]
}
