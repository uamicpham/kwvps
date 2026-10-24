#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/laravel.sh
}

@test "Laravel deploy leaves root-only cwd before invoking the site user" {
  local vhost="$BATS_TEST_TMPDIR/vhost.conf" enabled="$BATS_TEST_TMPDIR/enabled.conf"
  printf '# test vhost\n' > "$vhost"
  ln -s "$vhost" "$enabled"
  kw_laravel_layout_ready() {
    KW_SITE_ROOT="$BATS_TEST_TMPDIR/site"
    KW_SITE_OWNER=kwexamplecom
    KW_SITE_PHP=8.3
    KW_SITE_VHOST="$vhost"
    KW_SITE_ENABLED="$enabled"
  }
  kw_laravel_git_source() { :; }
  kw_nginx_ready() { :; }
  kw_has() { :; }
  kw_laravel_vhost_kind() { KW_LARAVEL_VHOST_KIND=http; KW_LARAVEL_FIRST=1; }
  kw_laravel_env_safe() { :; }
  stat() {
    if [[ $1 == -c && $2 == %u && $4 == "$vhost" ]]; then
      printf '0\n'
    else
      command stat "$@"
    fi
  }
  runuser() {
    if [[ $PWD == / ]]; then
      printf 'SAFE_CWD:%s\n' "$PWD" >&2
    else
      printf 'UNSAFE_CWD:%s\n' "$PWD" >&2
    fi
    return 33
  }
  mkdir -p "$BATS_TEST_TMPDIR/root-only"
  chmod 0700 "$BATS_TEST_TMPDIR/root-only"
  cd "$BATS_TEST_TMPDIR/root-only"

  run kw_laravel_deploy_locked example.com none
  [ "$status" -eq 2 ]
  [[ "$output" == *'SAFE_CWD:/'* ]]
  [[ "$output" != *UNSAFE_CWD* ]]
}
