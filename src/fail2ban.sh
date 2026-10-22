#!/usr/bin/env bash
# Fail2ban actions are confined to existing jails. KwVPS never rewrites jails.

kw_f2b_jail_valid() {
  [[ ${1:-} =~ ^[a-zA-Z0-9_-]{1,64}$ ]]
}

kw_f2b_ipv4_valid() {
  local ip=${1:-} octet
  local -a octets
  [[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  IFS='.' read -r -a octets <<< "$ip"
  for octet in "${octets[@]}"; do
    [[ ${#octet} -eq 1 || $octet != 0* ]] || return 1
    ((10#$octet <= 255)) || return 1
  done
}

kw_f2b_ready() {
  kw_os_supported '' || return 2
  kw_has fail2ban-client || { kw_log ERROR 'Fail2ban chưa được cài.'; return 2; }
  systemctl is-active --quiet fail2ban || { kw_log ERROR 'Fail2ban chưa hoạt động.'; return 2; }
}

kw_f2b_jail_exists() {
  local jail=$1 line names name
  local -a jails
  kw_f2b_jail_valid "$jail" || return 2
  line=$(fail2ban-client status) || return 2
  names=${line##*$'Jail list:'}
  [[ $line == *'Jail list:'* ]] || return 2
  names=${names//$'\n'/,}
  names=${names//$'\t'/}
  IFS=',' read -r -a jails <<< "$names"
  for name in "${jails[@]}"; do
    name=${name//[[:space:]]/}
    [[ $name == "$jail" ]] && return 0
  done
  return 1
}

kw_f2b_banned() {
  local jail=$1
  kw_f2b_ready || return 2
  kw_f2b_jail_exists "$jail" || { kw_log ERROR 'Jail không tồn tại.'; return 2; }
  fail2ban-client status "$jail"
}

kw_f2b_change() {
  local verb=$1 jail=$2 ip=$3 confirm=$4 ssh_source sessions
  [[ $verb == banip || $verb == unbanip ]] || return 2
  kw_f2b_jail_valid "$jail" && kw_f2b_ipv4_valid "$ip" || return 2
  [[ $confirm == "$jail/$ip" ]] || { kw_log ERROR 'Xác nhận jail/IP không khớp.'; return 2; }
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root.'; return 2; }
  kw_f2b_ready || return 2
  kw_f2b_jail_exists "$jail" || { kw_log ERROR 'Jail không tồn tại.'; return 2; }
  if [[ $verb == banip ]]; then
    ssh_source=${SSH_CONNECTION:-}
    ssh_source=${ssh_source%% *}
    [[ -z $ssh_source || $ip != "$ssh_source" ]] || {
      kw_log ERROR 'Từ chối khóa IP của kết nối SSH hiện tại.'; return 2;
    }
    sessions=$(who -u) || return 2
    [[ -n $sessions ]] || {
      kw_log ERROR 'Không xác định được phiên SSH; từ chối ban để tránh tự khóa.'; return 2;
    }
    [[ $sessions != *"($ip)"* ]] || {
      kw_log ERROR 'Từ chối khóa IP của phiên đăng nhập đang hoạt động.'; return 2;
    }
  fi
  fail2ban-client set "$jail" "$verb" "$ip"
}

kw_f2b_banned_interactive() {
  local jail
  kw_f2b_ready || return 2
  fail2ban-client status || return 2
  kw_prompt_validated 'Jail cần xem IP bị khóa: ' kw_f2b_jail_exists \
    'Jail không tồn tại' plain || return 0
  jail=$KW_PROMPT_VALUE
  kw_f2b_banned "$jail"
}

kw_f2b_change_interactive() {
  local verb=$1 jail ip confirm
  kw_f2b_ready || return 2
  fail2ban-client status || return 2
  kw_prompt_validated 'Jail: ' kw_f2b_jail_exists 'Jail không tồn tại' plain || return 0
  jail=$KW_PROMPT_VALUE
  kw_prompt_validated 'IPv4: ' kw_f2b_ipv4_valid 'Địa chỉ IPv4 không hợp lệ' plain || return 0
  ip=$KW_PROMPT_VALUE
  if [[ $verb == banip ]]; then
    kw_prompt_yes_no_token "Khóa $ip trong jail $jail?" "$jail/$ip" || return 0
  else
    kw_prompt_validated "Nhập $jail/$ip để xác nhận mở khóa: " \
      kw_value_equals 'Giá trị xác nhận không khớp' plain "$jail/$ip" || return 0
  fi
  confirm=$KW_PROMPT_VALUE
  kw_f2b_change "$verb" "$jail" "$ip" "$confirm"
}
