#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/sites.sh
  source src/laravel.sh
  source src/rename.sh
  source src/ssl.sh
  source src/cloudflare.sh
  source src/menu.sh
}

@test "site rename is reachable from the third Sites menu entry" {
  run kw_catalog sites
  [ "$status" -eq 0 ]
  [[ "$output" == *'Đổi tên miền|site-rename'* ]]
}

@test "site rename rejects missing confirmation and unsafe domains before filesystem access" {
  run kw_site_rename old.example.com new.example.com no
  [ "$status" -eq 2 ]
  run kw_site_rename 'old.example.com;id' new.example.com yes
  [ "$status" -eq 2 ]
  run kw_site_rename old.example.com old.example.com yes
  [ "$status" -eq 2 ]
}

@test "rename recognizes and re-renders a managed Laravel HTTP release vhost" {
  old=$BATS_TEST_TMPDIR/old.conf
  new=$BATS_TEST_TMPDIR/new.conf
  kw_laravel_render_vhost http old.example.com oldexamplecom > "$old"

  run kw_site_rename_vhost_kind "$old" old.example.com oldexamplecom
  [ "$status" -eq 0 ]
  [ "$output" = laravel-http ]

  kw_site_rename_render_vhost "$output" new.example.com newexamplecom > "$new"
  kw_site_vhost_matches "$new" new.example.com newexamplecom \
    kw_laravel_render_vhost http new.example.com newexamplecom
  grep -Fq 'root /var/www/kwvps/newexamplecom/deploy/current/public;' "$new"
  grep -Fq 'root /var/www/kwvps/newexamplecom/public;' "$new"
  ! grep -Fq 'old.example.com' "$new"
  ! grep -Fq 'oldexamplecom' "$new"
}

@test "rename preserves managed Tunnel Real IP for a Laravel HTTP vhost" {
  old=$BATS_TEST_TMPDIR/old.conf
  new=$BATS_TEST_TMPDIR/new.conf
  kw_laravel_render_vhost http old.example.com oldexamplecom |
    kw_cf_realip_vhost_overlay tunnel old.example.com oldexamplecom > "$old"

  run kw_site_rename_vhost_kind "$old" old.example.com oldexamplecom
  [ "$status" -eq 0 ]
  [ "$output" = laravel-http ]

  kw_site_rename_render_vhost "$output" new.example.com newexamplecom |
    kw_cf_realip_vhost_overlay tunnel new.example.com newexamplecom > "$new"
  kw_site_vhost_matches "$new" new.example.com newexamplecom \
    kw_laravel_render_vhost http new.example.com newexamplecom
  grep -Fq 'set_real_ip_from 127.0.0.1;' "$new"
  ! grep -Fq 'old.example.com' "$new"
}

@test "rename still rejects custom directives and TLS vhosts" {
  old=$BATS_TEST_TMPDIR/old.conf
  kw_laravel_render_vhost http old.example.com oldexamplecom > "$old"
  printf '  add_header X-Custom yes;\n' >> "$old"
  run kw_site_rename_vhost_kind "$old" old.example.com oldexamplecom
  [ "$status" -eq 2 ]

  kw_ssl_render_vhost old.example.com oldexamplecom > "$old"
  run kw_site_rename_vhost_kind "$old" old.example.com oldexamplecom
  [ "$status" -eq 2 ]
}
