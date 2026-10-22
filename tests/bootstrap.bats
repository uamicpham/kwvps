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
    'if [[ " $* " == *" -o "* ]]; then' \
    '  while (($#)); do if [[ $1 == -o ]]; then cp -- "$KW_TEST_ARCHIVE" "$2"; exit; fi; shift; done' \
    'fi' \
    'printf '\''{"tag_name":"v1.2.3","assets":[{"name":"kwvps-1.2.3.tar.gz","digest":"sha256:%s"}]} '\'' "$KW_TEST_DIGEST"' \
    > "$BATS_TEST_TMPDIR/bin/curl"
  chmod 0755 "$BATS_TEST_TMPDIR/bin/curl"
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
