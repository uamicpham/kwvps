#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/system.sh
  source src/updates.sh
  source src/menu.sh
}

@test "service update needs exact confirmation before apt access" {
  run kw_update_service_apply WRONG
  [ "$status" -eq 2 ]
}

@test "simulation rejects removal and upgrades outside the selected packages" {
  KW_UPDATE_PACKAGES=(nginx)
  apt-get() { printf '%s\n' 'Inst nginx [1] (2)' 'Remv mariadb-server [1]'; }
  run kw_update_service_simulate
  [ "$status" -eq 2 ]
  apt-get() { printf '%s\n' 'Inst nginx [1] (2)' 'Inst libc6 [1] (2)'; }
  run kw_update_service_simulate
  [ "$status" -eq 2 ]
}

@test "simulation accepts only explicitly selected upgrades" {
  KW_UPDATE_PACKAGES=(nginx php8.3-fpm)
  apt-get() { printf '%s\n' 'Inst nginx [1] (2)' 'Inst php8.3-fpm [1] (2)'; }
  run kw_update_service_simulate
  [ "$status" -eq 0 ]
  [[ "$output" == *'Inst nginx'* ]]
}

@test "Ubuntu update needs exact confirmation before apt access" {
  run kw_update_ubuntu_apply WRONG
  [ "$status" -eq 2 ]
}

@test "Ubuntu update simulation rejects any removal" {
  apt-get() { printf '%s\n' 'Inst nginx [1] (2)' 'Remv mariadb-server [1]'; }
  run kw_update_ubuntu_simulate
  [ "$status" -eq 2 ]
}

@test "Ubuntu update simulation reports no scheduled upgrades" {
  apt-get() { printf '%s\n' '0 upgraded, 0 newly installed, 0 to remove'; }
  run kw_update_ubuntu_simulate
  [ "$status" -eq 0 ]
  [[ "$output" == *'Không có package nào'* ]]
}

@test "KwVPS update menu exposes verified GitHub releases and local fallback" {
  run kw_catalog update
  [ "$status" -eq 0 ]
  [[ "$output" == *'Kiểm tra / cập nhật KwVPS|kwvps-update'* ]]
  [[ "$output" == *'Cấu hình GitHub repository|github-repo'* ]]
  [ "$KW_UPDATE_BUNDLE" = /root/kwvps-update ]
}

@test "GitHub repository accepts only an owner and repository name" {
  run kw_github_repo_valid owner/kwvps
  [ "$status" -eq 0 ]
  run kw_github_repo_valid '../other/repo'
  [ "$status" -ne 0 ]
  run kw_github_repo_valid 'owner/repo;id'
  [ "$status" -ne 0 ]
  run kw_github_repo_valid 'owner/repo/extra'
  [ "$status" -ne 0 ]
}

@test "GitHub release API requires a stable tag and SHA-256 asset digest" {
  kw_github_repo_read() { KW_GITHUB_REPO=owner/kwvps; }
  test_digest=$(printf '%064d' 0)
  curl() { printf '{"tag_name":"v1.2.3","assets":[{"name":"kwvps-1.2.3.tar.gz","digest":"sha256:%s"}]}' "$test_digest"; }
  run kw_github_release_info
  [ "$status" -eq 0 ]
  curl() { printf '{"tag_name":"v1.2.3","assets":[{"name":"kwvps-1.2.3.tar.gz"}]}'; }
  run kw_github_release_info
  [ "$status" -eq 2 ]
  curl() { printf '{"tag_name":"v1.2.3-dev","assets":[]}'; }
  run kw_github_release_info
  [ "$status" -eq 2 ]
}

@test "release archive rejects symlinks before extraction" {
  mkdir -p "$BATS_TEST_TMPDIR/kwvps"
  printf 'test\n' > "$BATS_TEST_TMPDIR/kwvps/kwvps"
  tar -czf "$BATS_TEST_TMPDIR/good.tar.gz" -C "$BATS_TEST_TMPDIR" kwvps
  run kw_github_archive_safe "$BATS_TEST_TMPDIR/good.tar.gz"
  [ "$status" -eq 0 ]
  ln -s /etc/passwd "$BATS_TEST_TMPDIR/kwvps/link"
  tar -czf "$BATS_TEST_TMPDIR/bad.tar.gz" -C "$BATS_TEST_TMPDIR" kwvps
  run kw_github_archive_safe "$BATS_TEST_TMPDIR/bad.tar.gz"
  [ "$status" -eq 2 ]
}
