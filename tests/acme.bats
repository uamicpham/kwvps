#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/system.sh
  source src/sites.sh
  source src/acme.sh
  source src/ssl.sh
  source src/menu.sh
}

@test "ACME provider menu is enabled and never exposes EAB in status" {
  run kw_catalog ssl
  [ "$status" -eq 0 ]
  [[ "$output" == *'Đổi ACME provider|acme-provider'* ]]
  run kw_acme_status
  [ "$status" -eq 0 ]
  [[ "$output" == *'chứng chỉ MỚI'* ]]
  [[ "$output" != *'eab-hmac-key'* ]]
}

@test "EAB values are constrained and selection needs confirmation" {
  kw_acme_eab_valid 'GD-VvWydSVFuss_GhBwYQQ'
  kw_acme_eab_valid 'MjXU3MH-Z0WQ7piMAnVsCpD1shgMiWx6ggPWiTmydgUaj7dWWWfQfA'
  ! kw_acme_eab_valid 'bad;id'
  ! kw_acme_eab_valid 'short'
  run kw_acme_provider_set zerossl validKID123 validHMAC123 wrong
  [ "$status" -eq 2 ]
  run kw_acme_provider_set letsencrypt '' '' wrong
  [ "$status" -eq 2 ]
}

@test "ZeroSSL and Lets Encrypt vhosts share safe paths but have distinct markers" {
  run kw_ssl_render_vhost ssl.example.com sslexamplecom zerossl
  [ "$status" -eq 0 ]
  [[ "$output" == *'# KwVPS TLS: ZeroSSL'* ]]
  [[ "$output" == *'/etc/letsencrypt/live/ssl.example.com/fullchain.pem'* ]]
  run kw_ssl_render_vhost ssl.example.com sslexamplecom letsencrypt
  [ "$status" -eq 0 ]
  [[ "$output" == *"# KwVPS TLS: Let's Encrypt"* ]]
  run kw_ssl_render_vhost ssl.example.com sslexamplecom injected
  [ "$status" -eq 2 ]
}
