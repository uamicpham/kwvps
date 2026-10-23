#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/sites.sh
  source src/backups.sh
  source src/cloudflare.sh
  source src/config_backups.sh
}

@test "Cloudflare backup password requires at least sixteen characters" {
  kw_config_secret_password_valid 1234567890123456
  ! kw_config_secret_password_valid short
}

@test "Cloudflare zone manifest must have exactly one domain and Zone ID" {
  kw_config_zone_manifest_valid $'example.com\n0123456789abcdef0123456789abcdef'
  ! kw_config_zone_manifest_valid $'example.com\n0123456789abcdef0123456789abcdef\nother.com'
  ! kw_config_zone_manifest_valid $'example.com\n../../etc/shadow'
}

@test "configuration backup refuses an orphaned Cloudflare site token" {
  kw_cf_zone_cache_read() { return 1; }
  kw_cf_site_token_path() { printf '%s/site-token\n' "$BATS_TEST_TMPDIR"; }
  run kw_config_cloudflare_zone example.com
  [ "$status" -eq 1 ]
  printf '%s\n' cfut_123456789012345678901234567890 > "$BATS_TEST_TMPDIR/site-token"
  run kw_config_cloudflare_zone example.com
  [ "$status" -eq 2 ]
  rm -- "$BATS_TEST_TMPDIR/site-token"
  ln -s -- missing-target "$BATS_TEST_TMPDIR/site-token"
  run kw_config_cloudflare_zone example.com
  [ "$status" -eq 2 ]
}

@test "configuration checksum helper rejects altered encrypted sidecar" {
  printf 'encrypted-test\n' > "$BATS_TEST_TMPDIR/backup.cf.enc"
  checksum=$(sha256sum "$BATS_TEST_TMPDIR/backup.cf.enc")
  printf '%s  backup.cf.enc\n' "${checksum%% *}" > "$BATS_TEST_TMPDIR/backup.cf.enc.sha256"
  stat() { printf '0:600\n'; }
  kw_config_checksum_valid "$BATS_TEST_TMPDIR/backup.cf.enc"
  printf 'altered\n' >> "$BATS_TEST_TMPDIR/backup.cf.enc"
  ! kw_config_checksum_valid "$BATS_TEST_TMPDIR/backup.cf.enc"
}

@test "configuration backup names are narrowly validated" {
  kw_config_backup_name_valid config-example.com-20261023-083015.tar.gz
  kw_config_backup_name_valid config-example.com-20261023-083015-2.tar.gz
  kw_config_backup_name_valid config-examplecom-20261023-083015.tar.gz
  kw_config_backup_name_valid config-123456789abc-20261021T120000Z-Ab12Cd34.tar.gz
  ! kw_config_backup_name_valid config-a..com-20261023-083015.tar.gz
  ! kw_config_backup_name_valid config-example.com-20261023-083015-0.tar.gz
  ! kw_config_backup_name_valid ../../etc/shadow
  ! kw_config_backup_name_valid config-123456789abc-20261021T120000Z-Ab12Cd34.tar.gz/../x
}

@test "configuration restore limits new and old backups to their owning site" {
  kw_config_backup_matches_site config-example.com-20261023-083015.tar.gz example.com examplecom
  kw_config_backup_matches_site config-examplecom-20261023-083015.tar.gz example.com examplecom
  kw_config_backup_matches_site config-examplecom-20261023T083015Z-AbCd1234.tar.gz example.com examplecom
  ! kw_config_backup_matches_site config-other.com-20261023-083015.tar.gz example.com examplecom
  ! kw_config_backup_matches_site config-othercom-20261023-083015.tar.gz example.com examplecom
  ! kw_config_backup_matches_site config-othercom-20261023T083015Z-AbCd1234.tar.gz example.com examplecom
}

@test "configuration backup requires exact domain confirmation" {
  run kw_config_backup example.com wrong.example.com
  [ "$status" -eq 2 ]
}

@test "configuration restore requires exact domain and valid archive name" {
  run kw_config_restore example.com config-123456789abc-20261021T120000Z-Ab12Cd34.tar.gz wrong.example.com
  [ "$status" -eq 2 ]
  run kw_config_restore example.com ../../etc/shadow example.com
  [ "$status" -eq 2 ]
}
