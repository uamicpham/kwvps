#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/fail2ban.sh
}

@test "IPv4 and jail validation reject injection and malformed values" {
  run kw_f2b_ipv4_valid 198.51.100.17
  [ "$status" -eq 0 ]
  run kw_f2b_ipv4_valid 198.51.100.999
  [ "$status" -eq 1 ]
  run kw_f2b_ipv4_valid '1.2.3.4;id'
  [ "$status" -eq 1 ]
  run kw_f2b_jail_valid sshd
  [ "$status" -eq 0 ]
  run kw_f2b_jail_valid 'sshd;id'
  [ "$status" -eq 1 ]
}

@test "ban and unban require exact combined confirmation before service access" {
  run kw_f2b_change banip sshd 198.51.100.17 wrong
  [ "$status" -eq 2 ]
  run kw_f2b_change unbanip sshd 198.51.100.17 wrong
  [ "$status" -eq 2 ]
}

@test "jail selection accepts only an exact listed name" {
  fail2ban-client() { printf 'Status\n|- Number of jail:\t2\n`- Jail list:\tsshd, nginx-http-auth\n'; }
  kw_f2b_jail_exists sshd
  kw_f2b_jail_exists nginx-http-auth
  ! kw_f2b_jail_exists nginx
}
