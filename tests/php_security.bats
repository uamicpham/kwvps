#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/php.sh
  source src/menu.sh
}

@test "critical October 2026 upstream PHP versions require fixed patch level" {
  kw_php_package_version_safe 8.5 8.5.12-1
  kw_php_package_version_safe 8.4 1:8.4.27-1+ubuntu24.04
  kw_php_package_version_safe 8.3 8.3.36-1
  ! kw_php_package_version_safe 8.5 8.5.11-1
  ! kw_php_package_version_safe 8.4 8.4.26-1
  ! kw_php_package_version_safe 8.3 8.3.35-1
  ! kw_php_package_version_safe 8.5 1:8.5.12~rc1-1
  ! kw_php_package_version_safe 8.4 1:8.4.27~rc1-1
  ! kw_php_package_version_safe 8.3 1:8.3.36~rc1-1
}

@test "Ubuntu 24.04 security backport is accepted without misreading upstream 8.3.6" {
  kw_php_package_version_safe 8.3 8.3.6-0ubuntu0.24.04.13
  ! kw_php_package_version_safe 8.3 8.3.6-0ubuntu0.24.04.12
  ! kw_php_package_version_safe 8.3 8.3.6-0ubuntu0.22.04.99
}

@test "PHP 7.4 and package/version mismatch fail closed" {
  ! kw_php_package_version_safe 7.4 1:7.4.33-99+ubuntu24.04.1+deb.sury.org+1
  ! kw_php_package_version_safe 8.4 8.5.12-1
  ! kw_php_package_version_safe 8.5 '8.5.12;id'
}

@test "PHP 7.4 may attach to a site only after a visible EOL acknowledgement" {
  kw_php_version_installed() { [[ $1 == 7.4 ]]; }
  KW_PHP_EOL_SITE_ACK=0
  ! kw_php_site_ready 7.4
  KW_PHP_EOL_SITE_ACK=1
  kw_php_site_ready 7.4
  ! kw_php_package_version_safe 7.4 1:7.4.33-99+ubuntu24.04.1+deb.sury.org+1
}

@test "APT candidate parser handles missing package without installing anything" {
  apt-cache() { printf 'php8.4-fpm:\n  Installed: (none)\n  Candidate: (none)\n'; }
  ! kw_php_apt_candidate 8.4
  apt-cache() { printf 'php8.4-fpm:\n  Installed: (none)\n  Candidate: 8.4.27-1+ubuntu24.04\n'; }
  kw_php_apt_candidate 8.4
  [ "$KW_PHP_APT_CANDIDATE" = 8.4.27-1+ubuntu24.04 ]
}

@test "candidate provenance accepts Ubuntu official mirrors and Ondrej Launchpad" {
  apt-cache() {
    printf 'php8.3-fpm | 8.3.6-0ubuntu0.24.04.13 | http://nova.clouds.archive.ubuntu.com/ubuntu noble-updates/universe amd64 Packages\n'
    printf 'php8.3-fpm | 8.3.6-0ubuntu0.24.04.13 | http://security.ubuntu.com/ubuntu noble-security/universe amd64 Packages\n'
    printf 'php8.4-fpm | 8.4.27-1+ubuntu24.04 | https://ppa.launchpadcontent.net/ondrej/php/ubuntu noble/main amd64 Packages\n'
  }
  kw_php_candidate_provenance 8.3 8.3.6-0ubuntu0.24.04.13
  [ "$KW_PHP_APT_ORIGIN_KIND" = ubuntu ]
  kw_php_candidate_provenance 8.4 8.4.27-1+ubuntu24.04
  [ "$KW_PHP_APT_ORIGIN_KIND" = ondrej ]
  [[ $KW_PHP_APT_ORIGIN_URL == *'ppa.launchpadcontent.net/ondrej/php/ubuntu'* ]]
}

@test "candidate provenance rejects Debian, unknown mirrors and mixed Ubuntu/PPA ties" {
  apt-cache() { printf 'php8.4-fpm | 8.4.27-1 | https://deb.sury.org/php bookworm/main amd64 Packages\n'; }
  ! kw_php_candidate_provenance 8.4 8.4.27-1
  apt-cache() { printf 'php8.4-fpm | 8.4.27-1 | https://example.invalid/ubuntu noble/main amd64 Packages\n'; }
  ! kw_php_candidate_provenance 8.4 8.4.27-1
  apt-cache() {
    printf 'php8.4-fpm | 8.4.27-1 | https://ppa.launchpadcontent.net/ondrej/php/ubuntu noble/main amd64 Packages\n'
    printf 'php8.4-fpm | 8.4.27-1 | http://security.ubuntu.com/ubuntu noble-security/main amd64 Packages\n'
  }
  ! kw_php_candidate_provenance 8.4 8.4.27-1
}

@test "safe configured candidate needs no PPA; PHP 7.4 fallback is available only from Ondrej" {
  kw_php_apt_candidate() { KW_PHP_APT_CANDIDATE=8.5.12-1; }
  kw_php_candidate_provenance() { KW_PHP_APT_ORIGIN_KIND=ondrej; KW_PHP_APT_ORIGIN_URL=https://ppa.launchpadcontent.net/ondrej/php/ubuntu; }
  kw_php_ondrej_pin_matches() { return 0; }
  kw_php_ondrej_enable() { printf 'unexpected PPA call\n' >&2; return 99; }
  kw_php_prepare_candidate 8.5
  [ "$KW_PHP_APT_CANDIDATE" = 8.5.12-1 ]
  MOCK_74_PPA=0
  kw_php_apt_candidate() {
    [[ $MOCK_74_PPA == 1 ]] || return 1
    KW_PHP_APT_CANDIDATE=1:7.4.33-18+ubuntu24.04.1+deb.sury.org+1
  }
  kw_php_ondrej_enable() { MOCK_74_PPA=1; }
  kw_php_candidate_provenance() {
    [[ $MOCK_74_PPA == 1 ]] || return 2
    KW_PHP_APT_ORIGIN_KIND=ondrej
    KW_PHP_APT_ORIGIN_URL=https://ppa.launchpadcontent.net/ondrej/php/ubuntu
  }
  kw_php_prepare_candidate 7.4 <<< 'y'
  [ "$KW_PHP_APT_CANDIDATE" = '1:7.4.33-18+ubuntu24.04.1+deb.sury.org+1' ]
}

@test "already configured PPA needs y before adding low-priority pin and rechecks candidate" {
  MOCK_PIN_APPLIED=0
  kw_php_apt_candidate() { KW_PHP_APT_CANDIDATE=8.5.12-1; }
  kw_php_candidate_provenance() { KW_PHP_APT_ORIGIN_KIND=ondrej; KW_PHP_APT_ORIGIN_URL=https://ppa.launchpadcontent.net/ondrej/php/ubuntu; }
  kw_php_ondrej_pin_matches() { [[ $MOCK_PIN_APPLIED == 1 ]]; }
  kw_php_ondrej_pin_install() { MOCK_PIN_APPLIED=1; }
  kw_php_prepare_candidate 8.5 <<< 'y'
  [ "$MOCK_PIN_APPLIED" = 1 ]
  [ "$KW_PHP_APT_CANDIDATE" = 8.5.12-1 ]
  [[ $(kw_php_ondrej_pin_contents) == *'Pin-Priority: 100'* ]]
}

@test "adding Ondrej PPA needs y confirmation and refuses unsafe candidate" {
  kw_php_apt_candidate() { return 1; }
  kw_php_ondrej_enable() { printf 'unexpected PPA call\n' >&2; return 99; }
  run kw_php_prepare_candidate 8.4 <<< 'n'
  [ "$status" -ne 0 ]
  [[ "$output" != *'unexpected PPA call'* ]]
  kw_php_apt_candidate() { KW_PHP_APT_CANDIDATE=8.4.26-1; }
  kw_php_ondrej_enable() { return 0; }
  kw_php_candidate_provenance() { KW_PHP_APT_ORIGIN_KIND=ondrej; KW_PHP_APT_ORIGIN_URL=https://ppa.launchpadcontent.net/ondrej/php/ubuntu; }
  run kw_php_prepare_candidate 8.4 <<< 'y'
  [ "$status" -ne 0 ]
  [[ "$output" == *'chưa đạt ngưỡng vá'* ]]
}

@test "confirmed Ubuntu PPA fallback accepts only patched PHP and reports origin" {
  MOCK_PPA_ENABLED=0
  kw_php_apt_candidate() {
    [[ $MOCK_PPA_ENABLED == 1 ]] || return 1
    KW_PHP_APT_CANDIDATE=8.4.27-1+ubuntu24.04
  }
  kw_php_ondrej_enable() { MOCK_PPA_ENABLED=1; }
  kw_php_candidate_provenance() { KW_PHP_APT_ORIGIN_KIND=ondrej; KW_PHP_APT_ORIGIN_URL=https://ppa.launchpadcontent.net/ondrej/php/ubuntu; }
  kw_php_prepare_candidate 8.4 <<< 'y'
  [ "$MOCK_PPA_ENABLED" = 1 ]
  [ "$KW_PHP_APT_CANDIDATE" = 8.4.27-1+ubuntu24.04 ]
}

@test "php-common requirement parser keeps the highest minimum" {
  kw_php_common_requirement $'php8.5-common : Depends: php-common (>= 2:95~) but 2:93ubuntu2 is to be installed\nphp8.5-fpm : Depends: php-common (>= 2:96~) but 2:93ubuntu2 is to be installed'
  [ "$KW_PHP_COMMON_REQUIRED" = '2:96~' ]
  ! kw_php_common_requirement 'E: unrelated dependency failure'
}

@test "php-common selection uses a verified patched-enough Ondrej PPA version" {
  apt-cache() {
    printf 'php-common | 2:101~+ubuntu24.04.1+deb.sury.org+1 | https://ppa.launchpadcontent.net/ondrej/php/ubuntu noble/main amd64 Packages\n'
    printf 'php-common | 2:93ubuntu2 | http://nova.clouds.archive.ubuntu.com/ubuntu noble/main amd64 Packages\n'
  }
  kw_php_common_ppa_version 8.5 '2:95~'
  [ "$KW_PHP_COMMON_VERSION" = '2:101~+ubuntu24.04.1+deb.sury.org+1' ]
  [ "$KW_PHP_COMMON_ORIGIN_URL" = 'https://ppa.launchpadcontent.net/ondrej/php/ubuntu' ]
  ! kw_php_common_ppa_version 8.5 '2:102~'
}

@test "APT simulation adds pinned PPA php-common only after dependency failure and never removes packages" {
  KW_PHP_APT_ORIGIN_KIND=ondrej
  apt-get() {
    if [[ " $* " == *' php-common='* ]]; then
      printf 'Inst php-common (2:101~+ubuntu24.04.1+deb.sury.org+1)\nInst php8.5-fpm (8.5.12-1)\n'
    else
      printf 'php8.5-common : Depends: php-common (>= 2:95~) but 2:93ubuntu2 is to be installed\n' >&2
      return 100
    fi
  }
  kw_php_common_ppa_version() {
    KW_PHP_COMMON_VERSION='2:101~+ubuntu24.04.1+deb.sury.org+1'
    KW_PHP_COMMON_ORIGIN_URL='https://ppa.launchpadcontent.net/ondrej/php/ubuntu'
  }
  kw_php_simulate_install 8.5 'php8.5-fpm=8.5.12-1'
  [ "${KW_PHP_INSTALL_PACKAGES[0]}" = 'php-common=2:101~+ubuntu24.04.1+deb.sury.org+1' ]
  [ "$KW_PHP_INSTALL_PPA_COMMON" = '2:101~+ubuntu24.04.1+deb.sury.org+1' ]
  apt-get() { printf 'Remv php8.3-fpm\n'; }
  ! kw_php_simulate_install 8.5 'php8.5-fpm=8.5.12-1'
}

@test "PHP 7.4 Breaks conflict retries with verified PPA php-common" {
  KW_PHP_APT_ORIGIN_KIND=ondrej
  apt-get() {
    [[ " $* " == *' php-common='* ]] || {
      printf ' php-common : Breaks: php7.4-common but 1:7.4.33-31+ubuntu24.04.1+deb.sury.org+1 is to be installed\n' >&2
      return 100
    }
    printf 'Inst php-common (2:101~+ubuntu24.04.1+deb.sury.org+1)\nInst php7.4-fpm (1:7.4.33-31+ubuntu24.04.1+deb.sury.org+1)\n'
  }
  kw_php_common_ppa_version() {
    [ "$1" = 7.4 ] && [ -z "$2" ] || return 2
    KW_PHP_COMMON_VERSION='2:101~+ubuntu24.04.1+deb.sury.org+1'
    KW_PHP_COMMON_ORIGIN_URL='https://ppa.launchpadcontent.net/ondrej/php/ubuntu'
  }
  kw_php_simulate_install 7.4 'php7.4-fpm=1:7.4.33-31+ubuntu24.04.1+deb.sury.org+1'
  [ "${KW_PHP_INSTALL_PACKAGES[0]}" = 'php-common=2:101~+ubuntu24.04.1+deb.sury.org+1' ]
  apt-get() { printf 'E: unresolved conflict\n' >&2; return 100; }
  ! kw_php_simulate_install 7.4 'php7.4-fpm=1:7.4.33-31+ubuntu24.04.1+deb.sury.org+1'
  [ "${KW_PHP_INSTALL_PACKAGES[0]}" = 'php-common=2:101~+ubuntu24.04.1+deb.sury.org+1' ]
}

@test "unrelated PHP 7.4 APT conflict does not change php-common" {
  KW_PHP_APT_ORIGIN_KIND=ondrej
  apt-get() { printf 'E: unrelated dependency failure\n' >&2; return 100; }
  kw_php_common_ppa_version() { return 99; }
  ! kw_php_simulate_install 7.4 'php7.4-fpm=1:7.4.33-31+ubuntu24.04.1+deb.sury.org+1'
  [ -z "$KW_PHP_INSTALL_PPA_COMMON" ]
}

@test "PHP security menu is read-only and key-only SSH remains unavailable" {
  run kw_catalog php
  [ "$status" -eq 0 ]
  [[ "$output" == *'Kiểm tra bản vá PHP|php-security'* ]]
  run kw_catalog ssh
  [ "$status" -eq 0 ]
  [[ "$output" == *'Chỉ cho phép AuthKey|pending'* ]]
}

@test "ionCube menu is wired and rejects malformed checksums" {
  run kw_catalog php
  [ "$status" -eq 0 ]
  [[ "$output" == *'ionCube theo version|php-ioncube'* ]]
  kw_php_ioncube_digest_valid "$(printf 'a%.0s' {1..64})"
  ! kw_php_ioncube_digest_valid "$(printf 'g%.0s' {1..64})"
  ! kw_php_ioncube_digest_valid abc
}
