#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/system.sh
  source src/tunnel.sh
}

@test "Tunnel token prompt uses visible input" {
  run grep -F 'Dán Tunnel token (hiển thị khi nhập; 0 hoặc Enter để quay lại): ' src/tunnel.sh
  [ "$status" -eq 0 ]
  run grep -F 'IFS= read -r token || return 0' src/tunnel.sh
  [ "$status" -eq 0 ]
  run grep -F 'read -r -s token' src/tunnel.sh
  [ "$status" -eq 1 ]
}

@test "Tunnel package install refuses missing confirmation before network access" {
  run kw_tunnel_install WRONG
  [ "$status" -eq 2 ]
}

@test "Tunnel service configuration refuses missing confirmation before writes" {
  run kw_tunnel_configure 'eyJhIjoiMDEyMzQ1Njc4OWFiY2RlZiIsInQiOiJ0ZXN0In0=' WRONG
  [ "$status" -eq 2 ]
}

@test "Tunnel token validator rejects shell injection and whitespace" {
  kw_tunnel_token_valid 'eyJhIjoiMDEyMzQ1Njc4OWFiY2RlZiIsInQiOiJ0ZXN0In0='
  ! kw_tunnel_token_valid 'token with spaces and unsafe content'
  ! kw_tunnel_token_valid 'eyJhIjoiMDEyMzQ1Njc4OWFiY2RlZiI7id'
}

@test "Tunnel unit reads token from file, not command line" {
  run kw_tunnel_render_unit
  [ "$status" -eq 0 ]
  [[ "$output" == *'--token-file /etc/kwvps/cloudflare/tunnel-token'* ]]
  [[ "$output" != *'--token ey'* ]]
}

@test "Tunnel menu exposes installer when cloudflared is absent" {
  kw_tunnel_installed() { return 1; }
  run kw_tunnel_config_interactive <<< '0'
  [ "$status" -eq 0 ]
  [[ "$output" == *'Cài cloudflared từ kho APT Cloudflare'* ]]
}

@test "Tunnel inbound menu exposes close and open actions" {
  run kw_tunnel_inbound_interactive <<< '0'
  [ "$status" -eq 0 ]
  [[ "$output" == *'1. Đóng inbound 80/443'* ]]
  [[ "$output" == *'2. Mở inbound 80/443'* ]]
}

@test "Tunnel inbound rejects unsupported action without changing firewall" {
  run kw_tunnel_inbound_change wrong
  [ "$status" -eq 2 ]
}
@test "ingress mode defaults to DNS and rejects unsafe names" {
  kw_tunnel_site_mode_path() {
    kw_domain_valid "$1" || return 2
    printf '%s/%s.mode\n' "$BATS_TEST_TMPDIR" "$1"
  }
  systemctl() { return 1; }
  run kw_tunnel_site_mode example.com
  [ "$status" -eq 0 ]
  [ "$output" = dns ]
  run kw_tunnel_site_mode '../etc/passwd'
  [ "$status" -eq 2 ]
}

@test "site ingress change requires exact confirmation" {
  run kw_tunnel_site_mode_set example.com tunnel wrong
  [ "$status" -eq 2 ]
}

@test "active cloudflared makes unclassified site unknown, not DNS" {
  kw_tunnel_site_mode_path() {
    kw_domain_valid "$1" || return 2
    printf '%s/%s.mode\n' "$BATS_TEST_TMPDIR" "$1"
  }
  systemctl() { [[ $1 == is-active && $2 == --quiet && $3 == cloudflared.service ]]; }
  run kw_tunnel_site_mode unclassified.example.com
  [ "$status" -eq 0 ]
  [ "$output" = unknown ]
}
