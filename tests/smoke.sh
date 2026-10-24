#!/usr/bin/env bash
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
source src/core.sh
source src/system.sh
source src/updates.sh
source src/menu.sh
source src/sites.sh
source src/laravel.sh
source src/php.sh
source src/backups.sh
source src/config_backups.sh
source src/db.sh
source src/db_manage.sh
source src/rename.sh
source src/fail2ban.sh
source src/firewall.sh
source src/swap.sh
source src/nginx.sh
source src/acme.sh
source src/ssl.sh
source src/cloudflare.sh
source src/tunnel.sh
source src/ssh.sh
source src/cache.sh
source src/utilities.sh
source src/cron.sh
tests=0
assert() {
  "$@" || { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
  tests=$((tests + 1))
}
reject() {
  if "$@" >/dev/null 2>&1; then printf 'UNEXPECTED SUCCESS: %s\n' "$*" >&2; exit 1; fi
  tests=$((tests + 1))
}
for file in kwvps install.sh upgrade.sh scripts/kwvps-launcher scripts/bootstrap-release.sh scripts/package-release.sh src/*.sh tests/*.sh; do assert bash -n "$file"; done
assert kw_domain_valid example.com
assert kw_domain_valid sub.example.com
assert kw_domain_valid xn--bcher-kva.example
for domain in '-bad.com' 'bad-.com' 'a..com' '../etc/passwd' 'https://site.com' '127.0.0.1' 'x;touch bad.com'; do
  reject kw_domain_valid "$domain"
done
for port in 1 22 443 65535 00022; do assert kw_port_valid "$port"; done
for port in 0 65536 -1 abc '22;id' ''; do reject kw_port_valid "$port"; done
assert kw_service_package php8.3-fpm
assert kw_service_package mariadb-server
reject kw_service_package php8.3-cli
reject kw_service_package unrelated
reject kw_service_package 'nginx;id'
output=$(kw_memory /does-not-exist)
assert test "$output" = 'N/A | Swap: N/A'
# Fixtures via process substitution: no temporary files or system changes.
output=$(kw_memory <(printf 'MemTotal: 8192 kB\nMemAvailable: 3072 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n'))
assert test "$output" = '5/8 MB | Swap: 0/0 MB'
output=$(kw_os_field ID <(printf 'ID="ubuntu"\n'))
assert test "$output" = ubuntu
# shellcheck disable=SC2016 # Deliberate literal injection fixture.
output=$(kw_os_field ID <(printf '%s\n' 'ID="$(printf executed)"'))
# shellcheck disable=SC2016 # Compare against the literal unexecuted value.
assert test "$output" = '$(printf executed)'
output=$(kw_os_field ID <(printf 'NAME="Ubuntu"\nID=ubuntu\nID_LIKE=debian\n'))
assert test "$output" = ubuntu
reject kw_os_field ID <(printf 'ID_LIKE=ubuntu\n')
output=$(bash kwvps --version)
assert test "$output" = "KwVPS $KW_VERSION"
if [[ $(uname -s) == Linux && $EUID -ne 0 ]]; then
  output=$(bash kwvps menu </dev/null 2>&1) && { printf 'UNEXPECTED SUCCESS: unprivileged menu\n' >&2; exit 1; }
  assert grep -Fq 'sudo kwvps' <<< "$output"
fi
output=$(kw_catalog firewall)
assert grep -Fq 'Bật Firewall UFW|fw-enable' <<< "$output"
assert grep -Fq 'Tắt Firewall UFW|fw-disable' <<< "$output"
output=$(kw_catalog nginx)
assert grep -Fq 'Sửa vhost theo domain (nano)|nginx-vhost-custom' <<< "$output"
output=$(kw_catalog sites)
assert grep -Fq 'Laravel theo site|@laravel' <<< "$output"
output=$(kw_catalog laravel)
assert grep -Fq 'Chuẩn bị thư mục Laravel|site-laravel' <<< "$output"
assert grep -Fq 'Pull code|laravel-pull' <<< "$output"
assert grep -Fq 'Deploy release Laravel|laravel-deploy' <<< "$output"
assert kw_laravel_git_url_valid https://github.com/example/laravel-app.git
assert kw_laravel_git_url_valid git@github.com:example/laravel-app.git
reject kw_laravel_git_url_valid 'https://secret@github.com/example/laravel-app.git'
reject kw_laravel_git_url_valid 'https://github.com/example/laravel-app.git?token=x'
assert kw_laravel_branch_valid main
reject kw_laravel_branch_valid ../main
for laravel_frontend in auto none npm pnpm yarn; do assert kw_laravel_frontend_valid "$laravel_frontend"; done
reject kw_laravel_frontend_valid 'npm;id'
assert test "$(kw_laravel_apt_package php-cli 8.4)" = php8.4-cli
assert test "$(kw_laravel_tool_label php-cli 8.4)" = 'PHP 8.4 CLI'
laravel_node_fixture() (
  kw_has() { [[ $1 == node || $1 == npm ]]; }
  node() { printf 'v24.22.1\n'; }
  npm() { printf '10.0.0\n'; }
  kw_laravel_node_ready
)
assert laravel_node_fixture
laravel_old_node_fixture() (
  kw_has() { [[ $1 == node || $1 == npm ]]; }
  node() { printf 'v18.20.8\n'; }
  ! kw_laravel_node_ready
)
assert laravel_old_node_fixture
laravel_node_origin_fixture() (
  kw_apt_candidate() { printf '24.22.1-1nodesource1\n'; }
  apt-cache() { printf 'nodejs | 24.22.1-1nodesource1 | https://deb.nodesource.com/node_24.x nodistro/main amd64 Packages\n'; }
  kw_laravel_nodesource_candidate
  [[ $KW_LARAVEL_NODE_CANDIDATE == 24.22.1-1nodesource1 ]]
)
assert laravel_node_origin_fixture
laravel_bad_node_origin_fixture() (
  kw_apt_candidate() { printf '24.22.1-1nodesource1\n'; }
  apt-cache() { printf 'nodejs | 24.22.1-1nodesource1 | https://example.invalid/node_24.x nodistro/main amd64 Packages\n'; }
  ! kw_laravel_nodesource_candidate
)
assert laravel_bad_node_origin_fixture
laravel_isolated_node_fixture() (
  KW_LARAVEL_NODE_APT_OPTS=()
  apt-cache() {
    case "$1" in
      policy) printf 'nodejs:\n  Candidate: 24.22.1-1nodesource1\n' ;;
      madison) printf 'nodejs | 24.22.1-1nodesource1 | https://deb.nodesource.com/node_24.x nodistro/main amd64 Packages\n' ;;
      show) printf 'Package: nodejs\nVersion: 24.22.1-1nodesource1\nArchitecture: amd64\nSHA256: %064d\n\n' 0 ;;
      *) return 99 ;;
    esac
  }
  kw_laravel_nodesource_isolated_candidate || return 1
  [[ $KW_LARAVEL_NODE_CANDIDATE == 24.22.1-1nodesource1 ]] || return 1
  [[ $(kw_laravel_nodesource_isolated_hash "$KW_LARAVEL_NODE_CANDIDATE") == $(printf '%064d' 0) ]]
)
assert laravel_isolated_node_fixture
output=$(
  kw_laravel_status() { KW_SITE_PHP=8.3; printf 'STATUS\n'; }
  kw_laravel_collect_missing_tools() { KW_LARAVEL_MISSING_TOOLS=(git composer); }
  kw_laravel_install_tool() { printf 'SELECTED:%s\n' "$2"; }
  kw_laravel_status_interactive example.com <<< $'2\n0'
)
assert grep -Fq ' 1. Git' <<< "$output"
assert grep -Fq ' 2. Composer' <<< "$output"
assert grep -Fq 'SELECTED:composer' <<< "$output"
output=$(
  kw_site_prompt_domain() { KW_SITE_CHOICE=example.com; }
  kw_laravel_layout_ready() { :; }
  kw_laravel_interactive deploy <<< '0'
)
assert grep -Fq '1. Tự nhận từ lockfile (khuyến nghị)' <<< "$output"
assert grep -Fq '3. Chọn công cụ thủ công (nâng cao)' <<< "$output"
reject grep -Fq '5. yarn' <<< "$output"
assert_laravel_apt_cancel_fixture() (
  kw_apt_candidate() { printf '1.0\n'; }
  kw_laravel_ubuntu_candidate_origin() { printf 'http://security.ubuntu.com/ubuntu\n'; }
  kw_laravel_apt_plan() { KW_LARAVEL_APT_PLAN='Inst git (1.0)'; }
  apt-get() { printf 'UNEXPECTED_INSTALL\n'; return 99; }
  kw_laravel_apt_install_tool git 8.3 <<< 'n'
)
output=$(assert_laravel_apt_cancel_fixture)
assert grep -Fq 'Đã hủy.' <<< "$output"
reject grep -Fq 'UNEXPECTED_INSTALL' <<< "$output"
output=$(kw_laravel_render_vhost letsencrypt example.com examplecom)
assert grep -Fq 'root /var/www/kwvps/examplecom/deploy/current/public;' <<< "$output"
assert grep -Fq 'root /var/www/kwvps/examplecom/public;' <<< "$output"
for laravel_kind in http zerossl paid; do
  output=$(kw_laravel_render_vhost "$laravel_kind" example.com examplecom)
  assert grep -Fq 'root /var/www/kwvps/examplecom/deploy/current/public;' <<< "$output"
  assert grep -Fq 'root /var/www/kwvps/examplecom/public;' <<< "$output"
done
assert_tunnel_realip_overlay_fixture() (
  local stage
  stage=$(mktemp -d) || return 1
  trap 'rm -f -- "$stage"/*; rmdir -- "$stage"' EXIT
  kw_site_render_vhost example.com examplecom > "$stage/http"
  kw_cf_realip_vhost_overlay tunnel example.com examplecom "$stage/http" > "$stage/tunnel" || return 1
  grep -Fq 'set_real_ip_from 127.0.0.1;' "$stage/tunnel" || return 1
  grep -Fq 'include /etc/nginx/conf.d/kwvps-cloudflare-realip.conf;' "$stage/tunnel" || return 1
  kw_site_vhost_matches "$stage/tunnel" example.com examplecom kw_site_render_vhost example.com examplecom || return 1
  kw_cf_realip_vhost_overlay tunnel example.com examplecom "$stage/tunnel" > "$stage/again" || return 1
  cmp -s -- "$stage/tunnel" "$stage/again" || return 1
  kw_cf_realip_vhost_overlay dns example.com examplecom "$stage/tunnel" > "$stage/dns" || return 1
  cmp -s -- "$stage/http" "$stage/dns" || return 1
  ! grep -Fq 'set_real_ip_from 127.0.0.1;' "$stage/dns" || return 1
  kw_tunnel_site_mode() { printf 'tunnel\n'; }
  kw_cf_realip_public_config_valid() { :; }
  kw_site_render_vhost example.com examplecom |
    kw_cf_realip_render_for_site example.com examplecom > "$stage/rendered" || return 1
  cmp -s -- "$stage/tunnel" "$stage/rendered" || return 1
  kw_ssl_render_vhost example.com examplecom > "$stage/https"
  kw_cf_realip_vhost_overlay tunnel example.com examplecom "$stage/https" > "$stage/https-tunnel" || return 1
  [[ $(grep -Fc 'set_real_ip_from 127.0.0.1;' "$stage/https-tunnel") == 2 ]] || return 1
  kw_site_vhost_matches "$stage/https-tunnel" example.com examplecom kw_ssl_render_vhost example.com examplecom || return 1
  kw_laravel_render_vhost letsencrypt example.com examplecom > "$stage/laravel"
  kw_cf_realip_vhost_overlay tunnel example.com examplecom "$stage/laravel" > "$stage/laravel-tunnel" || return 1
  KW_SITE_VHOST="$stage/laravel-tunnel"
  kw_laravel_vhost_kind example.com examplecom || return 1
  [[ $KW_LARAVEL_VHOST_KIND == letsencrypt && $KW_LARAVEL_FIRST == 0 ]] || return 1
  printf '  real_ip_header X-Forwarded-For;\n' >> "$stage/https-tunnel"
  if kw_cf_realip_vhost_overlay tunnel example.com examplecom "$stage/https-tunnel" >/dev/null 2>&1; then return 1; fi
)
assert assert_tunnel_realip_overlay_fixture
output=$(
  temporary_vhost=$(mktemp)
  trap 'rm -f -- "$temporary_vhost"' EXIT
  KW_SITE_VHOST=$temporary_vhost
  KW_SITE_ROOT=/var/www/kwvps/examplecom
  KW_SITE_PUBLIC=$KW_SITE_ROOT/public
  KW_SITE_SOCKET=/run/php/kwvps-examplecom.sock
  kw_laravel_render_vhost letsencrypt example.com examplecom > "$temporary_vhost"
  kw_laravel_vhost_kind example.com examplecom
  kw_nginx_vhost_identity "$temporary_vhost" example.com examplecom
  printf '%s/%s' "$KW_LARAVEL_VHOST_KIND" "$KW_LARAVEL_FIRST"
)
assert test "$output" = 'letsencrypt/0'
output=$(
  kw_site_lookup() { KW_SITE_ROOT=/var/www/kwvps/examplecom; KW_SITE_OWNER=kwexamplecom; }
  kw_site_laravel_plan example.com
)
assert grep -Fq '/var/www/kwvps/examplecom/source' <<< "$output"
assert grep -Fq '/var/www/kwvps/examplecom/deploy/releases' <<< "$output"
reject kw_site_laravel_prepare example.com wrong.example.com
output=$(kw_pma_render_nginx)
assert grep -Fq 'listen 127.0.0.1:9080;' <<< "$output"
output=$(kw_pma_render_security)
assert grep -Fq "['AllowRoot'] = false;" <<< "$output"
reject kw_pma_install wrong
reject kw_pma_admin_set_password ValidPassword123 create wrong
reject bash kwvps --unknown
reject bash kwvps --status extra
reject kw_journal 'nginx;id'

# Inventory must filter the command output to packages supported by KwVPS.
output=$(
  kw_read_command() {
    [[ $1 == dpkg-query ]] || return 99
    printf 'nginx\tinstalled\t1.2\nphp8.3-fpm\tinstalled\t8.3\nphp8.3-cli\tinstalled\t8.3\nredis-server\tconfig-files\t7.0\n'
  }
  kw_packages
)
assert test "${output#*nginx}" != "$output"
assert test "${output#*php8.3-fpm}" != "$output"
assert test "${output#*php8.3-cli}" = "$output"
assert test "${output#*redis-server}" = "$output"
output=$(
  kw_read_command() {
    [[ $1 == apt ]] || return 99
    printf 'Listing...\nnginx/noble 1.3 amd64 [upgradable from: 1.2]\nphp8.3-cli/noble 8.4 amd64 [upgradable from: 8.3]\n'
  }
  kw_pending
)
assert test "${output#*nginx/noble}" != "$output"
assert test "${output#*php8.3-cli/noble}" = "$output"
output=$(printf '1\n3\n\n0\n18\n1\n2\n\n0\n0\n0\n' | bash kwvps --preview)
assert test "${output#*'Đổi tên miền'}" != "$output"
assert test "${output#*PREVIEW:}" != "$output"
assert test "${output#*AntiDDoS}" != "$output"
output=$(printf '999\n0\n' | bash kwvps --preview)
assert test "${output#*Lựa chọn không hợp lệ}" != "$output"
output=$(KW_PREVIEW=1; kw_menu php <<< 0)
assert test "${output#*'Cấu hình PHP pool từng site'}" != "$output"
assert test "${output#*'Disk:'}" = "$output"
output=$(kw_php_version_installed() { [[ $1 == 8.3 ]]; }; kw_php_security_ready() { [[ $1 == 8.3 ]]; }; kw_php_choose_version <<< 3; printf 'SELECTED=%s\n' "$KW_PHP_CHOICE")
assert test "${output#*'1. PHP 8.5'}" != "$output"
assert test "${output#*'2. PHP 8.4'}" != "$output"
assert test "${output#*'3. PHP 8.3'}" != "$output"
assert test "${output#*'4. PHP 7.4'}" != "$output"
assert test "${output#*'SELECTED=8.3'}" != "$output"
assert bash kwvps --preview </dev/null >/dev/null
assert bash install.sh --help >/dev/null
for page in main sites ssl ssh db php nginx fail2ban utilities cron cache swap firewall disk logs update service-update backup tunnel advanced cloudflare; do
  output=$(kw_catalog "$page")
  assert test -n "$output"
  while IFS='|' read -r title action; do
    assert test -n "$title"
    assert test -n "$action"
    case "$action" in
      @*) assert kw_catalog "${action#@}" >/dev/null ;;
      *) assert test "${action#*[!a-z0-9-]}" = "$action" ;;
    esac
  done <<< "$output"
done

assert kw_site_php_valid 8.3
assert kw_db_identifier_valid kenhgamez5
assert kw_db_user_valid kenhgamez_user
assert kw_db_password_valid 'Safe-pass_123!'
reject kw_db_identifier_valid 'name;DROP'
reject kw_db_password_valid "abc' OR 1=1 --"
assert kw_db_upload_valid kenhgamez5.sql.gz
reject kw_db_upload_valid ../../etc/passwd
reject kw_db_drop_named kenhgamez5 NO
output=$(
  kw_db_choose_upload() { KW_DB_UPLOAD_CHOICE=existing.sql.gz; }
  kw_db_choose_managed() { KW_DB_MANAGED_CHOICE=demo_db; }
  mariadb() { printf '3\n'; }
  # shellcheck disable=SC2030 # The mock value is consumed in this same subshell.
  kw_prompt_yes_no_token() { KW_PROMPT_VALUE=$2; }
  kw_db_import_uploaded() { printf 'IMPORTED:%s:%s\n' "$1" "$2"; }
  kw_db_import_uploaded_interactive <<< '1'
)
assert test "${output#*'đã có 3 bảng'}" != "$output"
assert test "${output#*'Import không tự export hiện trạng'}" != "$output"
assert test "${output#*'IMPORTED:existing.sql.gz:demo_db'}" != "$output"
output=$(declare -f kw_db_import_uploaded_locked)
assert test "${output#*kw_db_export_named_locked}" = "$output"
reject kw_site_php_valid '8.3;id'
reject kw_site_php_valid '../8.3'
reject kw_site_plan 'example.com;id' 8.3
reject kw_site_plan example.com '8.3;id'
site_id=$(kw_site_id example.com)
assert test "$site_id" = examplecom
assert kw_site_id_matches_domain kwvpskenhgameztop kwvps.kenhgamez.top
assert test "$(kw_site_id a.b.com)" = "$(kw_site_id ab.com)"
assert kw_site_id_matches_domain kwvpskenhgameztop kwvps.kenhgamez.top
reject kw_site_id_matches_domain otherid kwvps.kenhgamez.top
reject kw_site_id longlonglonglonglonglonglonglong.example.com
assert test "$site_id" = "$(kw_site_id EXAMPLE.COM)"
# shellcheck disable=SC2031 # Prompt value is set and consumed in the same command substitution.
prompt_result=$(kw_prompt_validated 'Mật khẩu: ' kw_db_password_valid \
  '12–128 ký tự' secret <<< $'short\nValidPass_123!' && printf 'OK:%s' "$KW_PROMPT_VALUE")
assert test "${prompt_result#*Giá trị không hợp lệ:}" != "$prompt_result"
assert test "${prompt_result##*OK:}" = ValidPass_123!
# shellcheck disable=SC2031 # Confirmation value is set and consumed in the same substitution.
confirm_result=$(kw_prompt_confirm_domain example.com 'Xác nhận: ' <<< $'wrong.com\nEXAMPLE.COM' &&
  printf 'OK:%s' "$KW_PROMPT_VALUE")
assert test "${confirm_result#*Giá trị không hợp lệ:}" != "$confirm_result"
assert test "${confirm_result##*OK:}" = EXAMPLE.COM
db_retry_output=$(
  kw_site_prompt_domain() { KW_SITE_CHOICE=example.com; }
  kw_db_custom_create() { printf 'CREATED:%s:%s\n' "$2" "$3"; }
  kw_db_custom_create_interactive <<< $'demo_db\ndemo_user\nshort\nValidPass_123!\ny'
)
assert test "${db_retry_output#*Giá trị không hợp lệ:}" != "$db_retry_output"
assert test "${db_retry_output##*CREATED:}" = demo_db:demo_user
site_retry_output=$(
  kw_php_choose_version() { KW_PHP_CHOICE=8.3; }
  kw_site_create() { printf 'CREATED:%s:%s\n' "$1" "$2"; }
  kw_site_add_interactive <<< $'bad domain\nexample.com\ny'
)
assert test "${site_retry_output#*Giá trị không hợp lệ:}" != "$site_retry_output"
assert test "${site_retry_output##*CREATED:}" = example.com:8.3
for version in 8.5 8.4 8.3 7.4; do assert kw_php_version_supported "$version"; done
reject kw_php_version_supported 8.2
reject kw_php_version_supported '8.3;id'
assert kw_php_pool_value_valid pm.max_children 128
reject kw_php_pool_value_valid pm.max_children 129
assert kw_php_pool_value_valid pm.max_requests 10000
reject kw_php_pool_value_valid pm.max_requests 10001
reject kw_php_switch example.com 8.4 wrong.example.com
reject kw_php_pool_tune example.com pm.max_children 6 wrong.example.com
output=$(kw_site_plan EXAMPLE.COM 8.3)
assert test "${output#*Domain: example.com}" != "$output"
assert test "${output#*"Site ID: $site_id"}" != "$output"
output=$(kw_site_render_pool "$site_id" "kw$site_id")
assert test "${output#*"[kwvps-$site_id]"}" != "$output"
assert test "${output#*"listen = /run/php/kwvps-$site_id.sock"}" != "$output"
output=$(kw_site_render_vhost example.com "$site_id")
assert test "${output#*'server_name example.com;'}" != "$output"
assert test "${output#*"fastcgi_pass unix:/run/php/kwvps-$site_id.sock;"}" != "$output"
assert test "${output#*'location ~ /\.'}" != "$output"
assert test "${output#*'location ^~ /.well-known/acme-challenge/'}" != "$output"
output=$(kw_ssl_render_vhost example.com "$site_id")
assert test "${output#*'listen 443 ssl;'}" != "$output"
assert test "${output#*'ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;'}" != "$output"
# shellcheck disable=SC2016 # Nginx variables are intentionally literal.
assert test "${output#*'return 301 https://$host$request_uri;'}" != "$output"
reject kw_ssl_issue example.com wrong.example.com
reject kw_backup_source example.com wrong-domain
assert kw_backup_basename_valid 'source-example.com-20261023-083015.tar.gz'
assert kw_backup_basename_valid 'source-example.com-20261023-083015-2.tar.gz'
assert kw_backup_basename_valid 'source-123456789abc-20261021T102500Z-Ab12Cd34.tar.gz'
assert kw_config_backup_name_valid 'config-example.com-20261023-083015.tar.gz'
assert kw_config_backup_name_valid 'config-123456789abc-20261021T102500Z-Ab12Cd34.tar.gz'
assert kw_backup_source_matches_site 'source-example.com-20261023-083015.tar.gz' example.com examplecom
assert kw_backup_source_matches_site 'source-examplecom-20261021T102500Z-Ab12Cd34.tar.gz' example.com examplecom
reject kw_backup_source_matches_site 'source-other.com-20261023-083015.tar.gz' example.com examplecom
assert kw_config_backup_matches_site 'config-example.com-20261023-083015.tar.gz' example.com examplecom
assert kw_config_backup_matches_site 'config-examplecom-20261021T102500Z-Ab12Cd34.tar.gz' example.com examplecom
reject kw_config_backup_matches_site 'config-other.com-20261023-083015.tar.gz' example.com examplecom
assert kw_db_backup_name_valid 'db-kwdb_examplecom-20261023-083015.sql.gz'
assert kw_db_backup_name_valid 'db-examplecom-20261021T102500Z-Ab12Cd34.sql.gz'
assert kw_db_backup_for_site examplecom 'db-kwdb_examplecom-20261023-083015.sql.gz'
reject kw_db_backup_for_site othercom 'db-kwdb_examplecom-20261023-083015.sql.gz'
reject kw_db_backup_name_valid '../../etc/shadow'
reject kw_config_backup_name_valid '../../etc/shadow'
assert kw_config_secret_password_valid 'sixteen-characters'
reject kw_config_secret_password_valid short
assert kw_config_zone_manifest_valid $'example.com\n0123456789abcdef0123456789abcdef'
reject kw_config_zone_manifest_valid $'example.com\n0123456789abcdef0123456789abcdef\nother.com'
output=$(kw_catalog cf-token)
assert test "${output#*'Thêm/thay token theo site|cf-site-token-save'}" != "$output"
assert test "${output#*'token chung'}" = "$output"
output=$(kw_cf_site_token_path blog.example.com)
assert test "${output#/etc/kwvps/cloudflare/site-token-}" != "$output"
reject kw_cf_site_token_path 'blog.example.com/../other'
reject kw_cf_site_token_save blog.example.com cfut_123456789012345678901234567890 WRONG
output=$(printf '%s\n' '{"success":true,"result":[{"name":"example.com","id":"0123456789abcdef0123456789abcdef"}]}' | kw_cf_json_zone_match example.com)
assert test "$output" = 0123456789abcdef0123456789abcdef
reject kw_cf_json_zone_match other.com <<< '{"success":true,"result":[{"name":"example.com","id":"0123456789abcdef0123456789abcdef"}]}'
reject kw_config_backup example.com wrong.example.com
reject kw_config_restore example.com config-123456789abc-20261021T102500Z-Ab12Cd34.tar.gz wrong.example.com
reject kw_backup_basename_valid '../../etc/shadow'
reject kw_backup_basename_valid 'source-123456789abc-20261021T102500Z-Ab12Cd34.tar.gz/../x'
reject kw_db_remote_plan 'example.com;id' 3307
reject kw_db_remote_plan example.com '3307;id'
assert kw_f2b_ipv4_valid 203.0.113.7
reject kw_f2b_ipv4_valid 256.0.0.1
reject kw_f2b_ipv4_valid '1.2.3.4;id'
assert kw_f2b_jail_valid sshd
reject kw_f2b_jail_valid 'sshd;id'
assert kw_fw_port_allowed 8080
reject kw_fw_port_allowed 3306
assert_kw_fw_close_db_plan() { kw_fw_port_plan close 3306 tcp >/dev/null; }
assert assert_kw_fw_close_db_plan
reject kw_fw_port_allowed '8080;id'
assert kw_fw_proto_valid tcp
reject kw_fw_proto_valid 'tcp;id'
reject kw_fw_port_change open 8080 tcp wrong
reject kw_fw_ip_change ban 203.0.113.47 wrong
reject kw_fw_toggle enable wrong
output=$(
  ufw() {
    printf 'Status: active\n[ 1] 80/tcp DENY IN Anywhere # kwvps-port-deny-80-tcp\n'
    printf '[ 2] 80/tcp ALLOW IN Anywhere # user-rule\n'
  }
  kw_fw_rule_numbers port-deny 80 tcp
)
assert test "$output" = 1
assert_kw_fw_port_action_fixture() (
  ufw() { printf 'Status: active\n[ 1] 80/tcp DENY IN Anywhere # kwvps-port-deny-80-tcp\n'; }
  kw_fw_port_has_action 80 tcp DENY
)
assert assert_kw_fw_port_action_fixture
output=$(
  kw_has() { return 0; }
  sshd() { printf 'port 22\nport 2222\n'; }
  systemctl() { return 1; }
  SSH_CONNECTION='203.0.113.5 55444 192.0.2.10 2200'
  kw_fw_ssh_ports
)
assert test "$output" = $'22\n2222\n2200'
output=$(
  kw_has() { return 0; }
  sshd() { printf 'port 22\n'; }
  systemctl() {
    if [[ $* == 'is-active --quiet ssh.socket' ]]; then return 0;
    elif [[ $* == 'show ssh.socket -p Listen --value' ]]; then printf '[::]:22 (Stream)\n';
    else return 1; fi;
  }
  unset SSH_CONNECTION
  kw_fw_ssh_ports
)
assert test "$output" = $'22\n22'
assert kw_swap_size_valid 256
reject kw_swap_size_valid 127
reject kw_swap_size_valid 8193
reject kw_swap_size_valid '256;id'
reject kw_swap_change add 256 wrong
output=$(kw_nginx_render_baseline)
assert test "${output#*'server_tokens off;'}" != "$output"
reject kw_nginx_restore example.com wrong.example.com
reject kw_site_permissions example.com wrong.example.com
reject kw_nginx_baseline wrong
reject kw_cron_nano wrong
kw_site_lookup() {
  KW_SITE_OWNER="kw$site_id"
  KW_SITE_ROOT="/var/www/kwvps/$site_id"
  KW_SITE_PUBLIC="$KW_SITE_ROOT/public"
}
output=$(kw_backup_source_plan EXAMPLE.COM)
assert test "${output#*'Domain: example.com'}" != "$output"
assert test "${output#*'source-example.com-YYYYMMDD-HHMMSS'}" != "$output"
assert test "${output#*'không gồm database'}" != "$output"
output=$(
  mktemp() { command mktemp "$(pwd)/.cf-discover-test.XXXXXXXX"; }
  curl() {
    case "${*: -1}" in
      *'name=blog.example.com&per_page=1') printf '%s\n' '{"success":true,"result":[]}' ;;
      *'name=example.com&per_page=1') printf '%s\n' '{"success":true,"result":[{"name":"example.com","id":"0123456789abcdef0123456789abcdef"}]}' ;;
      *) return 99 ;;
    esac
  }
  kw_cf_zone_discover blog.example.com cfut_123456789012345678901234567890
)
assert test "$output" = 0123456789abcdef0123456789abcdef
printf 'PASS: %d checks\n' "$tests"
