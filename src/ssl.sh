#!/usr/bin/env bash
# Let's Encrypt HTTP-01 for pristine KwVPS HTTP sites only.

kw_ssl_cert_path() { printf '/etc/letsencrypt/live/%s/fullchain.pem' "$1"; }
kw_ssl_key_path() { printf '/etc/letsencrypt/live/%s/privkey.pem' "$1"; }

kw_ssl_install_renew_hook() {
  local dir=/etc/letsencrypt/renewal-hooks/deploy path=/etc/letsencrypt/renewal-hooks/deploy/kwvps-nginx
  [[ -d $dir && ! -L $dir && $(stat -c %u -- "$dir") == 0 ]] || return 2
  if [[ -e $path || -L $path ]]; then
    [[ -f $path && ! -L $path && $(stat -c %u -- "$path") == 0 ]] || return 2
    grep -Fxq '# Managed by KwVPS. Reload Nginx after certificate renewal.' "$path" || return 2
    return 0
  fi
  (umask 022; printf '%s\n' '#!/bin/sh' '# Managed by KwVPS. Reload Nginx after certificate renewal.' \
    'nginx -t >/dev/null 2>&1 && systemctl reload nginx' > "$path") || return 1
  chmod 0755 -- "$path"
}

kw_ssl_render_vhost() {
  local domain=$1 id=$2 provider=${3:-letsencrypt} marker
  case "$provider" in
    letsencrypt) marker="Let's Encrypt" ;;
    zerossl) marker=ZeroSSL ;;
    *) return 2 ;;
  esac
  cat <<EOF
# Managed by KwVPS. Site ID: ${id}
# KwVPS TLS: ${marker}
server {
  listen 80;
  listen [::]:80;
  server_name ${domain};
  root /var/www/kwvps/${id}/public;
  location ^~ /.well-known/acme-challenge/ {
    default_type text/plain;
    try_files \$uri =404;
  }
  location / { return 301 https://\$host\$request_uri; }
}
server {
  listen 443 ssl;
  listen [::]:443 ssl;
  server_name ${domain};
  root /var/www/kwvps/${id}/public;
  index index.php index.html;
  ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3;
  access_log /var/log/nginx/kwvps-${id}.access.log;
  error_log /var/log/nginx/kwvps-${id}.error.log;
  location / { try_files \$uri \$uri/ /index.php?\$args; }
  location ^~ /.well-known/acme-challenge/ {
    default_type text/plain;
    try_files \$uri =404;
  }
  location ~ /\. { deny all; }
  location ~ \.php\$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/kwvps-${id}.sock;
  }
}
EOF
}

kw_ssl_status() {
  local filter=${1:-all} file domain php id cert
  [[ $filter == all || $filter == unsecured ]] || return 2
  printf '%-32s %s\n' DOMAIN SSL
  for file in /etc/kwvps/sites/*.site; do
    [[ -f $file && ! -L $file ]] || continue
    domain=''; php=''; id=''
    while IFS='=' read -r key value; do
      case "$key" in
        domain) domain=$value ;;
        php_version) php=$value ;;
        site_id) id=$value ;;
      esac
    done < "$file"
    if ! kw_domain_valid "$domain" || ! kw_site_php_valid "$php" || [[ $id != "$(kw_site_id "$domain")" ]]; then
      continue
    fi
    cert=$(kw_ssl_cert_path "$domain")
    if [[ -f /etc/nginx/sites-available/kwvps-${id}.conf && \
       ! -L /etc/nginx/sites-available/kwvps-${id}.conf ]] && \
       grep -Fxq '# KwVPS TLS: Paid' "/etc/nginx/sites-available/kwvps-${id}.conf"; then
      [[ $filter != unsecured ]] || continue
      cert="/etc/kwvps/certs/${id}/fullchain.pem"
      if [[ -r $cert ]]; then
        printf '%-32s Paid SSL: %s\n' "$domain" "$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null || printf 'chứng chỉ không đọc được')"
      else
        printf '%-32s %s\n' "$domain" 'Paid SSL (sudo để xem hạn)'
      fi
    elif [[ -f /etc/nginx/sites-available/kwvps-${id}.conf && \
       ! -L /etc/nginx/sites-available/kwvps-${id}.conf ]] && \
       { grep -Fxq "# KwVPS TLS: Let's Encrypt" "/etc/nginx/sites-available/kwvps-${id}.conf" ||
         grep -Fxq '# KwVPS TLS: ZeroSSL' "/etc/nginx/sites-available/kwvps-${id}.conf"; }; then
      [[ $filter != unsecured ]] || continue
      if [[ -r $cert ]]; then
        printf '%-32s %s\n' "$domain" "$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null || printf 'chứng chỉ không đọc được')"
      else
        printf '%-32s %s\n' "$domain" 'Đã cấu hình HTTPS (sudo để xem hạn)'
      fi
    else
      printf '%-32s %s\n' "$domain" 'Chưa có chứng chỉ'
    fi
  done
}

kw_ssl_require_pristine_http() {
  local domain=$1 id
  kw_site_lookup "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  [[ -f $KW_SITE_VHOST && ! -L $KW_SITE_VHOST && $(stat -c %u -- "$KW_SITE_VHOST") == 0 && \
     -L $KW_SITE_ENABLED && $(readlink -f -- "$KW_SITE_ENABLED") == "$KW_SITE_VHOST" ]] || return 2
  cmp -s -- "$KW_SITE_VHOST" <(kw_site_render_vhost "$domain" "$id") || {
    kw_log ERROR 'Vhost không phải mẫu HTTP hiện tại; từ chối ghi đè cấu hình tùy chỉnh/SSL.'
    return 2
  }
}

kw_ssl_issue_locked() (
  local domain=$1 id backup temp='' swapped=0 committed=0 provider
  local -a certbot_config=()
  kw_nginx_ready || return 2
  if ! kw_has certbot || ! kw_has openssl || ! kw_has curl; then
    kw_log ERROR 'Cần certbot, openssl và curl.'; return 2
  fi
  kw_ssl_require_pristine_http "$domain" || return 2
  kw_acme_provider_current || { kw_log ERROR 'ACME provider không hợp lệ; xem menu SSL → Đổi ACME provider.'; return 2; }
  provider=$KW_ACME_PROVIDER
  if [[ $provider == zerossl ]]; then
    kw_acme_zerossl_ready || { kw_log ERROR 'Thiếu ZeroSSL EAB; xem menu SSL → Đổi ACME provider.'; return 2; }
    certbot_config=(--config "$KW_ACME_ZEROSSL_CONFIG")
  fi
  id=${KW_SITE_OWNER#kw}
  [[ ! -e /etc/letsencrypt/live/$domain && ! -L /etc/letsencrypt/live/$domain ]] || {
    kw_log ERROR 'Đã có chứng chỉ/tên miền trong Certbot; kiểm tra thủ công trước khi cấp lại.'; return 2;
  }
  nginx -t >/dev/null 2>&1 || return 2
  printf 'Đang cấp chứng chỉ %s cho %s bằng HTTP-01; không đăng ký email thông báo.\n' "$provider" "$domain"
  certbot certonly "${certbot_config[@]}" --webroot -w "$KW_SITE_PUBLIC" -d "$domain" \
    --non-interactive --agree-tos --register-unsafely-without-email || return 1
  [[ -f $(kw_ssl_cert_path "$domain") && -f $(kw_ssl_key_path "$domain") ]] || return 1
  kw_nginx_backup_file "$KW_SITE_VHOST" "ssl-$id" || return 1
  backup=$KW_NGINX_BACKUP
  temp=$(mktemp /etc/nginx/sites-available/.kwvps-ssl.XXXXXXXX) || return 1
  trap 'if ((swapped == 1 && committed == 0)); then cp -p -- "$backup" "$KW_SITE_VHOST" && nginx -t && systemctl reload nginx || kw_log ERROR "Rollback Nginx cần kiểm tra thủ công: $backup"; fi; [[ -z $temp ]] || rm -f -- "$temp"' EXIT
  kw_ssl_render_vhost "$domain" "$id" "$provider" > "$temp" || return 1
  chmod 0644 -- "$temp" || return 1
  mv -T -- "$temp" "$KW_SITE_VHOST" || return 1
  temp=''
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  swapped=1
  nginx -t || return 1
  systemctl reload nginx || return 1
  curl --fail --silent --show-error --max-time 15 --resolve "$domain:443:127.0.0.1" \
    "https://$domain/" -o /dev/null || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  committed=1
  if ! kw_ssl_install_renew_hook; then
    kw_log WARN 'HTTPS đã hoạt động nhưng chưa tạo được hook reload Nginx khi gia hạn. Cần xử lý thủ công.'
  fi
  printf 'HTTPS hoạt động cho %s. Vhost cũ: %s\n' "$domain" "$backup"
)

kw_ssl_issue() (
  local domain=${1,,} confirm=${2:-}
  kw_domain_valid "$domain" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root.'; return 2; }
  exec 9>/run/lock/kwvps-nginx.lock || return 2
  flock -n 9 || return 1
  kw_ssl_issue_locked "$domain"
)

kw_ssl_issue_interactive() {
  local domain confirm
  kw_acme_status || return 2
  printf 'Domain KwVPS cần cấp SSL ACME: '
  IFS= read -r domain || return 0
  domain=${domain,,}
  kw_ssl_require_pristine_http "$domain" || return 2
  printf 'DNS phải trỏ trực tiếp đến VPS; cổng 80/443 phải mở. Certbot cần có sẵn.\n'
  kw_prompt_yes_no_token "Cấp SSL cho $domain (không có email cảnh báo hết hạn)?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_ssl_issue "$domain" "${confirm,,}"
}

# Paid certificates are imported only for an untouched HTTP vhost. Existing TLS
# configurations are never overwritten or converted automatically.
kw_ssl_paid_input() {
  local file=$1 mode
  [[ $file =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,100}\.pem$ ]] || return 2
  [[ -d /home/ssl && ! -L /home/ssl && -f /home/ssl/$file && ! -L /home/ssl/$file ]] || return 2
  [[ $(stat -c %u -- /home/ssl "/home/ssl/$file") == $'0\n0' ]] || return 2
  mode=$(stat -c %a -- /home/ssl) || return 2
  (( (8#$mode & 0022) == 0 )) || return 2
  mode=$(stat -c %a -- "/home/ssl/$file") || return 2
  (( (8#$mode & 0022) == 0 ))
}

kw_ssl_paid_key_input() {
  local mode
  kw_ssl_paid_input "$1" || return 2
  mode=$(stat -c %a -- "/home/ssl/$1") || return 2
  (( (8#$mode & 0077) == 0 ))
}

kw_ssl_paid_validate() {
  local domain=$1 cert=$2 key=$3 cert_hash key_hash
  openssl x509 -in "$cert" -noout -checkhost "$domain" 2>/dev/null | grep -Fq 'does match certificate' || return 2
  openssl x509 -in "$cert" -noout -checkend 86400 >/dev/null 2>&1 || return 2
  openssl pkey -in "$key" -noout >/dev/null 2>&1 || return 2
  cert_hash=$(openssl x509 -in "$cert" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum) || return 2
  key_hash=$(openssl pkey -in "$key" -pubout -outform DER 2>/dev/null | sha256sum) || return 2
  [[ ${cert_hash%% *} == "${key_hash%% *}" ]]
}

kw_ssl_render_paid_vhost() {
  local domain=$1 id=$2
  kw_ssl_render_vhost "$domain" "$id" | sed \
    -e "s|# KwVPS TLS: Let's Encrypt|# KwVPS TLS: Paid|" \
    -e "s|/etc/letsencrypt/live/${domain}/fullchain.pem|/etc/kwvps/certs/${id}/fullchain.pem|" \
    -e "s|/etc/letsencrypt/live/${domain}/privkey.pem|/etc/kwvps/certs/${id}/privkey.pem|"
}

kw_ssl_paid_locked() (
  # shellcheck disable=SC2034 # State variables are read by the EXIT rollback trap.
  local domain=$1 cert_name=$2 key_name=$3 id cert key target temp='' vhost_temp='' backup='' committed=0 installed=0 swapped=0 restored=1
  kw_nginx_ready || return 2
  kw_ssl_paid_input "$cert_name" && kw_ssl_paid_key_input "$key_name" && [[ $cert_name != "$key_name" ]] || return 2
  kw_ssl_require_pristine_http "$domain" || return 2
  id=${KW_SITE_OWNER#kw}; cert="/home/ssl/$cert_name"; key="/home/ssl/$key_name"
  kw_ssl_paid_validate "$domain" "$cert" "$key" || { kw_log ERROR 'Chứng chỉ không đúng domain, sắp hết hạn, hoặc private key không khớp.'; return 2; }
  [[ -d /etc/kwvps && ! -L /etc/kwvps && $(stat -c %u -- /etc/kwvps) == 0 ]] || return 2
  install -d -m 0700 -o root -g root -- /etc/kwvps/certs || return 1
  [[ -d /etc/kwvps/certs && ! -L /etc/kwvps/certs && $(stat -c %u -- /etc/kwvps/certs) == 0 ]] || return 2
  target="/etc/kwvps/certs/$id"
  [[ ! -e $target && ! -L $target ]] || { kw_log ERROR 'Đã có vùng chứng chỉ cho site; không ghi đè.'; return 2; }
  temp=$(mktemp -d /etc/kwvps/certs/.kwvps-paid.XXXXXXXX) || return 1
  trap 'if ((committed == 0)); then if ((swapped)); then cp -p -- "$backup" "$KW_SITE_VHOST" && nginx -t && systemctl reload nginx || { restored=0; kw_log ERROR "Cần khôi phục vhost: $backup"; }; fi; if ((installed && restored)); then rm -f -- "$target/fullchain.pem" "$target/privkey.pem"; rmdir -- "$target" || true; fi; fi; [[ -z $vhost_temp ]] || rm -f -- "$vhost_temp"; [[ -z $temp ]] || { rm -f -- "$temp/fullchain.pem" "$temp/privkey.pem"; rmdir -- "$temp" || true; }' EXIT
  chmod 0700 -- "$temp" || return 1
  install -m 0644 -o root -g root -- "$cert" "$temp/fullchain.pem" || return 1
  install -m 0600 -o root -g root -- "$key" "$temp/privkey.pem" || return 1
  kw_ssl_paid_validate "$domain" "$temp/fullchain.pem" "$temp/privkey.pem" || return 2
  kw_nginx_backup_file "$KW_SITE_VHOST" "paid-$id" || return 1
  backup=$KW_NGINX_BACKUP
  vhost_temp=$(mktemp /etc/nginx/sites-available/.kwvps-paid.XXXXXXXX) || return 1
  kw_ssl_render_paid_vhost "$domain" "$id" > "$vhost_temp" || return 1
  chmod 0644 -- "$vhost_temp" || return 1
  mv -T -- "$temp" "$target" || return 1
  temp=''
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  installed=1
  mv -T -- "$vhost_temp" "$KW_SITE_VHOST" || return 1
  vhost_temp=''
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  swapped=1
  nginx -t || return 1
  systemctl reload nginx || return 1
  curl --fail --silent --show-error --max-time 15 --resolve "$domain:443:127.0.0.1" "https://$domain/" -o /dev/null || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  committed=1
  printf 'Đã cài paid SSL cho %s. Vhost cũ: %s\n' "$domain" "$backup"
)

kw_ssl_paid() (
  local domain=${1,,} cert_name=${2:-} key_name=${3:-} confirm=${4:-}
  kw_domain_valid "$domain" && kw_ssl_paid_input "$cert_name" && kw_ssl_paid_key_input "$key_name" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-nginx.lock || return 2
  flock -n 9 || return 1
  kw_ssl_paid_locked "$domain" "$cert_name" "$key_name"
)

kw_ssl_paid_interactive() {
  local domain cert_name key_name
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_ssl_require_pristine_http "$domain" || return 2
  printf 'Upload fullchain và private key PEM vào /home/ssl; file phải thuộc root, không là symlink. Không nhập nội dung key vào menu.\n'
  printf 'Tên file fullchain (.pem): '
  IFS= read -r cert_name || return 0
  kw_ssl_paid_input "$cert_name" || { kw_log ERROR 'File fullchain không hợp lệ.'; return 2; }
  printf 'Tên file private key (.pem): '
  IFS= read -r key_name || return 0
  kw_ssl_paid_key_input "$key_name" || { kw_log ERROR 'File private key phải thuộc root và chỉ root được đọc.'; return 2; }
  kw_ssl_paid_validate "$domain" "/home/ssl/$cert_name" "/home/ssl/$key_name" || { kw_log ERROR 'Cert/key không khớp hoặc chứng chỉ không hợp lệ.'; return 2; }
  printf 'Sẽ bật HTTPS cho %s; giữ bản sao vhost cũ để rollback. Không thay chứng chỉ hiện có.\n' "$domain"
  kw_prompt_yes_no_token "Cài paid SSL cho $domain?" "$domain" || return 0
  kw_ssl_paid "$domain" "$cert_name" "$key_name" "$KW_PROMPT_VALUE"
}
