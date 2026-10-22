#!/usr/bin/env bash
# Read-only diagnostics. os-release is parsed as data, never executed.
kw_os_release_path() {
  if [[ -r /etc/os-release ]]; then
    printf '%s\n' /etc/os-release
  elif [[ -r /usr/lib/os-release ]]; then
    printf '%s\n' /usr/lib/os-release
  else
    return 1
  fi
}

kw_os_field() {
  local key=$1 file line value
  [[ $key =~ ^[A-Z][A-Z0-9_]*$ ]] || return 2
  if (($# >= 2)); then
    file=$2
  else
    file=$(kw_os_release_path) || return 1
  fi
  [[ -r $file ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == "$key="* ]] || continue
    value=${line#*=}
    if [[ $value == \"*\" || $value == \'*\' ]]; then
      value=${value:1:${#value}-2}
    fi
    printf '%s\n' "$value"
    return 0
  done < "$file"
  return 1
}

kw_os_supported() {
  local file=${1:-} id version
  if [[ -n $file ]]; then
    id=$(kw_os_field ID "$file") || return 1
    version=$(kw_os_field VERSION_ID "$file") || return 1
  else
    id=$(kw_os_field ID) || return 1
    version=$(kw_os_field VERSION_ID) || return 1
  fi
  [[ $id == ubuntu && $version == 24.04 ]]
}

kw_os_show() {
  local name id version
  name=$(kw_os_field PRETTY_NAME) || name='Không xác định'
  id=$(kw_os_field ID) || id='unknown'
  version=$(kw_os_field VERSION_ID) || version='unknown'
  printf 'Hệ điều hành: %s\nKiến trúc: %s\n' "$name" "$(uname -m)"
  printf 'Định danh: %s %s\n' "$id" "$version"
}

kw_memory() {
  local file=${1:-/proc/meminfo}
  if [[ ! -r $file ]]; then printf 'N/A | Swap: N/A'; return 0; fi
  awk '
    $1 == "MemTotal:" && $2 ~ /^[0-9]+$/ { total=$2; have_total=1 }
    $1 == "MemAvailable:" && $2 ~ /^[0-9]+$/ { available=$2; have_available=1 }
    $1 == "SwapTotal:" && $2 ~ /^[0-9]+$/ { swap=$2; have_swap=1 }
    $1 == "SwapFree:" && $2 ~ /^[0-9]+$/ { free=$2; have_free=1 }
    END {
      if (!have_total || !have_available || total <= 0 || available > total) printf "N/A";
      else printf "%d/%d MB", (total-available)/1024, total/1024;
      if (!have_swap || !have_free || free > swap) printf " | Swap: N/A";
      else printf " | Swap: %d/%d MB", (swap-free)/1024, swap/1024;
    }' "$file"
}

kw_disk_usage() {
  local path=${1:-/} data
  [[ $path == /* && -e $path ]] || return 2
  data=$(kw_read_command df -Pk -- "$path") || return 1
  LC_ALL=C awk '
    NR == 2 && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $2 > 0 {
      printf "%.1f/%.1f GB", $3/1048576, $2/1048576;
      found=1
    }
    END { if (!found) exit 1 }
  ' <<< "$data"
}

kw_header() {
  local disk='N/A' path='/'
  printf '\nKwVPS %s\n' "$KW_VERSION"
  if ((KW_PREVIEW)); then
    printf 'CHẾ ĐỘ XEM MENU — không đo VPS hoặc chạy chức năng quản trị.\n'
    return 0
  fi
  if kw_has df && kw_has awk; then
    disk=$(kw_disk_usage "$path") || disk='N/A'
  fi
  printf 'Disk: %s | Ram: %s | Ngay: %s\n' "$disk" "$(kw_memory /proc/meminfo)" "$(date +%F)"
  printf 'Disk của filesystem gốc (/); GB/MB tính theo hệ 1024.\n'
  printf 'Thao tác thay đổi VPS cần quyền root và xác nhận.\n'
}

kw_doctor() {
  local id version cmd failed=0
  kw_os_show
  id=$(kw_os_field ID) || id='unknown'
  version=$(kw_os_field VERSION_ID) || version='unknown'
  if kw_os_supported ''; then
    printf '[OK] Đúng hệ điều hành mục tiêu Ubuntu 24.04.\n'
  else
    printf '[WARN] Hệ điều hành %s %s chưa thuộc phạm vi Ubuntu 24.04 đã chọn.\n' "$id" "$version"
    failed=1
  fi
  for cmd in awk df timeout dpkg-query apt systemctl ss uname date; do
    if kw_has "$cmd"; then printf '[OK] %s\n' "$cmd";
    else printf '[MISSING] %s\n' "$cmd"; failed=1; fi
  done
  if [[ ! -d /run/systemd/system ]]; then
    printf '[WARN] systemd chưa chạy hoặc môi trường không phải VPS đầy đủ.\n'
    failed=1
  fi
  printf 'Không cài gói, sửa cấu hình hoặc kiểm tra kết nối mạng.\n'
  return "$failed"
}

kw_service_package() {
  [[ $1 =~ ^(nginx([:-].*)?|php[0-9]+\.[0-9]+-fpm(:.*)?|mariadb-server([:-].*)?|redis-server(:.*)?|fail2ban(:.*)?|ufw(:.*)?|cloudflared(:.*)?)$ ]]
}

kw_service_unit() {
  case "$1" in
    nginx|mariadb|redis-server|fail2ban|cloudflared) return 0 ;;
  esac
  [[ $1 =~ ^php[0-9]+\.[0-9]+-fpm$ ]]
}

kw_service_status() {
  local unit=$1
  if ! kw_service_unit "$unit"; then
    kw_log ERROR 'Tên service không nằm trong danh sách cho phép.'
    return 2
  fi
  kw_read_command systemctl show --no-pager \
    --property=LoadState,ActiveState,SubState "$unit.service"
}

kw_packages() {
  local data package status version found=0
  # shellcheck disable=SC2016 # dpkg-query expands its own format variables.
  data=$(kw_read_command dpkg-query -W '-f=${binary:Package}\t${db:Status-Status}\t${Version}\n') || return 1
  printf '%-32s %s\n' 'PACKAGE ĐÃ CÀI' 'VERSION'
  while IFS=$'\t' read -r package status version; do
    if [[ $status == installed ]] && kw_service_package "$package"; then
      printf '%-32s %s\n' "$package" "$version"
      found=1
    fi
  done <<< "$data"
  ((found)) || printf 'Không tìm thấy package dịch vụ trong phạm vi KwVPS.\n'
  printf 'Chỉ inventory dpkg; binary cài thủ công và version tiến trình đang chạy chưa được kiểm chứng.\n'
}

kw_pending() {
  local data line package found=0
  printf 'Dựa trên cache apt hiện có; không chạy apt update và không cài gói.\n'
  data=$(LC_ALL=C kw_read_command apt list --upgradable) || return 1
  while IFS= read -r line; do
    package=${line%%/*}
    if kw_service_package "$package"; then printf '%s\n' "$line"; found=1; fi
  done <<< "$data"
  ((found)) || printf 'Không có package dịch vụ chờ cập nhật trong cache hiện tại (cache có thể cũ).\n'
}

kw_ports() {
  local failed=0
  printf 'Socket đang LISTEN (không đồng nghĩa mở từ Internet):\n'
  kw_read_command ss -lntu || failed=1
  printf '\nLuật UFW hiện tại (không gồm firewall nhà cung cấp):\n'
  kw_read_command ufw status verbose || failed=1
  return "$failed"
}

kw_swap() { kw_read_command swapon --show --bytes; }
kw_nginx_check() { kw_read_command nginx -t; }
kw_fail2ban() { kw_read_command fail2ban-client status; }
kw_cron() {
  printf 'Crontab của tài khoản đang chạy KwVPS; không phải toàn bộ cron hệ thống.\n'
  kw_read_command crontab -l
}

kw_journal() {
  local unit=$1
  case "$unit" in nginx|mariadb|cloudflared) ;;
    *) kw_log ERROR 'Unit không nằm trong danh sách cho phép.'; return 2 ;;
  esac
  printf '100 dòng gần nhất của %s; có thể chứa dữ liệu riêng, cần che trước chia sẻ.\n' "$unit"
  printf 'Đây là service journal, không thay thế access/error log theo domain.\n'
  kw_read_command journalctl --no-pager -n 100 -u "$unit.service"
}

# Clear only KwVPS-owned Nginx files. The systemd journal is a separate,
# explicitly selected, system-wide operation; active journal files remain.
kw_logs_web_scan() {
  local dir=/var/log/nginx file name size links
  KW_LOG_FILES=()
  KW_LOG_BYTES=0
  KW_LOG_NGINX_COUNT=0
  KW_LOG_PHP_COUNT=0
  KW_LOG_NGINX_BYTES=0
  KW_LOG_PHP_BYTES=0
  [[ -d $dir && ! -L $dir && $(stat -c %u -- "$dir") == 0 ]] || return 2
  [[ -d /var/log && ! -L /var/log && $(stat -c %u -- /var/log) == 0 ]] || return 2
  for file in "$dir"/kwvps-*.access.log* "$dir"/kwvps-*.error.log* /var/log/php[0-9]*-fpm.log*; do
    [[ -e $file || -L $file ]] || continue
    name=${file##*/}
    if [[ $file == "$dir"/* ]]; then
      [[ $name =~ ^kwvps-[a-z0-9]+\.(access|error)\.log(\.[0-9]+(\.gz)?)?$ ]] || continue
    else
      [[ $name =~ ^php(7\.4|8\.[345])-fpm\.log(\.[0-9]+(\.gz)?)?$ ]] || continue
    fi
    [[ -f $file && ! -L $file ]] || {
      kw_log ERROR "Log không phải file thường hoặc là symlink: $file"; return 2;
    }
    links=$(stat -c %h -- "$file") || return 2
    [[ $links == 1 ]] || { kw_log ERROR "Log có hard link, không dọn: $file"; return 2; }
    size=$(stat -c %s -- "$file") || return 2
    KW_LOG_FILES+=("$file")
    KW_LOG_BYTES=$((KW_LOG_BYTES + size))
    if [[ $file == "$dir"/* ]]; then
      KW_LOG_NGINX_COUNT=$((KW_LOG_NGINX_COUNT + 1))
      KW_LOG_NGINX_BYTES=$((KW_LOG_NGINX_BYTES + size))
    else
      KW_LOG_PHP_COUNT=$((KW_LOG_PHP_COUNT + 1))
      KW_LOG_PHP_BYTES=$((KW_LOG_PHP_BYTES + size))
    fi
  done
}

kw_logs_cleanup_plan() {
  local scope=${1:-}
  [[ $scope == web || $scope == journal || $scope == all ]] || return 2
  printf 'Kế hoạch dọn log:\n'
  if [[ $scope == web || $scope == all ]]; then
    kw_logs_web_scan || return 2
    printf '  /var/log/nginx: %d file site KwVPS, %d byte.\n' "$KW_LOG_NGINX_COUNT" "$KW_LOG_NGINX_BYTES"
    printf '  /var/log: %d file PHP-FPM, %d byte. File đang ghi sẽ được làm rỗng, bản xoay vòng sẽ bị xóa.\n' "$KW_LOG_PHP_COUNT" "$KW_LOG_PHP_BYTES"
    printf '  Không đụng access.log/error.log Nginx dùng chung, Fail2ban hoặc log website ngoài KwVPS.\n'
  fi
  if [[ $scope == journal || $scope == all ]]; then
    command -v journalctl >/dev/null 2>&1 || return 2
    printf '  systemd journal TOÀN VPS: xoay và dọn bản lưu cũ; ảnh hưởng log Nginx, PHP, MariaDB và mọi service khác.\n'
    printf '  Journal đang hoạt động vẫn được giữ; log mới sẽ tiếp tục ghi. Dung lượng hiện tại: '
    journalctl --disk-usage || return 2
  fi
  printf 'Không xóa thư mục, cấu hình, database hay dữ liệu website. Không thể phục hồi log đã dọn.\n'
}

kw_logs_cleanup_apply() (
  local scope=${1:-} confirm=${2:-} file name dir count=0 bytes=0
  [[ $scope == web || $scope == journal || $scope == all ]] &&
    [[ $confirm == "CLEAN-LOGS:$scope" ]] || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id &&
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  exec 9>/run/lock/kwvps-logs.lock || return 2
  flock -n 9 || { kw_log ERROR 'Một phiên dọn log khác đang chạy.'; return 1; }
  kw_logs_cleanup_plan "$scope" || return 2
  if [[ $scope == web || $scope == all ]]; then
    count=${#KW_LOG_FILES[@]}; bytes=$KW_LOG_BYTES
    for file in "${KW_LOG_FILES[@]}"; do
      name=${file##*/}
      if [[ $name =~ \.log$ ]]; then
        truncate -s 0 -- "$file" || return 1
      else
        rm -f -- "$file" || return 1
      fi
    done
    printf 'Đã dọn /var/log/nginx: %d file site KwVPS, %d byte trước khi dọn.\n' "$KW_LOG_NGINX_COUNT" "$KW_LOG_NGINX_BYTES"
    printf 'Đã dọn /var/log: %d file PHP-FPM, %d byte trước khi dọn.\n' "$KW_LOG_PHP_COUNT" "$KW_LOG_PHP_BYTES"
    printf 'Tổng: %d file, %d byte trước khi dọn.\n' "$count" "$bytes"
  fi
  if [[ $scope == journal || $scope == all ]]; then
    journalctl --rotate || return 1
    journalctl --vacuum-size=1M || return 1
    printf 'Đã dọn journal cũ trong các thư mục:\n'
    for dir in /var/log/journal /run/log/journal; do
      [[ ! -d $dir || -L $dir ]] || printf '  %s\n' "$dir"
    done
    printf 'Journal còn lại (bao gồm log đang hoạt động): '
    journalctl --disk-usage || return 1
  fi
  printf 'Các thư mục được xử lý đã liệt kê phía trên; bản thân thư mục không bị xóa.\n'
)

kw_logs_cleanup_interactive() {
  local choice scope
  printf '1. Dọn log site KwVPS và PHP-FPM\n2. Dọn journal cũ TOÀN VPS\n3. Cả hai\n0. Quay lại\nChọn: '
  IFS= read -r choice || return 0
  case "$choice" in
    1) scope=web ;;
    2) scope=journal ;;
    3) scope=all ;;
    *) return 0 ;;
  esac
  kw_logs_cleanup_plan "$scope" || return 2
  kw_prompt_yes_no_token "Dọn log theo phạm vi $scope?" "CLEAN-LOGS:$scope" || return 0
  kw_logs_cleanup_apply "$scope" "$KW_PROMPT_VALUE"
}

kw_tunnel_status() {
  kw_service_status cloudflared || return 1
  printf 'Trạng thái service không chứng minh hostname công khai hoạt động.\n'
}

kw_tunnel_restart() (
  local confirm=${1:-}
  [[ $confirm == RESTART-CLOUDFLARED ]] || return 2
  ((EUID == 0)) || { kw_log ERROR 'Cần root để restart Cloudflare Tunnel.'; return 2; }
  kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && \
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  kw_has cloudflared && kw_has systemctl && kw_has flock || return 2
  systemctl cat cloudflared.service >/dev/null 2>&1 || {
    kw_log ERROR 'Không tìm thấy service cloudflared.'; return 2;
  }
  systemctl is-active --quiet cloudflared.service || {
    kw_log ERROR 'Tunnel chưa active; cần kiểm tra cấu hình trước khi restart.'; return 2;
  }
  exec 9>/run/lock/kwvps-tunnel.lock || return 2
  flock -n 9 || return 1
  systemctl restart cloudflared.service || return 1
  systemctl is-active --quiet cloudflared.service || {
    kw_log ERROR 'Tunnel không active sau restart; xem journal Cloudflared.'; return 1;
  }
  printf 'Cloudflared đã restart và service active. Kiểm tra hostname công khai riêng.\n'
)

kw_tunnel_restart_interactive() {
  printf 'Restart Cloudflared có thể ngắt truy cập qua Tunnel trong thời gian ngắn.\n'
  kw_prompt_yes_no_token 'Restart Cloudflared?' RESTART-CLOUDFLARED || return 0
  kw_tunnel_restart "$KW_PROMPT_VALUE"
}
