#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/system.sh
  source src/ssh.sh
}

@test "SSH key operations reject missing confirmation before touching authorized_keys" {
  run kw_ssh_key_add root 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJj848/f0e6QXwL5r5Gu1qjuQjLE9XXP+5EgW1Ho2icf test' WRONG
  [ "$status" -eq 2 ]
  run kw_ssh_key_remove root 1 WRONG
  [ "$status" -eq 2 ]
}

@test "SSH public key validation accepts ed25519 and rejects injected options" {
  key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJj848/f0e6QXwL5r5Gu1qjuQjLE9XXP+5EgW1Ho2icf test'
  kw_ssh_key_valid "$key"
  run kw_ssh_key_fingerprint "$key"
  [ "$status" -eq 0 ]
  [[ "$output" == SHA256:* ]]
  ! kw_ssh_key_valid 'from="*" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJj848/f0e6QXwL5r5Gu1qjuQjLE9XXP+5EgW1Ho2icf'
  ! kw_ssh_key_valid 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJj848/f0e6QXwL5r5Gu1qjuQjLE9XXP+5EgW1Ho2icf;id'
}

@test "SSH account management is limited to root and ubuntu" {
  run kw_ssh_account_paths www-data
  [ "$status" -eq 2 ]
}

@test "SSH login limit ranges reject unsafe values" {
  kw_ssh_limit_auth_valid 3
  kw_ssh_limit_sessions_valid 5
  kw_ssh_limit_grace_valid 60
  ! kw_ssh_limit_auth_valid 1
  ! kw_ssh_limit_sessions_valid 0
  ! kw_ssh_limit_grace_valid '60;PermitRootLogin yes'
}

@test "SSH limits refuse writes without internal confirmation" {
  run kw_ssh_limits_apply 3 5 60 WRONG
  [ "$status" -eq 2 ]
}

@test "SSH key-only rejects missing confirmation before touching sshd" {
  run kw_ssh_key_only_apply enable WRONG
  [ "$status" -eq 2 ]
  run kw_ssh_key_only_apply disable WRONG
  [ "$status" -eq 2 ]
}
