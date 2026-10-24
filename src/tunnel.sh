#!/usr/bin/env bash
# Remotely-managed Cloudflare Tunnel: apt package, root-only token and service.
# Hostname/DNS routes remain in the Cloudflare dashboard; ports 80/443 are untouched.

readonly KW_TUNNEL_KEY=/usr/share/keyrings/kwvps-cloudflare-main.gpg
readonly KW_TUNNEL_REPO=/etc/apt/sources.list.d/kwvps-cloudflared.list
readonly KW_TUNNEL_TOKEN=/etc/kwvps/cloudflare/tunnel-token
readonly KW_TUNNEL_UNIT=/etc/systemd/system/cloudflared.service
readonly KW_TUNNEL_SITE_DIR=/etc/kwvps/cloudflare/tunnels

kw_tunnel_site_paths() {
  local domain=${1,,} id
  kw_domain_valid "$domain" || return 2
  id=$(kw_site_id "$domain") || return 2
  KW_TUNNEL_SITE_ID=$id
  KW_TUNNEL_SITE_TOKEN="$KW_TUNNEL_SITE_DIR/$id.token"
  KW_TUNNEL_SITE_UNIT="/etc/systemd/system/kwvps-cloudflared-$id.service"
  KW_TUNNEL_SITE_UNIT_NAME="kwvps-cloudflared-$id.service"
}

kw_tunnel_render_site_unit() {
  local id=${1:-}
  kw_site_id_valid "$id" || return 2
  printf '%s\n' \
    '# Managed by KwVPS. Site Cloudflare Tunnel.' \
    '[Unit]' \
    "Description=Cloudflare Tunnel (KwVPS site $id)" \
    'Wants=network-online.target' \
    'After=network-online.target' \
    '[Service]' \
    'Type=simple' \
    "ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run --token-file $KW_TUNNEL_SITE_DIR/$id.token" \
    'Restart=on-failure' \
    'RestartSec=5s' \
    'NoNewPrivileges=yes' \
    '[Install]' \
    'WantedBy=multi-user.target'
}

kw_tunnel_site_service_owned() {
  kw_tunnel_site_paths "$1" || return 2
  [[ -f $KW_TUNNEL_SITE_UNIT && ! -L $KW_TUNNEL_SITE_UNIT &&
     $(stat -c %u:%a -- "$KW_TUNNEL_SITE_UNIT") == 0:644 ]] || return 1
  cmp -s -- "$KW_TUNNEL_SITE_UNIT" <(kw_tunnel_render_site_unit "$KW_TUNNEL_SITE_ID")
}

kw_tunnel_site_token_safe() {
  kw_tunnel_site_paths "$1" || return 2
  [[ -d /etc/kwvps/cloudflare && ! -L /etc/kwvps/cloudflare &&
     $(stat -c %u:%a -- /etc/kwvps/cloudflare) == 0:700 &&
     -d $KW_TUNNEL_SITE_DIR && ! -L $KW_TUNNEL_SITE_DIR &&
     $(stat -c %u:%a -- "$KW_TUNNEL_SITE_DIR") == 0:700 &&
     -f $KW_TUNNEL_SITE_TOKEN && ! -L $KW_TUNNEL_SITE_TOKEN &&
     $(stat -c %u:%a -- "$KW_TUNNEL_SITE_TOKEN") == 0:600 ]]
}

kw_tunnel_site_connector_present() {
  kw_tunnel_site_paths "$1" || return 2
  [[ -e $KW_TUNNEL_SITE_UNIT || -L $KW_TUNNEL_SITE_UNIT ||
     -e $KW_TUNNEL_SITE_TOKEN || -L $KW_TUNNEL_SITE_TOKEN ]]
}

kw_tunnel_legacy_token_safe() {
  [[ -d /etc/kwvps/cloudflare && ! -L /etc/kwvps/cloudflare &&
     $(stat -c %u:%a -- /etc/kwvps/cloudflare) == 0:700 &&
     -f $KW_TUNNEL_TOKEN && ! -L $KW_TUNNEL_TOKEN &&
     $(stat -c %u:%a -- "$KW_TUNNEL_TOKEN") == 0:600 ]]
}

kw_tunnel_connector_active_for_site() {
  local domain=${1,,}
  kw_tunnel_site_paths "$domain" || return 2
  if kw_tunnel_site_connector_present "$domain"; then
    kw_tunnel_site_service_owned "$domain" && kw_tunnel_site_token_safe "$domain" &&
      systemctl is-active --quiet "$KW_TUNNEL_SITE_UNIT_NAME"
  else
    systemctl is-active --quiet cloudflared.service
  fi
}

kw_tunnel_collect_connectors() {
  local file domain id key value
  ((EUID == 0)) || { kw_log ERROR 'Cần chạy sudo kwvps để xem connector Tunnel.'; return 2; }
  KW_TUNNEL_CONNECTOR_UNITS=()
  KW_TUNNEL_CONNECTOR_LABELS=()
  for file in /etc/kwvps/sites/*.site; do
    [[ -f $file && ! -L $file && -r $file ]] || continue
    domain=''; id=''
    while IFS='=' read -r key value; do
      case "$key" in domain) domain=$value ;; site_id) id=$value ;; esac
    done < "$file"
    if ! kw_domain_valid "$domain" || ! kw_site_id_valid "$id" ||
       [[ $file != "/etc/kwvps/sites/$id.site" ]]; then
      continue
    fi
    kw_tunnel_site_paths "$domain" || return 2
    [[ $KW_TUNNEL_SITE_ID == "$id" ]] || return 2
    if kw_tunnel_site_connector_present "$domain"; then
      if ! kw_tunnel_site_service_owned "$domain" || ! kw_tunnel_site_token_safe "$domain"; then
        kw_log ERROR "Connector của $domain có file hoặc quyền không an toàn; cần kiểm tra thủ công."
        return 2
      fi
      KW_TUNNEL_CONNECTOR_UNITS+=("$KW_TUNNEL_SITE_UNIT_NAME")
      KW_TUNNEL_CONNECTOR_LABELS+=("$domain")
    fi
  done
  if [[ -e $KW_TUNNEL_UNIT || -L $KW_TUNNEL_UNIT ||
        -e $KW_TUNNEL_TOKEN || -L $KW_TUNNEL_TOKEN ]]; then
    if ! kw_tunnel_service_owned || ! kw_tunnel_legacy_token_safe; then
      kw_log ERROR 'Connector chung cũ có file hoặc quyền không an toàn; cần kiểm tra thủ công.'
      return 2
    fi
    KW_TUNNEL_CONNECTOR_UNITS+=(cloudflared.service)
    KW_TUNNEL_CONNECTOR_LABELS+=('Connector chung cũ')
  fi
}

kw_tunnel_status_all() {
  local i state
  kw_tunnel_collect_connectors || return 2
  if ((${#KW_TUNNEL_CONNECTOR_UNITS[@]} == 0)); then
    printf 'Chưa có connector Tunnel do KwVPS quản lý.\n'
    return 0
  fi
  for ((i = 0; i < ${#KW_TUNNEL_CONNECTOR_UNITS[@]}; i++)); do
    state=$(systemctl is-active "${KW_TUNNEL_CONNECTOR_UNITS[i]}" 2>/dev/null) || :
    [[ -n $state ]] || state=unknown
    printf '%d. %s | %s | %s\n' "$((i + 1))" "${KW_TUNNEL_CONNECTOR_LABELS[i]}" \
      "${KW_TUNNEL_CONNECTOR_UNITS[i]}" "$state"
  done
  printf 'Service active chưa chứng minh route/hostname công khai hoạt động.\n'
}

kw_tunnel_choose_connector() {
  local i choice
  kw_tunnel_collect_connectors || return 2
  if ((${#KW_TUNNEL_CONNECTOR_UNITS[@]} == 0)); then
    printf 'Chưa có connector Tunnel do KwVPS quản lý.\n'
    return 1
  fi
  printf 'Chọn connector Tunnel:\n'
  for ((i = 0; i < ${#KW_TUNNEL_CONNECTOR_UNITS[@]}; i++)); do
    printf '%d. %s\n' "$((i + 1))" "${KW_TUNNEL_CONNECTOR_LABELS[i]}"
  done
  printf '0. Quay lại\nChọn: '
  IFS= read -r choice || return 1
  [[ $choice =~ ^[0-9]+$ ]] || return 1
  ((choice >= 1 && choice <= ${#KW_TUNNEL_CONNECTOR_UNITS[@]})) || return 1
  # shellcheck disable=SC2034 # Read by system.sh menu actions.
  KW_TUNNEL_CHOICE_UNIT=${KW_TUNNEL_CONNECTOR_UNITS[choice-1]}
  # shellcheck disable=SC2034 # Read by system.sh menu actions.
  KW_TUNNEL_CHOICE_LABEL=${KW_TUNNEL_CONNECTOR_LABELS[choice-1]}
}

kw_tunnel_any_active() {
  local unit
  kw_tunnel_collect_connectors || return 1
  for unit in "${KW_TUNNEL_CONNECTOR_UNITS[@]}"; do
    systemctl is-active --quiet "$unit" && return 0
  done
  return 1
}

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
    if kw_tunnel_connector_active_for_site "$1" 2>/dev/null; then
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

kw_tunnel_realip_vhost_stage() {
  local domain=$1 mode=$2 candidate=$3 id
  kw_site_lookup "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  [[ -f $KW_SITE_VHOST && ! -L $KW_SITE_VHOST &&
     $(stat -c %u -- "$KW_SITE_VHOST") == 0 &&
     -L $KW_SITE_ENABLED &&
     $(readlink -f -- "$KW_SITE_ENABLED") == "$KW_SITE_VHOST" ]] || {
    kw_log ERROR "Vhost $domain không còn do KwVPS quản lý; chưa đổi chế độ Tunnel."
    return 2
  }
  if [[ $mode == tunnel ]] && ! kw_cf_realip_public_config_valid; then
    kw_log ERROR 'Cấu hình Cloudflare Real IP công khai chưa an toàn; cập nhật mục Cloudflare Real IP trước.'
    return 2
  fi
  if ! kw_cf_realip_vhost_overlay "$mode" "$domain" "$id" "$KW_SITE_VHOST" > "$candidate"; then
    kw_log ERROR "Vhost $domain có cấu trúc/Real IP tùy biến; chưa tự chèn Tunnel Real IP. Kiểm tra vhost thủ công."
    return 2
  fi
}

kw_tunnel_ensure_realip() {
  kw_cf_realip_public_config_valid && return 0
  printf 'Cloudflare Real IP chưa sẵn sàng; đang cập nhật dải IP Cloudflare và kiểm tra/restart Nginx.\n'
  kw_cf_realip_apply UPDATE-CLOUDFLARE-REALIP || {
    kw_log ERROR 'Không cập nhật được Cloudflare Real IP; giữ nguyên chế độ site.'
    return 2
  }
  kw_cf_realip_public_config_valid || return 2
}

kw_tunnel_site_mode_set() (
  local domain=${1,,} mode=$2 confirm=$3 path stage='' vhost_temp='' old_mode='' backup=''
  local vhost='' changed_vhost=0 changed_mode=0 committed=0
  kw_domain_valid "$domain" && [[ $mode == dns || $mode == tunnel ]] &&
    [[ $confirm == "INGRESS:$domain:$mode" ]] || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  kw_site_lookup "$domain" && kw_nginx_ready || return 2
  nginx -t >/dev/null 2>&1 || return 2
  if [[ $mode == tunnel ]]; then
    [[ ! -e /etc/kwvps/cloudflare/antiddos/$domain.rate &&
       ! -L /etc/kwvps/cloudflare/antiddos/$domain.rate ]] || {
      kw_log ERROR 'Tắt Nginx rate limit cho site này trước khi chọn Tunnel.'; return 2;
    }
    kw_tunnel_connector_active_for_site "$domain" || {
      kw_log ERROR "Connector Tunnel cho $domain chưa active; cấu hình token theo site hoặc kiểm tra connector chung cũ."; return 2;
    }
    kw_tunnel_ensure_realip || return 2
  fi
  # Follow the sites -> nginx -> cloudflare order used by domain rename.
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || return 1
  exec 8>/run/lock/kwvps-nginx.lock || return 2
  flock -n 8 || return 1
  exec 7>/run/lock/kwvps-cloudflare.lock || return 2
  flock -n 7 || return 1
  kw_site_lookup "$domain" || return 2
  if [[ $mode == tunnel ]]; then
    [[ ! -e /etc/kwvps/cloudflare/antiddos/$domain.rate &&
       ! -L /etc/kwvps/cloudflare/antiddos/$domain.rate ]] || return 2
    kw_tunnel_connector_active_for_site "$domain" || return 2
  fi
  install -d -o root -g root -m 0700 -- /etc/kwvps/ingress || return 1
  [[ -d /etc/kwvps/ingress && ! -L /etc/kwvps/ingress &&
     $(stat -c %u:%a -- /etc/kwvps/ingress) == 0:700 ]] || return 2
  path=$(kw_tunnel_site_mode_path "$domain") || return 2
  [[ ! -e $path && ! -L $path ]] || {
    [[ -f $path && ! -L $path && $(stat -c %u:%a -- "$path") == 0:600 ]] || return 2;
    IFS= read -r old_mode < "$path" || return 2
    [[ $old_mode == dns || $old_mode == tunnel ]] || return 2
  }
  vhost=$KW_SITE_VHOST
  vhost_temp=$(mktemp /etc/nginx/sites-available/.kwvps-tunnel-realip.XXXXXXXX) || return 1
  trap 'if (( ! committed )); then if ((changed_vhost)); then install -m 0644 -o root -g root -- "$backup" "$vhost" || kw_log ERROR "Cần phục hồi vhost từ $backup"; fi; if ((changed_mode)); then if [[ -n $old_mode ]]; then printf "%s\n" "$old_mode" > "$path" && chmod 0600 -- "$path" || kw_log ERROR "Cần phục hồi chế độ ingress: $path"; else rm -f -- "$path" || kw_log ERROR "Cần gỡ chế độ ingress mới: $path"; fi; fi; if ((changed_vhost)); then kw_nginx_test_restart || kw_log ERROR "Cần kiểm tra Nginx sau rollback: $domain"; fi; fi; [[ -z $stage ]] || rm -f -- "$stage"; [[ -z $vhost_temp ]] || rm -f -- "$vhost_temp"' EXIT
  kw_tunnel_realip_vhost_stage "$domain" "$mode" "$vhost_temp" || return 2
  if ! cmp -s -- "$vhost_temp" "$vhost"; then
    kw_nginx_backup_file "$vhost" "tunnel-realip-${KW_SITE_OWNER#kw}" || return 1
    backup=$KW_NGINX_BACKUP
    chmod 0644 -- "$vhost_temp" || return 1
    mv -T -- "$vhost_temp" "$vhost" || return 1
    vhost_temp=''
    changed_vhost=1
  fi
  if [[ $old_mode != "$mode" ]]; then
    stage=$(mktemp /etc/kwvps/ingress/.mode.XXXXXXXX) || return 1
    chmod 0600 -- "$stage" || return 1
    printf '%s\n' "$mode" > "$stage" || return 1
    mv -T -- "$stage" "$path" || return 1
    stage=''
    # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
    changed_mode=1
  fi
  if ((changed_vhost)); then kw_nginx_test_restart || return 1; fi
  committed=1
  printf 'Đã ghi chế độ %s cho %s; Route/DNS trên Cloudflare cần đối chiếu riêng.\n' "$mode" "$domain"
  if ((changed_vhost)); then
    printf 'Đã áp Real IP riêng cho vhost Tunnel và restart Nginx; bản trước: %s\n' "$backup"
    printf 'Lưu ý: tiến trình local có thể giả CF-Connecting-IP khi gọi loopback của site Tunnel.\n'
  fi
)

kw_tunnel_site_mode_interactive() {
  local domain mode current
  ((EUID == 0)) || { kw_log ERROR 'Cần chạy sudo kwvps để đổi chế độ Tunnel/DNS.'; return 2; }
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  current=$(kw_tunnel_site_mode "$domain") || return 2
  printf '%s đang ghi nhận: %s\n' "$domain" "$current"
  [[ $current != unknown ]] || printf 'Chưa phân loại vì cloudflared đang chạy; kiểm tra route trên Dashboard trước khi chọn.\n'
  printf '1. Tunnel\n2. DNS thông thường (DNS only hoặc đám mây cam)\n0. Quay lại\nChọn: '
  local choice
  IFS= read -r choice || return 0
  case "$choice" in 1) mode=tunnel ;; 2) mode=dns ;; *) return 0 ;; esac
  printf 'Chỉ cập nhật trạng thái KwVPS; không tự tạo/xóa route hay DNS trên Cloudflare.\n'
  kw_prompt_yes_no_token "Ghi chế độ $mode cho $domain?" "INGRESS:$domain:$mode" || return 0
  kw_tunnel_site_mode_set "$domain" "$mode" "$KW_PROMPT_VALUE"
}

kw_tunnel_post_config_interactive() {
  local domain=${1:-} current
  printf 'Chỉ bật chế độ Tunnel cho site đã tạo route tới VPS trong Cloudflare Dashboard.\n'
  if [[ -z $domain ]]; then
    printf 'Chọn site cần bật; 0 để bỏ qua.\n'
    kw_site_prompt_domain || return 0
    domain=$KW_SITE_CHOICE
  fi
  current=$(kw_tunnel_site_mode "$domain") || return 2
  if [[ $current == tunnel ]]; then
    printf '%s đã ghi nhận Tunnel. Có thể đồng bộ lại Cloudflare Real IP và vhost.\n' "$domain"
    kw_prompt_yes_no_token "Cập nhật Real IP cho $domain nếu còn thiếu?" "INGRESS:$domain:tunnel" || return 0
    kw_tunnel_site_mode_set "$domain" tunnel "$KW_PROMPT_VALUE"
    return $?
  fi
  printf 'KwVPS không tự tạo route/DNS; site chưa có route thật có thể không truy cập được.\n'
  kw_prompt_yes_no_token "Bật chế độ Tunnel và Real IP cho $domain?" "INGRESS:$domain:tunnel" || return 0
  kw_tunnel_site_mode_set "$domain" tunnel "$KW_PROMPT_VALUE" || {
    kw_log WARN 'Token/service đã lưu, nhưng chưa đổi chế độ site; dùng mục 4 sau khi xử lý lỗi.'
    return 1
  }
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

kw_tunnel_site_configure() (
  local domain=${1,,} token=${2:-} confirm=${3:-} token_tmp='' unit_tmp=''
  local old_token='' old_unit='' touched=0 committed=0 was_active=0 was_enabled=0
  [[ $confirm == "CONFIGURE-TUNNEL:$domain" ]] && kw_tunnel_token_valid "$token" || return 2
  ((EUID == 0)) && kw_os_supported '' && kw_tunnel_tokenfile_supported || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id &&
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  kw_site_lookup "$domain" && kw_tunnel_site_paths "$domain" || return 2
  kw_has systemctl && kw_has flock && kw_has mktemp || return 2
  if systemctl cat "$KW_TUNNEL_SITE_UNIT_NAME" >/dev/null 2>&1 &&
     ! kw_tunnel_site_service_owned "$domain"; then
    kw_log ERROR 'Service Tunnel theo site có cấu hình ngoài KwVPS; không ghi đè.'
    return 2
  fi
  if [[ -e $KW_TUNNEL_SITE_UNIT || -L $KW_TUNNEL_SITE_UNIT ]]; then
    kw_tunnel_site_service_owned "$domain" || return 2
    kw_tunnel_site_token_safe "$domain" || return 2
  else
    [[ ! -e $KW_TUNNEL_SITE_TOKEN && ! -L $KW_TUNNEL_SITE_TOKEN ]] || return 2
  fi
  exec 9>/run/lock/kwvps-tunnel.lock || return 2
  flock -n 9 || return 1
  exec 8>/run/lock/kwvps-cloudflare.lock || return 2
  flock -n 8 || return 1
  kw_site_lookup "$domain" && kw_tunnel_site_paths "$domain" || return 2
  [[ -d /etc/kwvps && ! -L /etc/kwvps && $(stat -c %u -- /etc/kwvps) == 0 ]] || return 2
  if [[ ! -e /etc/kwvps/cloudflare && ! -L /etc/kwvps/cloudflare ]]; then
    install -d -m 0700 -o root -g root -- /etc/kwvps/cloudflare || return 1
  fi
  [[ -d /etc/kwvps/cloudflare && ! -L /etc/kwvps/cloudflare &&
     $(stat -c %u:%a -- /etc/kwvps/cloudflare) == 0:700 ]] || return 2
  if [[ ! -e $KW_TUNNEL_SITE_DIR && ! -L $KW_TUNNEL_SITE_DIR ]]; then
    install -d -m 0700 -o root -g root -- "$KW_TUNNEL_SITE_DIR" || return 1
  fi
  [[ -d $KW_TUNNEL_SITE_DIR && ! -L $KW_TUNNEL_SITE_DIR &&
     $(stat -c %u:%a -- "$KW_TUNNEL_SITE_DIR") == 0:700 ]] || return 2
  trap 'if ((touched && ! committed)); then if [[ -n $old_token ]]; then cp -p -- "$old_token" "$KW_TUNNEL_SITE_TOKEN" || kw_log ERROR "Cần khôi phục token $domain"; else rm -f -- "$KW_TUNNEL_SITE_TOKEN"; fi; if [[ -n $old_unit ]]; then cp -p -- "$old_unit" "$KW_TUNNEL_SITE_UNIT" || kw_log ERROR "Cần khôi phục service $domain"; else systemctl disable --now "$KW_TUNNEL_SITE_UNIT_NAME" >/dev/null 2>&1 || true; rm -f -- "$KW_TUNNEL_SITE_UNIT"; fi; systemctl daemon-reload || true; if [[ -n $old_unit ]]; then if ((was_enabled)); then systemctl enable "$KW_TUNNEL_SITE_UNIT_NAME" >/dev/null || true; else systemctl disable "$KW_TUNNEL_SITE_UNIT_NAME" >/dev/null 2>&1 || true; fi; if ((was_active)); then systemctl restart "$KW_TUNNEL_SITE_UNIT_NAME" || kw_log ERROR "Cần khởi động lại connector $domain"; else systemctl stop "$KW_TUNNEL_SITE_UNIT_NAME" || true; fi; fi; fi; [[ -z $token_tmp ]] || rm -f -- "$token_tmp"; [[ -z $unit_tmp ]] || rm -f -- "$unit_tmp"; [[ -z $old_token ]] || rm -f -- "$old_token"; [[ -z $old_unit ]] || rm -f -- "$old_unit"' EXIT
  if [[ -f $KW_TUNNEL_SITE_UNIT ]]; then
    kw_tunnel_site_service_owned "$domain" && kw_tunnel_site_token_safe "$domain" || return 2
    systemctl is-active --quiet "$KW_TUNNEL_SITE_UNIT_NAME" && was_active=1
    systemctl is-enabled --quiet "$KW_TUNNEL_SITE_UNIT_NAME" && was_enabled=1
    old_token=$(mktemp /run/kwvps-site-tunnel-token-old.XXXXXXXX) || return 1
    old_unit=$(mktemp /run/kwvps-site-tunnel-unit-old.XXXXXXXX) || return 1
    cp -p -- "$KW_TUNNEL_SITE_TOKEN" "$old_token" || return 1
    cp -p -- "$KW_TUNNEL_SITE_UNIT" "$old_unit" || return 1
  else
    [[ ! -e $KW_TUNNEL_SITE_UNIT && ! -L $KW_TUNNEL_SITE_UNIT &&
       ! -e $KW_TUNNEL_SITE_TOKEN && ! -L $KW_TUNNEL_SITE_TOKEN ]] || return 2
  fi
  token_tmp=$(mktemp "$KW_TUNNEL_SITE_DIR/.token.XXXXXXXX") || return 1
  chmod 0600 -- "$token_tmp" || return 1
  printf '%s\n' "$token" > "$token_tmp" || return 1
  unit_tmp=$(mktemp /etc/systemd/system/.kwvps-site-tunnel.XXXXXXXX) || return 1
  kw_tunnel_render_site_unit "$KW_TUNNEL_SITE_ID" > "$unit_tmp" || return 1
  chmod 0644 -- "$unit_tmp" || return 1
  mv -T -- "$token_tmp" "$KW_TUNNEL_SITE_TOKEN" || return 1
  token_tmp=''
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  touched=1
  mv -T -- "$unit_tmp" "$KW_TUNNEL_SITE_UNIT" || return 1
  unit_tmp=''
  systemctl daemon-reload || return 1
  systemctl enable "$KW_TUNNEL_SITE_UNIT_NAME" || return 1
  systemctl restart "$KW_TUNNEL_SITE_UNIT_NAME" || return 1
  sleep 3
  systemctl is-active --quiet "$KW_TUNNEL_SITE_UNIT_NAME" || {
    kw_log ERROR "Connector Tunnel cho $domain chưa active; kiểm tra token và egress 7844."
    return 1
  }
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  committed=1
  printf 'Connector %s active; token riêng của %s chỉ nằm trong file root-only.\n' \
    "$KW_TUNNEL_SITE_UNIT_NAME" "$domain"
)

kw_tunnel_site_remove() (
  local domain=${1,,} confirm=${2:-} mode stage='' was_active=0 was_enabled=0 touched=0 committed=0
  kw_domain_valid "$domain" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id &&
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  kw_site_lookup "$domain" && kw_tunnel_site_paths "$domain" || return 2
  mode=$(kw_tunnel_site_mode "$domain") || return 2
  [[ $mode == dns ]] || {
    kw_log ERROR 'Chuyển site sang DNS ở mục 4 sau khi đổi route trước khi gỡ connector.'
    return 2
  }
  kw_tunnel_site_service_owned "$domain" && kw_tunnel_site_token_safe "$domain" || return 2
  exec 9>/run/lock/kwvps-tunnel.lock || return 2
  flock -n 9 || return 1
  exec 8>/run/lock/kwvps-cloudflare.lock || return 2
  flock -n 8 || return 1
  kw_site_lookup "$domain" && kw_tunnel_site_paths "$domain" || return 2
  kw_tunnel_site_service_owned "$domain" && kw_tunnel_site_token_safe "$domain" || return 2
  [[ $(kw_tunnel_site_mode "$domain") == dns ]] || return 2
  # shellcheck disable=SC2034 # Rollback trap reads prior service state.
  systemctl is-active --quiet "$KW_TUNNEL_SITE_UNIT_NAME" && was_active=1
  # shellcheck disable=SC2034 # Rollback trap reads prior enable state.
  systemctl is-enabled --quiet "$KW_TUNNEL_SITE_UNIT_NAME" && was_enabled=1
  stage=$(mktemp -d /run/kwvps-site-tunnel-remove.XXXXXXXX) || return 1
  trap 'if ((touched && ! committed)); then cp -p -- "$stage/token" "$KW_TUNNEL_SITE_TOKEN" || kw_log ERROR "Cần khôi phục token $domain"; cp -p -- "$stage/unit" "$KW_TUNNEL_SITE_UNIT" || kw_log ERROR "Cần khôi phục service $domain"; systemctl daemon-reload || true; if ((was_enabled)); then systemctl enable "$KW_TUNNEL_SITE_UNIT_NAME" >/dev/null || true; fi; if ((was_active)); then systemctl restart "$KW_TUNNEL_SITE_UNIT_NAME" || kw_log ERROR "Cần khởi động lại connector $domain"; fi; fi; if [[ -n $stage ]]; then rm -f -- "$stage/token" "$stage/unit"; rmdir -- "$stage" || true; fi' EXIT
  chmod 0700 -- "$stage" || return 1
  cp -p -- "$KW_TUNNEL_SITE_TOKEN" "$stage/token" || return 1
  cp -p -- "$KW_TUNNEL_SITE_UNIT" "$stage/unit" || return 1
  # shellcheck disable=SC2034 # Rollback trap reads mutation marker.
  touched=1
  systemctl disable --now "$KW_TUNNEL_SITE_UNIT_NAME" || return 1
  rm -f -- "$KW_TUNNEL_SITE_UNIT" "$KW_TUNNEL_SITE_TOKEN" || return 1
  systemctl daemon-reload || return 1
  systemctl is-active --quiet "$KW_TUNNEL_SITE_UNIT_NAME" && return 1
  # shellcheck disable=SC2034 # Rollback trap reads commit marker.
  committed=1
  printf 'Đã gỡ connector và token riêng của %s. Connector chung cũ không thay đổi.\n' "$domain"
)

kw_tunnel_site_remove_interactive() {
  local domain confirm
  ((EUID == 0)) || { kw_log ERROR 'Cần chạy sudo kwvps để gỡ connector Tunnel.'; return 2; }
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_tunnel_site_paths "$domain" || return 2
  if ! kw_tunnel_site_connector_present "$domain"; then
    printf '%s chưa có connector/token riêng.\n' "$domain"
    return 0
  fi
  printf 'Sẽ dừng %s và xóa token riêng của %s. Route trên Cloudflare không tự đổi.\n' \
    "$KW_TUNNEL_SITE_UNIT_NAME" "$domain"
  kw_prompt_confirm_domain "$domain" 'Nhập lại đúng domain để GỠ connector: ' || return 0
  confirm=$KW_PROMPT_VALUE
  kw_tunnel_site_remove "$domain" "${confirm,,}"
}

kw_tunnel_guide() {
  printf '%s\n' \
    '1) Cloudflare Dashboard → Networking → Tunnels → Create Tunnel → chọn loại Cloudflared.' \
    '2) Tạo Tunnel quản lý trên Cloudflare, sao chép riêng Tunnel token (không dán cả lệnh cài).' \
    '3) Chọn site rồi lưu Tunnel token riêng cho site đó; không gửi token qua chat.' \
    '4) Trong Tunnel → Routes → Add route → Published application: chọn hostname của site KwVPS.' \
    '   Sau khi route hoạt động, ghi nhận chế độ Tunnel cho riêng site đó ở mục 4.' \
    '5) Site HTTP: Service URL http://127.0.0.1:80. Site HTTPS: https://127.0.0.1:443,' \
    '   đặt Origin Server Name bằng hostname thật để xác minh chứng chỉ; không bật Disable TLS verification.' \
    '6) Thử hostname từ ngoài và kiểm tra log. Có thể đóng inbound 80/443 sau khi mọi route,' \
    '   site và gia hạn SSL đã kiểm chứng; Nginx vẫn nghe local, cloudflared cần outbound 7844.' \
    '   KwVPS không tự đóng cổng. Tắt anti-DDoS local trước khi chuyển site sang Tunnel.' \
    'Mỗi site cấu hình riêng sẽ có token root-only và service cloudflared riêng.' \
    'Connector chung cloudflared.service cũ vẫn được giữ để site hiện tại không bị ngắt.' \
    'Tunnel token khác API token Cloudflare theo site ở menu Bảo mật/Cloudflare.'
  if kw_site_prompt_domain; then
    if kw_site_lookup "$KW_SITE_CHOICE" && [[ -f $KW_SITE_VHOST ]] &&
       grep -Eq 'ssl_certificate[[:space:]]' "$KW_SITE_VHOST"; then
      printf 'Site %s: HTTPS origin, chọn https://127.0.0.1:443 và Origin Server Name = %s.\n' \
        "$KW_SITE_CHOICE" "$KW_SITE_CHOICE"
    else
      printf 'Site %s: HTTP origin, chọn http://127.0.0.1:80.\n' "$KW_SITE_CHOICE"
    fi
  fi
}

kw_tunnel_site_config_interactive() {
  local domain token
  ((EUID == 0)) || { kw_log ERROR 'Cần chạy sudo kwvps để lưu Tunnel token.'; return 2; }
  kw_tunnel_tokenfile_supported || { kw_log ERROR 'cloudflared cần bản 2025.4.0 trở lên cho --token-file.'; return 2; }
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_tunnel_site_paths "$domain" || return 2
  printf 'Token riêng cho %s; connector: %s. Route/DNS trên Cloudflare vẫn cần cấu hình riêng.\n' \
    "$domain" "$KW_TUNNEL_SITE_UNIT_NAME"
  if [[ -e $KW_TUNNEL_SITE_TOKEN || -L $KW_TUNNEL_SITE_TOKEN ]]; then
    printf 'Thay token sẽ restart connector của site này. Kiểm tra route trước khi thay.\n'
  fi
  while :; do
    printf 'Dán Tunnel token (hiển thị khi nhập; 0 hoặc Enter để quay lại): '
    IFS= read -r token || return 0
    [[ $token != 0 && -n $token ]] || return 0
    kw_tunnel_token_valid "$token" && break
    printf 'Tunnel token không hợp lệ (40–4096 ký tự, không khoảng trắng). Nhập lại.\n'
  done
  kw_prompt_yes_no_token "Lưu token và khởi động connector cho $domain?" "CONFIGURE-TUNNEL:$domain" || return 0
  kw_tunnel_site_configure "$domain" "$token" "$KW_PROMPT_VALUE" || return $?
  kw_tunnel_post_config_interactive "$domain"
}

kw_tunnel_legacy_config_interactive() {
  local token
  ((EUID == 0)) || { kw_log ERROR 'Cần chạy sudo kwvps để lưu Tunnel token.'; return 2; }
  kw_tunnel_tokenfile_supported || { kw_log ERROR 'cloudflared cần bản 2025.4.0 trở lên cho --token-file.'; return 2; }
  printf 'Connector chung cũ có thể phục vụ nhiều site; thay token có thể gián đoạn tất cả site đang dùng nó.\n'
  while :; do
    printf 'Dán Tunnel token chung cũ (hiển thị khi nhập; 0 hoặc Enter để quay lại): '
    IFS= read -r token || return 0
    [[ $token != 0 && -n $token ]] || return 0
    kw_tunnel_token_valid "$token" && break
    printf 'Tunnel token không hợp lệ (40–4096 ký tự, không khoảng trắng). Nhập lại.\n'
  done
  kw_prompt_yes_no_token 'Lưu token và khởi động cloudflared.service chung cũ?' CONFIGURE-CLOUDFLARED || return 0
  kw_tunnel_configure "$token" "$KW_PROMPT_VALUE" || return $?
  kw_tunnel_post_config_interactive
}

kw_tunnel_config_interactive() {
  local choice
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
  printf '1. Hướng dẫn tạo Tunnel và route theo site\n2. Lưu/thay Tunnel token theo site\n3. Kiểm tra trạng thái connector\n4. Chế độ kết nối từng site (Tunnel/DNS)\n5. Gỡ connector/token riêng của site\n6. Token chung cũ (site đã dùng)\n0. Quay lại\nChọn: '
  IFS= read -r choice || return 0
  case "$choice" in
    1) kw_tunnel_guide ;;
    2) kw_tunnel_site_config_interactive ;;
    3) kw_tunnel_status_all ;;
    4) kw_tunnel_site_mode_interactive ;;
    5) kw_tunnel_site_remove_interactive ;;
    6) kw_tunnel_legacy_config_interactive ;;
    *) return 0 ;;
  esac
}

# Manage public ingress only. Nginx keeps listening on loopback for cloudflared.
kw_tunnel_acme_renewals() {
  local file
  shopt -s nullglob
  for file in /etc/letsencrypt/renewal/*.conf; do
    [[ -f $file && ! -L $file ]] || continue
    grep -Eq '^authenticator[[:space:]]*=[[:space:]]*webroot' "$file" && printf '%s\n' "$file"
  done
  shopt -u nullglob
}

kw_tunnel_inbound_rollback() {
  local port number
  local -a numbers
  ((inbound_committed == 0)) || return 0
  if [[ $action == open && $removed_attempted == 1 ]]; then
    for port in "${removed_ports[@]}"; do
      mapfile -t numbers < <(kw_fw_rule_numbers port-deny "$port" tcp)
      ((${#numbers[@]} == 0)) || continue
      ufw insert 1 deny "$port/tcp" comment "kwvps-port-deny-$port-tcp" 2>/dev/null ||
        ufw deny "$port/tcp" comment "kwvps-port-deny-$port-tcp" ||
        kw_log ERROR "Không phục hồi được DENY $port/tcp; kiểm tra UFW thủ công."
    done
  fi
  for port in "${created_ports[@]}"; do
    mapfile -t numbers < <(kw_fw_rule_numbers port-deny "$port" tcp | sort -nr)
    for number in "${numbers[@]}"; do
      ufw --force delete "$number" || kw_log ERROR "Không hoàn tác được DENY $port/tcp; kiểm tra UFW thủ công."
    done
  done
  for port in "${removed_allow_ports[@]}"; do
    ufw allow "$port/tcp" comment "kwvps-port-$port-tcp" ||
      kw_log ERROR "Không phục hồi được ALLOW $port/tcp; kiểm tra UFW thủ công."
  done
  if ((was_inactive)); then
    ufw --force disable || kw_log ERROR 'Không tắt lại được UFW sau lỗi; kiểm tra console cứu hộ.'
  fi
  kw_log WARN 'Thao tác inbound chưa hoàn tất; đã thử hoàn tác các rule mới.'
}

kw_tunnel_inbound_denied() {
  local port=$1
  kw_fw_port_has_action_family "$port" tcp DENY 4 &&
    kw_fw_port_has_action_family "$port" tcp DENY 6 &&
    ! kw_fw_port_has_action_family "$port" tcp ALLOW 4 &&
    ! kw_fw_port_has_action_family "$port" tcp ALLOW 6
}

kw_tunnel_inbound_close_rules() {
  local port line state number
  local -a numbers
  for port in 80 443; do
    if kw_tunnel_inbound_denied "$port"; then continue; fi
    state=$(LC_ALL=C ufw status numbered) || return 2
    while IFS= read -r line; do
      if [[ $line =~ ^\[[[:space:]]*[0-9]+\][[:space:]]+${port}/tcp[[:space:]] &&
            $line == *'ALLOW IN'* && $line != *"# kwvps-port-$port-tcp" ]]; then
        kw_log ERROR "Còn ALLOW $port/tcp ngoài KwVPS; không tự xóa rule này."
        return 2
      fi
    done <<< "$state"
    mapfile -t numbers < <(kw_fw_rule_numbers port "$port" tcp | sort -nr)
    if ((${#numbers[@]} > 0)); then
      removed_allow_ports+=("$port")
      for number in "${numbers[@]}"; do
        ufw --force delete "$number" || return 1
      done
    fi
    mapfile -t numbers < <(kw_fw_rule_numbers port-deny "$port" tcp)
    if ((${#numbers[@]} > 0)); then
      kw_tunnel_inbound_denied "$port" && continue
      kw_log ERROR "Rule DENY $port/tcp có sẵn nhưng chưa chặn đủ IPv4/IPv6; kiểm tra UFW thủ công."
      return 2
    fi
    # Record before invoking UFW: a command may add one family then fail.
    created_ports+=("$port")
    if ! ufw insert 1 deny "$port/tcp" comment "kwvps-port-deny-$port-tcp"; then
      kw_log WARN "UFW không chèn được DENY $port/tcp ở đầu; thử thêm rule thường."
      ufw deny "$port/tcp" comment "kwvps-port-deny-$port-tcp" || {
        kw_log ERROR "UFW từ chối tạo DENY $port/tcp; xem lỗi UFW ngay phía trên."
        return 1
      }
    fi
    kw_tunnel_inbound_denied "$port" || {
      kw_log ERROR "Không xác minh được DENY $port/tcp cho cả IPv4 và IPv6; trạng thái UFW hiện tại:"
      LC_ALL=C ufw status numbered >&2 || true
      return 1
    }
  done
}

kw_tunnel_inbound_change() (
  local action=$1 renewals='' port state line number ssh_ports ssh_port inbound_committed=0 was_inactive=0 removed_attempted=0
  local -a created_ports=() removed_ports=() removed_allow_ports=() numbers=()
  ((EUID == 0)) || { kw_log ERROR 'Cần root để đổi inbound 80/443.'; return 2; }
  [[ $action == close || $action == open ]] || return 2
  kw_has ufw && kw_has flock || return 2
  exec 9>/run/lock/kwvps-ufw.lock || return 2
  flock -n 9 || { kw_log ERROR 'Một thao tác UFW khác đang chạy.'; return 1; }
  if [[ $action == close ]]; then
    kw_tunnel_any_active || {
      kw_log ERROR 'Chưa có connector Tunnel KwVPS active; giữ inbound 80/443.'; return 2;
    }
    kw_fw_ipv6_enabled || {
      kw_log ERROR 'UFW IPV6 chưa bật; không thể bảo đảm đóng inbound 80/443 trên IPv6.'; return 2;
    }
    ssh_ports=$(kw_fw_ssh_ports) || return 2
    [[ -n $ssh_ports ]] || return 2
    while IFS= read -r ssh_port; do
      [[ $ssh_port != 80 && $ssh_port != 443 ]] || {
        kw_log ERROR "SSH đang dùng cổng $ssh_port; từ chối khóa inbound 80/443."
        return 2
      }
    done <<< "$ssh_ports"
    renewals=$(kw_tunnel_acme_renewals) || return 2
    if [[ -n $renewals ]]; then
      printf 'Phát hiện chứng chỉ HTTP-01 webroot:\n%s\n' "$renewals"
      kw_has certbot || { kw_log ERROR 'Thiếu certbot; giữ cổng 80.'; return 2; }
    fi
  fi
  state=$(LC_ALL=C ufw status) || return 2
  [[ $state == 'Status: inactive'* ]] && was_inactive=1
  trap kw_tunnel_inbound_rollback EXIT
  kw_fw_enable_safe || return 2
  if [[ $action == close ]]; then
    kw_tunnel_inbound_close_rules || return $?
    if [[ -n $renewals ]]; then
      printf 'Đang thử gia hạn ACME qua Tunnel khi inbound đã đóng...\n'
      certbot renew --dry-run --no-random-sleep-on-renew --non-interactive --quiet || {
        kw_log ERROR 'Thử gia hạn HTTP-01 thất bại; sẽ hoàn tác rule chặn 80/443.'; return 1;
      }
    fi
    printf 'Đã khóa inbound UFW 80/443 bằng DENY ưu tiên; Nginx local và outbound Tunnel không đổi.\n'
  else
    state=$(LC_ALL=C ufw status numbered) || return 2
    while IFS= read -r line; do
      for port in 80 443; do
        if [[ $line =~ ^\[[[:space:]]*[0-9]+\][[:space:]]+${port}/tcp[[:space:]] &&
              $line == *'DENY IN'* && $line != *"# kwvps-port-deny-$port-tcp" ]]; then
          kw_log ERROR "Còn rule DENY ngoài KwVPS cho $port/tcp; không tự thay rule này."
          return 2
        fi
      done
    done <<< "$state"
    for port in 80 443; do
      mapfile -t numbers < <(kw_fw_rule_numbers port-deny "$port" tcp)
      ((${#numbers[@]} == 0)) || removed_ports+=("$port")
    done
    mapfile -t numbers < <({ kw_fw_rule_numbers port-deny 80 tcp; kw_fw_rule_numbers port-deny 443 tcp; } | sort -nr)
    ((${#numbers[@]} == 0)) || removed_attempted=1
    for number in "${numbers[@]}"; do ufw --force delete "$number" || return 1; done
    for port in 80 443; do
      ufw allow "$port/tcp" comment "kwvps-port-$port-tcp" || return 1
      kw_fw_port_has_action "$port" tcp ALLOW || {
        kw_log ERROR "Không xác minh được ALLOW $port/tcp."; return 1;
      }
    done
    printf 'Đã mở inbound UFW 80/443.\n'
  fi
  inbound_committed=1
  trap - EXIT
  LC_ALL=C ufw status numbered
)

kw_tunnel_inbound_interactive() {
  local choice ufw_state
  ufw_state=$(LC_ALL=C ufw status 2>/dev/null || true)
  printf 'Inbound 80/443 chỉ là firewall UFW, không tắt Nginx local.\n'
  if [[ $ufw_state == 'Status: inactive'* ]]; then
    printf 'Lưu ý: UFW hiện đang TẮT. KwVPS sẽ tự động thêm rule ALLOW cho cổng SSH và kích hoạt UFW.\n'
  else
    printf 'Nếu UFW đang tắt, KwVPS sẽ bảo vệ SSH rồi tự bật UFW; các dịch vụ inbound khác có thể bị chặn.\n'
  fi
  printf 'Lần bật UFW để mở 80/443 có thể gián đoạn inbound ngắn trước khi ALLOW được thêm.\n'
  printf 'Đóng cổng 80 có thể ảnh hưởng HTTP-01; KwVPS sẽ thử gia hạn ACME và hoàn tác nếu lỗi.\n'
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
