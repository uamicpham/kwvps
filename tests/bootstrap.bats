#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.." || return 1
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/release/kwvps"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "KwVPS 1.2.3\n"' > "$BATS_TEST_TMPDIR/release/kwvps/kwvps"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "INSTALLER_CHECKED:%s\n" "$1"' > "$BATS_TEST_TMPDIR/release/kwvps/install.sh"
  printf '%s\n' uamicpham/kwvps > "$BATS_TEST_TMPDIR/release/kwvps/release-repo"
  tar -czf "$BATS_TEST_TMPDIR/asset.tar.gz" -C "$BATS_TEST_TMPDIR/release" kwvps
  KW_TEST_ARCHIVE="$BATS_TEST_TMPDIR/asset.tar.gz"
  KW_TEST_DIGEST=$(sha256sum "$KW_TEST_ARCHIVE")
  KW_TEST_DIGEST=${KW_TEST_DIGEST%% *}
  export KW_TEST_ARCHIVE KW_TEST_DIGEST
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >> "$BATS_TEST_TMPDIR/curl-args"' \
    'if [[ " $* " == *" -o "* ]]; then' \
    '  while (($#)); do if [[ $1 == -o ]]; then cp -- "$KW_TEST_ARCHIVE" "$2"; exit; fi; shift; done' \
    'fi' \
    'tag=${KW_TEST_TAG:-v1.2.3}' \
    'printf '\''{"tag_name":"%s","assets":[{"name":"kwvps-%s.tar.gz","digest":"sha256:%s"}]} '\'' "$tag" "${tag#v}" "$KW_TEST_DIGEST"' \
    > "$BATS_TEST_TMPDIR/bin/curl"
  chmod 0755 "$BATS_TEST_TMPDIR/bin/curl"
}

@test "bootstrap pins the requested release endpoint" {
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash scripts/bootstrap-release.sh --check --release=v1.2.3
  [ "$status" -eq 0 ]
  [[ "$output" == *'INSTALLER_CHECKED:--check'* ]]
  grep -q '/releases/tags/v1.2.3' "$BATS_TEST_TMPDIR/curl-args"
}

@test "bootstrap rejects a mismatched release tag" {
  export KW_TEST_TAG=v9.9.9
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash scripts/bootstrap-release.sh --check --release=v1.2.3
  [ "$status" -eq 2 ]
  [[ "$output" == *'tag khác bản đã chọn'* ]]
  [[ "$output" != *'INSTALLER_CHECKED'* ]]
}

@test "bootstrap rejects malformed pinned tags before network access" {
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash scripts/bootstrap-release.sh --check --release=../../main
  [ "$status" -eq 2 ]
  [[ "$output" == *'Dùng: bash bootstrap-release.sh'* ]]
}

@test "bootstrap refuses an unsupported CPU before network access" {
  printf '%s\n' '#!/usr/bin/env bash' 'printf "aarch64\n"' > "$BATS_TEST_TMPDIR/bin/uname"
  chmod 0755 "$BATS_TEST_TMPDIR/bin/uname"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash scripts/bootstrap-release.sh --check --release=v1.2.3
  [ "$status" -eq 2 ]
  [[ "$output" == *'cần x86_64'* ]]
  [ ! -e "$BATS_TEST_TMPDIR/curl-args" ]
}

@test "installer preflight refuses an unsupported CPU" {
  printf '%s\n' '#!/usr/bin/env bash' 'printf "aarch64\n"' > "$BATS_TEST_TMPDIR/bin/uname"
  chmod 0755 "$BATS_TEST_TMPDIR/bin/uname"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash install.sh --check
  [ "$status" -ne 0 ]
  [[ "$output" == *'Kiến trúc này chưa được hỗ trợ; cần x86_64'* ]]
}

@test "installer wires root-only backup directory creation into new installs" {
  run bash install.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *'/var/backups/kwvps (root:root, quyền 0700)'* ]]
  grep -Fq 'if install_backup_preflight; then' install.sh
  grep -Fq 'install_backup_root || return 1' install.sh
  grep -Fq 'install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT"' install.sh
}

@test "APT candidate reader drains output without SIGPIPE under pipefail" {
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "php8.3-fpm:\n  Candidate: 8.3.6-0ubuntu0.24.04.13\n"' \
    "awk 'BEGIN { for (i=0; i<20000; i++) print \"tail\" }'" \
    > "$BATS_TEST_TMPDIR/bin/apt-cache"
  chmod 0755 "$BATS_TEST_TMPDIR/bin/apt-cache"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash -c \
    'set -Eeuo pipefail; source src/core.sh; kw_apt_candidate php8.3-fpm'
  [ "$status" -eq 0 ]
  [ "$output" = '8.3.6-0ubuntu0.24.04.13' ]
}

@test "APT candidate reader refuses a missing candidate" {
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "php8.3-fpm:\n  Candidate: (none)\n"' \
    > "$BATS_TEST_TMPDIR/bin/apt-cache"
  chmod 0755 "$BATS_TEST_TMPDIR/bin/apt-cache"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash -c \
    'set -Eeuo pipefail; source src/core.sh; kw_apt_candidate php8.3-fpm'
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "bootstrap validates the release and performs preflight without installing" {
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash scripts/bootstrap-release.sh --check
  [ "$status" -eq 0 ]
  [[ "$output" == *'Đã xác minh KwVPS 1.2.3'* ]]
  [[ "$output" == *'INSTALLER_CHECKED:--check'* ]]
}

@test "bootstrap refuses an asset with a wrong digest before executing installer" {
  KW_TEST_DIGEST=$(printf '%064d' 0)
  export KW_TEST_DIGEST
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash scripts/bootstrap-release.sh --check
  [ "$status" -eq 2 ]
  [[ "$output" == *'SHA-256 của gói không khớp'* ]]
  [[ "$output" != *'INSTALLER_CHECKED'* ]]
}

@test "bootstrap rejects unsupported arguments before network access" {
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash scripts/bootstrap-release.sh --invalid
  [ "$status" -eq 2 ]
  [[ "$output" == *'Dùng: bash bootstrap-release.sh'* ]]
}
