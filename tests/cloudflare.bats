#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/system.sh
  source src/cloudflare.sh
}

@test "Cloudflare Real IP requires exact confirmation before network access" {
  run kw_cf_realip_apply WRONG
  [ "$status" -eq 2 ]
}

@test "per-domain anti-DDoS accepts only fixed rates and requires confirmation" {
  kw_cf_antiddos_rate_valid 5
  kw_cf_antiddos_rate_valid 50
  kw_cf_antiddos_rate_valid off
  ! kw_cf_antiddos_rate_valid '5; include /etc/passwd'
  run kw_cf_antiddos_apply example.com 10 wrong
  [ "$status" -eq 2 ]
}

@test "anti-DDoS help distinguishes local and Cloudflare rate limiting" {
  run kw_cf_antiddos_explain
  [ "$status" -eq 0 ]
  [[ "$output" == *'Nginx local'* ]]
  [[ "$output" == *'Cloudflare Rate Limiting'* ]]
  [[ "$output" == *'Gói Free không hỗ trợ'* ]]
}

@test "anti-DDoS menu offers two independent backends" {
  run kw_cf_antiddos_interactive <<< '0'
  [ "$status" -eq 0 ]
  [[ "$output" == *'1. Rate limit Nginx local'* ]]
  [[ "$output" == *'2. Rate limit Cloudflare theo domain'* ]]
}

@test "Cloudflare rate rule scopes hostname and counts per IP" {
  run kw_cf_rate_rule_json blog.example.com 10 kwvps-rate-test no
  [ "$status" -eq 0 ]
  [[ "$output" == *'http.host eq \"blog.example.com\"'* ]]
  [[ "$output" == *'"ip.src"'* ]]
  [[ "$output" == *'"requests_per_period": 100'* ]]
  [[ "$output" == *'"period": 10'* ]]
}

@test "Cloudflare Free fallback rule matches the entire zone" {
  run kw_cf_rate_rule_json blog.example.com 10 kwvps-rate-zone-test yes zone
  [ "$status" -eq 0 ]
  [[ "$output" == *'"kind": "zone"'* ]]
  [[ "$output" == *'"expression": "true"'* ]]
  [[ "$output" != *'http.host eq'* ]]
  [[ "$output" == *'"ip.src"'* ]]
}

@test "Cloudflare Free menu warns about all hostnames and accepts No" {
  kw_site_prompt_domain() { KW_SITE_CHOICE=blog.example.com; }
  kw_cf_zone_cache_read() { KW_CF_ZONE_ID=0123456789abcdef0123456789abcdef; }
  kw_cf_zone_for_domain() { KW_CF_ZONE_NAME=example.com; }
  kw_cf_api() { printf '%s\n' '{"success":true,"result":{"plan":{"legacy_id":"free"}}}'; }
  kw_cf_rate_apply() { printf 'MUST NOT APPLY\n'; return 99; }
  run kw_cf_rate_interactive <<< $'1\nn'
  [ "$status" -eq 0 ]
  [[ "$output" == *'TOÀN ZONE example.com'* ]]
  [[ "$output" == *'mọi hostname/subdomain'* ]]
  [[ "$output" != *'MUST NOT APPLY'* ]]
}

@test "Cloudflare rate refuses invalid confirmation before API or writes" {
  run kw_cf_rate_apply blog.example.com 0123456789abcdef0123456789abcdef 10 wrong
  [ "$status" -eq 2 ]
  run kw_cf_rate_apply blog.example.com 0123456789abcdef0123456789abcdef 10 CF-RATE:blog.example.com:10 zone
  [ "$status" -eq 2 ]
}

@test "Cloudflare rate detects Free plan and validates owned rule ID" {
  run kw_cf_rate_plan <<< '{"success":true,"result":{"plan":{"legacy_id":"free"}}}'
  [ "$status" -eq 0 ]
  [ "$output" = free ]
  run kw_cf_rate_rule_id kwvps-rate-test <<< '{"success":true,"result":{"phase":"http_ratelimit","rules":[{"ref":"other","id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},{"ref":"kwvps-rate-test","id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}}'
  [ "$status" -eq 0 ]
  [ "$output" = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ]
}

@test "Cloudflare rate API rejects a route outside owned rules" {
  run kw_cf_rate_api DELETE 0123456789abcdef0123456789abcdef 'rule/../settings/security_level'
  [ "$status" -eq 2 ]
  run kw_cf_rate_api GET 0123456789abcdef0123456789abcdef entrypoint '' yes
  [ "$status" -eq 2 ]
}

@test "Cloudflare rate error message shows API cause without exposing token" {
  run kw_cf_rate_error_summary <<< '{"errors":[{"code":20126,"message":"bad rule cfut_SECRET12345678901234567890"}]}'
  [ "$status" -eq 0 ]
  [[ "$output" == *'Cloudflare error 20126: bad rule [REDACTED]'* ]]
  [[ "$output" != *'cfut_SECRET'* ]]
}

@test "per-domain anti-DDoS renders isolated Nginx host maps" {
  kw_cf_antiddos_state_dir="$BATS_TEST_TMPDIR/antiddos"
  mkdir "$kw_cf_antiddos_state_dir"
  printf '10\n' > "$kw_cf_antiddos_state_dir/example.com.rate"
  stat() { printf '0:600\n'; }
  run kw_cf_antiddos_render
  [ "$status" -eq 0 ]
  [[ "$output" == *'example.com $binary_remote_addr;'* ]]
  [[ "$output" == *'rate=10r/s;'* ]]
  [[ "$output" == *'limit_req_status 429;'* ]]
}

@test "Cloudflare CIDR validator accepts canonical IPv4 and IPv6 ranges" {
  printf '%s\n' '203.0.113.0/24' > "$BATS_TEST_TMPDIR/v4"
  printf '%s\n' '2001:db8::/32' > "$BATS_TEST_TMPDIR/v6"
  run kw_cf_realip_lines "$BATS_TEST_TMPDIR/v4" 4
  [ "$status" -eq 0 ]
  [ "$output" = 'set_real_ip_from 203.0.113.0/24;' ]
  run kw_cf_realip_lines "$BATS_TEST_TMPDIR/v6" 6
  [ "$status" -eq 0 ]
  [ "$output" = 'set_real_ip_from 2001:db8::/32;' ]
}

@test "Cloudflare CIDR validator rejects host bits, duplicates and injected directives" {
  printf '%s\n' '203.0.113.1/24' > "$BATS_TEST_TMPDIR/bad"
  run kw_cf_realip_lines "$BATS_TEST_TMPDIR/bad" 4
  [ "$status" -eq 2 ]
  printf '%s\n' '203.0.113.0/24' '203.0.113.0/24' > "$BATS_TEST_TMPDIR/bad"
  run kw_cf_realip_lines "$BATS_TEST_TMPDIR/bad" 4
  [ "$status" -eq 2 ]
  printf '%s\n' '203.0.113.0/24; include /etc/passwd' > "$BATS_TEST_TMPDIR/bad"
  run kw_cf_realip_lines "$BATS_TEST_TMPDIR/bad" 4
  [ "$status" -eq 2 ]
}

@test "Under Attack rejects missing confirmation before network access" {
  run kw_cf_under_attack_apply example.com 0123456789abcdef0123456789abcdef enable wrong
  [ "$status" -eq 2 ]
}

@test "Cloudflare zone ID and security level are strictly validated" {
  kw_cf_zone_id_valid 0123456789abcdef0123456789abcdef
  ! kw_cf_zone_id_valid 'abc/../token'
  kw_cf_level_valid under_attack
  ! kw_cf_level_valid 'under_attack;id'
}

@test "zone lookup refuses a domain outside the selected Cloudflare zone" {
  kw_cf_api() { printf '%s\n' '{"success":true,"result":{"name":"example.org"}}'; }
  run kw_cf_zone_for_domain example.com 0123456789abcdef0123456789abcdef
  [ "$status" -eq 2 ]
  run kw_cf_zone_for_domain blog.example.org 0123456789abcdef0123456789abcdef
  [ "$status" -eq 0 ]
}

@test "Cloudflare API JSON parser refuses success false" {
  run kw_cf_json_field security_level <<< '{"success":false,"result":{"value":"under_attack"}}'
  [ "$status" -eq 2 ]
}

@test "saved Zone ID is accepted only for its original domain" {
  kw_cf_zone_cache_path() { printf '%s\n' "$BATS_TEST_TMPDIR/zone.id"; }
  stat() { printf '0:600\n'; }
  printf '%s\n%s\n' example.com 0123456789abcdef0123456789abcdef > "$BATS_TEST_TMPDIR/zone.id"
  run kw_cf_zone_cache_read example.com
  [ "$status" -eq 0 ]
  run kw_cf_zone_cache_read different.com
  [ "$status" -eq 2 ]
}

@test "Under Attack menu reuses validated saved Zone ID without prompting again" {
  kw_site_prompt_domain() { KW_SITE_CHOICE=blog.example.com; }
  kw_cf_zone_cache_read() { KW_CF_ZONE_ID=0123456789abcdef0123456789abcdef; }
  kw_cf_zone_for_domain() { KW_CF_ZONE_NAME=example.com; }
  kw_cf_zone_cache_save() { :; }
  kw_cf_security_current() { printf 'medium'; }
  run kw_cf_under_attack_interactive <<< '0'
  [ "$status" -eq 0 ]
  [[ "$output" == *'Zone ID đã lưu'* ]]
  [[ "$output" != *'Zone ID Cloudflare (32'* ]]
  [[ "$output" == *'ảnh hưởng MỌI hostname'* ]]
}

@test "zone discovery finds the most specific accessible parent zone" {
  kw_cf_api() {
    case "$2" in
      'zones?name=blog.example.com') printf '%s\n' '{"success":true,"result":[]}' ;;
      'zones?name=example.com') printf '%s\n' '{"success":true,"result":[{"name":"example.com","id":"0123456789abcdef0123456789abcdef"}]}' ;;
      *) return 2 ;;
    esac
  }
  kw_cf_zone_discover blog.example.com
  [ "$KW_CF_ZONE_ID" = 0123456789abcdef0123456789abcdef ]
}

@test "zone discovery rejects an invalid or ambiguous Cloudflare response" {
  run kw_cf_json_zone_id example.com <<< '{"success":true,"result":[{"name":"example.com","id":"bad"}]}'
  [ "$status" -eq 2 ]
}

@test "Cloudflare token input validation accepts API token shape and rejects injection" {
  test_token="cfut_$(printf 'a%.0s' {1..30})"
  kw_cf_token_valid "$test_token"
  ! kw_cf_token_valid 'cfut_bad token'
  ! kw_cf_token_valid 'short'
  ! kw_cf_token_valid 'cfut_bad;id'
}

@test "Cloudflare token cannot be saved without explicit internal confirmation" {
  test_token="cfut_$(printf 'a%.0s' {1..30})"
  run kw_cf_token_save "$test_token" WRONG
  [ "$status" -eq 2 ]
}

@test "Cloudflare token help names the menu without exposing a token" {
  run kw_cf_token_help
  [ "$status" -eq 0 ]
  [[ "$output" == *'Cấu hình API token (mục 4)'* ]]
}

@test "Cloudflare token submenu has status add and instructions" {
  source src/menu.sh
  run kw_catalog cf-token
  [ "$status" -eq 0 ]
  [[ "$output" == *'Trạng thái API token|cf-token-status'* ]]
  [[ "$output" == *'Thêm hoặc thay API token|cf-token-save'* ]]
  [[ "$output" == *'Hướng dẫn lấy token và cấp quyền|cf-token-guide'* ]]
}
