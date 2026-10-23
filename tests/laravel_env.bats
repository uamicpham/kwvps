#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/sites.sh
  source src/laravel.sh
  mkdir -p "$BATS_TEST_TMPDIR/site/deploy/shared"
}

@test "Laravel .env policy accepts only a private regular file owned by the site" {
  local env_file="$BATS_TEST_TMPDIR/site/deploy/shared/.env" owner
  owner=$(id -un)
  printf 'APP_KEY=keep-secret\n' > "$env_file"
  chmod 0600 "$env_file"

  kw_laravel_env_safe "$env_file" "$owner"
  ! kw_laravel_env_safe "$env_file" a_different_site_owner

  chmod 0644 "$env_file"
  ! kw_laravel_env_safe "$env_file" "$owner"
  chmod 0600 "$env_file"

  ln "$env_file" "$BATS_TEST_TMPDIR/second-hardlink"
  ! kw_laravel_env_safe "$env_file" "$owner"
}

@test "Laravel .env policy never follows a symlink" {
  local env_file="$BATS_TEST_TMPDIR/site/deploy/shared/.env" owner
  owner=$(id -un)
  printf 'DO_NOT_TOUCH=1\n' > "$BATS_TEST_TMPDIR/outside"
  chmod 0600 "$BATS_TEST_TMPDIR/outside"
  ln -s "$BATS_TEST_TMPDIR/outside" "$env_file"

  ! kw_laravel_env_safe "$env_file" "$owner"
  [ "$(< "$BATS_TEST_TMPDIR/outside")" = DO_NOT_TOUCH=1 ]
}

@test "Laravel .env prepare keeps an unsafe file unchanged when repair is declined" {
  local env_file="$BATS_TEST_TMPDIR/site/deploy/shared/.env"
  KW_SITE_ROOT="$BATS_TEST_TMPDIR/site"
  KW_SITE_OWNER=$(id -un)
  kw_laravel_layout_ready() { :; }
  printf 'APP_KEY=keep-secret\n' > "$env_file"
  chmod 0644 "$env_file"

  run kw_laravel_env_prepare example.com <<< 'n'
  [ "$(stat -c %a -- "$env_file")" = 644 ]
  [ "$(< "$env_file")" = APP_KEY=keep-secret ]
  [[ "$output" != *'APP_KEY=keep-secret'* ]]
}

@test "Laravel .env prepare repairs the selected file mode without changing its contents" {
  local env_file="$BATS_TEST_TMPDIR/site/deploy/shared/.env"
  KW_SITE_ROOT="$BATS_TEST_TMPDIR/site"
  KW_SITE_OWNER=$(id -un)
  kw_laravel_layout_ready() { :; }
  printf 'APP_KEY=keep-secret\n' > "$env_file"
  chmod 0644 "$env_file"

  run kw_laravel_env_prepare example.com <<< 'y'
  [ "$status" -eq 0 ]
  [ "$(stat -c %a -- "$env_file")" = 600 ]
  [ "$(< "$env_file")" = APP_KEY=keep-secret ]
  [[ "$output" != *'APP_KEY=keep-secret'* ]]
}

@test "Laravel .env prepare rejects a symlink without modifying its target" {
  local env_file="$BATS_TEST_TMPDIR/site/deploy/shared/.env"
  KW_SITE_ROOT="$BATS_TEST_TMPDIR/site"
  KW_SITE_OWNER=$(id -un)
  kw_laravel_layout_ready() { :; }
  printf 'APP_KEY=outside\n' > "$BATS_TEST_TMPDIR/outside"
  chmod 0644 "$BATS_TEST_TMPDIR/outside"
  ln -s "$BATS_TEST_TMPDIR/outside" "$env_file"

  run kw_laravel_env_prepare example.com <<< 'y'
  [ "$status" -ne 0 ]
  [ -L "$env_file" ]
  [ "$(stat -c %a -- "$BATS_TEST_TMPDIR/outside")" = 644 ]
  [ "$(< "$BATS_TEST_TMPDIR/outside")" = APP_KEY=outside ]
}

@test "Laravel .env prepare refuses a hardlinked file even after confirmation" {
  local env_file="$BATS_TEST_TMPDIR/site/deploy/shared/.env"
  KW_SITE_ROOT="$BATS_TEST_TMPDIR/site"
  KW_SITE_OWNER=$(id -un)
  kw_laravel_layout_ready() { :; }
  printf 'APP_KEY=hardlink\n' > "$env_file"
  chmod 0644 "$env_file"
  ln "$env_file" "$BATS_TEST_TMPDIR/second-hardlink"

  run kw_laravel_env_prepare example.com <<< 'y'
  [ "$status" -ne 0 ]
  [ "$(stat -c %a -- "$env_file")" = 644 ]
  [ "$(< "$BATS_TEST_TMPDIR/second-hardlink")" = APP_KEY=hardlink ]
}

@test "Laravel fd repair adopts a root-owned .env without changing its contents" {
  local env_file="$BATS_TEST_TMPDIR/site/deploy/shared/.env" owner
  owner=$(id -un)
  if [[ $EUID -eq 0 ]] || ! command -v sudo >/dev/null || ! sudo -n true >/dev/null 2>&1; then
    skip 'Needs an unprivileged test user with passwordless sudo'
  fi
  printf 'APP_KEY=keep-secret\n' > "$env_file"
  sudo -n chown root:root -- "$env_file"
  sudo -n chmod 0644 -- "$env_file"

  run sudo -n bash -c \
    'source "$1/src/core.sh"; source "$1/src/laravel.sh"; kw_laravel_env_repair_fd "$2" "$3"' \
    _ "$PWD" "$BATS_TEST_TMPDIR/site" "$owner"
  [ "$status" -eq 0 ]
  [ "$(stat -c '%u:%a:%h' -- "$env_file")" = "$(id -u):600:1" ]
  [ "$(< "$env_file")" = APP_KEY=keep-secret ]
  [[ "$output" != *'APP_KEY=keep-secret'* ]]
}

@test "Laravel deploy applies the same .env policy before touching Git" {
  local vhost="$BATS_TEST_TMPDIR/vhost.conf" enabled="$BATS_TEST_TMPDIR/enabled.conf"
  printf '# test vhost\n' > "$vhost"
  ln -s "$vhost" "$enabled"
  kw_laravel_layout_ready() {
    KW_SITE_ROOT="$BATS_TEST_TMPDIR/site"
    KW_SITE_OWNER=$(id -un)
    KW_SITE_PHP=8.3
    KW_SITE_VHOST="$vhost"
    KW_SITE_ENABLED="$enabled"
  }
  kw_laravel_git_source() { :; }
  kw_nginx_ready() { :; }
  kw_has() { :; }
  kw_laravel_vhost_kind() { KW_LARAVEL_VHOST_KIND=http; KW_LARAVEL_FIRST=1; }
  stat() {
    if [[ $1 == -c && $2 == %u && $4 == "$vhost" ]]; then
      printf '0\n'
    else
      command stat "$@"
    fi
  }
  kw_laravel_env_safe() {
    printf 'POLICY_CHECK:%s:%s\n' "$1" "$2"
    return 1
  }
  git() { printf 'UNEXPECTED_GIT\n'; return 99; }

  run kw_laravel_deploy_locked example.com none
  [ "$status" -eq 2 ]
  [[ "$output" == *"POLICY_CHECK:$BATS_TEST_TMPDIR/site/deploy/shared/.env:"* ]]
  [[ "$output" != *UNEXPECTED_GIT* ]]
}
