#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/system.sh
  source src/sites.sh
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

@test "site connector uses a separate token and service" {
  run kw_tunnel_render_site_unit examplecom
  [ "$status" -eq 0 ]
  [[ "$output" == *'kwvps-cloudflared-examplecom.service'* ||
     "$output" == *'Cloudflare Tunnel (KwVPS site examplecom)'* ]]
  [[ "$output" == *'--token-file /etc/kwvps/cloudflare/tunnels/examplecom.token'* ]]
  [[ "$output" != *'/etc/kwvps/cloudflare/tunnel-token'* ]]
}

@test "site connector rejects a missing or mismatched confirmation" {
  run kw_tunnel_site_configure example.com 'eyJhIjoiMDEyMzQ1Njc4OWFiY2RlZiIsInQiOiJ0ZXN0In0=' WRONG
  [ "$status" -eq 2 ]
  run kw_tunnel_site_remove example.com wrong.example.com
  [ "$status" -eq 2 ]
}

@test "site connector takes precedence over the legacy shared connector" {
  kw_tunnel_site_connector_present() { return 0; }
  kw_tunnel_site_service_owned() { return 0; }
  kw_tunnel_site_token_safe() { return 0; }
  systemctl() { [[ $1 == is-active && $2 == --quiet && $3 == kwvps-cloudflared-examplecom.service ]]; }
  run kw_tunnel_connector_active_for_site example.com
  [ "$status" -eq 0 ]
}

@test "connector selection uses numbered site and legacy entries" {
  kw_tunnel_collect_connectors() {
    KW_TUNNEL_CONNECTOR_UNITS=(kwvps-cloudflared-examplecom.service cloudflared.service)
    KW_TUNNEL_CONNECTOR_LABELS=(example.com 'Connector chung cũ')
  }
  choose_second() { kw_tunnel_choose_connector <<< '2'; printf '%s\n' "$KW_TUNNEL_CHOICE_UNIT"; }
  run choose_second
  [ "$status" -eq 0 ]
  [[ "$output" == *'2. Connector chung cũ'* ]]
  [[ "$output" == *'cloudflared.service' ]]
}

@test "inbound close recognizes an active site connector without a shared service" {
  kw_tunnel_collect_connectors() {
    KW_TUNNEL_CONNECTOR_UNITS=(kwvps-cloudflared-examplecom.service)
    KW_TUNNEL_CONNECTOR_LABELS=(example.com)
  }
  systemctl() { [[ $1 == is-active && $2 == --quiet && $3 == kwvps-cloudflared-examplecom.service ]]; }
  run kw_tunnel_any_active
  [ "$status" -eq 0 ]
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

@test "explicit DNS label stays DNS while cloudflared is active" {
  kw_tunnel_site_mode_path() {
    kw_domain_valid "$1" || return 2
    printf '%s/%s.mode\n' "$BATS_TEST_TMPDIR" "$1"
  }
  systemctl() { [[ $1 == is-active && $2 == --quiet && $3 == cloudflared.service ]]; }
  stat() { [[ $1 == -c && $2 == %u:%a ]] && printf '0:600\n'; }
  printf 'dns\n' > "$BATS_TEST_TMPDIR/example.com.mode"
  run kw_tunnel_site_mode example.com
  [ "$status" -eq 0 ]
  [ "$output" = dns ]
}

@test "configured Tunnel offers an explicit per-site switch" {
  kw_site_prompt_domain() { KW_SITE_CHOICE=example.com; }
  kw_tunnel_site_mode() { printf 'dns\n'; }
  kw_prompt_yes_no_token() { printf 'PROMPT:%s\n' "$1"; KW_PROMPT_VALUE=$2; }
  kw_tunnel_site_mode_set() { printf 'SET:%s:%s:%s\n' "$1" "$2" "$3"; }
  run kw_tunnel_post_config_interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *'PROMPT:Bật chế độ Tunnel và Real IP cho example.com?'* ]]
  [[ "$output" == *'SET:example.com:tunnel:INGRESS:example.com:tunnel'* ]]
}

@test "accepting Tunnel setup repairs missing Cloudflare Real IP" {
  kw_cf_realip_public_config_valid() { [[ ${REALIP_READY:-0} == 1 ]]; }
  kw_cf_realip_apply() { [[ $1 == UPDATE-CLOUDFLARE-REALIP ]] || return 2; REALIP_READY=1; }
  run kw_tunnel_ensure_realip
  [ "$status" -eq 0 ]
  [[ "$output" == *'đang cập nhật dải IP Cloudflare'* ]]
}

@test "already marked Tunnel offers Real IP repair after yes" {
  kw_tunnel_site_mode() { printf 'tunnel\n'; }
  kw_prompt_yes_no_token() { KW_PROMPT_VALUE=$2; }
  kw_tunnel_site_mode_set() { printf 'SET:%s:%s:%s\n' "$1" "$2" "$3"; }
  run kw_tunnel_post_config_interactive example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *'SET:example.com:tunnel:INGRESS:example.com:tunnel'* ]]
}
