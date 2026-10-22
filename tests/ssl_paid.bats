#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/sites.sh
  source src/ssl.sh
  source src/menu.sh
}

@test "paid SSL menu routes to a real action" {
  run kw_catalog ssl
  [ "$status" -eq 0 ]
  [[ "$output" == *'Thêm paid SSL|ssl-paid'* ]]
}

@test "paid SSL renderer uses site-owned certificate path and no Lets Encrypt marker" {
  run kw_ssl_render_paid_vhost paid.example.com paidexamplecom
  [ "$status" -eq 0 ]
  [[ "$output" == *'# KwVPS TLS: Paid'* ]]
  [[ "$output" == *'/etc/kwvps/certs/paidexamplecom/fullchain.pem'* ]]
  [[ "$output" == *'/etc/kwvps/certs/paidexamplecom/privkey.pem'* ]]
  [[ "$output" != *'/etc/letsencrypt/live/'* ]]
}

@test "paid SSL refuses missing domain confirmation before filesystem access" {
  run kw_ssl_paid paid.example.com fullchain.pem privkey.pem wrong.example.com
  [ "$status" -eq 2 ]
}

@test "paid SSL certificate must match domain and private key" {
  openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
    -subj /CN=paid.example.com -keyout "$BATS_TEST_TMPDIR/key.pem" \
    -out "$BATS_TEST_TMPDIR/cert.pem" >/dev/null 2>&1
  kw_ssl_paid_validate paid.example.com "$BATS_TEST_TMPDIR/cert.pem" "$BATS_TEST_TMPDIR/key.pem"
  ! kw_ssl_paid_validate other.example.com "$BATS_TEST_TMPDIR/cert.pem" "$BATS_TEST_TMPDIR/key.pem"
  openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
    -subj /CN=paid.example.com -keyout "$BATS_TEST_TMPDIR/other-key.pem" \
    -out "$BATS_TEST_TMPDIR/other-cert.pem" >/dev/null 2>&1
  ! kw_ssl_paid_validate paid.example.com "$BATS_TEST_TMPDIR/cert.pem" "$BATS_TEST_TMPDIR/other-key.pem"
}
