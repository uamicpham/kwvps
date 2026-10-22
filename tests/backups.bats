#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/system.sh
  source src/sites.sh
  source src/backups.sh
}

@test "source backup plan is read-only and documents exclusions" {
  kw_site_lookup() {
    KW_SITE_OWNER=kw123456789abc
    KW_SITE_ROOT=/var/www/kwvps/123456789abc
    KW_SITE_PUBLIC="$KW_SITE_ROOT/public"
  }
  run kw_backup_source_plan ExAmPlE.com
  [ "$status" -eq 0 ]
  [[ "$output" == *'Domain: example.com'* ]]
  [[ "$output" == *'source-123456789abc-'* ]]
  [[ "$output" == *'không gồm database'* ]]
}

@test "source archive includes public content and rejects symlink root" {
  mkdir -p "$BATS_TEST_TMPDIR/site/public"
  printf 'test content\n' > "$BATS_TEST_TMPDIR/site/public/index.txt"
  run kw_backup_archive_create "$BATS_TEST_TMPDIR/site" "$BATS_TEST_TMPDIR/source.tar.gz"
  [ "$status" -eq 0 ]
  run tar -xOf "$BATS_TEST_TMPDIR/source.tar.gz" public/index.txt
  [ "$status" -eq 0 ]
  [ "$output" = 'test content' ]
  mv "$BATS_TEST_TMPDIR/site/public" "$BATS_TEST_TMPDIR/site/content"
  ln -s "$BATS_TEST_TMPDIR/site/content" "$BATS_TEST_TMPDIR/site/public"
  run kw_backup_archive_create "$BATS_TEST_TMPDIR/site" "$BATS_TEST_TMPDIR/should-not-exist.tar.gz"
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/should-not-exist.tar.gz" ]
}

@test "source backup requires exact domain confirmation before any write" {
  run kw_backup_source example.com wrong.example.com
  [ "$status" -eq 2 ]
  [[ "$output" == *'Xác nhận domain không khớp'* ]]
}

@test "backup verifier rejects path traversal before filesystem access" {
  run kw_backup_verify '../../etc/shadow'
  [ "$status" -eq 2 ]
  [[ "$output" == *'Cần sudo/root'* || "$output" == *'Tên backup không hợp lệ'* ]]
}

@test "safe source extractor accepts regular files and refuses symlinks" {
  mkdir -p "$BATS_TEST_TMPDIR/site/public" "$BATS_TEST_TMPDIR/stage"
  printf 'hello\n' > "$BATS_TEST_TMPDIR/site/public/index.txt"
  tar -C "$BATS_TEST_TMPDIR/site" -czf "$BATS_TEST_TMPDIR/good.tar.gz" public
  run python3 scripts/restore_source.py "$BATS_TEST_TMPDIR/good.tar.gz" "$BATS_TEST_TMPDIR/stage"
  [ "$status" -eq 0 ]
  [ "$(< "$BATS_TEST_TMPDIR/stage/public/index.txt")" = hello ]
  ln -s /etc/passwd "$BATS_TEST_TMPDIR/site/public/passwd"
  tar -C "$BATS_TEST_TMPDIR/site" -czf "$BATS_TEST_TMPDIR/bad.tar.gz" public
  mkdir "$BATS_TEST_TMPDIR/reject"
  run python3 scripts/restore_source.py "$BATS_TEST_TMPDIR/bad.tar.gz" "$BATS_TEST_TMPDIR/reject"
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/reject/public/passwd" ]
}

@test "backup creation refuses source trees with links it cannot restore" {
  mkdir -p "$BATS_TEST_TMPDIR/site/public"
  ln -s /etc/passwd "$BATS_TEST_TMPDIR/site/public/passwd"
  run kw_backup_archive_create "$BATS_TEST_TMPDIR/site" "$BATS_TEST_TMPDIR/source.tar.gz"
  [ "$status" -eq 1 ]
  [[ "$output" == *'không thể khôi phục an toàn'* ]]
}

@test "source restore rejects a backup from another site" {
  kw_site_lookup() { KW_SITE_OWNER=kw123456789abc; }
  run kw_restore_source_plan example.com source-aaaaaaaaaaaa-20261021T010203Z-AbCd1234.tar.gz
  [ "$status" -eq 2 ]
  [[ "$output" == *'không thuộc site'* ]]
}
