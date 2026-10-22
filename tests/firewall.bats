#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/fail2ban.sh
  source src/firewall.sh
}

@test "public port rules exclude MariaDB and reject unsafe input" {
  run kw_fw_port_plan open 8080 tcp
  [ "$status" -eq 0 ]
  run kw_fw_port_plan open 3306 tcp
  [ "$status" -eq 2 ]
  run kw_fw_port_plan open '8080;id' tcp
  [ "$status" -eq 2 ]
  run kw_fw_port_plan open 8080 'tcp;id'
  [ "$status" -eq 2 ]
}

@test "port and IP mutations require exact confirmation" {
  run kw_fw_port_change open 8080 tcp wrong
  [ "$status" -eq 2 ]
  run kw_fw_ip_change ban 203.0.113.47 wrong
  [ "$status" -eq 2 ]
}

@test "only marked UFW rules are selected for deletion" {
  ufw() {
    printf 'Status: active\n\nTo                         Action      From\n'
    printf '[ 1] 8080/tcp                   ALLOW IN    Anywhere                   # kwvps-port-8080-tcp\n'
    printf '[ 2] 8080/tcp (v6)              ALLOW IN    Anywhere (v6)              # kwvps-port-8080-tcp\n'
    printf '[ 3] 9090/tcp                   ALLOW IN    Anywhere                   # user-rule\n'
    printf '[ 4] Anywhere                   DENY IN     203.0.113.47               # kwvps-block-203-0-113-47\n'
  }
  run kw_fw_rule_numbers port 8080 tcp
  [ "$status" -eq 0 ]
  [ "$output" = $'1\n2' ]
  run kw_fw_rule_numbers port 9090 tcp
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run kw_fw_rule_numbers ip 203.0.113.47
  [ "$status" -eq 0 ]
  [ "$output" = 4 ]
}
