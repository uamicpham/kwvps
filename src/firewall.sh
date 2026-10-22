#!/usr/bin/env bash
# UFW changes only active firewalls and rules carrying KwVPS-owned comments.
# This module never enables UFW or edits provider firewalls.

kw_fw_proto_valid() { [[ ${1:-} == tcp || ${1:-} == udp ]]; }

kw_fw_port_allowed() {
  kw_port_valid "${1:-}" || return 1
  # MariaDB's default port is intentionally excluded from a public allow rule.
  [[ $1 != 3306 ]]
}

kw_fw_ready() {
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để thay đổi UFW.'; return 2; }
  kw_os_supported '' || return 2
  kw_has ufw || { kw_log ERROR 'UFW chưa được cài.'; return 2; }
  local status
  status=$(LC_ALL=C ufw status) || return 2
  [[ $status == 'Status: active'* ]] || {
    kw_log ERROR 'UFW đang tắt; KwVPS không tự bật vì có thể khóa SSH.'; return 2;
  }
}

kw_fw_rule_numbers() {
  local kind=$1 value=$2 proto=${3:-} status line number marker
  case "$kind" in
    port)
      kw_fw_port_allowed "$value" && kw_fw_proto_valid "$proto" || return 2
      marker="kwvps-port-${value}-${proto}"
      ;;
    ip)
      kw_f2b_ipv4_valid "$value" || return 2
      marker="kwvps-block-${value//./-}"
      ;;
    *) return 2 ;;
  esac
  status=$(LC_ALL=C ufw status numbered) || return 2
  while IFS= read -r line; do
    [[ $line == *"# $marker" ]] || continue
    if [[ $kind == port ]]; then
      [[ $line == *"${value}/${proto}"* && $line == *'ALLOW IN'* ]] || continue
    else
      [[ $line == *"DENY IN"* && $line == *" $value"* ]] || continue
    fi
    [[ $line =~ ^\[[[:space:]]*([0-9]+)\] ]] || continue
    number=${BASH_REMATCH[1]}
    printf '%d\n' "$((10#$number))"
  done <<< "$status"
}

kw_fw_port_plan() {
  local verb=$1 port=$2 proto=$3
  [[ $verb == open || $verb == close ]] || return 2
  kw_fw_port_allowed "$port" && kw_fw_proto_valid "$proto" || return 2
  printf 'Kế hoạch UFW: %s %s/%s. Chỉ thao tác rule gắn nhãn KwVPS; UFW phải active.\n' \
    "$verb" "$port" "$proto"
  printf 'Không tự bật UFW, không đổi firewall nhà cung cấp. Cổng 3306 bị loại khỏi lệnh mở công khai.\n'
}

kw_fw_port_change() {
  local verb=$1 port=$2 proto=$3 confirm=$4 status line
  local -a numbers
  kw_fw_port_plan "$verb" "$port" "$proto" || return 2
  [[ $confirm == "${verb}/${port}/${proto}" ]] || { kw_log ERROR 'Xác nhận không khớp.'; return 2; }
  kw_fw_ready || return 2
  status=$(LC_ALL=C ufw status numbered) || return 2
  if [[ $verb == open ]]; then
    # Do not duplicate or supersede any existing rule for this port/protocol.
    while IFS= read -r line; do
      if [[ $line =~ ^\[[[:space:]]*[0-9]+\][[:space:]]+${port}/${proto}[[:space:]] ]]; then
        kw_log ERROR 'Đã có rule cho cổng này; không tự sửa rule ngoài KwVPS.'
        return 2
      fi
    done <<< "$status"
    ufw allow "${port}/${proto}" comment "kwvps-port-${port}-${proto}"
    return
  fi
  # Never close the default SSH port or the configured SSH daemon port.
  [[ $port != 22 ]] || { kw_log ERROR 'Không đóng cổng SSH 22 từ menu.'; return 2; }
  kw_has sshd || { kw_log ERROR 'Không đọc được cấu hình SSH; từ chối đóng port.'; return 2; }
  local ssh_port ssh_ports
  ssh_ports=$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2}') || return 2
  [[ -n $ssh_ports ]] || return 2
  while IFS= read -r ssh_port; do
    [[ $ssh_port != "$port" ]] || {
      kw_log ERROR 'Không đóng cổng SSH đang cấu hình.'; return 2;
    }
  done <<< "$ssh_ports"
  mapfile -t numbers < <(kw_fw_rule_numbers port "$port" "$proto" | sort -nr)
  ((${#numbers[@]} > 0)) || { kw_log ERROR 'Không có rule KwVPS tương ứng để gỡ.'; return 2; }
  for line in "${numbers[@]}"; do ufw --force delete "$line" || return 1; done
}

kw_fw_ip_plan() {
  local verb=$1 ip=$2
  [[ $verb == ban || $verb == unban ]] && kw_f2b_ipv4_valid "$ip" || return 2
  printf 'Kế hoạch UFW: %s IPv4 %s. Chỉ gỡ rule do KwVPS tạo.\n' "$verb" "$ip"
  printf 'Không ảnh hưởng ban của Fail2ban/Cloudflare hoặc firewall nhà cung cấp.\n'
}

kw_fw_ip_change() {
  local verb=$1 ip=$2 confirm=$3 sessions status line
  local -a numbers
  kw_fw_ip_plan "$verb" "$ip" || return 2
  [[ $confirm == "${verb}/${ip}" ]] || { kw_log ERROR 'Xác nhận không khớp.'; return 2; }
  kw_fw_ready || return 2
  if [[ $verb == ban ]]; then
    sessions=$(who -u) || return 2
    [[ -n $sessions && $sessions != *"($ip)"* ]] || {
      kw_log ERROR 'IP đang đăng nhập hoặc không xác định được phiên SSH; từ chối ban.'; return 2;
    }
    status=$(LC_ALL=C ufw status numbered) || return 2
    while IFS= read -r line; do
      [[ $line != *" $ip"* ]] || { kw_log ERROR 'IP đã có rule; không tự ghi đè.'; return 2; }
    done <<< "$status"
    ufw insert 1 deny from "$ip" comment "kwvps-block-${ip//./-}"
    return
  fi
  mapfile -t numbers < <(kw_fw_rule_numbers ip "$ip" | sort -nr)
  ((${#numbers[@]} > 0)) || { kw_log ERROR 'Không có rule KwVPS tương ứng để gỡ.'; return 2; }
  for line in "${numbers[@]}"; do ufw --force delete "$line" || return 1; done
}

kw_fw_port_interactive() {
  local verb=$1 port proto confirm
  kw_prompt_validated 'Cổng: ' kw_fw_port_allowed 'Cổng 1–65535; không mở trực tiếp 3306' plain || return 0
  port=$KW_PROMPT_VALUE
  kw_prompt_validated 'Giao thức tcp/udp: ' kw_fw_proto_valid 'Chỉ nhận tcp hoặc udp' plain || return 0
  proto=$KW_PROMPT_VALUE
  kw_fw_port_plan "$verb" "$port" "$proto" || return 2
  if [[ $verb == open ]]; then
    kw_prompt_yes_no_token "Mở cổng $port/$proto?" "$verb/$port/$proto" || return 0
  else
    kw_prompt_validated "Nhập $verb/$port/$proto để xác nhận khóa/xóa rule: " kw_value_equals \
      'Giá trị xác nhận không khớp' plain "$verb/$port/$proto" || return 0
  fi
  confirm=$KW_PROMPT_VALUE
  kw_fw_port_change "$verb" "$port" "$proto" "$confirm"
}

kw_fw_ip_interactive() {
  local verb=$1 ip confirm
  kw_prompt_validated 'IPv4: ' kw_f2b_ipv4_valid 'Địa chỉ IPv4 không hợp lệ' plain || return 0
  ip=$KW_PROMPT_VALUE
  kw_fw_ip_plan "$verb" "$ip" || return 2
  if [[ $verb == ban ]]; then
    kw_prompt_yes_no_token "Khóa IPv4 $ip?" "$verb/$ip" || return 0
  else
    kw_prompt_validated "Nhập $verb/$ip để xác nhận mở khóa: " kw_value_equals \
      'Giá trị xác nhận không khớp' plain "$verb/$ip" || return 0
  fi
  confirm=$KW_PROMPT_VALUE
  kw_fw_ip_change "$verb" "$ip" "$confirm"
}

kw_fw_ip_list() {
  kw_fw_ready || return 2
  printf 'Rule UFW hiện tại; nguồn ban Fail2ban được xem ở menu riêng.\n'
  LC_ALL=C ufw status numbered
}
