#!/usr/bin/env bash
# Remotely-managed Cloudflare Tunnel: apt package, root-only token and service.
# Hostname/DNS routes remain in the Cloudflare dashboard; ports 80/443 are untouched.

readonly KW_TUNNEL_KEY=/usr/share/keyrings/kwvps-cloudflare-main.gpg
readonly KW_TUNNEL_REPO=/etc/apt/sources.list.d/kwvps-cloudflared.list
readonly KW_TUNNEL_TOKEN=/etc/kwvps/cloudflare/tunnel-token
readonly KW_TUNNEL_UNIT=/etc/systemd/system/cloudflared.service

kw_tunnel_installed() {
  [[ $(dpkg-query -W -f='${db:Status-Status}' cloudflared 2>/dev/null) == installed ]] &&
    [[ -x /usr/bin/cloudflared && ! -L /usr/bin/cloudflared ]]
}

kw_tunnel_install_plan() {
  kw_os_supported '' || return 2
  if kw_tunnel_installed; then
    printf 'cloudflared đã cài: '
    /usr/bin/cloudflared --version
    return 0
  fi
  [[ ! -e $KW_TUNNEL_KEY && ! -L $KW_TUNNEL_KEY &&
     ! -e $KW_TUNNEL_REPO && ! -L $KW_TUNNEL_REPO ]] || {
    kw_log ERROR 'File nguồn/key Cloudflare của KwVPS đã có; cần kiểm tra thủ công trước khi cài.'
    return 2
  }
  printf 'Sẽ thêm kho APT chính thức Cloudflare (Ubuntu 24.04 Noble), cập nhật chỉ kho này rồi cài package cloudflared.\n'
  printf 'Nguồn: https://pkg.cloudflare.com/cloudflared noble main; key: https://pkg.cloudflare.com/cloudflare-main.gpg\n'
  printf 'Không cài service, không yêu cầu token, không đổi DNS/firewall/cổng 80/443 ở bước này.\n'
}

kw_tunnel_install() (
  local confirm=${1:-} key_tmp='' repo_tmp='' simulation=''
  [[ $confirm == INSTALL-CLOUDFLARED ]] || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id &&
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  kw_tunnel_installed && { printf 'cloudflared đã cài.\n'; return 0; }
  for tool in curl apt-get gpg flock dpkg-query; do kw_has "$tool" || return 2; done
  [[ -d /usr/share/keyrings && ! -L /usr/share/keyrings &&
     -d /etc/apt/sources.list.d && ! -L /etc/apt/sources.list.d ]] || return 2
  exec 9>/run/lock/kwvps-tunnel.lock || return 2
  flock -n 9 || return 1
  kw_tunnel_install_plan || return 2
  key_tmp=$(mktemp /usr/share/keyrings/.kwvps-cf-key.XXXXXXXX) || return 1
  repo_tmp=$(mktemp /etc/apt/sources.list.d/.kwvps-cloudflared.XXXXXXXX) || return 1
  trap '[[ -z $key_tmp ]] || rm -f -- "$key_tmp"; [[ -z $repo_tmp ]] || rm -f -- "$repo_tmp"' EXIT
  curl -fsSL --proto '=https' --tlsv1.2 --connect-timeout 8 --max-time 30 \
    https://pkg.cloudflare.com/cloudflare-main.gpg -o "$key_tmp" || return 1
  [[ -s $key_tmp && $(stat -c %s -- "$key_tmp") -le 65536 ]] || return 2
  gpg --batch --quiet --show-keys "$key_tmp" >/dev/null 2>&1 || return 2
  chmod 0644 -- "$key_tmp" || return 1
  printf 'deb [signed-by=%s] https://pkg.cloudflare.com/cloudflared noble main\n' "$KW_TUNNEL_KEY" > "$repo_tmp" || return 1
  chmod 0644 -- "$repo_tmp" || return 1
  mv -T -- "$key_tmp" "$KW_TUNNEL_KEY" || return 1
  key_tmp=''
  mv -T -- "$repo_tmp" "$KW_TUNNEL_REPO" || return 1
  repo_tmp=''
  apt-get update -o Dir::Etc::sourcelist="$KW_TUNNEL_REPO" \
    -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 || return 1
  simulation=$(LC_ALL=C apt-get -s --no-remove install --no-install-recommends cloudflared 2>&1) || return 2
  [[ $simulation != *$'\nRemv '* && $simulation != Remv\ * &&
     $simulation != *$'\nPurg '* && $simulation != Purg\ * ]] || return 2
  printf 'Kế hoạch apt:\n%s\n' "$simulation"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove --no-install-recommends cloudflared || return 1
  kw_tunnel_installed || return 1
  printf 'Đã cài '
  /usr/bin/cloudflared --version
  printf 'Chưa tạo/chạy Tunnel; mở lại mục Cấu hình Tunnel để nhập token.\n'
)

kw_tunnel_token_valid() {
  [[ ${1:-} =~ ^[A-Za-z0-9._~+/-]{40,4096}={0,2}$ ]]
}

kw_tunnel_tokenfile_supported() {
  local version year month patch
  kw_tunnel_installed || return 2
  version=$(/usr/bin/cloudflared --version) || return 2
  [[ $version =~ version[[:space:]]+(20[0-9]{2})\.([0-9]{1,2})\.([0-9]+) ]] || return 2
  year=${BASH_REMATCH[1]}; month=${BASH_REMATCH[2]}; patch=${BASH_REMATCH[3]}
  ((10#$year > 2025 || (10#$year == 2025 && 10#$month >= 4))) &&
    [[ -n $patch ]]
}

kw_tunnel_service_owned() {
  [[ -f $KW_TUNNEL_UNIT && ! -L $KW_TUNNEL_UNIT &&
     $(stat -c %u -- "$KW_TUNNEL_UNIT") == 0 ]] &&
    grep -Fxq '# Managed by KwVPS. Remote Cloudflare Tunnel.' "$KW_TUNNEL_UNIT"
}

kw_tunnel_antiddos_enabled() {
  local state domain mode
  for state in /etc/kwvps/cloudflare/antiddos/*.rate; do
    [[ -e $state || -L $state ]] || continue
    domain=${state##*/}; domain=${domain%.rate}
    mode=$(kw_tunnel_site_mode "$domain") || return 0
    [[ $mode != dns ]] && return 0
  done
  return 1
}

# A cloudflared process may serve several sites. Ingress is a property of the
# hostname, not of the systemd service. Unmarked sites are unknown while the
# connector runs, so pre-existing routes cannot silently enable local bans.
kw_tunnel_site_mode_path() {
  kw_domain_valid "$1" || return 2
  printf '/etc/kwvps/ingress/%s.mode\n' "${1,,}"
}

kw_tunnel_site_mode() {
  local path value
  path=$(kw_tunnel_site_mode_path "$1") || return 2
  if [[ ! -e $path && ! -L $path ]]; then
    if systemctl is-active --quiet cloudflared.service 2>/dev/null; then
      printf 'unknown\n'
    else
      printf 'dns\n'
    fi
    return 0
  fi
  [[ -f $path && ! -L $path && $(stat -c %u:%a -- "$path") == 0:600 ]] || return 2
  IFS= read -r value < "$path" || return 2
  [[ $value == dns || $value == tunnel ]] || return 2
  printf '%s\n' "$value"
}

kw_tunnel_site_mode_set() (
  local domain=${1,,} mode=$2 confirm=$3 path stage
  kw_domain_valid "$domain" && [[ $mode == dns || $mode == tunnel ]] &&
    [[ $confirm == "INGRESS:$domain:$mode" ]] || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  kw_site_lookup "$domain" || return 2
  if [[ $mode == tunnel ]]; then
    [[ ! -e /etc/kwvps/cloudflare/antiddos/$domain.rate &&
       ! -L /etc/kwvps/cloudflare/antiddos/$domain.rate ]] || {
      kw_log ERROR 'Tắt Nginx rate limit cho site này trước khi chọn Tunnel.'; return 2;
    }
    systemctl is-active --quiet cloudflared.service || {
      kw_log ERROR 'cloudflared chưa active.'; return 2;
    }
  fi
  install -d -o root -g root -m 0700 -- /etc/kwvps/ingress || return 1
  [[ -d /etc/kwvps/ingress && ! -L /etc/kwvps/ingress &&
     $(stat -c %u:%a -- /etc/kwvps/ingress) == 0:700 ]] || return 2
  path=$(kw_tunnel_site_mode_path "$domain") || return 2
  [[ ! -e $path && ! -L $path ]] || {
    [[ -f $path && ! -L $path && $(stat -c %u:%a -- "$path") == 0:600 ]] || return 2;
  }
  stage=$(mktemp /etc/kwvps/ingress/.mode.XXXXXXXX) || return 1
  trap 'rm -f -- "$stage"' EXIT
  chmod 0600 -- "$stage" || return 1
  printf '%s\n' "$mode" > "$stage" || return 1
  mv -T -- "$stage" "$path" || return 1
  printf 'Đã ghi chế độ %s cho %s. Route/DNS trên Cloudflare cần được đối chiếu riêng.\n' "$mode" "$domain"
)

kw_tunnel_site_mode_interactive() {
  local domain mode current
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  current=$(kw_tunnel_site_mode "$domain") || return 2
  printf '%s đang ghi nhận: %s\n1. Tunnel\n2. DNS thông thường (DNS only hoặc đám mây cam)\n0. Quay lại\nChọn: ' "$domain" "$current"
  [[ $current != unknown ]] || printf '\nChưa phân loại vì cloudflared đang chạy; kiểm tra route trên Dashboard trước khi chọn.\n'
  local choice
  IFS= read -r choice || return 0
  case "$choice" in 1) mode=tunnel ;; 2) mode=dns ;; *) return 0 ;; esac
  printf 'Chỉ cập nhật trạng thái KwVPS; không tự tạo/xóa route hay DNS trên Cloudflare.\n'
  kw_prompt_yes_no_token "Ghi chế độ $mode cho $domain?" "INGRESS:$domain:$mode" || return 0
  kw_tunnel_site_mode_set "$domain" "$mode" "$KW_PROMPT_VALUE"
}

kw_tunnel_render_unit() {
  printf '%s\n' \
    '# Managed by KwVPS. Remote Cloudflare Tunnel.' \
    '[Unit]' \
    'Description=Cloudflare Tunnel (KwVPS)' \
    'Wants=network-online.target' \
    'After=network-online.target' \
    '[Service]' \
    'Type=simple' \
    'ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run --token-file /etc/kwvps/cloudflare/tunnel-token' \
    'Restart=on-failure' \
    'RestartSec=5s' \
    'NoNewPrivileges=yes' \
    '[Install]' \
    'WantedBy=multi-user.target'
}

kw_tunnel_configure() (
  local token=${1:-} confirm=${2:-} token_tmp='' unit_tmp='' old_token='' old_unit=''
  local touched=0 committed=0
  [[ $confirm == CONFIGURE-CLOUDFLARED ]] && kw_tunnel_token_valid "$token" || return 2
  ((EUID == 0)) && kw_os_supported '' && kw_tunnel_tokenfile_supported || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id &&
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  if kw_tunnel_antiddos_enabled; then
    kw_log ERROR 'Có site đánh dấu Tunnel đang bật anti-DDoS local. Tắt giới hạn site đó trước.'
    return 2
  fi
  [[ -d /etc/kwvps && ! -L /etc/kwvps && $(stat -c %u -- /etc/kwvps) == 0 ]] || return 2
  kw_has systemctl && kw_has flock && kw_has mktemp || return 2
  if systemctl cat cloudflared.service >/dev/null 2>&1 && ! kw_tunnel_service_owned; then
    kw_log ERROR 'cloudflared.service đã có từ bên ngoài KwVPS; không ghi đè.'
    return 2
  fi
  [[ ! -e $KW_TUNNEL_UNIT && ! -L $KW_TUNNEL_UNIT ]] || kw_tunnel_service_owned || return 2
  [[ ! -e $KW_TUNNEL_TOKEN && ! -L $KW_TUNNEL_TOKEN ]] || {
    [[ -f $KW_TUNNEL_TOKEN && ! -L $KW_TUNNEL_TOKEN &&
       $(stat -c %u:%a -- "$KW_TUNNEL_TOKEN") == 0:600 ]] || return 2
  }
  exec 9>/run/lock/kwvps-tunnel.lock || return 2
  flock -n 9 || return 1
  exec 8>/run/lock/kwvps-cloudflare.lock || return 2
  flock -n 8 || return 1
  if kw_tunnel_antiddos_enabled; then
    kw_log ERROR 'Site Tunnel vừa bật anti-DDoS local; hủy để tránh chặn nhầm.'
    return 2
  fi
  if [[ ! -e /etc/kwvps/cloudflare && ! -L /etc/kwvps/cloudflare ]]; then
    install -d -o root -g root -m 0700 -- /etc/kwvps/cloudflare || return 1
  fi
  [[ -d /etc/kwvps/cloudflare && ! -L /etc/kwvps/cloudflare &&
     $(stat -c %u:%a -- /etc/kwvps/cloudflare) == 0:700 ]] || return 2
  if [[ -f $KW_TUNNEL_TOKEN ]]; then
    old_token=$(mktemp /run/kwvps-tunnel-token-old.XXXXXXXX) || return 1
    cp -p -- "$KW_TUNNEL_TOKEN" "$old_token" || return 1
    chmod 0600 -- "$old_token" || return 1
  fi
  if kw_tunnel_service_owned; then
    old_unit=$(mktemp /run/kwvps-tunnel-unit-old.XXXXXXXX) || return 1
    cp -p -- "$KW_TUNNEL_UNIT" "$old_unit" || return 1
  fi
  trap 'if ((touched && ! committed)); then if [[ -n $old_token ]]; then cp -p -- "$old_token" "$KW_TUNNEL_TOKEN"; else rm -f -- "$KW_TUNNEL_TOKEN"; fi; if [[ -n $old_unit ]]; then cp -p -- "$old_unit" "$KW_TUNNEL_UNIT"; else systemctl disable --now cloudflared.service >/dev/null 2>&1 || true; rm -f -- "$KW_TUNNEL_UNIT"; fi; systemctl daemon-reload; [[ -z $old_unit ]] || systemctl restart cloudflared.service || true; fi; [[ -z $token_tmp ]] || rm -f -- "$token_tmp"; [[ -z $unit_tmp ]] || rm -f -- "$unit_tmp"; [[ -z $old_token ]] || rm -f -- "$old_token"; [[ -z $old_unit ]] || rm -f -- "$old_unit"' EXIT
  token_tmp=$(mktemp /etc/kwvps/cloudflare/.tunnel-token.XXXXXXXX) || return 1
  chmod 0600 -- "$token_tmp" || return 1
  printf '%s\n' "$token" > "$token_tmp" || return 1
  unit_tmp=$(mktemp /etc/systemd/system/.kwvps-cloudflared.XXXXXXXX) || return 1
  kw_tunnel_render_unit > "$unit_tmp" || return 1
  chmod 0644 -- "$unit_tmp" || return 1
  mv -T -- "$token_tmp" "$KW_TUNNEL_TOKEN" || return 1
  token_tmp=''
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  touched=1
  mv -T -- "$unit_tmp" "$KW_TUNNEL_UNIT" || return 1
  unit_tmp=''
  systemctl daemon-reload || return 1
  systemctl enable --now cloudflared.service || return 1
  systemctl restart cloudflared.service || return 1
  sleep 3
  systemctl is-active --quiet cloudflared.service || {
    kw_log ERROR 'Tunnel service chưa active; token có thể không hợp lệ hoặc egress 7844 bị chặn.'
    return 1
  }
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  committed=1
  printf 'cloudflared.service active; token chỉ lưu trong file root-only. Chưa chứng minh hostname public hoạt động.\n'
)

kw_tunnel_guide() {
  printf '%s\n' \
    '1) Cloudflare Dashboard → Networking → Tunnels → Create Tunnel → chọn loại Cloudflared.' \
    '2) Tạo Tunnel quản lý trên Cloudflare, sao chép riêng Tunnel token (không dán cả lệnh cài).' \
    '3) Quay lại mục này, chọn cấu hình service và dán token khi được hỏi; không gửi token qua chat.' \
    '4) Trong Tunnel → Routes → Add route → Published application: chọn hostname của site KwVPS.' \
    '5) Site HTTP: Service URL http://127.0.0.1:80. Site HTTPS: https://127.0.0.1:443,' \
    '   đặt Origin Server Name bằng hostname thật để xác minh chứng chỉ; không bật Disable TLS verification.' \
    '6) Thử hostname từ ngoài và kiểm tra log. Có thể đóng inbound 80/443 sau khi mọi route,' \
    '   site và gia hạn SSL đã kiểm chứng; Nginx vẫn nghe local, cloudflared cần outbound 7844.' \
    '   KwVPS không tự đóng cổng. Tắt anti-DDoS local trước: Real IP qua Tunnel chưa xác minh.' \
    'Tunnel token khác API token Cloudflare ở menu Bảo mật/Cloudflare.'
  if [[ ${1:-} != --no-site-prompt ]] && kw_site_prompt_domain; then
    if kw_site_lookup "$KW_SITE_CHOICE" && [[ -f $KW_SITE_VHOST ]] &&
       grep -Eq 'ssl_certificate[[:space:]]' "$KW_SITE_VHOST"; then
      printf 'Site %s: HTTPS origin, chọn https://127.0.0.1:443 và Origin Server Name = %s.\n' \
        "$KW_SITE_CHOICE" "$KW_SITE_CHOICE"
    else
      printf 'Site %s: HTTP origin, chọn http://127.0.0.1:80.\n' "$KW_SITE_CHOICE"
    fi
  fi
}

kw_tunnel_config_interactive() {
  local choice token
  # Rendering the menu and reading the guide do not require root. Each
  # mutating action checks privileges again at its own entry point.
  if ! kw_tunnel_installed; then
    printf 'cloudflared chưa cài.\n1. Cài cloudflared từ kho APT Cloudflare\n2. Hướng dẫn tạo Tunnel\n0. Quay lại\nChọn: '
    IFS= read -r choice || return 0
    case "$choice" in
      1)
        kw_tunnel_install_plan || return 2
        kw_prompt_yes_no_token 'Cài cloudflared trên VPS?' INSTALL-CLOUDFLARED || return 0
        kw_tunnel_install "$KW_PROMPT_VALUE" ;;
      2) kw_tunnel_guide ;;
      *) return 0 ;;
    esac
    return $?
  fi
  printf 'Đã cài: '
  /usr/bin/cloudflared --version || return 2
  printf '1. Hướng dẫn tạo Tunnel và route theo site\n2. Lưu/thay Tunnel token và cấu hình service\n3. Kiểm tra trạng thái service\n4. Ghi nhận chế độ từng site\n0. Quay lại\nChọn: '
  IFS= read -r choice || return 0
  case "$choice" in
    1) kw_tunnel_guide ;;
    2)
      kw_tunnel_tokenfile_supported || { kw_log ERROR 'cloudflared cần bản 2025.4.0 trở lên cho --token-file.'; return 2; }
      kw_tunnel_guide --no-site-prompt
      while :; do
        printf 'Dán Tunnel token (hiển thị khi nhập; 0 hoặc Enter để quay lại): '
        IFS= read -r token || return 0
        [[ $token != 0 && -n $token ]] || return 0
        kw_tunnel_token_valid "$token" && break
        printf 'Tunnel token không hợp lệ (40–4096 ký tự, không khoảng trắng). Nhập lại.\n'
      done
      kw_prompt_yes_no_token 'Lưu token và khởi động cloudflared.service?' CONFIGURE-CLOUDFLARED || return 0
      kw_tunnel_configure "$token" "$KW_PROMPT_VALUE" ;;
    3) kw_tunnel_status ;;
    4) kw_tunnel_site_mode_interactive ;;
    *) return 0 ;;
  esac
}

# Manage public ingress only. Nginx keeps listening on loopback for cloudflared.
kw_tunnel_inbound_rules() {
  LC_ALL=C ufw status numbered | awk '
    /ALLOW IN/ && /(^|[[:space:]])(80|443)\/tcp([[:space:]]|$)/ {
      if ($0 ~ /(^|[[:space:]])80\/tcp([[:space:]]|$)/) p=80; else p=443
      if ($0 ~ /\(v6\)/) v=6; else v=4
      print p, v
    }'
}

kw_tunnel_acme_renewals() {
  local file
  shopt -s nullglob
  for file in /etc/letsencrypt/renewal/*.conf; do
    [[ -f $file && ! -L $file ]] || continue
    grep -Eq '^authenticator[[:space:]]*=[[:space:]]*webroot' "$file" && printf '%s\n' "$file"
  done
  shopt -u nullglob
}

kw_tunnel_inbound_change() (
  local action=$1 rules renewals port
  ((EUID == 0)) || { kw_log ERROR 'Cần root để đổi inbound 80/443.'; return 2; }
  kw_fw_ready || return 2
  [[ $action == close || $action == open ]] || return 2
  if [[ $action == close ]]; then
    systemctl is-active --quiet cloudflared.service || {
      kw_log ERROR 'Tunnel chưa active; giữ inbound 80/443.'; return 2;
    }
    LC_ALL=C ufw status verbose | grep -Eq '^Default: deny \(incoming\)' || {
      kw_log ERROR 'UFW không mặc định deny incoming; không thể bảo đảm đóng cổng bằng cách gỡ ALLOW.'; return 2;
    }
    renewals=$(kw_tunnel_acme_renewals) || return 2
    if [[ -n $renewals ]]; then
      printf 'Phát hiện chứng chỉ HTTP-01 webroot:\n%s\n' "$renewals"
      kw_has certbot || { kw_log ERROR 'Thiếu certbot; giữ cổng 80.'; return 2; }
    fi
    rules=$(kw_tunnel_inbound_rules) || return 2
    if [[ -z $rules ]]; then printf 'Inbound 80/443 đã không có ALLOW trong UFW.\n'; return 0; fi
    # UFW removes matching IPv4 and IPv6 rules together. Roll back both on failure.
    trap 'for port in 80 443; do [[ $rules != *"$port "* ]] || ufw allow "$port/tcp" >/dev/null; done; kw_log WARN "Đã khôi phục ALLOW 80/443 sau lỗi; kiểm tra ufw status numbered."' EXIT
    for port in 80 443; do
      [[ $rules == *"$port "* ]] || continue
      ufw --force delete allow "$port/tcp" || return 1
    done
    if [[ -n $(kw_tunnel_inbound_rules) ]]; then
      kw_log ERROR 'Vẫn còn rule ALLOW inbound 80/443; sẽ khôi phục trạng thái trước đó.'
      return 1
    fi
    if [[ -n $renewals ]]; then
      printf 'Đang thử gia hạn ACME qua Tunnel khi inbound đã đóng...\n'
      certbot renew --dry-run --no-random-sleep-on-renew --non-interactive --quiet || {
        kw_log ERROR 'Thử gia hạn HTTP-01 thất bại; sẽ mở lại inbound 80/443.'; return 1;
      }
    fi
    trap - EXIT
    printf 'Đã đóng inbound UFW 80/443; Nginx local và outbound Tunnel không đổi.\n'
  else
    for port in 80 443; do
      if ! kw_tunnel_inbound_rules | grep -q "^$port "; then
        ufw allow "$port/tcp" comment "kwvps-port-$port-tcp" || return 1
      fi
    done
    printf 'Đã mở inbound UFW 80/443.\n'
  fi
  LC_ALL=C ufw status numbered
)

kw_tunnel_inbound_interactive() {
  local choice
  printf 'Inbound 80/443 chỉ là firewall UFW, không tắt Nginx local.\n'
  printf 'Đóng cổng 80 có thể ảnh hưởng HTTP-01; KwVPS sẽ thử gia hạn ACME và khôi phục nếu lỗi.\n'
  printf 'Firewall nhà cung cấp VPS nằm ngoài KwVPS.\n1. Đóng inbound 80/443\n2. Mở inbound 80/443\n0. Quay lại\nChọn: '
  IFS= read -r choice || return 0
  case "$choice" in
    1) kw_prompt_yes_no_token 'Đóng inbound 80/443 của toàn VPS?' TUNNEL-CLOSE-INBOUND || return 0
       kw_tunnel_inbound_change close ;;
    2) kw_prompt_yes_no_token 'Mở inbound 80/443 của toàn VPS?' TUNNEL-OPEN-INBOUND || return 0
       kw_tunnel_inbound_change open ;;
    *) return 0 ;;
  esac
}
