#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/sites.sh
  source src/laravel.sh
  source src/ssl.sh
  source src/menu.sh
  mkdir -p "$BATS_TEST_TMPDIR/site"
}

@test "Laravel action appears in site menu" {
  run kw_catalog sites
  [ "$status" -eq 0 ]
  [[ "$output" == *'Laravel theo site|@laravel'* ]]
  run kw_catalog laravel
  [ "$status" -eq 0 ]
  [[ "$output" == *'Chuẩn bị thư mục Laravel|site-laravel'* ]]
  [[ "$output" == *'Pull code|laravel-pull'* ]]
  [[ "$output" == *'Deploy release Laravel|laravel-deploy'* ]]
}

@test "generic Git input rejects credentials and command-like URL" {
  run kw_laravel_git_url_valid https://github.com/example/project.git
  [ "$status" -eq 0 ]
  run kw_laravel_git_url_valid git@github.com:example/project.git
  [ "$status" -eq 0 ]
  run kw_laravel_git_url_valid 'https://token@github.com/example/project.git'
  [ "$status" -ne 0 ]
  run kw_laravel_git_url_valid 'https://github.com/example/project.git?token=secret'
  [ "$status" -ne 0 ]
  run kw_laravel_branch_valid main
  [ "$status" -eq 0 ]
  run kw_laravel_branch_valid ../main
  [ "$status" -ne 0 ]
  run kw_laravel_frontend_valid pnpm
  [ "$status" -eq 0 ]
  run kw_laravel_frontend_valid 'pnpm;id'
  [ "$status" -ne 0 ]
}

@test "Laravel vhost keeps HTTP-01 on original public while serving current release" {
  run kw_laravel_render_vhost letsencrypt example.com examplecom
  [ "$status" -eq 0 ]
  [[ "$output" == *'root /var/www/kwvps/examplecom/deploy/current/public;'* ]]
  [[ "$output" == *'root /var/www/kwvps/examplecom/public;'* ]]
  [[ "$output" == *'# KwVPS Laravel release root'* ]]
}

@test "Laravel plan displays paths but does not create them" {
  kw_site_lookup() {
    KW_SITE_ROOT="$BATS_TEST_TMPDIR/site"
    KW_SITE_OWNER=kwexamplecom
  }
  run kw_site_laravel_plan example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/site/source"* ]]
  [[ "$output" == *"$BATS_TEST_TMPDIR/site/deploy/releases"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/site/source" ]
  [ ! -e "$BATS_TEST_TMPDIR/site/deploy" ]
}

@test "Laravel layout creates only private source and shared storage" {
  runuser() { shift 3; "$@"; }
  chown() { :; }
  stat() {
    if [[ $1 == -c && $2 == '%U:%a' ]]; then
      printf 'kwexamplecom:%s\n' "$(command stat -c %a -- "$4")"
    elif [[ $1 == -c && $2 == %G ]]; then
      printf 'www-data\n'
    else
      command stat "$@"
    fi
  }
  kw_site_laravel_create_layout "$BATS_TEST_TMPDIR/site" kwexamplecom
  [ -d "$BATS_TEST_TMPDIR/site/source" ]
  [ -d "$BATS_TEST_TMPDIR/site/deploy/releases" ]
  [ -d "$BATS_TEST_TMPDIR/site/deploy/shared/storage/app/public" ]
  [ -d "$BATS_TEST_TMPDIR/site/deploy/shared/storage/framework/cache/data" ]
  [ "$(command stat -c %a -- "$BATS_TEST_TMPDIR/site/deploy/shared/storage/app/public")" = 2750 ]
  [ ! -e "$BATS_TEST_TMPDIR/site/deploy/shared/.env" ]
  [ ! -e "$BATS_TEST_TMPDIR/site/deploy/current" ]
}

@test "Laravel layout refuses existing source without touching it" {
  mkdir "$BATS_TEST_TMPDIR/site/source"
  printf 'keep\n' > "$BATS_TEST_TMPDIR/site/source/file"
  run kw_site_laravel_create_layout "$BATS_TEST_TMPDIR/site" kwexamplecom
  [ "$status" -eq 2 ]
  [ "$(< "$BATS_TEST_TMPDIR/site/source/file")" = keep ]
  [ ! -e "$BATS_TEST_TMPDIR/site/deploy" ]
}

@test "Laravel layout rejects a symlink at the source path" {
  mkdir "$BATS_TEST_TMPDIR/elsewhere"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$BATS_TEST_TMPDIR/site/source"
  run kw_site_laravel_create_layout "$BATS_TEST_TMPDIR/site" kwexamplecom
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/site/deploy" ]
  [ -L "$BATS_TEST_TMPDIR/site/source" ]
}

@test "Laravel layout refuses to duplicate an older prefixed deploy" {
  mkdir "$BATS_TEST_TMPDIR/site/kenhgamez-deploy"
  run kw_site_laravel_create_layout "$BATS_TEST_TMPDIR/site" kwexamplecom
  [ "$status" -eq 2 ]
  [ -d "$BATS_TEST_TMPDIR/site/kenhgamez-deploy" ]
  [ ! -e "$BATS_TEST_TMPDIR/site/source" ]
  [ ! -e "$BATS_TEST_TMPDIR/site/deploy" ]
}

@test "Laravel layout removes only new empty directories after a failure" {
  runuser() {
    [[ ${*: -1} != */framework/views ]] || return 1
    shift 3
    "$@"
  }
  run kw_site_laravel_create_layout "$BATS_TEST_TMPDIR/site" kwexamplecom
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/site/source" ]
  [ ! -e "$BATS_TEST_TMPDIR/site/deploy" ]
}

@test "Laravel preparation requires exact site confirmation" {
  run kw_site_laravel_prepare example.com wrong.example.com
  [ "$status" -eq 2 ]
  [ ! -e "$BATS_TEST_TMPDIR/site/source" ]
}
