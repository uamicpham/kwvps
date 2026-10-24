#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/system.sh
  source src/firewall.sh
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

@test "Tunnel inbound verification requires both address families" {
  ufw() {
    printf 'Status: active\n'
    printf '[ 1] 80/tcp DENY IN Anywhere # kwvps-port-deny-80-tcp\n'
    [[ ${UFW_HAS_V6:-0} == 1 ]] &&
      printf '[ 2] 80/tcp (v6) DENY IN Anywhere (v6) # kwvps-port-deny-80-tcp\n'
    return 0
  }
  ! kw_tunnel_inbound_denied 80
  UFW_HAS_V6=1 kw_tunnel_inbound_denied 80
}

@test "Tunnel close removes KwVPS ALLOW before inserting DENY" {
  local allow80=1 allow443=1 deny80=0 deny443=0 delete_count=0 history=''
  created_ports=() removed_allow_ports=()
  kw_fw_rule_numbers() {
    if [[ $1 == port ]]; then
      if [[ $2 == 80 && $allow80 == 1 || $2 == 443 && $allow443 == 1 ]]; then
        printf '1\n2\n'
      fi
    fi
  }
  kw_tunnel_inbound_denied() {
    if [[ $1 == 80 ]]; then [[ $deny80 == 1 && $allow80 == 0 ]]
    else [[ $deny443 == 1 && $allow443 == 0 ]]; fi
  }
  ufw() {
    if [[ $1 == status ]]; then
      printf 'Status: active\n'
      if [[ $allow80 == 1 ]]; then printf '[ 1] 80/tcp ALLOW IN Anywhere # kwvps-port-80-tcp\n'; fi
      if [[ $allow443 == 1 ]]; then printf '[ 2] 443/tcp ALLOW IN Anywhere # kwvps-port-443-tcp\n'; fi
    elif [[ $1 == --force && $2 == delete ]]; then
      history+="delete:$3 "
      delete_count=$((delete_count + 1))
      if ((delete_count == 2)); then allow80=0
      elif ((delete_count == 4)); then allow443=0; fi
    elif [[ $1 == insert ]]; then
      history+="deny:$4 "
      if [[ $4 == 80/tcp ]]; then [[ $allow80 == 0 ]] || return 1; deny80=1
      else [[ $allow443 == 0 ]] || return 1; deny443=1; fi
    else
      return 2
    fi
  }
  kw_tunnel_inbound_close_rules
  [ "$allow80" -eq 0 ] && [ "$allow443" -eq 0 ]
  [ "$deny80" -eq 1 ] && [ "$deny443" -eq 1 ]
  [ "${removed_allow_ports[*]}" = '80 443' ]
  [ "${created_ports[*]}" = '80 443' ]
  [[ $history == delete:*deny:80/tcp*delete:*deny:443/tcp* ]]
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
