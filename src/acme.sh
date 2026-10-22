#!/usr/bin/env bash
# ACME provider for future certificates only; existing Certbot renewals stay intact.
readonly KW_ACME_DIR=/etc/kwvps/acme
readonly KW_ACME_PROVIDER_FILE=$KW_ACME_DIR/provider
readonly KW_ACME_ZEROSSL_CONFIG=$KW_ACME_DIR/zerossl.ini

kw_acme_eab_valid() {
  local value=${1:-}
  ((${#value} >= 8 && ${#value} <= 256)) && [[ $value =~ ^[A-Za-z0-9_-]+$ ]]
}

kw_acme_provider_current() {
  local value
  KW_ACME_PROVIDER=letsencrypt
  [[ -e $KW_ACME_PROVIDER_FILE || -L $KW_ACME_PROVIDER_FILE ]] || return 0
  [[ -f $KW_ACME_PROVIDER_FILE && ! -L $KW_ACME_PROVIDER_FILE && \
     $(stat -c %u:%a -- "$KW_ACME_PROVIDER_FILE") == 0:600 ]] || return 2
  value=$(< "$KW_ACME_PROVIDER_FILE")
  [[ $value == letsencrypt || $value == zerossl ]] || return 2
  KW_ACME_PROVIDER=$value
}

kw_acme_zerossl_ready() {
  local -a lines=()
  [[ -f $KW_ACME_ZEROSSL_CONFIG && ! -L $KW_ACME_ZEROSSL_CONFIG && \
     $(stat -c %u:%a -- "$KW_ACME_ZEROSSL_CONFIG") == 0:600 ]] || return 2
  mapfile -t lines < "$KW_ACME_ZEROSSL_CONFIG" || return 2
  ((${#lines[@]} == 3)) || return 2
  [[ ${lines[0]} == 'server = https://acme.zerossl.com/v2/DV90' && \
     ${lines[1]} == 'eab-kid = '* && ${lines[2]} == 'eab-hmac-key = '* ]] || return 2
  kw_acme_eab_valid "${lines[1]#eab-kid = }" && kw_acme_eab_valid "${lines[2]#eab-hmac-key = }"
}

kw_acme_status() {
  kw_acme_provider_current || { kw_log ERROR 'File ACME provider không hợp lệ.'; return 2; }
  printf 'ACME provider cho chứng chỉ MỚI: %s\n' "$KW_ACME_PROVIDER"
  printf 'Chứng chỉ đã cấp giữ nguyên provider/lịch gia hạn của Certbot.\n'
  if [[ $KW_ACME_PROVIDER == zerossl ]]; then
    if kw_acme_zerossl_ready; then printf 'ZeroSSL EAB: đã lưu root-only (không hiển thị).\n'
    else printf 'ZeroSSL EAB: thiếu hoặc sai quyền; không thể cấp chứng chỉ mới.\n'; fi
  fi
}

kw_acme_provider_set() (
  local provider=${1:-} kid=${2:-} hmac=${3:-} confirm=${4:-} temp='' provider_temp=''
  [[ $provider == letsencrypt || $provider == zerossl ]] && [[ $confirm == "$provider" ]] || return 2
  if [[ $provider == zerossl ]]; then kw_acme_eab_valid "$kid" && kw_acme_eab_valid "$hmac" || return 2; fi
  ((EUID == 0)) && kw_os_supported '' || return 2
  [[ -d /etc/kwvps && ! -L /etc/kwvps && $(stat -c %u -- /etc/kwvps) == 0 ]] || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  exec 9>/run/lock/kwvps-acme.lock || return 2
  flock -n 9 || return 1
  if [[ -e $KW_ACME_DIR || -L $KW_ACME_DIR ]]; then
    [[ -d $KW_ACME_DIR && ! -L $KW_ACME_DIR && $(stat -c %u:%a -- "$KW_ACME_DIR") == 0:700 ]] || return 2
  else
    install -d -m 0700 -o root -g root -- "$KW_ACME_DIR" || return 1
  fi
  kw_acme_provider_current || return 2
  [[ ! -e $KW_ACME_ZEROSSL_CONFIG && ! -L $KW_ACME_ZEROSSL_CONFIG ]] ||
    kw_acme_zerossl_ready || return 2
  trap '[[ -z $temp ]] || rm -f -- "$temp"; [[ -z $provider_temp ]] || rm -f -- "$provider_temp"' EXIT
  if [[ $provider == zerossl ]]; then
    temp=$(mktemp "$KW_ACME_DIR/.zerossl.XXXXXXXX") || return 1
    chmod 0600 -- "$temp" || return 1
    printf 'server = https://acme.zerossl.com/v2/DV90\neab-kid = %s\neab-hmac-key = %s\n' \
      "$kid" "$hmac" > "$temp" || return 1
    mv -T -- "$temp" "$KW_ACME_ZEROSSL_CONFIG" || return 1
    temp=''
  fi
  provider_temp=$(mktemp "$KW_ACME_DIR/.provider.XXXXXXXX") || return 1
  chmod 0600 -- "$provider_temp" || return 1
  printf '%s\n' "$provider" > "$provider_temp" || return 1
  mv -T -- "$provider_temp" "$KW_ACME_PROVIDER_FILE" || return 1
  provider_temp=''
  printf 'Đã chọn %s cho các lần cấp chứng chỉ MỚI; chứng chỉ đã có không đổi.\n' "$provider"
)

kw_acme_provider_interactive() {
  local choice provider kid='' hmac=''
  kw_acme_status || return 2
  printf "1. Let's Encrypt\n2. ZeroSSL (cần EAB)\n0. Quay lại\nChọn: "
  IFS= read -r choice || return 0
  case "$choice" in 1) provider=letsencrypt ;; 2) provider=zerossl ;; 0) return 0 ;; *) printf 'Lựa chọn không hợp lệ.\n'; return 2 ;; esac
  if [[ $provider == zerossl ]]; then
    printf 'Tạo EAB: ZeroSSL Dashboard → Developer → Generate EAB credentials.\n'
    printf 'Không gửi EAB qua chat; chỉ nhập trực tiếp trong terminal VPS.\n'
    printf 'EAB KID: '
    IFS= read -r kid || return 0
    kw_acme_eab_valid "$kid" || { kw_log ERROR 'EAB KID không hợp lệ.'; return 2; }
    printf 'EAB HMAC key (ẩn): '
    IFS= read -r -s hmac || return 0
    printf '\n'
    kw_acme_eab_valid "$hmac" || { kw_log ERROR 'EAB HMAC không hợp lệ.'; return 2; }
  fi
  kw_prompt_yes_no_token "Chọn $provider cho chứng chỉ cấp mới?" "$provider" || return 0
  kw_acme_provider_set "$provider" "$kid" "$hmac" "$KW_PROMPT_VALUE"
}
