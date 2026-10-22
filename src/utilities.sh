#!/usr/bin/env bash
# phpMyAdmin is private to a PuTTY SSH local port-forward, never public Nginx.
readonly KW_PMA_NGINX=/etc/nginx/conf.d/kwvps-phpmyadmin.conf
readonly KW_PMA_POOL=/etc/php/8.3/fpm/pool.d/kwvps-phpmyadmin.conf
readonly KW_PMA_SECURITY=/etc/phpmyadmin/conf.d/99-kwvps-security.php
readonly KW_PMA_ADMIN_MARKER=/etc/kwvps/pma-admin-managed

kw_pma_installed() {
  [[ $(dpkg-query -W -f='${db:Status-Status}' phpmyadmin 2>/dev/null) == installed &&
     -f /usr/share/phpmyadmin/index.php && ! -L /usr/share/phpmyadmin/index.php ]]
}

kw_pma_render_nginx() {
  cat <<'EOF'
# Managed by KwVPS. Private phpMyAdmin; SSH port forwarding only.
server {
  listen 127.0.0.1:9080;
  server_name localhost;
  root /usr/share/phpmyadmin;
  index index.php;
  access_log /var/log/nginx/kwvps-phpmyadmin.access.log;
  error_log /var/log/nginx/kwvps-phpmyadmin.error.log;
  add_header X-Content-Type-Options nosniff always;
  add_header X-Frame-Options DENY always;
  location / { try_files $uri $uri/ /index.php?$args; }
  location ~ /\. { deny all; }
  location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/kwvps-phpmyadmin.sock;
  }
}
EOF
}

kw_pma_render_pool() {
  cat <<'EOF'
; Managed by KwVPS. phpMyAdmin runs outside site-specific PHP pools.
[kwvps-phpmyadmin]
user = www-data
group = www-data
listen = /run/php/kwvps-phpmyadmin.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = ondemand
pm.max_children = 4
pm.process_idle_timeout = 10s
pm.max_requests = 300
clear_env = yes
security.limit_extensions = .php
EOF
}

kw_pma_render_security() {
  cat <<'EOF'
<?php
// Managed by KwVPS. Never permit MariaDB root or passwordless web login.
if (empty($cfg['Servers'])) {
    $cfg['Servers'][1] = [];
}
foreach (array_keys($cfg['Servers']) as $kwpmaServer) {
    $cfg['Servers'][$kwpmaServer]['auth_type'] = 'cookie';
    $cfg['Servers'][$kwpmaServer]['host'] = 'localhost';
    $cfg['Servers'][$kwpmaServer]['connect_type'] = 'socket';
    $cfg['Servers'][$kwpmaServer]['AllowRoot'] = false;
    $cfg['Servers'][$kwpmaServer]['AllowNoPassword'] = false;
}
unset($kwpmaServer);
EOF
}

kw_pma_status() {
  if kw_pma_installed; then
    printf 'phpMyAdmin Ubuntu: '
    dpkg-query -W -f='${Version}\n' phpmyadmin || return 1
  else
    printf 'phpMyAdmin: chưa cài.\n'
  fi
  if [[ -f $KW_PMA_NGINX && ! -L $KW_PMA_NGINX ]] &&
     [[ -f $KW_PMA_POOL && ! -L $KW_PMA_POOL ]] &&
     [[ -f $KW_PMA_SECURITY && ! -L $KW_PMA_SECURITY ]]; then
    printf 'KwVPS endpoint: http://127.0.0.1:9080 (chỉ qua SSH tunnel).\n'
  else
    printf 'KwVPS endpoint: chưa cấu hình.\n'
  fi
}

kw_pma_ready() {
  kw_pma_installed || return 2
  [[ -f $KW_PMA_NGINX && ! -L $KW_PMA_NGINX &&
     -f $KW_PMA_POOL && ! -L $KW_PMA_POOL &&
     -f $KW_PMA_SECURITY && ! -L $KW_PMA_SECURITY ]] || return 2
  cmp -s -- "$KW_PMA_NGINX" <(kw_pma_render_nginx) &&
    cmp -s -- "$KW_PMA_POOL" <(kw_pma_render_pool) &&
    cmp -s -- "$KW_PMA_SECURITY" <(kw_pma_render_security) || return 2
  systemctl is-active --quiet nginx && systemctl is-active --quiet php8.3-fpm || return 2
  # Never accept a public listener for the management endpoint.
  local sockets address found=0 line
  sockets=$(ss -H -ltn '( sport = :9080 )') || return 2
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    address=$(awk '{print $4}' <<< "$line")
    [[ $address == 127.0.0.1:9080 ]] || return 2
    found=1
  done <<< "$sockets"
  ((found))
}

kw_pma_install_plan() {
  local simulation candidate
  kw_os_supported '' && kw_php_security_ready 8.3 || return 2
  kw_has apt-get && kw_has apt-cache && kw_has debconf-set-selections || return 2
  candidate=$(kw_apt_candidate php8.3-fpm) || return 2
  kw_php_package_version_safe 8.3 "$candidate" || {
    kw_log ERROR "PHP 8.3 ứng viên $candidate chưa có bản vá được xác minh."; return 2;
  }
  simulation=$(LC_ALL=C apt-get -s --no-remove install --no-install-recommends \
    phpmyadmin php8.3-mbstring php8.3-xml php8.3-zip php8.3-gd 2>&1) || return 2
  [[ $simulation != *$'\nRemv '* && $simulation != Remv\ * &&
     $simulation != *$'\nPurg '* && $simulation != Purg\ * ]] || return 2
  printf 'Kế hoạch cài gói Ubuntu (không xóa package):\n%s\n' "$simulation"
  printf 'Sau cài chỉ tạo web endpoint loopback 127.0.0.1:9080; không mở UFW hoặc public vhost.\n'
}

kw_pma_setup_locked() (
  local nginx_tmp='' pool_tmp='' security_tmp='' added_nginx=0 added_pool=0 added_security=0 committed=0 attempt
  ((EUID == 0)) && kw_os_supported '' && kw_pma_installed || return 2
  kw_php_security_ready 8.3 && kw_has nginx && kw_has php-fpm8.3 || return 2
  [[ -d /etc/nginx/conf.d && ! -L /etc/nginx/conf.d &&
     -d /etc/php/8.3/fpm/pool.d && ! -L /etc/php/8.3/fpm/pool.d &&
     -d /etc/phpmyadmin/conf.d && ! -L /etc/phpmyadmin/conf.d ]] || return 2
  for path in "$KW_PMA_NGINX" "$KW_PMA_POOL" "$KW_PMA_SECURITY"; do
    [[ ! -e $path && ! -L $path ]] || {
      kw_log ERROR "Đã có cấu hình $path; không ghi đè."; return 2;
    }
  done
  nginx -t >/dev/null 2>&1 && php-fpm8.3 -t >/dev/null 2>&1 || return 2
  nginx_tmp=$(mktemp /etc/nginx/conf.d/.kwvps-pma.XXXXXXXX) || return 1
  pool_tmp=$(mktemp /etc/php/8.3/fpm/pool.d/.kwvps-pma.XXXXXXXX) || return 1
  security_tmp=$(mktemp /etc/phpmyadmin/conf.d/.kwvps-pma.XXXXXXXX) || return 1
  trap 'if ((committed == 0)); then if ((added_nginx)); then rm -f -- "$KW_PMA_NGINX"; fi; if ((added_pool)); then rm -f -- "$KW_PMA_POOL"; fi; if ((added_security)); then rm -f -- "$KW_PMA_SECURITY"; fi; nginx -t >/dev/null 2>&1 && systemctl reload nginx || true; php-fpm8.3 -t >/dev/null 2>&1 && systemctl reload php8.3-fpm || true; fi; [[ -z $nginx_tmp ]] || rm -f -- "$nginx_tmp"; [[ -z $pool_tmp ]] || rm -f -- "$pool_tmp"; [[ -z $security_tmp ]] || rm -f -- "$security_tmp"' EXIT
  kw_pma_render_nginx > "$nginx_tmp" || return 1
  kw_pma_render_pool > "$pool_tmp" || return 1
  kw_pma_render_security > "$security_tmp" || return 1
  chmod 0644 -- "$nginx_tmp" "$pool_tmp" "$security_tmp" || return 1
  php -l "$security_tmp" >/dev/null || return 1
  mv -T -- "$security_tmp" "$KW_PMA_SECURITY" || return 1
  security_tmp=''
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  added_security=1
  mv -T -- "$pool_tmp" "$KW_PMA_POOL" || return 1
  pool_tmp=''
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  added_pool=1
  php-fpm8.3 -t >/dev/null || return 1
  mv -T -- "$nginx_tmp" "$KW_PMA_NGINX" || return 1
  nginx_tmp=''
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  added_nginx=1
  nginx -t >/dev/null || return 1
  systemctl reload php8.3-fpm && systemctl reload nginx || return 1
  systemctl is-active --quiet php8.3-fpm && systemctl is-active --quiet nginx || return 1
  for ((attempt=0; attempt<10; attempt++)); do
    [[ -S /run/php/kwvps-phpmyadmin.sock ]] && break
    sleep 1
  done
  [[ -S /run/php/kwvps-phpmyadmin.sock ]] || {
    kw_log ERROR 'PHP-FPM socket phpMyAdmin chưa xuất hiện.'; return 1;
  }
  [[ $(curl --silent --location --max-redirs 3 --output /dev/null \
    --write-out '%{http_code}' --max-time 8 http://127.0.0.1:9080/) == 200 ]] || {
      kw_log ERROR 'phpMyAdmin không trả HTTP 200 qua loopback.'; return 1;
    }
  kw_pma_ready || { kw_log ERROR 'Endpoint không đạt kiểm tra loopback-only.'; return 1; }
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  committed=1
  printf 'phpMyAdmin sẵn sàng tại loopback 127.0.0.1:9080. Dùng PuTTY SSH tunnel để truy cập.\n'
)

kw_pma_install() (
  local confirm=${1:-}
  [[ $confirm == INSTALL-PMA ]] || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id &&
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  exec 9>/run/lock/kwvps-pma.lock || return 2
  flock -n 9 || return 1
  kw_pma_installed && { kw_log ERROR 'phpMyAdmin đã cài; không cài lại.'; return 2; }
  kw_pma_install_plan || return 2
  printf 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect\n' | debconf-set-selections || return 1
  printf 'phpmyadmin phpmyadmin/dbconfig-install boolean false\n' | debconf-set-selections || return 1
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove --no-install-recommends \
    phpmyadmin php8.3-mbstring php8.3-xml php8.3-zip php8.3-gd || return 1
  kw_pma_installed || return 1
  kw_pma_setup_locked || {
    kw_log ERROR 'Gói đã cài nhưng endpoint chưa hoạt động; không mở public. Kiểm tra Nginx/PHP-FPM.'
    return 1
  }
)

kw_pma_permissions_interactive() {
  local choice
  kw_pma_status || return 1
  if ! kw_pma_installed; then
    printf '1. Cài gói Ubuntu và cấu hình truy cập riêng qua SSH tunnel\n0. Quay lại\nChọn: '
    IFS= read -r choice || return 0
    [[ $choice == 1 ]] || return 0
    kw_pma_install_plan || return 2
    kw_prompt_yes_no_token 'Cài phpMyAdmin, không mở truy cập công khai?' INSTALL-PMA || return 0
    kw_pma_install "$KW_PROMPT_VALUE"
    return $?
  fi
  if ! kw_pma_ready; then
    printf 'Gói có sẵn nhưng endpoint KwVPS chưa đạt.\n1. Cấu hình endpoint riêng qua SSH tunnel\n0. Quay lại\nChọn: '
    IFS= read -r choice || return 0
    [[ $choice == 1 ]] || return 0
    kw_prompt_yes_no_token 'Tạo endpoint phpMyAdmin chỉ nghe loopback?' SETUP-PMA || return 0
    exec 9>/run/lock/kwvps-pma.lock || return 2
    flock -n 9 || return 1
    kw_pma_setup_locked
    return $?
  fi
  printf 'Mã gói Ubuntu do dpkg quản lý; KwVPS không chmod/chown toàn bộ mã phpMyAdmin.\n'
  printf 'Kiểm tra file package đã sửa: '
  if dpkg --verify phpmyadmin; then printf 'không phát hiện sai lệch.\n'; else
    printf 'có sai lệch; xem dòng phía trên trước khi sửa thủ công.\n'
  fi
}

kw_pma_tunnel_guide() {
  printf 'PuTTY: Connection → SSH → Tunnels; Source port 9080, Destination 127.0.0.1:9080, chọn Local và Add; mở lại phiên SSH.\n'
  printf 'Sau đó mở http://127.0.0.1:9080 trên máy tính. Không mở port 9080 bằng UFW.\n'
}

kw_pma_site_interactive() {
  local domain name found=0
  kw_pma_ready || { kw_log ERROR 'phpMyAdmin chưa sẵn sàng; xem Tiện ích → mục 1.'; return 2; }
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  printf 'Database/user của site %s:\n' "$domain"
  while IFS= read -r name; do
    kw_db_select_meta "$name" || continue
    [[ $KW_DB_SELECTED_DOMAIN == "$domain" ]] || continue
    found=$((found + 1))
    printf '%d. %s — %s\n' "$found" "$name" "$KW_DB_SELECTED_USER"
  done < <(kw_db_managed_names)
  ((found)) || printf 'Site chưa có DB KwVPS quản lý; tạo ở menu DB.\n'
  printf 'Đăng nhập phpMyAdmin bằng user DB của site và mật khẩu bạn đã đặt.\n'
  kw_pma_tunnel_guide
}

kw_pma_admin_exists() {
  [[ $(mariadb --protocol=socket -uroot -N -B -e \
    "SELECT COUNT(*) FROM mysql.user WHERE User='kwvps_admin' AND Host='localhost';" 2>/dev/null) == 1 ]]
}

kw_pma_admin_managed() {
  [[ -f $KW_PMA_ADMIN_MARKER && ! -L $KW_PMA_ADMIN_MARKER &&
     $(stat -c %u -- "$KW_PMA_ADMIN_MARKER") == 0 &&
     $(stat -c %a -- "$KW_PMA_ADMIN_MARKER") == 600 &&
     $(< "$KW_PMA_ADMIN_MARKER") == kwvps-pma-admin-v1 ]]
}

kw_pma_admin_set_password() (
  local password=$1 mode=$2 confirm=${3:-} marker_tmp=''
  [[ $confirm == PMA-ADMIN ]] && [[ $mode == create || $mode == change ]] || return 2
  kw_db_password_valid "$password" || return 2
  ((EUID == 0)) && kw_pma_ready && kw_db_ready || return 2
  exec 9>/run/lock/kwvps-db.lock || return 2
  flock -n 9 || return 1
  if [[ $mode == create ]]; then
    kw_pma_admin_exists && { kw_log ERROR 'User admin đã tồn tại; không ghi đè.'; return 2; }
    [[ ! -e $KW_PMA_ADMIN_MARKER && ! -L $KW_PMA_ADMIN_MARKER ]] || return 2
    printf "CREATE USER 'kwvps_admin'@'localhost' IDENTIFIED BY '%s';\n" "$password" |
      mariadb --protocol=socket -uroot || return 1
    if ! printf "GRANT ALL PRIVILEGES ON *.* TO 'kwvps_admin'@'localhost';\n" |
      mariadb --protocol=socket -uroot; then
      printf "DROP USER 'kwvps_admin'@'localhost';\n" | mariadb --protocol=socket -uroot ||
        kw_log ERROR 'Không gỡ được user admin tạo dở; cần kiểm tra MariaDB.'
      return 1
    fi
    if ! marker_tmp=$(mktemp /etc/kwvps/.pma-admin.XXXXXXXX); then
      printf "DROP USER 'kwvps_admin'@'localhost';\n" | mariadb --protocol=socket -uroot ||
        kw_log ERROR 'Không gỡ được user admin sau lỗi tạo marker.'
      return 1
    fi
    if ! printf 'kwvps-pma-admin-v1\n' > "$marker_tmp" ||
       ! chmod 0600 -- "$marker_tmp" ||
       ! mv -T -- "$marker_tmp" "$KW_PMA_ADMIN_MARKER"; then
      rm -f -- "$marker_tmp"
      printf "DROP USER 'kwvps_admin'@'localhost';\n" | mariadb --protocol=socket -uroot ||
        kw_log ERROR 'Không gỡ được user admin sau lỗi ghi marker.'
      return 1
    fi
    printf 'Đã tạo kwvps_admin@localhost với quyền quản trị mọi DB, không có GRANT OPTION.\n'
  else
    if ! kw_pma_admin_exists || ! kw_pma_admin_managed; then
      kw_log ERROR 'User admin không có marker KwVPS hợp lệ; không thay mật khẩu.'; return 2;
    fi
    printf "ALTER USER 'kwvps_admin'@'localhost' IDENTIFIED BY '%s';\n" "$password" |
      mariadb --protocol=socket -uroot || return 1
    printf 'Đã đổi mật khẩu kwvps_admin@localhost.\n'
  fi
)

kw_pma_admin_interactive() {
  local password mode verb
  kw_pma_ready || { kw_log ERROR 'phpMyAdmin chưa sẵn sàng; xem Tiện ích → mục 1.'; return 2; }
  kw_db_ready || return 2
  if kw_pma_admin_exists; then
    kw_pma_admin_managed || { kw_log ERROR 'User kwvps_admin đã có nhưng không do KwVPS quản lý.'; return 2; }
    printf 'User kwvps_admin@localhost đã tồn tại.\n1. Đổi mật khẩu admin\n0. Quay lại\nChọn: '
    IFS= read -r mode || return 0
    [[ $mode == 1 ]] || { kw_pma_tunnel_guide; return 0; }
    mode=change
    verb='Đổi mật khẩu'
  else
    printf 'Chưa có user admin toàn DB. Tạo tài khoản này có quyền cao trên MariaDB.\n1. Tạo admin\n0. Quay lại\nChọn: '
    IFS= read -r mode || return 0
    [[ $mode == 1 ]] || return 0
    mode=create
    verb=Tạo
  fi
  kw_prompt_validated 'Mật khẩu admin DB (ẩn, 12–128 ký tự): ' \
    kw_db_password_valid 'Mật khẩu cần 12–128 ký tự trong tập chữ/số/_!@#%+=.-' secret || return 0
  password=$KW_PROMPT_VALUE
  KW_PROMPT_VALUE=''
  kw_prompt_yes_no_token "$verb tài khoản kwvps_admin có quyền mọi DB?" PMA-ADMIN || return 0
  kw_pma_admin_set_password "$password" "$mode" "$KW_PROMPT_VALUE" || return $?
  printf 'Đăng nhập phpMyAdmin bằng kwvps_admin và mật khẩu vừa đặt.\n'
  kw_pma_tunnel_guide
}
