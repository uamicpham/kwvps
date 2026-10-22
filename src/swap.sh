#!/usr/bin/env bash
# A single KwVPS-owned swapfile. Existing system swap is never modified.
readonly KW_SWAP_DIR=/var/lib/kwvps
readonly KW_SWAP_FILE=/var/lib/kwvps/swapfile
readonly KW_SWAP_FSTAB_LINE='/var/lib/kwvps/swapfile none swap sw 0 0'

kw_swap_size_valid() {
  [[ ${1:-} =~ ^[1-9][0-9]{2,3}$ ]] || return 1
  ((10#$1 >= 128 && 10#$1 <= 8192))
}

kw_swap_ready() {
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để quản lý swap.'; return 2; }
  kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && \
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  [[ -f /etc/fstab && ! -L /etc/fstab && $(stat -c %u /etc/fstab) == 0 ]] || return 2
  local cmd
  for cmd in fallocate mkswap swapon swapoff flock df awk mktemp cp mv; do
    kw_has "$cmd" || { kw_log ERROR "Thiếu $cmd."; return 2; }
  done
}

kw_swap_fstab_count() {
  awk -v wanted="$KW_SWAP_FSTAB_LINE" '$0 == wanted {count++} END {print count+0}' /etc/fstab
}

kw_swap_fstab_path_count() {
  awk -v wanted="$KW_SWAP_FILE" '$1 == wanted {count++} END {print count+0}' /etc/fstab
}

kw_swap_owned_file() {
  [[ -d $KW_SWAP_DIR && ! -L $KW_SWAP_DIR && \
     $(stat -c %u "$KW_SWAP_DIR") == 0 && $(stat -c %a "$KW_SWAP_DIR") == 700 && \
     -f $KW_SWAP_FILE && ! -L $KW_SWAP_FILE && \
     $(stat -c %u "$KW_SWAP_FILE") == 0 && $(stat -c %a "$KW_SWAP_FILE") == 600 ]]
}

kw_swap_active_owned() {
  local names
  names=$(swapon --noheadings --show=NAME) || return 2
  [[ $'\n'"$names"$'\n' == *$'\n'"$KW_SWAP_FILE"$'\n'* ]]
}

kw_swap_plan() {
  local verb=$1 size=${2:-} available check_path=$KW_SWAP_DIR
  [[ $verb == add || $verb == remove ]] || return 2
  if [[ $verb == add ]]; then
    kw_swap_size_valid "$size" || return 2
    [[ -d $check_path ]] || check_path=/var/lib
    available=$(df -Pm -- "$check_path" 2>/dev/null | awk 'NR == 2 {print $4}') || available=''
    printf 'Kế hoạch thêm swapfile KwVPS %s MB tại %s.\n' "$size" "$KW_SWAP_FILE"
    printf 'Dung lượng trống tại %s: %s MB (cần thêm ít nhất 512 MB dự phòng).\n' "$KW_SWAP_DIR" "${available:-chưa xác định}"
  else
    printf 'Kế hoạch gỡ đúng swapfile KwVPS tại %s; không đụng swap khác.\n' "$KW_SWAP_FILE"
  fi
  printf 'Thay đổi /etc/fstab sau khi kiểm tra; giữ bản fstab trước thay đổi trong /var/backups/kwvps.\n'
}

kw_swap_fstab_backup() {
  local timestamp target
  kw_backup_dir_safe /var/backups 0022 || return 2
  if [[ ! -e $KW_BACKUP_ROOT && ! -L $KW_BACKUP_ROOT ]]; then
    install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT" || return 1
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  timestamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
  target="$KW_BACKUP_ROOT/fstab-before-swap-$timestamp-$$"
  [[ ! -e $target && ! -L $target ]] || return 2
  cp -p -- /etc/fstab "$target" || return 1
  chmod 0600 -- "$target" || return 1
  printf 'Bản fstab trước thay đổi: %s\n' "$target"
}

kw_swap_add_locked() (
  local size=$1 free_mb temp='' created=0 active=0 committed=0
  kw_swap_ready || return 2
  [[ ! -e $KW_SWAP_FILE && ! -L $KW_SWAP_FILE ]] || return 2
  [[ $(kw_swap_fstab_path_count) == 0 ]] || return 2
  if [[ ! -e $KW_SWAP_DIR && ! -L $KW_SWAP_DIR ]]; then
    install -d -m 0700 -o root -g root -- "$KW_SWAP_DIR" || return 1
  fi
  [[ -d $KW_SWAP_DIR && ! -L $KW_SWAP_DIR && $(stat -c %u "$KW_SWAP_DIR") == 0 && \
     $(stat -c %a "$KW_SWAP_DIR") == 700 ]] || return 2
  free_mb=$(df -Pm -- "$KW_SWAP_DIR" | awk 'NR == 2 {print $4}') || return 2
  if [[ ! $free_mb =~ ^[0-9]+$ ]] || ((free_mb < size + 512)); then
    kw_log ERROR 'Không đủ dung lượng trống và dự phòng 512 MB.'; return 2;
  fi
  trap 'if ((committed == 0)); then ((active == 0)) || swapoff -- "$KW_SWAP_FILE" || true; ((created == 0)) || rm -f -- "$KW_SWAP_FILE"; fi; [[ -z $temp ]] || rm -f -- "$temp"' EXIT
  (set -C; umask 077; : > "$KW_SWAP_FILE") || return 1
  # shellcheck disable=SC2034 # Read by the EXIT trap.
  created=1
  fallocate -l "${size}M" -- "$KW_SWAP_FILE" || return 1
  chmod 0600 -- "$KW_SWAP_FILE" || return 1
  mkswap -- "$KW_SWAP_FILE" >/dev/null || return 1
  swapon -- "$KW_SWAP_FILE" || return 1
  # shellcheck disable=SC2034 # Read by the EXIT trap.
  active=1
  temp=$(mktemp /etc/.kwvps-fstab.XXXXXXXX) || return 1
  cp -p -- /etc/fstab "$temp" || return 1
  printf '\n%s\n' "$KW_SWAP_FSTAB_LINE" >> "$temp" || return 1
  kw_swap_fstab_backup || return 1
  mv -T -- "$temp" /etc/fstab || return 1
  temp=''
  # shellcheck disable=SC2034 # Read by the EXIT trap.
  committed=1
  printf 'Đã thêm swapfile %s MB.\n' "$size"
)

kw_swap_remove_locked() (
  local temp='' disabled=0 committed=0
  kw_swap_ready || return 2
  kw_swap_owned_file || { kw_log ERROR 'Không thấy swapfile KwVPS đúng quyền/đường dẫn.'; return 2; }
  [[ $(kw_swap_fstab_count) == 1 && $(kw_swap_fstab_path_count) == 1 ]] || return 2
  kw_swap_active_owned || { kw_log ERROR 'Swapfile KwVPS không active; cần kiểm tra thủ công.'; return 2; }
  trap 'if ((disabled == 1 && committed == 0)); then swapon -- "$KW_SWAP_FILE" || true; fi; [[ -z $temp ]] || rm -f -- "$temp"' EXIT
  temp=$(mktemp /etc/.kwvps-fstab.XXXXXXXX) || return 1
  cp -p -- /etc/fstab "$temp" || return 1
  awk -v unwanted="$KW_SWAP_FSTAB_LINE" '$0 != unwanted {print}' /etc/fstab > "$temp" || return 1
  kw_swap_fstab_backup || return 1
  swapoff -- "$KW_SWAP_FILE" || return 1
  # shellcheck disable=SC2034 # Read by the EXIT trap.
  disabled=1
  mv -T -- "$temp" /etc/fstab || return 1
  temp=''
  # shellcheck disable=SC2034 # Read by the EXIT trap.
  committed=1
  rm -f -- "$KW_SWAP_FILE" || { kw_log WARN 'fstab đã gỡ nhưng swapfile vẫn còn; cần kiểm tra.'; return 1; }
  printf 'Đã gỡ swapfile KwVPS; swap khác không thay đổi.\n'
)

kw_swap_change() (
  local verb=$1 size=${2:-} confirm=${3:-}
  kw_swap_plan "$verb" "$size" || return 2
  if [[ $verb == add ]]; then
    [[ $confirm == "ADD-SWAP-${size}" ]] || return 2
  else
    [[ $confirm == REMOVE-KWVPS-SWAP ]] || return 2
  fi
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-swap.lock || return 2
  flock -n 9 || return 1
  if [[ $verb == add ]]; then kw_swap_add_locked "$size"; else kw_swap_remove_locked; fi
)

kw_swap_change_interactive() {
  local verb=$1 size='' confirm
  if [[ $verb == add ]]; then
    kw_prompt_validated 'Dung lượng swapfile (MB, 128-8192): ' \
      kw_swap_size_valid 'Chỉ nhận số nguyên từ 128 đến 8192' plain || return 0
    size=$KW_PROMPT_VALUE
  fi
  kw_swap_plan "$verb" "$size" || return 2
  if [[ $verb == add ]]; then
    kw_prompt_yes_no_token "Thêm swapfile $size MB?" "ADD-SWAP-$size" || return 0
  else
    kw_prompt_validated 'Nhập REMOVE-KWVPS-SWAP để xác nhận: ' kw_value_equals \
      'Giá trị xác nhận không khớp' plain REMOVE-KWVPS-SWAP || return 0
  fi
  confirm=$KW_PROMPT_VALUE
  kw_swap_change "$verb" "$size" "$confirm"
}
