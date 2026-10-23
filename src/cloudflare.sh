#!/usr/bin/env bash
# Trust only Cloudflare-published proxy ranges for CF-Connecting-IP in Nginx.

kw_cf_realip_target=/etc/nginx/conf.d/kwvps-cloudflare-realip.conf

kw_cf_realip_plan() {
  printf 'Cloudflare Real IP cho Nginx toàn VPS:\n'
  printf '  File: %s\n' "$kw_cf_realip_target"
  printf '  Nguồn: https://www.cloudflare.com/ips-v4 và /ips-v6\n'
  printf '  Chỉ tin CF-Connecting-IP khi kết nối đến từ dải IP Cloudflare chính thức.\n'
  printf '  Kiểm tra CIDR, nginx -t và reload; lỗi sẽ trả cấu hình cũ.\n'
  printf '  Không đóng/mở port hoặc bật AntiDDoS/Under Attack.\n'
}

kw_cf_realip_lines() {
  local path=$1 family=$2
  [[ -f $path && ! -L $path ]] || return 2
  python3 -c '
import ipaddress, pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text(encoding="ascii").splitlines()
family = int(sys.argv[2])
if not 1 <= len(lines) <= 100 or len(lines) != len(set(lines)):
    sys.exit(2)
for line in lines:
    if not line or line != line.strip():
        sys.exit(2)
    try:
        network = ipaddress.ip_network(line, strict=True)
    except ValueError:
        sys.exit(2)
    if network.version != family:
        sys.exit(2)
    print("set_real_ip_from " + str(network) + ";")
' "$path" "$family"
}

kw_cf_realip_rollback() {
  ((KW_CF_DONE == 0)) || return 0
  if [[ -n $KW_CF_OLD && -f $KW_CF_OLD ]]; then
    cp -a -- "$KW_CF_OLD" "$kw_cf_realip_target" || kw_log ERROR 'Không khôi phục được Real IP cũ.'
  elif ((KW_CF_REPLACED)); then
    rm -f -- "$kw_cf_realip_target" || kw_log ERROR 'Không gỡ được Real IP vừa tạo.'
  fi
  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx >/dev/null 2>&1 ||
      kw_log ERROR 'Cần kiểm tra Nginx sau khi hoàn tác Real IP.'
  else
    kw_log ERROR 'Cần kiểm tra Nginx sau khi hoàn tác Real IP.'
  fi
}

kw_cf_realip_apply() (
  local confirm=${1:-} stage='' candidate='' stamp='' backup=''
  local KW_CF_DONE=0 KW_CF_REPLACED=0 KW_CF_OLD=''
  [[ $confirm == UPDATE-CLOUDFLARE-REALIP ]] || return 2
  ((EUID == 0)) || return 2
  kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  for cmd in curl python3 nginx systemctl flock mktemp; do kw_has "$cmd" || return 2; done
  [[ -d /etc/nginx/conf.d && ! -L /etc/nginx/conf.d ]] || return 2
  [[ ! -L $kw_cf_realip_target ]] || return 2
  nginx -V 2>&1 | grep -Fq -- '--with-http_realip_module' || return 2
  nginx -t >/dev/null 2>&1 && systemctl is-active --quiet nginx || return 2
  exec 9>/run/lock/kwvps-cloudflare.lock || return 2
  flock -n 9 || return 1
  stage=$(mktemp -d /run/kwvps-cloudflare.XXXXXXXX) || return 1
  trap 'rm -f -- "$stage/ips-v4" "$stage/ips-v6"; rmdir -- "$stage" 2>/dev/null || true' EXIT
  curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 --max-time 25 \
    https://www.cloudflare.com/ips-v4 -o "$stage/ips-v4" || return 1
  curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 --max-time 25 \
    https://www.cloudflare.com/ips-v6 -o "$stage/ips-v6" || return 1
  candidate=$(mktemp /etc/nginx/conf.d/.kwvps-cloudflare.XXXXXXXX) || return 1
  trap 'rm -f -- "$candidate" "$stage/ips-v4" "$stage/ips-v6"; rmdir -- "$stage" 2>/dev/null || true; kw_cf_realip_rollback' EXIT
  {
    printf '# KwVPS: Cloudflare official proxy ranges. Do not add origin/client IPs here.\n'
    kw_cf_realip_lines "$stage/ips-v4" 4 || return 2
    kw_cf_realip_lines "$stage/ips-v6" 6 || return 2
    printf 'real_ip_header CF-Connecting-IP;\nreal_ip_recursive on;\n'
  } > "$candidate" || return 2
  chmod 0644 -- "$candidate" || return 1
  if [[ -f $kw_cf_realip_target ]]; then
    [[ $(stat -c %u -- "$kw_cf_realip_target") == 0 ]] || return 2
    kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
    stamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
    backup="$KW_BACKUP_ROOT/cf-realip-${stamp}-${BASHPID}.conf"
    [[ ! -e $backup && ! -L $backup ]] || return 2
    cp -a -- "$kw_cf_realip_target" "$backup" || return 1
    KW_CF_OLD=$backup
  elif [[ -e $kw_cf_realip_target ]]; then
    return 2
  fi
  mv -T -- "$candidate" "$kw_cf_realip_target" || return 1
  KW_CF_REPLACED=1
  nginx -t >/dev/null 2>&1 || return 1
  systemctl reload nginx || return 1
  KW_CF_DONE=1
  printf 'Đã cập nhật Cloudflare Real IP; bản cấu hình cũ: %s\n' "${KW_CF_OLD:-không có}"
)

kw_cf_realip_interactive() {
  kw_cf_realip_plan
  kw_prompt_yes_no_token 'Cập nhật Cloudflare Real IP?' UPDATE-CLOUDFLARE-REALIP || return 0
  kw_cf_realip_apply "$KW_PROMPT_VALUE"
}

kw_cf_zone_id_valid() { [[ ${1:-} =~ ^[a-fA-F0-9]{32}$ ]]; }

kw_cf_token_valid() { [[ ${1:-} =~ ^[A-Za-z0-9._-]{20,256}$ ]]; }

kw_cf_token_help() {
  printf 'Cloudflare API token: Công cụ nâng cao → Bảo mật/Cloudflare → Cấu hình API token → Thêm/thay token theo zone.\n'
}

kw_cf_zone_token_path() {
  kw_cf_zone_id_valid "${1:-}" || return 2
  printf '/etc/kwvps/cloudflare/token-%s\n' "${1,,}"
}

kw_cf_token_read() {
  local zone=${1:-} path token
  if [[ -n $zone ]]; then
    path=$(kw_cf_zone_token_path "$zone") || return 2
    [[ -e $path || -L $path ]] || path=/etc/kwvps/cloudflare/token
  else
    path=/etc/kwvps/cloudflare/token
  fi
  [[ -f $path && ! -L $path ]] || {
    kw_log ERROR "Thiếu API token cho zone ${zone:-tự tìm}. Lưu token theo zone trong menu Cấu hình API token."
    kw_cf_token_help >&2
    return 2
  }
  [[ $(stat -c %u:%a -- "$path") == 0:600 ]] || {
    kw_log ERROR "Token Cloudflare không an toàn tại $path (cần root:root, 0600)."
    return 2
  }
  IFS= read -r token < "$path" || return 2
  kw_cf_token_valid "$token" || { kw_log ERROR 'Token Cloudflare không đúng định dạng.'; return 2; }
  printf '%s\n' "$token"
}

kw_cf_token_guide() {
  printf '%s\n' \
    'Lấy token: Cloudflare Dashboard → biểu tượng tài khoản → My Profile → API Tokens → Create Token → Custom token.' \
    'Quyền cho Under Attack: Zone / Zone / Read; Zone / Zone Settings / Read; Zone / Zone Settings / Edit.' \
    'Để dùng Rate Limiting Cloudflare: thêm Zone / WAF / Read và Zone / WAF / Edit (Zone WAF Write).' \
    'Để tự đẩy IP bị Nginx limit lên Cloudflare: cần quyền IP Access rules Read/Write. API hiện liệt kê Account Firewall Access Rules Read/Edit; quyền Zone Firewall Services có thể không đủ.' \
    'Trong My Profile → API Tokens, mở token hiện có và chọn Edit để thêm quyền; giữ các quyền Under Attack.' \
    'Nếu Cloudflare cấp giá trị token mới, dùng mục Thêm hoặc thay API token của KwVPS để lưu lại trên VPS.' \
    'Zone Resources: Include → Specific zone → chọn đúng zone chứa domain. Mỗi zone/tài khoản Cloudflare có thể dùng token riêng.' \
    'Create Token, sao chép token một lần; chọn Thêm/thay token theo zone để dán. Không gửi token vào chat, URL hoặc mã nguồn.' \
    'Zone ID thuộc từng zone/domain gốc, KHÔNG phải ID chung cho tài khoản. Tìm tại Cloudflare Dashboard → chọn domain gốc → Overview → Zone ID.' \
    'Với token riêng, nhập Zone ID thủ công khi lưu token; KwVPS xác minh zone/domain rồi lưu cả hai. Tự tìm Zone ID chỉ dùng token chung cũ.' \
    'Nginx rate limit đơn thuần không dùng token; tùy chọn đẩy IP bị limit lên Cloudflare có dùng token.' \
    'Gói Free không cho điều kiện hostname của Rate Limiting; KwVPS sẽ báo phạm vi TOÀN ZONE và hỏi y/N.' \
    'Rate Limiting đếm/chặn tại biên Cloudflare; không phải chức năng tự đưa IP từ log Nginx lên Cloudflare.' \
    'Tunnel token là bí mật khác, cấu hình trong menu Cloudflare Tunnel.' \
    'Sau khi thay/revoke token ở Cloudflare, dùng lại mục 2 để cập nhật token trên VPS.'
}

kw_cf_token_status() {
  local dir=/etc/kwvps/cloudflare path=/etc/kwvps/cloudflare/token item found=0
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để xem trạng thái API token.'; return 2; }
  if [[ -e $dir || -L $dir ]]; then
    [[ -d $dir && ! -L $dir && $(stat -c %u:%a -- "$dir") == 0:700 ]] || {
      kw_log ERROR 'Thư mục Cloudflare không an toàn; cần root:root và 0700.'
      return 2
    }
  fi
  if [[ -e $path || -L $path ]]; then
    [[ -f $path && ! -L $path && $(stat -c %u:%a -- "$path") == 0:600 ]] || {
      kw_log ERROR 'File token chung không an toàn; cần root:root và 0600.'; return 2;
    }
    printf 'Token chung cũ: đã lưu (không hiển thị giá trị).\n'
    found=1
  fi
  for item in "$dir"/token-*; do
    [[ -e $item || -L $item ]] || continue
    [[ ${item##*/} =~ ^token-[a-f0-9]{32}$ && -f $item && ! -L $item &&
       $(stat -c %u:%a -- "$item") == 0:600 ]] || {
      kw_log ERROR "File token theo zone không an toàn: $item"; return 2;
    }
    printf 'Token zone %s: đã lưu (không hiển thị giá trị).\n' "${item##*/token-}"
    found=1
  done
  ((found)) || { printf 'Chưa lưu API token Cloudflare trên VPS.\n'; kw_cf_token_help; }
}

kw_cf_token_verify() (
  local token=${1:-} config response
  kw_cf_token_valid "$token" && kw_has curl && kw_has python3 || return 2
  config=$(mktemp /run/kwvps-cf-verify.XXXXXXXX) || return 1
  trap 'rm -f -- "$config"' EXIT
  chmod 0600 -- "$config" || return 1
  printf 'header = "Authorization: Bearer %s"\n' "$token" > "$config" || return 1
  response=$(curl -fsS --proto '=https' --tlsv1.2 --connect-timeout 8 --max-time 25 \
    --config "$config" https://api.cloudflare.com/client/v4/user/tokens/verify) || {
      kw_log ERROR 'Cloudflare không xác minh được token; token cũ vẫn được giữ.'
      return 1
    }
  printf '%s' "$response" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    result = data.get("result")
    if data.get("success") is not True or not isinstance(result, dict) or result.get("status") != "active":
        raise ValueError("token không ở trạng thái active")
except (ValueError, TypeError, json.JSONDecodeError) as error:
    print("Cloudflare từ chối token: " + str(error), file=sys.stderr)
    sys.exit(2)
' || return 2
)

kw_cf_token_save() (
  local token=${1:-} confirm=${2:-} dir=/etc/kwvps/cloudflare path stage=''
  [[ $confirm == SAVE-CF-TOKEN ]] && kw_cf_token_valid "$token" || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  [[ -d /etc/kwvps && ! -L /etc/kwvps && $(stat -c %u -- /etc/kwvps) == 0 ]] || return 2
  if [[ -e $dir || -L $dir ]]; then
    [[ -d $dir && ! -L $dir && $(stat -c %u:%a -- "$dir") == 0:700 ]] || return 2
  else
    install -d -o root -g root -m 0700 -- "$dir" || return 1
  fi
  path=$dir/token
  [[ ! -e $path && ! -L $path ]] || {
    [[ -f $path && ! -L $path && $(stat -c %u -- "$path") == 0 ]] || return 2
  }
  exec 9>/run/lock/kwvps-cloudflare-token.lock || return 2
  flock -n 9 || return 1
  kw_cf_token_verify "$token" || return 2
  stage=$(mktemp "$dir/.token.XXXXXXXX") || return 1
  trap 'rm -f -- "$stage"' EXIT
  chmod 0600 -- "$stage" || return 1
  printf '%s\n' "$token" > "$stage" || return 1
  mv -T -- "$stage" "$path" || return 1
  printf 'Đã lưu token Cloudflare hợp lệ, quyền root-only. Giá trị token không được hiển thị.\n'
)

kw_cf_token_save_interactive() {
  local token
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để lưu API token.'; return 2; }
  kw_prompt_validated 'Dán API token (ẩn ký tự; Enter để hủy): ' kw_cf_token_valid 'Token cần 20–256 ký tự chữ/số/._-; không có khoảng trắng' secret || return 0
  token=$KW_PROMPT_VALUE
  KW_PROMPT_VALUE=''
  kw_prompt_yes_no_token 'Xác minh với Cloudflare rồi lưu/thay token trên VPS?' SAVE-CF-TOKEN || return 0
  kw_cf_token_save "$token" "$KW_PROMPT_VALUE"
}

kw_cf_zone_token_save() (
  local domain=${1,,} zone=${2,,} token=${3:-} confirm=${4:-} dir=/etc/kwvps/cloudflare path stage config response zone_name
  [[ $confirm == "SAVE-CF-ZONE:$domain:$zone" ]] &&
    kw_domain_valid "$domain" && kw_cf_zone_id_valid "$zone" && kw_cf_token_valid "$token" || return 2
  ((EUID == 0)) && kw_os_supported '' && kw_site_lookup "$domain" || return 2
  if [[ ! -e $dir && ! -L $dir ]]; then
    install -d -o root -g root -m 0700 -- "$dir" || return 1
  fi
  [[ -d $dir && ! -L $dir && $(stat -c %u:%a -- "$dir") == 0:700 ]] || {
    kw_log ERROR 'Thư mục Cloudflare chưa an toàn; cần root:root và 0700.'; return 2;
  }
  kw_cf_token_verify "$token" || return 2
  config=$(mktemp /run/kwvps-cf-verify-zone.XXXXXXXX) || return 1
  trap 'rm -f -- "$config" "${stage:-}"' EXIT
  chmod 0600 -- "$config" || return 1
  printf 'header = "Authorization: Bearer %s"\n' "$token" > "$config" || return 1
  response=$(curl -fsS --proto '=https' --tlsv1.2 --connect-timeout 8 --max-time 25 \
    --config "$config" "https://api.cloudflare.com/client/v4/zones/$zone") || {
      kw_log ERROR 'Token không đọc được Zone ID này; kiểm tra Zone Read và Zone Resources.'; return 2;
    }
  zone_name=$(printf '%s' "$response" | kw_cf_json_field zone_name) || return 2
  [[ $domain == "$zone_name" || $domain == *".$zone_name" ]] || {
    kw_log ERROR "Site $domain không thuộc zone $zone_name; chưa lưu token."; return 2;
  }
  path=$(kw_cf_zone_token_path "$zone") || return 2
  [[ ! -e $path && ! -L $path ]] || {
    [[ -f $path && ! -L $path && $(stat -c %u:%a -- "$path") == 0:600 ]] || return 2;
  }
  stage=$(mktemp "$dir/.token-zone.XXXXXXXX") || return 1
  chmod 0600 -- "$stage" || return 1
  printf '%s\n' "$token" > "$stage" || return 1
  mv -T -- "$stage" "$path" || return 1
  stage=''
  kw_cf_zone_cache_save "$domain" "$zone" || return 2
  printf 'Đã lưu token riêng cho zone %s (%s); không hiển thị giá trị.\n' "$zone_name" "$zone"
)

kw_cf_zone_token_save_interactive() {
  local domain zone token
  ((EUID == 0)) || return 2
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  printf 'Zone ID lấy tại Cloudflare Dashboard → chọn domain gốc → Overview → Zone ID.\n'
  kw_prompt_validated 'Zone ID (32 ký tự hex; Enter để hủy): ' kw_cf_zone_id_valid 'Zone ID không hợp lệ' plain || return 0
  zone=$KW_PROMPT_VALUE
  kw_prompt_validated 'Dán API token riêng cho zone (ẩn ký tự; Enter để hủy): ' kw_cf_token_valid 'Token cần 20–256 ký tự chữ/số/._-' secret || return 0
  token=$KW_PROMPT_VALUE
  KW_PROMPT_VALUE=''
  kw_prompt_yes_no_token "Xác minh rồi lưu token cho $domain (zone $zone)?" "SAVE-CF-ZONE:$domain:$zone" || return 0
  kw_cf_zone_token_save "$domain" "$zone" "$token" "$KW_PROMPT_VALUE"
}

kw_cf_zone_cache_path() {
  local domain=${1,,} digest
  kw_domain_valid "$domain" && kw_has sha256sum || return 2
  digest=$(printf '%s' "$domain" | sha256sum) || return 2
  digest=${digest%% *}
  [[ $digest =~ ^[a-f0-9]{64}$ ]] || return 2
  printf '/etc/kwvps/cloudflare/zone-%s.id\n' "$digest"
}

kw_cf_zone_cache_read() {
  local domain=${1,,} path saved_domain saved_id
  path=$(kw_cf_zone_cache_path "$domain") || return 2
  [[ -e $path || -L $path ]] || return 1
  [[ -f $path && ! -L $path && $(stat -c %u:%a -- "$path") == 0:600 ]] || return 2
  {
    IFS= read -r saved_domain || return 2
    IFS= read -r saved_id || return 2
    ! IFS= read -r _ || return 2
  } < "$path"
  [[ $saved_domain == "$domain" ]] && kw_cf_zone_id_valid "$saved_id" || return 2
  KW_CF_ZONE_ID=$saved_id
}

kw_cf_zone_cache_save() (
  local domain=${1,,} zone_id=$2 path stage
  ((EUID == 0)) && kw_domain_valid "$domain" && kw_cf_zone_id_valid "$zone_id" || return 2
  [[ -d /etc/kwvps/cloudflare && ! -L /etc/kwvps/cloudflare &&
     $(stat -c %u:%a -- /etc/kwvps/cloudflare) == 0:700 ]] || return 2
  path=$(kw_cf_zone_cache_path "$domain") || return 2
  [[ ! -e $path && ! -L $path ]] || {
    [[ -f $path && ! -L $path && $(stat -c %u:%a -- "$path") == 0:600 ]] || return 2
  }
  stage=$(mktemp /etc/kwvps/cloudflare/.zone-id.XXXXXXXX) || return 1
  trap 'rm -f -- "$stage"' EXIT
  chmod 0600 -- "$stage" || return 1
  printf '%s\n%s\n' "$domain" "$zone_id" > "$stage" || return 1
  mv -T -- "$stage" "$path"
)

kw_cf_zone_id_interactive() {
  local domain zone choice status
  ((EUID == 0)) || return 2
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  if kw_cf_zone_cache_read "$domain"; then
    printf 'Zone ID đã lưu cho %s: %s\n' "$domain" "$KW_CF_ZONE_ID"
  else
    status=$?
    ((status == 1)) || { kw_log ERROR 'Zone ID đã lưu không hợp lệ; cần kiểm tra file root-only.'; return 2; }
    printf 'Chưa lưu Zone ID cho %s.\n' "$domain"
  fi
  printf 'Zone ID thuộc zone/domain gốc, không thuộc toàn tài khoản. Cloudflare Dashboard → chọn domain gốc → Overview → Zone ID.\n'
  printf '1. Tự tìm bằng API token\n2. Nhập Zone ID thủ công\n0. Quay lại\nChọn: '
  IFS= read -r choice || return 0
  case "$choice" in
    1) kw_cf_zone_discover "$domain" || { kw_log ERROR 'Không tự tìm được; kiểm tra quyền Zone Read của API token hoặc chọn mục 2.'; return 2; }; zone=$KW_CF_ZONE_ID ;;
    2) kw_prompt_validated 'Zone ID (32 ký tự hex; Enter để hủy): ' kw_cf_zone_id_valid 'Zone ID không hợp lệ' plain || return 0; zone=$KW_PROMPT_VALUE ;;
    *) return 0 ;;
  esac
  kw_cf_zone_for_domain "$domain" "$zone" || return 2
  kw_cf_zone_cache_save "$domain" "$zone" || return 2
  printf 'Đã xác minh và lưu Zone ID cho %s (zone %s).\n' "$domain" "$KW_CF_ZONE_NAME"
}

kw_cf_level_valid() {
  case "${1:-}" in off|essentially_off|low|medium|high|under_attack) return 0 ;; *) return 1 ;; esac
}

kw_cf_api() (
  local method=$1 path=$2 body=${3:-} token config zone_name zone=''
  [[ $method == GET || $method == PATCH ]] || return 2
  if [[ $path =~ ^zones/[a-fA-F0-9]{32}(/settings/security_level)?$ ]]; then
    zone=${path#zones/}; zone=${zone%%/*}
  elif [[ $method == GET && $path =~ ^zones\?name=([a-z0-9.-]+)$ ]]; then
    zone_name=${BASH_REMATCH[1]}
    kw_domain_valid "$zone_name" || return 2
  else
    return 2
  fi
  [[ $method != PATCH ]] || kw_cf_level_valid "$body" || return 2
  [[ $method != PATCH || $path == */settings/security_level ]] || return 2
  token=$(kw_cf_token_read "$zone") || return 2
  config=$(mktemp /run/kwvps-cf-api.XXXXXXXX) || return 1
  trap 'rm -f -- "$config"' EXIT
  chmod 0600 -- "$config" || return 1
  printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n' "$token" > "$config" || return 1
  if [[ $method == PATCH ]]; then
    curl -fsS --proto '=https' --tlsv1.2 --connect-timeout 8 --max-time 25 \
      --config "$config" -X PATCH -d "{\"value\":\"$body\"}" \
      "https://api.cloudflare.com/client/v4/$path"
  else
    curl -fsS --proto '=https' --tlsv1.2 --connect-timeout 8 --max-time 25 \
      --config "$config" "https://api.cloudflare.com/client/v4/$path"
  fi
)

kw_cf_json_field() {
  local field=$1
  case "$field" in zone_name|security_level) ;; *) return 2 ;; esac
  python3 -c '
import json, sys
field = sys.argv[1]
try:
    data = json.load(sys.stdin)
    if data.get("success") is not True or not isinstance(data.get("result"), dict):
        raise ValueError("Cloudflare API returned an error")
    value = data["result"].get("name" if field == "zone_name" else "value")
    if not isinstance(value, str) or not value or "\n" in value:
        raise ValueError("Missing API field")
except (ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
    print("Cloudflare API response invalid: " + str(error), file=sys.stderr)
    sys.exit(2)
print(value)
' "$field"
}

kw_cf_json_zone_id() {
  local name=${1,,}
  kw_domain_valid "$name" || return 2
  python3 -c '
import json, re, sys
name = sys.argv[1]
try:
    data = json.load(sys.stdin)
    if data.get("success") is not True or not isinstance(data.get("result"), list):
        raise ValueError("Cloudflare API returned an error")
    matches = [item for item in data["result"] if isinstance(item, dict) and item.get("name") == name]
    if not matches:
        sys.exit(1)
    if len(matches) != 1 or not re.fullmatch(r"[a-fA-F0-9]{32}", str(matches[0].get("id", ""))):
        raise ValueError("Invalid or ambiguous zone ID")
    print(matches[0]["id"])
except (ValueError, TypeError, KeyError, json.JSONDecodeError) as error:
    print("Cloudflare zone lookup invalid: " + str(error), file=sys.stderr)
    sys.exit(2)
' "$name"
}

kw_cf_zone_discover() {
  local domain=${1,,} candidate response zone_id result
  kw_domain_valid "$domain" || return 2
  candidate=$domain
  while [[ $candidate == *.* ]]; do
    response=$(kw_cf_api GET "zones?name=$candidate") || return 2
    if zone_id=$(printf '%s' "$response" | kw_cf_json_zone_id "$candidate"); then
      KW_CF_ZONE_ID=$zone_id
      return 0
    else
      result=$?
      ((result == 1)) || return 2
    fi
    candidate=${candidate#*.}
  done
  return 1
}

kw_cf_zone_for_domain() {
  local domain=${1,,} zone_id=$2 response zone
  kw_domain_valid "$domain" && kw_cf_zone_id_valid "$zone_id" || return 2
  response=$(kw_cf_api GET "zones/$zone_id") || return 2
  zone=$(printf '%s' "$response" | kw_cf_json_field zone_name) || return 2
  kw_domain_valid "$zone" || return 2
  [[ $domain == "$zone" || $domain == *".$zone" ]] || {
    kw_log ERROR "Domain $domain không thuộc zone $zone."; return 2;
  }
  KW_CF_ZONE_NAME=$zone
}

kw_cf_security_current() {
  local response value
  response=$(kw_cf_api GET "zones/$1/settings/security_level") || return 2
  value=$(printf '%s' "$response" | kw_cf_json_field security_level) || return 2
  kw_cf_level_valid "$value" || return 2
  printf '%s' "$value"
}

kw_cf_security_set() {
  local response value
  kw_cf_level_valid "$2" || return 2
  response=$(kw_cf_api PATCH "zones/$1/settings/security_level" "$2") || return 1
  value=$(printf '%s' "$response" | kw_cf_json_field security_level) || return 1
  [[ $value == "$2" ]] || return 1
}

kw_cf_under_attack_apply() (
  local domain=${1,,} zone_id=$2 mode=$3 confirm=${4:-} current state previous verify stage
  kw_domain_valid "$domain" && kw_cf_zone_id_valid "$zone_id" || return 2
  [[ $mode == enable || $mode == disable ]] || return 2
  [[ $confirm == "${mode}:${zone_id}" ]] || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  for cmd in curl python3 flock mktemp; do kw_has "$cmd" || return 2; done
  [[ -d /etc/kwvps/cloudflare && ! -L /etc/kwvps/cloudflare ]] || return 2
  [[ $(stat -c %u:%a -- /etc/kwvps/cloudflare) == 0:700 ]] || return 2
  exec 9>/run/lock/kwvps-cloudflare.lock || return 2
  flock -n 9 || return 1
  kw_cf_zone_for_domain "$domain" "$zone_id" || return 2
  current=$(kw_cf_security_current "$zone_id") || return 2
  state="/etc/kwvps/cloudflare/under-attack-${zone_id}.state"
  [[ ! -L $state ]] || return 2
  if [[ $mode == enable ]]; then
    [[ ! -e $state ]] || { kw_log ERROR 'Zone đã có trạng thái Under Attack do KwVPS quản lý.'; return 2; }
    [[ $current != under_attack ]] || { kw_log ERROR 'Zone đã bật Under Attack ngoài KwVPS; không biết mức cũ để hoàn tác.'; return 2; }
    stage=$(mktemp /etc/kwvps/cloudflare/.under-attack.XXXXXXXX) || return 1
    chmod 0600 -- "$stage" || { rm -f -- "$stage"; return 1; }
    printf '%s\n' "$current" > "$stage" || { rm -f -- "$stage"; return 1; }
    mv -T -- "$stage" "$state" || { rm -f -- "$stage"; return 1; }
    if ! kw_cf_security_set "$zone_id" under_attack ||
       [[ $(kw_cf_security_current "$zone_id") != under_attack ]]; then
      if kw_cf_security_set "$zone_id" "$current"; then
        rm -f -- "$state"
      else
        kw_log ERROR 'Không trả được mức bảo vệ cũ; trạng thái lưu vẫn còn. Kiểm tra Cloudflare ngay.'
      fi
      return 1
    fi
    printf 'Đã bật Under Attack cho TOÀN ZONE %s; mức cũ: %s.\n' "$KW_CF_ZONE_NAME" "$current"
  else
    [[ -f $state && ! -L $state && $(stat -c %u:%a -- "$state") == 0:600 ]] || {
      kw_log ERROR 'Không có mức bảo vệ trước đó do KwVPS lưu; không tự đoán giá trị để tắt.'; return 2;
    }
    IFS= read -r previous < "$state" || return 2
    kw_cf_level_valid "$previous" && [[ $previous != under_attack ]] || return 2
    [[ $current == under_attack ]] || { kw_log ERROR 'Cloudflare đã thay đổi ngoài KwVPS; không ghi đè.'; return 2; }
    kw_cf_security_set "$zone_id" "$previous" || return 1
    verify=$(kw_cf_security_current "$zone_id") || return 1
    [[ $verify == "$previous" ]] || return 1
    rm -f -- "$state" || return 1
    printf 'Đã tắt Under Attack cho zone %s, trả về mức %s.\n' "$KW_CF_ZONE_NAME" "$previous"
  fi
)

kw_cf_under_attack_interactive() {
  local domain zone_id mode current cache_status
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  if kw_cf_zone_cache_read "$domain"; then
    zone_id=$KW_CF_ZONE_ID
    printf 'Zone ID đã lưu cho %s: %s\n' "$domain" "$zone_id"
  else
    cache_status=$?
    if ((cache_status != 1)); then
      kw_log ERROR 'Zone ID đã lưu có quyền/nội dung không hợp lệ; không tự ghi đè.'
      return 2
    fi
    if kw_cf_zone_discover "$domain"; then
      zone_id=$KW_CF_ZONE_ID
      printf 'Đã tìm thấy Zone ID cho %s: %s\n' "$domain" "$zone_id"
    else
      printf 'Không tự tìm được zone; bạn có thể nhập Zone ID thủ công.\n'
      kw_prompt_validated 'Zone ID Cloudflare (32 ký tự hex): ' kw_cf_zone_id_valid 'Zone ID không hợp lệ' plain || return 0
      zone_id=$KW_PROMPT_VALUE
    fi
  fi
  if ! kw_cf_zone_for_domain "$domain" "$zone_id"; then
    printf 'Zone ID đã lưu không còn xác minh được. Nhập Zone ID mới hoặc Enter để hủy.\n'
    kw_prompt_validated 'Zone ID mới: ' kw_cf_zone_id_valid 'Zone ID không hợp lệ' plain || return 0
    zone_id=$KW_PROMPT_VALUE
    kw_cf_zone_for_domain "$domain" "$zone_id" || return 2
  fi
  kw_cf_zone_cache_save "$domain" "$zone_id" || return 2
  current=$(kw_cf_security_current "$zone_id") || return 2
  printf 'Zone: %s; mức bảo vệ hiện tại: %s. Thay đổi ảnh hưởng MỌI hostname trong zone.\n' "$KW_CF_ZONE_NAME" "$current"
  printf '1. Bật Under Attack\n2. Tắt và khôi phục mức cũ KwVPS đã lưu\n3. Đổi Zone ID đã lưu\n0. Quay lại\nChọn: '
  local choice
  IFS= read -r choice || return 0
  case "$choice" in
    1) mode=enable ;;
    2) mode=disable ;;
    3)
      kw_prompt_validated 'Zone ID mới: ' kw_cf_zone_id_valid 'Zone ID không hợp lệ' plain || return 0
      zone_id=$KW_PROMPT_VALUE
      kw_cf_zone_for_domain "$domain" "$zone_id" || return 2
      kw_cf_zone_cache_save "$domain" "$zone_id" || return 2
      printf 'Đã lưu Zone ID mới cho %s. Chưa thay đổi mức bảo vệ.\n' "$domain"
      return 0 ;;
    *) return 0 ;;
  esac
  kw_prompt_yes_no_token "${mode} Under Attack cho TOÀN ZONE $KW_CF_ZONE_NAME?" "${mode}:${zone_id}" || return 0
  kw_cf_under_attack_apply "$domain" "$zone_id" "$mode" "$KW_PROMPT_VALUE"
}

# Local Nginx request limits. This reuses the existing Real IP setup and does
# not change Cloudflare zone settings, firewall rules or individual vhosts.
kw_cf_antiddos_rate_valid() {
  case "${1:-}" in 5|10|20|50|off) return 0 ;; *) return 1 ;; esac
}

kw_cf_antiddos_explain() {
  printf '%s\n' \
    '1) Nginx local: vượt ngưỡng trả 429; không dùng cho SITE được đánh dấu Tunnel (Real IP chưa xác minh).' \
    '2) Cloudflare Rate Limiting: Cloudflare đếm theo IP khách tại biên, chỉ áp cho hostname đã chọn.' \
    '   Cloudflare rule dùng API token riêng theo zone (hoặc token chung cũ); cần Zone WAF Read/Write.' \
    '   Gói Free không hỗ trợ điều kiện hostname: chỉ có thể tạo rule TOÀN ZONE sau xác nhận y/N.' \
    '3) Tùy chọn riêng của Nginx local: đếm 5 lần bị 429/60 giây trong log rồi block IP 15 phút tại Cloudflare.' \
    '   Chỉ dùng cho site chế độ DNS; rule IP Access áp dụng cho TOÀN ZONE, không riêng hostname.' \
    'Tunnel token khác Cloudflare API token. Xem hướng dẫn token trong Bảo mật/Cloudflare → mục 4 → mục 3.'
}

kw_cf_antiddos_state_dir=/etc/kwvps/cloudflare/antiddos
kw_cf_antiddos_conf=/etc/nginx/conf.d/kwvps-antiddos.conf

kw_cf_antiddos_render() {
  # shellcheck disable=SC2016 # Dollar expressions belong to Nginx, not Bash.
  local file domain rate tier
  [[ -d $kw_cf_antiddos_state_dir && ! -L $kw_cf_antiddos_state_dir ]] || return 2
  printf '# Managed by KwVPS. Local per-host request limits; Real IP must remain enabled.\n'
  for tier in 5 10 20 50; do
    # shellcheck disable=SC2016
    printf 'map $host $kwvps_antiddos_%s_key {\n  default "";\n' "$tier"
    for file in "$kw_cf_antiddos_state_dir"/*.rate; do
      [[ -e $file || -L $file ]] || continue
      [[ -f $file && ! -L $file && $(stat -c %u:%a -- "$file") == 0:600 ]] || return 2
      domain=${file##*/}; domain=${domain%.rate}
      kw_domain_valid "$domain" || return 2
      IFS= read -r rate < "$file" || return 2
      kw_cf_antiddos_rate_valid "$rate" && [[ $rate != off ]] || return 2
      if [[ $rate == "$tier" ]]; then
        # shellcheck disable=SC2016
        printf '  %s $binary_remote_addr;\n' "$domain"
      fi
    done
    # shellcheck disable=SC2016
    printf '}\nlimit_req_zone $kwvps_antiddos_%s_key zone=kwvps_antiddos_%s:10m rate=%sr/s;\n' "$tier" "$tier" "$tier"
    printf 'limit_req zone=kwvps_antiddos_%s burst=%s nodelay;\n' "$tier" "$((tier * 2))"
  done
  printf 'limit_req_status 429;\n'
}

kw_cf_antiddos_apply() (
  local domain=${1,,} rate=${2:-} confirm=${3:-} state ingress old_state='' old_conf='' temp='' committed=0
  kw_domain_valid "$domain" && kw_cf_antiddos_rate_valid "$rate" || return 2
  [[ $confirm == "ANTIDDOS:$domain:$rate" ]] || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  kw_site_lookup "$domain" || return 2
  [[ -f $kw_cf_realip_target && ! -L $kw_cf_realip_target ]] || {
    kw_log ERROR 'Trước tiên bật Cloudflare Real IP ở mục 1.'; return 2;
  }
  if [[ ! -e /etc/kwvps/cloudflare && ! -L /etc/kwvps/cloudflare ]]; then
    install -d -o root -g root -m 0700 -- /etc/kwvps/cloudflare || return 1
  fi
  [[ -d /etc/kwvps/cloudflare && ! -L /etc/kwvps/cloudflare &&
     $(stat -c %u:%a -- /etc/kwvps/cloudflare) == 0:700 ]] || {
    kw_log ERROR 'Thư mục /etc/kwvps/cloudflare phải thuộc root:root, quyền 0700 và không là symlink.'; return 2;
  }
  kw_has nginx && kw_has flock && kw_has mktemp && kw_has systemctl || {
    kw_log ERROR 'Thiếu nginx, flock, mktemp hoặc systemctl.'; return 2;
  }
  ingress=$(kw_tunnel_site_mode "$domain") || {
    kw_log ERROR 'Không đọc được chế độ DNS/Tunnel của site; kiểm tra metadata ingress.'; return 2;
  }
  if [[ $rate != off && $ingress != dns ]]; then
    kw_log ERROR 'Site dùng Tunnel hoặc chưa phân loại ingress; chọn DNS thông thường trong menu Tunnel trước khi bật rate limit local.'
    return 2
  fi
  nginx -t && systemctl is-active --quiet nginx || {
    kw_log ERROR 'Cấu hình Nginx hiện không hợp lệ hoặc service chưa chạy; chưa áp rate limit.'; return 2;
  }
  exec 9>/run/lock/kwvps-cloudflare.lock || return 2
  flock -n 9 || return 1
  ingress=$(kw_tunnel_site_mode "$domain") || {
    kw_log ERROR 'Không đọc được chế độ ingress sau khi khóa; chưa áp rate limit.'; return 2;
  }
  if [[ $rate != off && $ingress != dns ]]; then
    kw_log ERROR 'Site không còn xác nhận chế độ DNS; hủy rate limit để tránh gom mọi khách vào một IP.'
    return 2
  fi
  if [[ ! -e $kw_cf_antiddos_state_dir && ! -L $kw_cf_antiddos_state_dir ]]; then
    install -d -o root -g root -m 0700 -- "$kw_cf_antiddos_state_dir" || return 1
  fi
  [[ -d $kw_cf_antiddos_state_dir && ! -L $kw_cf_antiddos_state_dir &&
     $(stat -c %u:%a -- "$kw_cf_antiddos_state_dir") == 0:700 ]] || {
    kw_log ERROR 'Thư mục rate limit phải thuộc root:root, quyền 0700 và không là symlink.'; return 2;
  }
  state="$kw_cf_antiddos_state_dir/$domain.rate"
  if [[ $rate == off && -e $kw_cf_antiddos_state_dir/$domain.push ]]; then
    kw_log ERROR 'Tắt đẩy IP lên Cloudflare ở mục 7 trước khi tắt Nginx rate limit.'
    return 2
  fi
  [[ ! -e $state && ! -L $state ]] || {
    [[ -f $state && ! -L $state && $(stat -c %u:%a -- "$state") == 0:600 ]] || return 2
    old_state=$(< "$state")
    kw_cf_antiddos_rate_valid "$old_state" && [[ $old_state != off ]] || return 2
  }
  [[ ! -e $kw_cf_antiddos_conf && ! -L $kw_cf_antiddos_conf ]] || {
    [[ -f $kw_cf_antiddos_conf && ! -L $kw_cf_antiddos_conf &&
       $(stat -c %u -- "$kw_cf_antiddos_conf") == 0 ]] || return 2
    old_conf=$(mktemp /run/kwvps-antiddos-old.XXXXXXXX) || return 1
    cp -p -- "$kw_cf_antiddos_conf" "$old_conf" || return 1
  }
  trap 'if (( ! committed )); then if [[ -n $old_state ]]; then printf "%s\n" "$old_state" > "$state"; chmod 0600 -- "$state"; else rm -f -- "$state"; fi; if [[ -n $old_conf ]]; then cp -p -- "$old_conf" "$kw_cf_antiddos_conf"; else rm -f -- "$kw_cf_antiddos_conf"; fi; nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || kw_log ERROR "Cần kiểm tra rollback anti-DDoS Nginx."; fi; [[ -z $temp ]] || rm -f -- "$temp"; [[ -z $old_conf ]] || rm -f -- "$old_conf"' EXIT
  if [[ $rate == off ]]; then
    rm -f -- "$state" || return 1
  else
    temp=$(mktemp "$kw_cf_antiddos_state_dir/.rate.XXXXXXXX") || return 1
    chmod 0600 -- "$temp" || return 1
    printf '%s\n' "$rate" > "$temp" || return 1
    mv -T -- "$temp" "$state" || return 1
    temp=''
  fi
  temp=$(mktemp /etc/nginx/conf.d/.kwvps-antiddos.XXXXXXXX) || return 1
  kw_cf_antiddos_render > "$temp" || {
    kw_log ERROR 'Không dựng được cấu hình rate limit; kiểm tra các file .rate root-only, quyền 0600.'; return 2;
  }
  chmod 0644 -- "$temp" || return 1
  mv -T -- "$temp" "$kw_cf_antiddos_conf" || return 1
  temp=''
  nginx -t || { kw_log ERROR 'Nginx từ chối cấu hình rate limit mới; đã hoàn tác.'; return 1; }
  systemctl reload nginx || { kw_log ERROR 'Không reload được Nginx; đã hoàn tác.'; return 1; }
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  committed=1
  printf 'Đã đặt giới hạn local cho %s: %s request/giây (off = tắt).\n' "$domain" "$rate"
)

kw_cf_antiddos_local_interactive() {
  local domain rate state
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  state="$kw_cf_antiddos_state_dir/$domain.rate"
  printf 'Giới hạn hiện tại: '
  if [[ -f $state && ! -L $state ]]; then
    head -n 1 -- "$state"
  else
    printf 'off\n'
  fi
  printf 'Chặn vượt ngưỡng bằng HTTP 429 tại Nginx; áp dụng riêng hostname đã chọn.\n'
  printf 'Cần bật Cloudflare Real IP (mục 1). KwVPS không đổi 80/443; rate limit này không ngăn bypass origin.\n'
  printf '1. 5 req/s\n2. 10 req/s\n3. 20 req/s\n4. 50 req/s\n5. Tắt\n6. Bật tự đẩy IP bị limit lên Cloudflare\n7. Tắt tự đẩy IP lên Cloudflare\n0. Quay lại\nChọn: '
  local choice
  IFS= read -r choice || return 0
  case "$choice" in
    1) rate=5 ;; 2) rate=10 ;; 3) rate=20 ;; 4) rate=50 ;; 5) rate=off ;;
    6) kw_cf_limit_push_interactive "$domain" enable; return $? ;;
    7) kw_cf_limit_push_interactive "$domain" disable; return $? ;;
    *) return 0 ;;
  esac
  kw_prompt_yes_no_token "Áp giới hạn $rate cho $domain?" "ANTIDDOS:$domain:$rate" || return 0
  kw_cf_antiddos_apply "$domain" "$rate" "$KW_PROMPT_VALUE"
}

kw_cf_limit_push_apply() (
  local domain=${1,,} zone=$2 mode=$3 confirm=$4 state stage ingress
  kw_domain_valid "$domain" && kw_cf_zone_id_valid "$zone" || return 2
  [[ $mode == enable || $mode == disable ]] && [[ $confirm == "CF-LIMIT-PUSH:$domain:$mode" ]] || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  kw_site_lookup "$domain" || return 2
  [[ -d $kw_cf_antiddos_state_dir && ! -L $kw_cf_antiddos_state_dir ]] || return 2
  state="$kw_cf_antiddos_state_dir/$domain.push"
  if [[ $mode == disable ]]; then
    [[ -f $state && ! -L $state && $(stat -c %u:%a -- "$state") == 0:600 ]] || return 2
    rm -f -- "$state" || return 1
    printf 'Đã tắt đẩy IP cho %s. Ban cũ sẽ tự hết hạn sau tối đa 15 phút.\n' "$domain"
    return 0
  fi
  [[ -f $kw_cf_antiddos_state_dir/$domain.rate && ! -L $kw_cf_antiddos_state_dir/$domain.rate ]] || return 2
  [[ -f $kw_cf_realip_target && ! -L $kw_cf_realip_target ]] || return 2
  ingress=$(kw_tunnel_site_mode "$domain") || return 2
  [[ $ingress == dns ]] || { kw_log ERROR 'Chưa xác minh site này dùng DNS thông thường; không bật bridge Nginx.'; return 2; }
  [[ ! -e $state && ! -L $state ]] || { kw_log ERROR 'Đã bật đẩy IP cho site này.'; return 2; }
  kw_cf_token_read "$zone" >/dev/null || return 2
  [[ -f /etc/systemd/system/kwvps-cf-limit-ban.timer && -f /opt/kwvps/scripts/cf_limit_ban.py ]] || {
    kw_log ERROR 'Chưa cài timer/worker; nâng cấp KwVPS trước.'; return 2;
  }
  kw_cf_zone_for_domain "$domain" "$zone" || return 2
  python3 /opt/kwvps/scripts/cf_limit_ban.py --check-zone "$zone" || {
    kw_log ERROR 'Token không đọc được IP Access rule; xem hướng dẫn quyền Firewall Services ở mục API token.'
    return 2
  }
  stage=$(mktemp "$kw_cf_antiddos_state_dir/.push.XXXXXXXX") || return 1
  trap 'rm -f -- "$stage"' EXIT
  chmod 0600 -- "$stage" || return 1
  printf '%s\n%s\n' "${KW_SITE_OWNER#kw}" "$zone" > "$stage" || return 1
  mv -T -- "$stage" "$state" || return 1
  systemctl enable --now kwvps-cf-limit-ban.timer || { rm -f -- "$state"; return 1; }
  printf 'Đã bật: 5 lần Nginx từ chối/60 giây sẽ block IP 15 phút trên TOÀN ZONE %s.\n' "$KW_CF_ZONE_NAME"
)

kw_cf_limit_push_interactive() {
  local domain=$1 mode=$2 zone cache_status
  if [[ $mode == enable ]]; then
    if kw_cf_zone_cache_read "$domain"; then zone=$KW_CF_ZONE_ID
    else
      cache_status=$?
      ((cache_status == 1)) || { kw_log ERROR 'Zone ID đã lưu không hợp lệ; kiểm tra file trước khi tiếp tục.'; return 2; }
      if kw_cf_zone_discover "$domain"; then
        zone=$KW_CF_ZONE_ID
      else
      printf 'Không tự tìm được Zone ID. Đây là ID của zone/domain gốc, không phải của cả tài khoản.\n'
      printf 'Xem tại Cloudflare Dashboard → chọn domain gốc → Overview → Zone ID; hoặc lưu ở Công cụ nâng cao → Bảo mật/Cloudflare → Cấu hình API token → mục 4.\n'
      kw_prompt_validated 'Zone ID (32 ký tự hex; Enter để hủy): ' kw_cf_zone_id_valid 'Zone ID không hợp lệ' plain || return 0
      zone=$KW_PROMPT_VALUE
      kw_cf_zone_for_domain "$domain" "$zone" || return 2
      kw_cf_zone_cache_save "$domain" "$zone" || return 2
      fi
    fi
    kw_cf_zone_for_domain "$domain" "$zone" || return 2
    printf 'IP bị Nginx limit 5 lần/60 giây sẽ bị Cloudflare block 15 phút trên TOÀN ZONE %s.\n' "$KW_CF_ZONE_NAME"
    printf 'Cần quyền IP Access rules Read/Write; API Cloudflare hiện liệt kê Account Firewall Access Rules Read/Edit. Không gửi token qua chat.\n'
  else
    [[ -f $kw_cf_antiddos_state_dir/$domain.push && ! -L $kw_cf_antiddos_state_dir/$domain.push &&
       $(stat -c %u:%a -- "$kw_cf_antiddos_state_dir/$domain.push") == 0:600 ]] || return 2
    zone=$(sed -n '2p' "$kw_cf_antiddos_state_dir/$domain.push") || return 2
    kw_cf_zone_id_valid "$zone" || return 2
  fi
  kw_prompt_yes_no_token "${mode} đẩy IP bị Nginx limit cho $domain?" "CF-LIMIT-PUSH:$domain:$mode" || return 0
  kw_cf_limit_push_apply "$domain" "$zone" "$mode" "$KW_PROMPT_VALUE"
}

kw_cf_antiddos_interactive() {
  local choice
  kw_cf_antiddos_explain
  printf '1. Rate limit Nginx local\n2. Rate limit Cloudflare theo domain\n0. Quay lại\nChọn: '
  IFS= read -r choice || return 0
  case "$choice" in
    1) kw_cf_antiddos_local_interactive ;;
    2) kw_cf_rate_interactive ;;
    *) return 0 ;;
  esac
}

# Zone-level Rulesets API. Never replace a whole ruleset: doing so could erase
# Cloudflare rules created outside KwVPS. Only add/delete the exact owned rule.
kw_cf_rate_marker() {
  local digest
  kw_domain_valid "$1" || return 2
  digest=$(printf '%s' "$1" | sha256sum) || return 2
  printf 'kwvps-rate-%s\n' "${digest:0:16}"
}

kw_cf_rate_plan() {
  python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    result = data["result"]
    assert data["success"] is True and isinstance(result, dict)
    value = result["plan"]["legacy_id"]
    assert isinstance(value, str)
except (ValueError, KeyError, TypeError, AssertionError, json.JSONDecodeError):
    sys.exit(2)
print(value)
'
}

kw_cf_rate_rule_json() {
  local domain=$1 rate=$2 marker=$3 root=${4:-no} scope=${5:-host}
  kw_domain_valid "$domain" && kw_cf_antiddos_rate_valid "$rate" && [[ $rate != off ]] || return 2
  [[ $scope == host || $scope == zone ]] || return 2
  python3 -c '
import json, sys
domain, rate, marker, root, scope = sys.argv[1:]
rule = {
    "ref": marker,
    "description": "KwVPS " + ("zone" if scope == "zone" else "host") + " rate limit " + domain,
    "expression": "true" if scope == "zone" else "(http.host eq " + json.dumps(domain) + ")",
    "action": "block",
    "ratelimit": {
        "characteristics": ["cf.colo.id", "ip.src"],
        "period": 10,
        "requests_per_period": int(rate) * 10,
        "mitigation_timeout": 10,
    },
}
if root == "yes":
    print(json.dumps({"kind": "zone", "name": "KwVPS zone rate limiting", "phase": "http_ratelimit", "rules": [rule]}))
else:
    print(json.dumps(rule))
' "$domain" "$rate" "$marker" "$root" "$scope"
}

kw_cf_rate_entry_id() {
  python3 -c '
import json, re, sys
try:
    data = json.load(sys.stdin)
    result = data["result"]
    value = result["id"]
    assert data["success"] is True and result["phase"] == "http_ratelimit"
    assert re.fullmatch(r"[a-fA-F0-9]{32}", value)
except (ValueError, KeyError, TypeError, AssertionError, json.JSONDecodeError):
    sys.exit(2)
print(value)
'
}

kw_cf_rate_rule_id() {
  local marker=$1
  python3 -c '
import json, re, sys
try:
    data = json.load(sys.stdin)
    result = data["result"]
    assert data["success"] is True and result["phase"] == "http_ratelimit"
    matches = [rule for rule in result.get("rules", []) if rule.get("ref") == sys.argv[1]]
    if not matches:
        sys.exit(1)
    assert len(matches) == 1
    value = matches[0]["id"]
    assert re.fullmatch(r"[a-fA-F0-9]{32}", value)
except (ValueError, KeyError, TypeError, AssertionError, json.JSONDecodeError):
    sys.exit(2)
print(value)
' "$marker"
}

kw_cf_rate_api() {
  local method=$1 zone=$2 route=$3 payload=${4:-} dry=${5:-no} token config response status
  kw_cf_zone_id_valid "$zone" || return 2
  [[ $dry == no || $dry == yes ]] || return 2
  [[ $dry == no || $method == POST ]] || return 2
  case "$method:$route" in
    GET:entrypoint|POST:ruleset) ;;
    POST:rule/*) [[ ${route#rule/} =~ ^[a-fA-F0-9]{32}/rules$ ]] || return 2 ;;
    DELETE:rule/*) [[ ${route#rule/} =~ ^[a-fA-F0-9]{32}/rules/[a-fA-F0-9]{32}$ ]] || return 2 ;;
    *) return 2 ;;
  esac
  token=$(kw_cf_token_read "$zone") || return 2
  config=$(mktemp /run/kwvps-cf-rate-config.XXXXXXXX) || return 1
  response=$(mktemp /run/kwvps-cf-rate-response.XXXXXXXX) || { rm -f -- "$config"; return 1; }
  chmod 0600 -- "$config" "$response" || return 1
  printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n' "$token" > "$config" || return 1
  case "$route" in
    entrypoint) route="zones/$zone/rulesets/phases/http_ratelimit/entrypoint" ;;
    ruleset) route="zones/$zone/rulesets" ;;
    rule/*) route="zones/$zone/rulesets/${route#rule/}" ;;
  esac
  [[ $dry == no ]] || route="$route?dry_run=true"
  local -a args=(--proto '=https' --tlsv1.2 --connect-timeout 8 --max-time 30 --config "$config" -sS -o "$response" -w '%{http_code}' -X "$method")
  if [[ $method == POST ]]; then
    [[ -f $payload && ! -L $payload ]] || { rm -f -- "$config" "$response"; return 2; }
    args+=(--data-binary "@$payload")
  fi
  status=$(curl "${args[@]}" "https://api.cloudflare.com/client/v4/$route") || {
    rm -f -- "$config" "$response"; kw_log ERROR 'Không kết nối được Cloudflare API.'; return 1;
  }
  KW_CF_RATE_STATUS=$status
  KW_CF_RATE_RESPONSE=$(< "$response")
  rm -f -- "$config" "$response"
  [[ $status =~ ^[0-9]{3}$ ]] || return 2
}

kw_cf_rate_error_summary() {
  python3 -c '
import json, re, sys
try:
    data = json.load(sys.stdin)
    errors = data.get("errors", [])
    if not isinstance(errors, list):
        raise ValueError
    for error in errors[:3]:
        if not isinstance(error, dict):
            continue
        code = str(error.get("code", "?"))[:30]
        message = str(error.get("message", "Cloudflare rejected the rule"))
        message = re.sub(r"cfut_[A-Za-z0-9._-]+", "[REDACTED]", message)
        message = re.sub(r"[\r\n]+", " ", message)[:350]
        print("Cloudflare error " + code + ": " + message, file=sys.stderr)
except (ValueError, TypeError, json.JSONDecodeError):
    print("Cloudflare trả phản hồi lỗi không đọc được.", file=sys.stderr)
'
}

kw_cf_rate_state_path() {
  printf '/etc/kwvps/cloudflare/%s.state\n' "$(kw_cf_rate_marker "$1")"
}

kw_cf_rate_zone_state_path() {
  kw_cf_zone_id_valid "$1" || return 2
  printf '/etc/kwvps/cloudflare/kwvps-rate-zone-%s.state\n' "$1"
}

kw_cf_rate_apply() (
  local domain=${1,,} zone=$2 rate=$3 confirm=$4 scope=${5:-host} marker state target zone_json plan entry ruleset rule_id payload='' write_route rc
  kw_domain_valid "$domain" && kw_cf_zone_id_valid "$zone" && kw_cf_antiddos_rate_valid "$rate" || return 2
  [[ $scope == host || $scope == zone ]] || return 2
  if [[ $scope == zone ]]; then
    [[ $confirm == "CF-RATE-ZONE:$zone:$rate" ]] || return 2
  else
    [[ $confirm == "CF-RATE:$domain:$rate" ]] || return 2
  fi
  ((EUID == 0)) && kw_os_supported '' || return 2
  kw_site_lookup "$domain" || return 2
  if [[ $scope == zone ]]; then
    marker="kwvps-rate-zone-$zone"
    state=$(kw_cf_rate_zone_state_path "$zone") || return 2
    target="zone:$zone"
  else
    marker=$(kw_cf_rate_marker "$domain") || return 2
    state=$(kw_cf_rate_state_path "$domain") || return 2
    target=$domain
  fi
  [[ ! -L $state ]] || return 2
  exec 9>/run/lock/kwvps-cloudflare.lock || return 2
  flock -n 9 || return 1
  kw_cf_zone_for_domain "$domain" "$zone" || return 2
  zone_json=$(kw_cf_api GET "zones/$zone") || return 2
  plan=$(printf '%s' "$zone_json" | kw_cf_rate_plan) || return 2
  if [[ $scope == zone && $plan != free ]]; then
    kw_log ERROR 'Phạm vi toàn zone chỉ dùng cho gói Free sau xác nhận riêng.'
    return 2
  fi
  if [[ $scope == host && $plan == free ]]; then
    kw_log ERROR 'Gói Free không hỗ trợ hostname; quay lại menu để xác nhận phạm vi TOÀN ZONE.'
    return 2
  fi
  if [[ $plan != free && $plan != pro && $plan != business && $plan != enterprise ]]; then
    kw_log ERROR "Gói Cloudflare $plan chưa được KwVPS hỗ trợ."
    return 2
  fi
  kw_cf_rate_api GET "$zone" entrypoint || return 2
  if [[ $KW_CF_RATE_STATUS == 200 ]]; then
    entry=$KW_CF_RATE_RESPONSE
    ruleset=$(printf '%s' "$entry" | kw_cf_rate_entry_id) || return 2
  elif [[ $KW_CF_RATE_STATUS == 404 && $rate != off ]]; then
    entry=''
    ruleset=''
  else
    kw_log ERROR "Không đọc được Cloudflare Rate Limiting (HTTP $KW_CF_RATE_STATUS); kiểm tra quyền Zone WAF Read/Write."
    kw_cf_token_help
    return 2
  fi
  if [[ $rate == off ]]; then
    [[ -f $state && $(stat -c %u:%a -- "$state") == 0:600 ]] || {
      kw_log ERROR 'Không có rule Cloudflare do KwVPS quản lý cho phạm vi này.'; return 2;
    }
    local saved_domain saved_zone saved_ruleset saved_rule saved_rate
    read -r saved_domain saved_zone saved_ruleset saved_rule saved_rate < "$state" || return 2
    [[ $saved_domain == "$target" && $saved_zone == "$zone" && $saved_ruleset == "$ruleset" &&
       $saved_rule =~ ^[a-fA-F0-9]{32}$ ]] &&
      kw_cf_antiddos_rate_valid "$saved_rate" && [[ $saved_rate != off ]] || return 2
    rule_id=$(printf '%s' "$entry" | kw_cf_rate_rule_id "$marker") || return 2
    [[ $rule_id == "$saved_rule" ]] || return 2
    kw_cf_rate_api DELETE "$zone" "rule/$ruleset/rules/$rule_id" || return 1
    [[ $KW_CF_RATE_STATUS == 200 || $KW_CF_RATE_STATUS == 204 ]] || {
      kw_log ERROR "Cloudflare không xóa rule (HTTP $KW_CF_RATE_STATUS)."; return 1;
    }
    rm -f -- "$state" || { kw_log ERROR 'Đã xóa trên Cloudflare nhưng chưa xóa được state local.'; return 1; }
    printf 'Đã tắt Cloudflare Rate Limiting cho %s.\n' "$target"
    return 0
  fi
  [[ ! -e $state ]] || { kw_log ERROR 'Phạm vi này đã có rule KwVPS; tắt rule cũ trước khi đổi mức.'; return 2; }
  if [[ -n $entry ]]; then
    if rule_id=$(printf '%s' "$entry" | kw_cf_rate_rule_id "$marker"); then
      kw_log ERROR 'Cloudflare đã có rule cùng mã KwVPS nhưng thiếu state; kiểm tra thủ công trước khi ghi.'; return 2
    else
      rc=$?
      ((rc == 1)) || return 2
    fi
  fi
  payload=$(mktemp /run/kwvps-cf-rate-payload.XXXXXXXX) || return 1
  trap 'rm -f -- "$payload"' EXIT
  chmod 0600 -- "$payload" || return 1
  if [[ -z $ruleset ]]; then
    kw_cf_rate_rule_json "$domain" "$rate" "$marker" yes "$scope" > "$payload" || return 2
    write_route=ruleset
  else
    kw_cf_rate_rule_json "$domain" "$rate" "$marker" no "$scope" > "$payload" || return 2
    write_route="rule/$ruleset/rules"
  fi
  kw_cf_rate_api POST "$zone" "$write_route" "$payload" yes || return 1
  if [[ $KW_CF_RATE_STATUS != 200 && $KW_CF_RATE_STATUS != 201 ]]; then
    printf '%s' "$KW_CF_RATE_RESPONSE" | kw_cf_rate_error_summary
    kw_log ERROR "Cloudflare từ chối kiểm tra rule (HTTP $KW_CF_RATE_STATUS); chưa thay đổi Cloudflare."
    return 1
  fi
  kw_cf_rate_api POST "$zone" "$write_route" "$payload" || return 1
  [[ $KW_CF_RATE_STATUS == 200 || $KW_CF_RATE_STATUS == 201 ]] || {
    printf '%s' "$KW_CF_RATE_RESPONSE" | kw_cf_rate_error_summary
    kw_log ERROR "Cloudflare từ chối tạo Rate Limiting (HTTP $KW_CF_RATE_STATUS)."; return 1;
  }
  kw_cf_rate_api GET "$zone" entrypoint || {
    kw_log ERROR 'Rule có thể đã tạo nhưng không đọc lại được; kiểm tra Cloudflare Dashboard.'; return 1;
  }
  [[ $KW_CF_RATE_STATUS == 200 ]] || return 1
  entry=$KW_CF_RATE_RESPONSE
  ruleset=$(printf '%s' "$entry" | kw_cf_rate_entry_id) || return 1
  rule_id=$(printf '%s' "$entry" | kw_cf_rate_rule_id "$marker") || {
    kw_log ERROR 'Không tìm được rule vừa tạo; kiểm tra Cloudflare Dashboard.'; return 1;
  }
  local stage
  stage=$(mktemp /etc/kwvps/cloudflare/.rate-state.XXXXXXXX) || return 1
  chmod 0600 -- "$stage" || return 1
  printf '%s %s %s %s %s\n' "$target" "$zone" "$ruleset" "$rule_id" "$rate" > "$stage" || return 1
  mv -T -- "$stage" "$state" || return 1
  printf 'Đã bật Cloudflare Rate Limiting cho %s: %s request/10 giây/IP, block 10 giây.\n' "$target" "$((rate * 10))"
)

kw_cf_rate_interactive() {
  local domain zone rate choice cache_status state plan zone_json scope prompt confirm
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  if kw_cf_zone_cache_read "$domain"; then
    zone=$KW_CF_ZONE_ID
  else
    cache_status=$?
    ((cache_status == 1)) || return 2
    if kw_cf_zone_discover "$domain"; then
      zone=$KW_CF_ZONE_ID
    else
      printf 'Không tự tìm được Zone ID; nhập ID đã gắn token riêng (Cấu hình API token → Thêm/thay token theo zone).\n'
      kw_prompt_validated 'Zone ID (32 ký tự hex; Enter để hủy): ' kw_cf_zone_id_valid 'Zone ID không hợp lệ' plain || return 0
      zone=$KW_PROMPT_VALUE
      kw_cf_zone_for_domain "$domain" "$zone" || return 2
    fi
    kw_cf_zone_cache_save "$domain" "$zone" || return 2
  fi
  kw_cf_zone_for_domain "$domain" "$zone" || return 2
  zone_json=$(kw_cf_api GET "zones/$zone") || return 2
  plan=$(printf '%s' "$zone_json" | kw_cf_rate_plan) || return 2
  if [[ $plan == free ]]; then
    scope=zone
    state=$(kw_cf_rate_zone_state_path "$zone") || return 2
    printf 'Cloudflare Free: KHÔNG giới hạn riêng %s. Rule sẽ áp cho TOÀN ZONE %s, mọi hostname/subdomain.\n' "$domain" "$KW_CF_ZONE_NAME"
  elif [[ $plan == pro || $plan == business || $plan == enterprise ]]; then
    scope=host
    state=$(kw_cf_rate_state_path "$domain") || return 2
    printf 'Cloudflare %s: rule chỉ áp cho hostname %s.\n' "$plan" "$domain"
  else
    kw_log ERROR "Gói Cloudflare $plan chưa được KwVPS hỗ trợ."
    return 2
  fi
  printf 'Giới hạn hiện tại do KwVPS lưu: '
  if [[ -f $state && ! -L $state ]]; then
    awk '{print $5 " req/s"}' "$state"
  else
    printf 'off\n'
  fi
  printf 'Mỗi IP tại Cloudflare: 1. 50/10s  2. 100/10s  3. 200/10s  4. 500/10s  5. Tắt\n0. Quay lại\nChọn: '
  IFS= read -r choice || return 0
  case "$choice" in 1) rate=5 ;; 2) rate=10 ;; 3) rate=20 ;; 4) rate=50 ;; 5) rate=off ;; *) return 0 ;; esac
  if [[ $scope == zone ]]; then
    prompt="Áp Cloudflare Rate Limiting $rate cho TOÀN ZONE $KW_CF_ZONE_NAME (mọi hostname/subdomain)?"
    confirm="CF-RATE-ZONE:$zone:$rate"
  else
    prompt="Áp Cloudflare Rate Limiting $rate cho riêng $domain?"
    confirm="CF-RATE:$domain:$rate"
  fi
  kw_prompt_yes_no_token "$prompt" "$confirm" || return 0
  kw_cf_rate_apply "$domain" "$zone" "$rate" "$KW_PROMPT_VALUE" "$scope"
}
