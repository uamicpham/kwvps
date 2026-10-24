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
  run kw_fw_port_plan close 3306 tcp
  [ "$status" -eq 0 ]
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
  run kw_fw_toggle enable wrong
  [ "$status" -eq 2 ]
}

@test "only marked UFW rules are selected for deletion" {
  ufw() {
    printf 'Status: active\n\nTo                         Action      From\n'
    printf '[ 1] 8080/tcp                   ALLOW IN    Anywhere                   # kwvps-port-8080-tcp\n'
    printf '[ 2] 8080/tcp (v6)              ALLOW IN    Anywhere (v6)              # kwvps-port-8080-tcp\n'
    printf '[ 3] 9090/tcp                   ALLOW IN    Anywhere                   # user-rule\n'
    printf '[ 4] Anywhere                   DENY IN     203.0.113.47               # kwvps-block-203-0-113-47\n'
    printf '[ 5] 8080/tcp                   DENY IN     Anywhere                   # kwvps-port-deny-8080-tcp\n'
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
  run kw_fw_rule_numbers port-deny 8080 tcp
  [ "$status" -eq 0 ]
  [ "$output" = 5 ]
  run kw_fw_port_has_action 8080 tcp DENY
  [ "$status" -eq 0 ]
  run kw_fw_port_has_action 9090 tcp DENY
  [ "$status" -eq 1 ]
}

@test "UFW action coverage distinguishes IPv4 and IPv6" {
  ufw() {
    printf 'Status: active\n'
    printf '[ 1] 80/tcp DENY IN Anywhere # kwvps-port-deny-80-tcp\n'
    printf '[ 2] 80/tcp (v6) DENY IN Anywhere (v6) # kwvps-port-deny-80-tcp\n'
    printf '[ 3] 443/tcp DENY IN Anywhere # kwvps-port-deny-443-tcp\n'
  }
  kw_fw_port_has_action_family 80 tcp DENY 4
  kw_fw_port_has_action_family 80 tcp DENY 6
  kw_fw_port_has_action_family 443 tcp DENY 4
  ! kw_fw_port_has_action_family 443 tcp DENY 6
  ! kw_fw_port_has_action_family 80 tcp ALLOW 4
}

@test "closing a port removes KwVPS ALLOW before adding DENY" {
  local allow=1 deny=0 deletes=0 history=''
  rollback_allow=0 rollback_new_deny=0
  kw_fw_rule_numbers() {
    if [[ $1 == port && $allow == 1 ]]; then printf '1\n2\n'; fi
  }
  kw_fw_port_has_action_family() {
    if [[ $3 == DENY ]]; then [[ $deny == 1 && $allow == 0 ]]
    else [[ $allow == 1 ]]; fi
  }
  ufw() {
    if [[ $1 == status ]]; then
      printf 'Status: active\n'
      if [[ $allow == 1 ]]; then
        printf '[ 1] 8080/tcp ALLOW IN Anywhere # kwvps-port-8080-tcp\n'
      fi
    elif [[ $1 == --force && $2 == delete ]]; then
      history+="delete:$3 "
      deletes=$((deletes + 1))
      if ((deletes == 2)); then allow=0; fi
    elif [[ $1 == insert ]]; then
      history+='deny '
      [[ $allow == 0 ]] || return 1
      deny=1
    else return 2; fi
  }
  kw_fw_port_close_rules 8080 tcp
  [ "$allow" -eq 0 ] && [ "$deny" -eq 1 ]
  [ "$rollback_allow" -eq 1 ] && [ "$rollback_new_deny" -eq 1 ]
  [[ $history == delete:*deny* ]]
}

@test "SSH guard collects configured and current SSH ports" {
  kw_has() { return 0; }
  sshd() { printf 'port 22\nport 2222\n'; }
  systemctl() { return 1; }
  SSH_CONNECTION='203.0.113.5 55444 192.0.2.10 2200'
  run kw_fw_ssh_ports
  [ "$status" -eq 0 ]
  [ "$output" = $'22\n2222\n2200' ]
}

@test "SSH guard refuses active socket without the current SSH port" {
  kw_has() { return 0; }
  sshd() { printf 'port 22\n'; }
  systemctl() { [[ $* == 'is-active --quiet ssh.socket' ]]; }
  unset SSH_CONNECTION
  run kw_fw_ssh_ports
  [ "$status" -eq 2 ]
  [[ "$output" == *'từ chối bật UFW'* ]]
}

@test "SSH guard collects socket ports when active without SSH_CONNECTION" {
  kw_has() { return 0; }
  sshd() { printf 'port 22\n'; }
  systemctl() {
    if [[ $* == 'is-active --quiet ssh.socket' ]]; then return 0;
    elif [[ $* == 'show ssh.socket -p Listen --value' ]]; then printf '[::]:22 (Stream)\n';
    else return 1; fi;
  }
  unset SSH_CONNECTION
  run kw_fw_ssh_ports
  [ "$status" -eq 0 ]
  [[ "$output" == *'22'* ]]
}
