#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/sites.sh
  source src/laravel.sh
  source src/php.sh
  source src/ssl.sh
  source src/menu.sh
  mkdir -p "$BATS_TEST_TMPDIR/site"
}

@test "Laravel tool list contains only missing commands" {
  kw_laravel_tool_ready() { [[ $1 == git || $1 == composer ]]; }
  kw_laravel_collect_missing_tools 8.3
  [ "${KW_LARAVEL_MISSING_TOOLS[0]}" = php-cli ]
  [[ " ${KW_LARAVEL_MISSING_TOOLS[*]} " == *' node-npm '* ]]
  [[ " ${KW_LARAVEL_MISSING_TOOLS[*]} " != *' git '* ]]
  [[ " ${KW_LARAVEL_MISSING_TOOLS[*]} " != *' composer '* ]]
}

@test "Laravel Node status rejects obsolete Node and accepts current even LTS" {
  kw_has() { [[ $1 == node || $1 == npm ]]; }
  npm() { printf '10.0.0\n'; }
  node() { printf 'v18.20.8\n'; }
  ! kw_laravel_node_ready
  node() { printf 'v22.11.0\n'; }
  ! kw_laravel_node_ready
  node() { printf 'v24.22.1\n'; }
  kw_laravel_node_ready
}

@test "Laravel status menu selects missing tool by number and returns with zero" {
  kw_laravel_status() { KW_SITE_PHP=8.3; printf 'STATUS\n'; }
  kw_laravel_collect_missing_tools() { KW_LARAVEL_MISSING_TOOLS=(git composer); }
  kw_laravel_install_tool() { printf 'SELECTED:%s\n' "$2"; }
  run kw_laravel_status_interactive example.com <<< $'2\n0'
  [ "$status" -eq 0 ]
  [[ "$output" == *' 1. Git'* ]]
  [[ "$output" == *' 2. Composer'* ]]
  [[ "$output" == *'SELECTED:composer'* ]]
  [[ "$output" != *'SELECTED:git'* ]]
}

@test "Laravel tool status is available before layout preparation" {
  kw_site_prompt_domain() { KW_SITE_CHOICE=example.com; }
  kw_laravel_layout_ready() { printf 'UNEXPECTED_LAYOUT_CHECK\n'; return 2; }
  kw_laravel_status_interactive() { printf 'STATUS_READY\n'; }
  run kw_laravel_interactive status
  [ "$status" -eq 0 ]
  [[ "$output" == *'STATUS_READY'* ]]
  [[ "$output" != *'UNEXPECTED_LAYOUT_CHECK'* ]]
}

@test "Laravel APT install refuses failed simulation" {
  apt-get() { printf 'E: impossible\n'; return 100; }
  run kw_laravel_apt_plan git 1.0
  [ "$status" -eq 2 ]
  [[ "$output" == *'APT không mô phỏng được'* ]]
}

@test "Laravel APT install cancellation never invokes package mutation" {
  kw_apt_candidate() { printf '1.0\n'; }
  kw_laravel_ubuntu_candidate_origin() { printf 'http://security.ubuntu.com/ubuntu\n'; }
  kw_laravel_apt_plan() { KW_LARAVEL_APT_PLAN='Inst git (1.0)'; }
  apt-get() { printf 'UNEXPECTED_INSTALL\n'; return 99; }
  run kw_laravel_apt_install_tool git 8.3 <<< 'n'
  [ "$status" -eq 0 ]
  [[ "$output" == *'Đã hủy.'* ]]
  [[ "$output" != *'UNEXPECTED_INSTALL'* ]]
}

@test "Laravel APT tool origin rejects untrusted repository" {
  apt-cache() { printf 'git | 1.0 | https://example.invalid/ubuntu noble/main amd64 Packages\n'; }
  ! kw_laravel_ubuntu_candidate_origin git 1.0
  apt-cache() { printf 'git | 1.0 | http://security.ubuntu.com/ubuntu noble-security/main amd64 Packages\n'; }
  run kw_laravel_ubuntu_candidate_origin git 1.0
  [ "$status" -eq 0 ]
  [ "$output" = http://security.ubuntu.com/ubuntu ]
}

@test "Laravel Node candidate requires NodeSource 24 origin" {
  kw_apt_candidate() { printf '24.22.1-1nodesource1\n'; }
  apt-cache() { printf 'nodejs | 24.22.1-1nodesource1 | https://deb.nodesource.com/node_24.x nodistro/main amd64 Packages\n'; }
  kw_laravel_nodesource_candidate
  [ "$KW_LARAVEL_NODE_CANDIDATE" = 24.22.1-1nodesource1 ]
  apt-cache() { printf 'nodejs | 24.22.1-1nodesource1 | https://example.invalid/node_24.x nodistro/main amd64 Packages\n'; }
  ! kw_laravel_nodesource_candidate
}

@test "isolated NodeSource candidate reads a long APT policy under pipefail" {
  set -o pipefail
  KW_LARAVEL_NODE_APT_OPTS=()
  apt-cache() {
    case "$1" in
      policy)
        awk 'BEGIN {
          print "nodejs:";
          print "  Candidate: 24.22.1-1nodesource1";
          for (i=0; i<12000; i++) print "  24.22.1-1nodesource1 500"
        }'
        ;;
      madison)
        printf 'nodejs | 24.22.1-1nodesource1 | https://deb.nodesource.com/node_24.x nodistro/main amd64 Packages\n'
        ;;
      *) return 99 ;;
    esac
  }
  kw_laravel_nodesource_isolated_candidate
  [ "$KW_LARAVEL_NODE_CANDIDATE" = 24.22.1-1nodesource1 ]
}

@test "Laravel pnpm/Yarn installation waits for suitable Node" {
  kw_laravel_node_ready() { return 1; }
  npm() { printf 'UNEXPECTED_NPM\n'; return 99; }
  corepack() { printf 'UNEXPECTED_COREPACK\n'; return 99; }
  run kw_laravel_frontend_install pnpm
  [ "$status" -eq 2 ]
  [[ "$output" == *'Cần Node.js/npm phù hợp'* ]]
  [[ "$output" != *'UNEXPECTED_'* ]]
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
  kw_laravel_migrate_valid 0
  kw_laravel_migrate_valid 1
  ! kw_laravel_migrate_valid '1;id'
}

@test "Laravel migration is opt-in and rejects unexpected answers" {
  kw_laravel_migrate_prompt <<< ''
  [ "$KW_LARAVEL_MIGRATE" = 0 ]
  kw_laravel_migrate_prompt <<< 'y'
  [ "$KW_LARAVEL_MIGRATE" = 1 ]
  run kw_laravel_migrate_prompt <<< $'wrong\nn'
  [ "$status" -eq 0 ]
  [[ "$output" == *'Chỉ nhập y hoặc N.'* ]]
}

@test "Laravel deploy confirmation passes explicit migrate choice" {
  kw_prompt_yes_no_token() { return 0; }
  kw_laravel_with_lock() { printf 'ACTION:%s\n' "$*"; }
  run kw_laravel_deploy_confirm example.com auto 1
  [ "$status" -eq 0 ]
  [[ "$output" == *'ACTION:deploy example.com auto 1'* ]]
  [[ "$output" == *'rollback code không phục hồi database'* ]]
  run kw_laravel_deploy_confirm example.com auto 0
  [ "$status" -eq 0 ]
  [[ "$output" == *'ACTION:deploy example.com auto 0'* ]]
  run kw_laravel_deploy_confirm example.com auto '--migrate;id'
  [ "$status" -eq 2 ]
  [[ "$output" != *'ACTION:'* ]]
}

@test "Laravel migration runs with the site PHP/user and reports failure" {
  runuser() { printf 'RUN:%s\n' "$*"; }
  run kw_laravel_run_migrations kwexamplecom 8.3 /site/deploy/releases/new
  [ "$status" -eq 0 ]
  [[ "$output" == *'RUN:-u kwexamplecom -- php8.3 /site/deploy/releases/new/artisan migrate --force --no-interaction'* ]]
  runuser() { return 1; }
  run kw_laravel_run_migrations kwexamplecom 8.3 /site/deploy/releases/new
  [ "$status" -eq 1 ]
  [[ "$output" == *'Database có thể đã thay đổi một phần'* ]]
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
  runuser() {
    if [[ ${1:-} == -u && ${3:-} == -g && ${4:-} == www-data && ${5:-} == -- ]]; then
      shift 5
      "$@"
    elif [[ ${1:-} == -u && ${3:-} == -- ]]; then
      shift 3
      # Reproduce Linux dropping setgid when the site user is not in www-data.
      if [[ ${1:-} == chmod && ${2:-} == 2750 ]]; then
        command chmod 0750 -- "$4"
      else
        "$@"
      fi
    else
      return 2
    fi
  }
  chown() { :; }
  stat() {
    if [[ $1 == -c && $2 == '%U:%G' ]]; then
      printf 'kwexamplecom:www-data\n'
    elif [[ $1 == -c && $2 == '%U:%a' ]]; then
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
