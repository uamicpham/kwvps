#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/sites.sh
  source src/laravel.sh
  source src/rename.sh
  source src/ssl.sh
  source src/cloudflare.sh
  source src/tunnel.sh
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

@test "rename moves a site Tunnel token and restores the old connector on rollback" {
  KW_RENAME_STAGE=$BATS_TEST_TMPDIR/stage
  mkdir -p "$KW_RENAME_STAGE"
  KW_RENAME_OLD_TUNNEL_TOKEN=$BATS_TEST_TMPDIR/old.token
  KW_RENAME_NEW_TUNNEL_TOKEN=$BATS_TEST_TMPDIR/new.token
  KW_RENAME_OLD_TUNNEL_UNIT=$BATS_TEST_TMPDIR/old.service
  KW_RENAME_NEW_TUNNEL_UNIT=$BATS_TEST_TMPDIR/new.service
  KW_RENAME_OLD_TUNNEL_SERVICE=kwvps-cloudflared-oldexamplecom.service
  KW_RENAME_NEW_TUNNEL_SERVICE=kwvps-cloudflared-newexamplecom.service
  KW_RENAME_TUNNEL_PRESENT=1
  KW_RENAME_TUNNEL_TOUCHED=0
  KW_RENAME_TUNNEL_WAS_ACTIVE=1
  KW_RENAME_TUNNEL_WAS_ENABLED=1
  printf 'test-token-not-real\n' > "$KW_RENAME_OLD_TUNNEL_TOKEN"
  chmod 0600 "$KW_RENAME_OLD_TUNNEL_TOKEN"
  printf 'old unit\n' > "$KW_RENAME_OLD_TUNNEL_UNIT"
  cp -p "$KW_RENAME_OLD_TUNNEL_TOKEN" "$KW_RENAME_STAGE/tunnel-token"
  cp -p "$KW_RENAME_OLD_TUNNEL_UNIT" "$KW_RENAME_STAGE/tunnel-unit"
  kw_tunnel_render_site_unit newexamplecom > "$KW_RENAME_STAGE/new-tunnel-unit"
  chmod 0644 "$KW_RENAME_STAGE/new-tunnel-unit"
  systemctl() {
    [[ $1 != cat ]] || return 1
    printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/systemctl.log"
  }
  sleep() { :; }
  kw_tunnel_site_service_owned() { [[ $1 == new.example.com && -f $KW_RENAME_NEW_TUNNEL_UNIT ]]; }
  kw_tunnel_site_token_safe() { [[ $1 == new.example.com && -f $KW_RENAME_NEW_TUNNEL_TOKEN ]]; }

  kw_site_rename_tunnel_migrate new.example.com
  [ "$KW_RENAME_TUNNEL_TOUCHED" -eq 1 ]
  [ ! -e "$KW_RENAME_OLD_TUNNEL_UNIT" ]
  [ ! -e "$KW_RENAME_OLD_TUNNEL_TOKEN" ]
  [ "$(< "$KW_RENAME_NEW_TUNNEL_TOKEN")" = test-token-not-real ]
  grep -Fq 'newexamplecom.token' "$KW_RENAME_NEW_TUNNEL_UNIT"
  grep -Fq 'disable --now kwvps-cloudflared-oldexamplecom.service' "$BATS_TEST_TMPDIR/systemctl.log"
  grep -Fq 'start kwvps-cloudflared-newexamplecom.service' "$BATS_TEST_TMPDIR/systemctl.log"

  kw_site_rename_tunnel_rollback
  [ ! -e "$KW_RENAME_NEW_TUNNEL_UNIT" ]
  [ ! -e "$KW_RENAME_NEW_TUNNEL_TOKEN" ]
  [ "$(< "$KW_RENAME_OLD_TUNNEL_TOKEN")" = test-token-not-real ]
  [ "$(< "$KW_RENAME_OLD_TUNNEL_UNIT")" = 'old unit' ]
  grep -Fq 'restart kwvps-cloudflared-oldexamplecom.service' "$BATS_TEST_TMPDIR/systemctl.log"
}
