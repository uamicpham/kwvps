#!/usr/bin/env bash
# Shared primitives. No writes, network access, eval, or automatic sudo.
readonly KW_VERSION='0.50.17'
KW_PREVIEW=0

kw_log() {
  printf '[%s] %s: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >&2
}

kw_help() {
  printf '%s\n' \
    'KwVPS — quản lý site trên Ubuntu Server 24.04 LTS sạch' \
    'bash kwvps                     Menu tương tác (Linux)' \
    'bash kwvps --preview           Xem menu, không gọi công cụ quản trị' \
    'bash kwvps --status            Thông tin hệ thống' \
    'bash kwvps --doctor            Kiểm tra môi trường Ubuntu 24.04' \
    'bash kwvps --services          Package/version đã cài' \
    'bash kwvps --pending-updates   Package dịch vụ chờ cập nhật (cache apt)' \
    'bash kwvps --ports             Socket đang listen và trạng thái UFW' \
    'bash kwvps --swap              Swap hiện tại' \
    'bash kwvps --site-plan DOMAIN PHP   Xem kế hoạch thêm site' \
    'bash kwvps --site-list         Site do KwVPS quản lý (Linux)' \
    'sudo kwvps --laravel-deploy DOMAIN [--migrate]   Pull Git và deploy Laravel; migration mặc định tắt' \
    'bash kwvps --version           Phiên bản KwVPS' \
    'bash kwvps --help              Trợ giúp' \
    '0: quay lại (menu gốc: thoát). Ctrl+C: thoát. EOF: thoát.' \
    'Mã thoát: 0 thành công, 1 kiểm tra/lệnh lỗi, 2 đầu vào/môi trường sai,' \
    '3 chưa triển khai, 130 bị hủy. Thao tác tạo site chỉ có trong menu Linux.'
}

kw_has() { command -v "$1" >/dev/null 2>&1; }

# Read all of apt-cache's output before selecting Candidate. Exiting an awk
# pipeline early can send SIGPIPE to apt-cache under pipefail (exit 141).
kw_apt_candidate() {
  local package=${1:-} policy candidate
  [[ $package =~ ^[a-z0-9.+-]+$ ]] || return 2
  policy=$(LC_ALL=C apt-cache policy "$package") || return 1
  candidate=$(awk '/^[[:space:]]*Candidate:/ && !found { print $2; found=1 }' <<< "$policy") || return 1
  [[ -n $candidate && $candidate != '(none)' ]] || return 1
  printf '%s\n' "$candidate"
}

kw_prompt_validated() {
  local prompt=$1 validator=$2 hint=$3 secret=$4 value
  shift 4
  while :; do
    printf '%s' "$prompt"
    if [[ $secret == secret ]]; then
      IFS= read -r -s value || return 1
      printf '\n'
    else
      IFS= read -r value || return 1
    fi
    [[ -n $value ]] || { printf 'Đã hủy.\n'; return 1; }
    if "$validator" "$@" "$value"; then
      # shellcheck disable=SC2034 # Shared with sourced interactive modules.
      KW_PROMPT_VALUE=$value
      return 0
    fi
    printf 'Giá trị không hợp lệ: %s. Nhập lại hoặc Enter để hủy.\n' "$hint"
  done
}

kw_value_equals() { [[ ${1:-} == "${2:-}" ]]; }
kw_value_equals_ci() { [[ ${1,,} == "${2,,}" ]]; }
kw_prompt_confirm_domain() {
  kw_prompt_validated "$2" kw_value_equals_ci 'Tên xác nhận phải đúng domain' plain "$1"
}
kw_prompt_yes_no_token() {
  local question=$1 token=$2 answer
  while :; do
    printf '%s [y/N]: ' "$question"
    IFS= read -r answer || return 1
    case "$answer" in
      y|Y|yes|YES)
        # shellcheck disable=SC2034 # Read by sourced interactive modules.
        KW_PROMPT_VALUE=$token
        return 0 ;;
      ''|n|N|no|NO|0) printf 'Đã hủy.\n'; return 1 ;;
      *) printf 'Chỉ nhập y hoặc N.\n' ;;
    esac
  done
}
kw_prompt_confirm_token() {
  kw_prompt_validated "$2" kw_value_equals 'Giá trị xác nhận không khớp' plain "$1"
}

kw_read_command() {
  if ! kw_has "$1"; then
    kw_log WARN "Thiếu công cụ $1; không tự cài."
    return 1
  fi
  if ! kw_has timeout; then
    kw_log WARN 'Thiếu timeout để giới hạn thời gian truy vấn.'
    return 1
  fi
  local result=0
  timeout --foreground 15s "$@" || result=$?
  if ((result != 0)); then
    kw_log WARN "Truy vấn $1 không thành công (mã $result); có thể thiếu quyền."
  fi
  return "$result"
}

kw_domain_valid() {
  local domain=$1 label
  local -a labels
  [[ ${#domain} -le 253 && $domain == *.* && $domain != *. ]] || return 1
  [[ $domain =~ ^[a-zA-Z0-9.-]+$ ]] || return 1
  IFS='.' read -r -a labels <<< "$domain"
  for label in "${labels[@]}"; do
    [[ ${#label} -ge 1 && ${#label} -le 63 ]] || return 1
    [[ $label != -* && $label != *- ]] || return 1
  done
  # Hostnames only: literal IPv4 belongs to network configuration, not a site.
  [[ ! $domain =~ ^[0-9.]+$ ]]
}

kw_port_valid() {
  [[ $1 =~ ^[0-9]{1,5}$ ]] || return 1
  ((10#$1 >= 1 && 10#$1 <= 65535))
}

kw_main() {
  if [[ ${1:-} == --site-plan ]]; then
    if (($# != 3)); then kw_help >&2; return 2; fi
    kw_site_plan "$2" "$3"
    return
  fi
  if [[ ${1:-} == --laravel-deploy ]]; then
    if { (($# != 2 && $# != 3)); } || { (($# == 3)) && [[ $3 != --migrate ]]; }; then
      kw_help >&2; return 2
    fi
    if [[ $(uname -s) != Linux ]]; then
      kw_log ERROR 'Deploy Laravel cần Ubuntu VPS; không chạy trên máy phát triển.'
      return 2
    fi
    if ! kw_os_supported; then
      kw_log ERROR 'Deploy Laravel chỉ hỗ trợ Ubuntu 24.04.'
      return 2
    fi
    if ((EUID != 0)); then
      kw_log ERROR 'Cần quyền quản trị để deploy Laravel. Hãy chạy: sudo kwvps --laravel-deploy DOMAIN [--migrate]'
      return 2
    fi
    kw_laravel_deploy_confirm "$2" auto "$(( $# == 3 ))"
    return
  fi
  if (($# > 1)); then kw_help >&2; return 2; fi
  case "${1:-menu}" in
    --help|-h) kw_help; return 0 ;;
    --version) printf 'KwVPS %s\n' "$KW_VERSION"; return 0 ;;
    --preview)
      # shellcheck disable=SC2034 # Read by sourced menu/system modules.
      KW_PREVIEW=1
      kw_menu main
      return 0
      ;;
    menu|--status|--doctor|--services|--pending-updates|--ports|--swap|--site-list) ;;
    *) kw_log ERROR 'Tùy chọn không hợp lệ. Dùng --help.'; return 2 ;;
  esac
  if [[ $(uname -s) != Linux ]]; then
    kw_log ERROR 'Chức năng quản trị cần Linux; dùng --preview để xem menu trên máy phát triển.'
    return 2
  fi
  if [[ ${1:-menu} == menu && $EUID -ne 0 ]]; then
    kw_log ERROR 'Cần quyền quản trị để dùng menu KwVPS. Hãy chạy: sudo kwvps'
    return 2
  fi
  case "${1:-menu}" in
    menu) kw_menu main ;;
    --status) kw_header; kw_os_show ;;
    --doctor) kw_doctor ;;
    --services) kw_packages ;;
    --pending-updates) kw_pending ;;
    --ports) kw_ports ;;
    --swap) kw_swap ;;
    --site-list) kw_site_list ;;
  esac
}
