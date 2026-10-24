#!/usr/bin/env bash
# UFW changes remain local to this VPS; provider firewalls are not managed.
# Enabling UFW protects every configured/current SSH port before activation.

kw_fw_proto_valid() { [[ ${1:-} == tcp || ${1:-} == udp ]]; }

kw_fw_ipv6_enabled() {
  [[ -f /etc/default/ufw && ! -L /etc/default/ufw ]] &&
    grep -Eq '^IPV6=yes$' /etc/default/ufw
}

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
    kw_log ERROR 'UFW đang tắt; chọn Bật Firewall hoặc thao tác mở/khóa port.'; return 2;
  }
}

kw_fw_ssh_ports() {
  local config port client_port local_port extra socket_listen
  local -a socket_ports=()
  kw_has sshd || { kw_log ERROR 'Không đọc được sshd để bảo vệ cổng SSH.'; return 2; }
  config=$(sshd -T 2>/dev/null) || { kw_log ERROR 'sshd -T không hợp lệ; không bật UFW.'; return 2; }
  if systemctl is-active --quiet ssh.socket; then
    socket_listen=$(systemctl show ssh.socket -p Listen --value 2>/dev/null)
    while read -r port; do
      if kw_port_valid "$port"; then
        socket_ports+=("$port")
        printf '%s\n' "$port"
      fi
    done < <(grep -oE ':[0-9]+' <<< "$socket_listen" | tr -d ':')
    if [[ -z ${SSH_CONNECTION:-} && ${#socket_ports[@]} -eq 0 ]]; then
      kw_log ERROR 'ssh.socket đang chạy nhưng không biết cổng của phiên SSH hiện tại; từ chối bật UFW để tránh khóa máy.'
      return 2
    fi
  fi
  while read -r _ port; do
    kw_port_valid "$port" || { kw_log ERROR 'Cổng SSH không hợp lệ; không bật UFW.'; return 2; }
    printf '%s\n' "$port"
  done < <(awk '$1 == "port" {print $1, $2}' <<< "$config")
  if [[ -n ${SSH_CONNECTION:-} ]]; then
    read -r _ client_port _ local_port extra <<< "$SSH_CONNECTION"
    if [[ -n ${extra:-} ]] || ! kw_port_valid "$client_port" || ! kw_port_valid "$local_port"; then
      kw_log ERROR 'Không đọc được cổng phiên SSH hiện tại; không bật UFW.'; return 2;
    fi
    printf '%s\n' "$local_port"
  fi
}

kw_fw_enable_safe() {
  local state ports port numbered mode
  ((EUID == 0)) && kw_os_supported '' && kw_has ufw || return 2
  state=$(LC_ALL=C ufw status) || return 2
  [[ $state == 'Status: active'* ]] && return 0
  [[ $state == 'Status: inactive'* ]] || { kw_log ERROR 'Trạng thái UFW không xác định; không bật.'; return 2; }
  mode=$(stat -c %a -- /etc/default/ufw 2>/dev/null) || return 2
  if ! {
    [[ -f /etc/default/ufw && ! -L /etc/default/ufw && $(stat -c %u -- /etc/default/ufw) == 0 &&
       $mode =~ ^[0-7]{3,4}$ ]] &&
      (( (8#$mode & 0022) == 0 )) &&
      grep -Eq '^DEFAULT_INPUT_POLICY="?DROP"?$' /etc/default/ufw && kw_fw_ipv6_enabled
  }; then
    kw_log ERROR 'UFW cần mặc định deny incoming và IPV6=yes trước khi tự bật; kiểm tra /etc/default/ufw.'; return 2;
  fi
  ports=$(kw_fw_ssh_ports) || return 2
  [[ -n $ports ]] || { kw_log ERROR 'Không tìm được cổng SSH để bảo vệ; không bật UFW.'; return 2; }
  ports=$(sort -nu <<< "$ports") || return 2
  printf 'UFW đang tắt. Bảo vệ cổng SSH trước khi bật: %s\n' "$(tr '\n' ' ' <<< "$ports")"
  while IFS= read -r port; do
    kw_port_valid "$port" || return 2
    ufw insert 1 allow "${port}/tcp" comment "kwvps-ssh-guard-${port}" 2>/dev/null ||
      ufw allow "${port}/tcp" comment "kwvps-ssh-guard-${port}" || return 1
  done <<< "$ports"
  if ! ufw --force enable; then
    ufw --force disable >/dev/null 2>&1 || kw_log ERROR 'Không tắt lại được UFW sau lỗi bật; kiểm tra console cứu hộ.'
    return 1
  fi
  state=$(LC_ALL=C ufw status) || return 1
  numbered=$(LC_ALL=C ufw status numbered) || return 1
  if [[ $state != 'Status: active'* ]]; then
    ufw --force disable >/dev/null 2>&1 || kw_log ERROR 'Không tắt lại được UFW; kiểm tra console cứu hộ.'
    kw_log ERROR 'UFW không active sau khi bật.'
    return 1
  fi
  while IFS= read -r port; do
    if [[ $numbered != *"# kwvps-ssh-guard-${port}"* ]]; then
      ufw --force disable >/dev/null 2>&1 || kw_log ERROR 'Không tắt lại được UFW; kiểm tra console cứu hộ.'
      kw_log ERROR "Không thấy rule bảo vệ SSH $port sau khi bật UFW."
      return 1
    fi
  done <<< "$ports"
  printf 'Đã bật UFW; cổng SSH được bảo vệ. Kiểm tra thêm firewall của nhà cung cấp VPS.\n'
}

kw_fw_toggle() (
  local action=$1 confirm=${2:-} state
  [[ $action == enable || $action == disable ]] && [[ $confirm == "ufw-$action" ]] || return 2
  ((EUID == 0)) && kw_os_supported '' && kw_has ufw && kw_has flock || return 2
  exec 9>/run/lock/kwvps-ufw.lock || return 2
  flock -n 9 || { kw_log ERROR 'Một thao tác UFW khác đang chạy.'; return 1; }
  if [[ $action == enable ]]; then
    kw_fw_enable_safe || return $?
    printf 'UFW đang bật. Rule hiện tại:\n'
    LC_ALL=C ufw status numbered
    return
  fi
  state=$(LC_ALL=C ufw status) || return 2
  if [[ $state == 'Status: inactive'* ]]; then printf 'UFW đã tắt.\n'; return 0; fi
  [[ $state == 'Status: active'* ]] || return 2
  ufw --force disable || return 1
  state=$(LC_ALL=C ufw status) || return 1
  [[ $state == 'Status: inactive'* ]] || { kw_log ERROR 'UFW chưa tắt sau lệnh disable.'; return 1; }
  printf 'Đã tắt UFW của VPS. Firewall nhà cung cấp không đổi.\n'
)

kw_fw_toggle_interactive() {
  local action=$1
  [[ $action == enable || $action == disable ]] || return 2
  if [[ $action == enable ]]; then
    printf 'Bật UFW với mặc định deny incoming. KwVPS thêm ALLOW cho cổng SSH đang cấu hình/đang kết nối trước khi bật.\n'
    printf 'Các dịch vụ inbound khác có thể bị chặn; kiểm tra rule và console cứu hộ trước khi tiếp tục.\n'
    kw_prompt_yes_no_token 'Bật Firewall UFW của toàn VPS?' ufw-enable || return 0
  else
    printf 'Tắt UFW sẽ ngừng thực thi mọi rule UFW, gồm các rule chặn IP/cổng.\n'
    kw_prompt_yes_no_token 'Tắt Firewall UFW của toàn VPS?' ufw-disable || return 0
  fi
  kw_fw_toggle "$action" "$KW_PROMPT_VALUE"
}

kw_fw_rule_numbers() {
  local kind=$1 value=$2 proto=${3:-} status line number marker
  case "$kind" in
    port)
      kw_fw_port_allowed "$value" && kw_fw_proto_valid "$proto" || return 2
      marker="kwvps-port-${value}-${proto}"
      ;;
    port-deny)
      kw_port_valid "$value" && kw_fw_proto_valid "$proto" || return 2
      marker="kwvps-port-deny-${value}-${proto}"
      ;;
    ip)
      kw_f2b_ipv4_valid "$value" || return 2
      marker="kwvps-block-${value//./-}"
      ;;
    *) return 2 ;;
  esac
  status=$(LC_ALL=C ufw status numbered) || return 2
  while IFS= read -r line; do
    [[ $line == *"# $marker"* ]] || continue
    if [[ $kind == port || $kind == port-deny ]]; then
      [[ $line == *"${value}/${proto}"* ]] || continue
      if [[ $kind == port ]]; then
        [[ $line == *'ALLOW IN'* ]] || continue
      else
        [[ $line == *'DENY IN'* ]] || continue
      fi
    else
      [[ $line == *"DENY IN"* && $line == *" $value"* ]] || continue
    fi
    [[ $line =~ ^\[[[:space:]]*([0-9]+)\] ]] || continue
    number=${BASH_REMATCH[1]}
    printf '%d\n' "$((10#$number))"
  done <<< "$status"
}

kw_fw_port_has_action() {
  local port=$1 proto=$2 action=$3 status line
  kw_port_valid "$port" && kw_fw_proto_valid "$proto" || return 2
  [[ $action == ALLOW || $action == DENY ]] || return 2
  status=$(LC_ALL=C ufw status numbered) || return 2
  while IFS= read -r line; do
    if [[ $line =~ ^\[[[:space:]]*[0-9]+\][[:space:]]+${port}(/${proto})?([[:space:]]+\(v6\))?[[:space:]]+${action}([[:space:]]+IN)?[[:space:]] ]]; then
      return 0
    fi
  done <<< "$status"
  return 1
}

# UFW prints IPv4 and IPv6 as separate rows. A single matching row does not
# prove that inbound traffic is blocked on both address families.
kw_fw_port_has_action_family() {
  local port=$1 proto=$2 action=$3 family=$4 status line target
  kw_port_valid "$port" && kw_fw_proto_valid "$proto" || return 2
  [[ $action == ALLOW || $action == DENY ]] && [[ $family == 4 || $family == 6 ]] || return 2
  status=$(LC_ALL=C ufw status numbered) || return 2
  while IFS= read -r line; do
    [[ $line =~ ^\[[[:space:]]*[0-9]+\][[:space:]]+([^[:space:]]+) ]] || continue
    target=${BASH_REMATCH[1]}
    [[ $target == "$port/$proto" ]] || continue
    [[ $line == *" $action IN "* ]] || continue
    if [[ $family == 4 && $line != *'(v6)'* ]] ||
       [[ $family == 6 && $line == *'(v6)'* ]]; then
      return 0
    fi
  done <<< "$status"
  return 1
}

kw_fw_port_plan() {
  local verb=$1 port=$2 proto=$3
  [[ $verb == open || $verb == close ]] || return 2
  if [[ $verb == open ]]; then kw_fw_port_allowed "$port" || return 2
  else kw_port_valid "$port" || return 2; fi
  kw_fw_proto_valid "$proto" || return 2
  printf 'Kế hoạch UFW: %s %s/%s. Chỉ gỡ rule gắn nhãn KwVPS.\n' \
    "$verb" "$port" "$proto"
  printf 'Nếu UFW đang tắt, KwVPS sẽ bảo vệ SSH rồi tự bật UFW (deny incoming); dịch vụ inbound khác có thể bị ảnh hưởng.\n'
  [[ $verb != open ]] || printf 'Lần bật UFW đầu tiên có thể gián đoạn inbound ngắn trước khi thêm ALLOW cho cổng này.\n'
  printf 'Không đổi firewall nhà cung cấp. Cổng 3306 bị loại khỏi lệnh mở công khai.\n'
}

kw_fw_port_rollback() {
  ((committed == 0)) || return 0
  if ((rollback_deny)); then
    ufw insert 1 deny "${port}/${proto}" comment "kwvps-port-deny-${port}-${proto}" 2>/dev/null ||
      ufw deny "${port}/${proto}" comment "kwvps-port-deny-${port}-${proto}" ||
      kw_log ERROR "Không phục hồi được DENY $port/$proto; kiểm tra UFW thủ công."
  fi
  if ((was_inactive)); then
    ufw --force disable || kw_log ERROR 'Không tắt lại được UFW sau lỗi; kiểm tra console cứu hộ.'
  fi
}

kw_fw_port_change() (
  local verb=$1 port=$2 proto=$3 confirm=$4 status line ssh_ports ssh_port rollback_deny=0 was_inactive=0 committed=0
  local -a numbers
  kw_fw_port_plan "$verb" "$port" "$proto" || return 2
  [[ $confirm == "${verb}/${port}/${proto}" ]] || { kw_log ERROR 'Xác nhận không khớp.'; return 2; }
  ((EUID == 0)) && kw_os_supported '' && kw_has ufw && kw_has flock || return 2
  exec 9>/run/lock/kwvps-ufw.lock || return 2
  flock -n 9 || { kw_log ERROR 'Một thao tác UFW khác đang chạy.'; return 1; }
  if [[ $verb == close ]]; then
    [[ $port != 22 ]] || { kw_log ERROR 'Không đóng cổng SSH 22 từ menu.'; return 2; }
    kw_fw_ipv6_enabled || { kw_log ERROR 'UFW IPV6 chưa bật; không thể bảo đảm khóa cổng cả IPv6.'; return 2; }
    ssh_ports=$(kw_fw_ssh_ports) || return 2
    [[ -n $ssh_ports ]] || return 2
    while IFS= read -r ssh_port; do
      [[ $ssh_port != "$port" ]] || {
        kw_log ERROR 'Không đóng cổng SSH đang cấu hình hoặc đang kết nối.'; return 2;
      }
    done <<< "$ssh_ports"
  fi
  status=$(LC_ALL=C ufw status) || return 2
  [[ $status == 'Status: inactive'* ]] && was_inactive=1
  trap kw_fw_port_rollback EXIT
  kw_fw_enable_safe || return 2
  status=$(LC_ALL=C ufw status numbered) || return 2
  if [[ $verb == open ]]; then
    while IFS= read -r line; do
      if [[ $line =~ ^\[[[:space:]]*[0-9]+\][[:space:]]+${port}/${proto}[[:space:]] &&
            $line == *'DENY IN'* && $line != *"# kwvps-port-deny-${port}-${proto}" ]]; then
        kw_log ERROR 'Còn rule DENY ngoài KwVPS; cần kiểm tra thủ công.'
        return 2
      fi
    done <<< "$status"
    mapfile -t numbers < <(kw_fw_rule_numbers port-deny "$port" "$proto" | sort -nr)
    if ((${#numbers[@]} > 0)); then
      rollback_deny=1
    fi
    for line in "${numbers[@]}"; do ufw --force delete "$line" || return 1; done
    ufw allow "${port}/${proto}" comment "kwvps-port-${port}-${proto}" || return 1
    kw_fw_port_has_action "$port" "$proto" ALLOW || {
      kw_log ERROR 'Không xác minh được rule ALLOW vừa áp.'; return 1;
    }
    rollback_deny=0
    committed=1
    printf 'Đã yêu cầu ALLOW inbound %s/%s; kiểm tra rule khác và firewall nhà cung cấp nếu chưa truy cập được.\n' "$port" "$proto"
    return
  fi
  mapfile -t numbers < <(kw_fw_rule_numbers port-deny "$port" "$proto")
  if ((${#numbers[@]} > 0)); then
    committed=1
    printf 'Cổng %s/%s đã có rule chặn KwVPS.\n' "$port" "$proto"
    return 0
  fi
  ufw insert 1 deny "${port}/${proto}" comment "kwvps-port-deny-${port}-${proto}" 2>/dev/null ||
    ufw deny "${port}/${proto}" comment "kwvps-port-deny-${port}-${proto}" || return 1
  mapfile -t numbers < <(kw_fw_rule_numbers port-deny "$port" "$proto")
  ((${#numbers[@]} > 0)) || kw_fw_port_has_action "$port" "$proto" DENY || {
    kw_log ERROR 'Không xác minh được rule DENY vừa áp.'; return 1;
  }
  committed=1
  printf 'Đã đặt DENY inbound cho %s/%s; rule ALLOW có sẵn được giữ nguyên.\n' "$port" "$proto"
)

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
    ufw insert 1 deny from "$ip" comment "kwvps-block-${ip//./-}" 2>/dev/null ||
      ufw deny from "$ip" comment "kwvps-block-${ip//./-}"
    return
  fi
  mapfile -t numbers < <(kw_fw_rule_numbers ip "$ip" | sort -nr)
  ((${#numbers[@]} > 0)) || { kw_log ERROR 'Không có rule KwVPS tương ứng để gỡ.'; return 2; }
  for line in "${numbers[@]}"; do ufw --force delete "$line" || return 1; done
}

kw_fw_port_interactive() {
  local verb=$1 port proto confirm
  if [[ $verb == open ]]; then
    kw_prompt_validated 'Cổng: ' kw_fw_port_allowed 'Cổng 1–65535; không mở trực tiếp 3306' plain || return 0
  else
    kw_prompt_validated 'Cổng: ' kw_port_valid 'Cổng 1–65535' plain || return 0
  fi
  port=$KW_PROMPT_VALUE
  kw_prompt_validated 'Giao thức tcp/udp: ' kw_fw_proto_valid 'Chỉ nhận tcp hoặc udp' plain || return 0
  proto=$KW_PROMPT_VALUE
  kw_fw_port_plan "$verb" "$port" "$proto" || return 2
  kw_prompt_yes_no_token "$([[ $verb == open ]] && printf Mở || printf Khóa) cổng $port/$proto?" \
    "$verb/$port/$proto" || return 0
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
