#!/usr/bin/env bash
# Conservative SSH account/key operations; daemon changes are separate.

kw_ssh_limits_target=/etc/ssh/sshd_config.d/70-kwvps-limits.conf

kw_ssh_limit_auth_valid() { [[ ${1:-} =~ ^[0-9]+$ ]] && ((10#$1 >= 2 && 10#$1 <= 10)); }
kw_ssh_limit_sessions_valid() { [[ ${1:-} =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 20)); }
kw_ssh_limit_grace_valid() { [[ ${1:-} =~ ^[0-9]+$ ]] && ((10#$1 >= 30 && 10#$1 <= 120)); }

kw_ssh_limits_current() {
  local effective
  effective=$(sshd -T) || return 1
  printf 'Giới hạn SSH hiện tại:\n'
  printf '%s\n' "$effective" | grep -e '^maxauthtries ' -e '^maxsessions ' -e '^logingracetime ' || return 1
  printf 'Không thay đổi port, PasswordAuthentication hoặc PubkeyAuthentication.\n'
}

kw_ssh_limits_rollback() {
  ((KW_SSH_LIMIT_DONE == 0)) || return 0
  if [[ -n $KW_SSH_LIMIT_OLD && -f $KW_SSH_LIMIT_OLD ]]; then
    cp -a -- "$KW_SSH_LIMIT_OLD" "$kw_ssh_limits_target" || kw_log ERROR 'Không khôi phục được file giới hạn SSH.'
  elif ((KW_SSH_LIMIT_REPLACED)); then
    rm -f -- "$kw_ssh_limits_target" || kw_log ERROR 'Không gỡ được file giới hạn SSH mới.'
  fi
  if sshd -t; then
    systemctl reload ssh || kw_log ERROR 'Cần kiểm tra SSH sau hoàn tác.'
  else
    kw_log ERROR 'Cấu hình SSH vẫn lỗi sau hoàn tác; dùng console cứu hộ.'
  fi
}

kw_ssh_limits_apply() (
  local auth=${1:-} sessions=${2:-} grace=${3:-} confirm=${4:-} stage='' backup='' effective first_line
  local KW_SSH_LIMIT_DONE=0 KW_SSH_LIMIT_REPLACED=0 KW_SSH_LIMIT_OLD=''
  [[ $confirm == APPLY-SSH-LIMITS ]] || return 2
  kw_ssh_limit_auth_valid "$auth" && kw_ssh_limit_sessions_valid "$sessions" && kw_ssh_limit_grace_valid "$grace" || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  for cmd in sshd systemctl flock mktemp; do kw_has "$cmd" || return 2; done
  [[ -d /etc/ssh/sshd_config.d && ! -L /etc/ssh/sshd_config.d &&
     $(stat -c %u -- /etc/ssh/sshd_config.d) == 0 ]] || return 2
  [[ ! -L $kw_ssh_limits_target ]] || return 2
  sshd -t && systemctl is-active --quiet ssh || return 2
  exec 9>/run/lock/kwvps-ssh-config.lock || return 2
  flock -n 9 || return 1
  if [[ -e $kw_ssh_limits_target ]]; then
    [[ -f $kw_ssh_limits_target && $(stat -c %u -- "$kw_ssh_limits_target") == 0 ]] || return 2
    IFS= read -r first_line < "$kw_ssh_limits_target" || return 2
    [[ $first_line == '# KwVPS SSH login limits' ]] || return 2
    kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
    backup="$KW_BACKUP_ROOT/ssh-limits-$(date -u +%Y%m%dT%H%M%SZ)-${BASHPID}.conf"
    [[ ! -e $backup && ! -L $backup ]] || return 2
    cp -a -- "$kw_ssh_limits_target" "$backup" || return 1
    KW_SSH_LIMIT_OLD=$backup
  fi
  stage=$(mktemp /etc/ssh/sshd_config.d/.kwvps-limits.XXXXXXXX) || return 1
  trap 'rm -f -- "$stage"; kw_ssh_limits_rollback' EXIT
  printf '# KwVPS SSH login limits\nMaxAuthTries %s\nMaxSessions %s\nLoginGraceTime %s\n' \
    "$auth" "$sessions" "$grace" > "$stage" || return 1
  chmod 0644 -- "$stage" || return 1
  mv -T -- "$stage" "$kw_ssh_limits_target" || return 1
  KW_SSH_LIMIT_REPLACED=1
  sshd -t || return 1
  effective=$(sshd -T) || return 1
  grep -Fxq "maxauthtries $((10#$auth))" <<< "$effective" || return 1
  grep -Fxq "maxsessions $((10#$sessions))" <<< "$effective" || return 1
  grep -Fxq "logingracetime $((10#$grace))" <<< "$effective" || return 1
  systemctl reload ssh || return 1
  systemctl is-active --quiet ssh || return 1
  KW_SSH_LIMIT_DONE=1
  printf 'Đã áp giới hạn SSH: MaxAuthTries=%s, MaxSessions=%s, LoginGraceTime=%ss.\n' "$auth" "$sessions" "$grace"
)

kw_ssh_limits_interactive() {
  local auth sessions grace
  kw_ssh_limits_current || return 1
  printf 'MaxAuthTries: số lần xác thực sai mỗi kết nối (2–10).\n'
  kw_prompt_validated 'MaxAuthTries: ' kw_ssh_limit_auth_valid 'Nhập 2–10' plain || return 0
  auth=$KW_PROMPT_VALUE
  kw_prompt_validated 'MaxSessions: số phiên mỗi kết nối (1–20): ' kw_ssh_limit_sessions_valid 'Nhập 1–20' plain || return 0
  sessions=$KW_PROMPT_VALUE
  kw_prompt_validated 'LoginGraceTime giây (30–120): ' kw_ssh_limit_grace_valid 'Nhập 30–120' plain || return 0
  grace=$KW_PROMPT_VALUE
  printf 'Sẽ áp MaxAuthTries=%s, MaxSessions=%s, LoginGraceTime=%ss; không đổi port hoặc phương thức đăng nhập.\n' "$auth" "$sessions" "$grace"
  kw_prompt_yes_no_token 'Áp giới hạn SSH?' APPLY-SSH-LIMITS || return 0
  kw_ssh_limits_apply "$auth" "$sessions" "$grace" "$KW_PROMPT_VALUE"
}

kw_ssh_account_paths() {
  local account=$1 entry name uid gid home
  case "$account" in root|ubuntu) ;; *) return 2 ;; esac
  entry=$(getent passwd "$account") || return 2
  IFS=: read -r name _ uid gid _ home _ <<< "$entry"
  [[ $name == "$account" && $uid =~ ^[0-9]+$ && $gid =~ ^[0-9]+$ ]] || return 2
  if [[ $account == root ]]; then [[ $home == /root ]]; else [[ $home == /home/ubuntu ]]; fi || return 2
  [[ -d $home && ! -L $home ]] || return 2
  KW_SSH_UID=$uid KW_SSH_GID=$gid
  KW_SSH_DIR="$home/.ssh" KW_SSH_KEYS="$home/.ssh/authorized_keys"
}

kw_ssh_key_valid() {
  local key=${1:-}
  [[ ${#key} -le 1024 && $key =~ ^ssh-ed25519[[:space:]][A-Za-z0-9+/=]+([[:space:]][A-Za-z0-9._@-]+)?$ ]] || return 1
  ssh-keygen -lf <(printf '%s\n' "$key") >/dev/null 2>&1
}

kw_ssh_keys_preflight() {
  local account=$1 owner mode
  kw_ssh_account_paths "$account" || return 2
  if [[ -e $KW_SSH_DIR || -L $KW_SSH_DIR ]]; then
    [[ -d $KW_SSH_DIR && ! -L $KW_SSH_DIR ]] || return 2
    owner=$(stat -c %u -- "$KW_SSH_DIR") || return 2
    mode=$(stat -c %a -- "$KW_SSH_DIR") || return 2
    [[ $owner == "$KW_SSH_UID" && $mode == 700 ]] || return 2
  fi
  if [[ -e $KW_SSH_KEYS || -L $KW_SSH_KEYS ]]; then
    [[ -f $KW_SSH_KEYS && ! -L $KW_SSH_KEYS ]] || return 2
    owner=$(stat -c %u -- "$KW_SSH_KEYS") || return 2
    mode=$(stat -c %a -- "$KW_SSH_KEYS") || return 2
    [[ $owner == "$KW_SSH_UID" && $mode == 600 ]] || return 2
  fi
}

kw_ssh_key_fingerprint() {
  local key=$1 info
  info=$(ssh-keygen -lf <(printf '%s\n' "$key") 2>/dev/null) || return 2
  [[ $info =~ SHA256:[A-Za-z0-9+/=]+ ]] || return 2
  printf '%s' "${BASH_REMATCH[0]}"
}

kw_ssh_keys_collect() {
  local account=$1 line
  KW_SSH_KEY_LINES=() KW_SSH_KEY_FINGERPRINTS=()
  kw_ssh_keys_preflight "$account" || return 2
  [[ -f $KW_SSH_KEYS ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -n $line && $line != \#* ]] || continue
    kw_ssh_key_valid "$line" || { kw_log ERROR 'authorized_keys có dòng không thuộc dạng ed25519 thuần; không tự sửa.'; return 2; }
    KW_SSH_KEY_LINES+=("$line")
    KW_SSH_KEY_FINGERPRINTS+=("$(kw_ssh_key_fingerprint "$line")")
  done < "$KW_SSH_KEYS"
}

kw_ssh_keys_list() {
  local account=$1 index
  kw_ssh_keys_collect "$account" || return 2
  printf 'Public key của %s:\n' "$account"
  for index in "${!KW_SSH_KEY_LINES[@]}"; do
    printf '%d. %s\n' "$((index+1))" "${KW_SSH_KEY_FINGERPRINTS[index]}"
  done
  ((${#KW_SSH_KEY_LINES[@]})) || printf 'Chưa có khóa ed25519.\n'
}

kw_ssh_key_add() (
  local account=$1 key=$2 confirm=${3:-} stage=''
  [[ $confirm == ADD-SSH-KEY ]] && kw_ssh_key_valid "$key" || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  exec 9>/run/lock/kwvps-ssh-keys.lock || return 2
  flock -n 9 || return 1
  kw_ssh_keys_preflight "$account" || return 2
  if [[ ! -d $KW_SSH_DIR ]]; then
    install -d -m 0700 -o "$KW_SSH_UID" -g "$KW_SSH_GID" -- "$KW_SSH_DIR" || return 1
  fi
  if [[ -f $KW_SSH_KEYS ]] && grep -Fxq -- "$key" "$KW_SSH_KEYS"; then
    kw_log ERROR 'Khóa đã tồn tại.'; return 2
  fi
  stage=$(mktemp "$KW_SSH_DIR/.authorized_keys.XXXXXXXX") || return 1
  trap 'rm -f -- "$stage"' EXIT
  if [[ -f $KW_SSH_KEYS ]]; then cp -- "$KW_SSH_KEYS" "$stage" || return 1; fi
  if [[ -s $stage && -n $(tail -c 1 -- "$stage") ]]; then
    printf '\n' >> "$stage" || return 1
  fi
  printf '%s\n' "$key" >> "$stage" || return 1
  chown "$KW_SSH_UID:$KW_SSH_GID" -- "$stage" || return 1
  chmod 0600 -- "$stage" || return 1
  mv -T -- "$stage" "$KW_SSH_KEYS" || return 1
  printf 'Đã thêm public key %s cho %s. Thử đăng nhập phiên SSH mới trước khi thay đổi xác thực.\n' \
    "$(kw_ssh_key_fingerprint "$key")" "$account"
)

kw_ssh_key_remove() (
  local account=$1 index=$2 fingerprint=${3:-} line stage='' cursor=0 removed=0
  [[ $index =~ ^[1-9][0-9]*$ && $fingerprint =~ ^SHA256:[A-Za-z0-9+/=]+$ ]] || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  exec 9>/run/lock/kwvps-ssh-keys.lock || return 2
  flock -n 9 || return 1
  kw_ssh_keys_collect "$account" || return 2
  ((index <= ${#KW_SSH_KEY_LINES[@]} && ${#KW_SSH_KEY_LINES[@]} > 1)) || {
    kw_log ERROR 'Không xóa khóa cuối cùng của tài khoản.'; return 2;
  }
  [[ ${KW_SSH_KEY_FINGERPRINTS[index-1]} == "$fingerprint" ]] || return 2
  stage=$(mktemp "$KW_SSH_DIR/.authorized_keys.XXXXXXXX") || return 1
  trap 'rm -f -- "$stage"' EXIT
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ -n $line && $line != \#* ]]; then
      cursor=$((cursor+1))
      if ((cursor == index)); then removed=1; continue; fi
    fi
    printf '%s\n' "$line" >> "$stage" || return 1
  done < "$KW_SSH_KEYS"
  ((removed)) || return 2
  chown "$KW_SSH_UID:$KW_SSH_GID" -- "$stage" || return 1
  chmod 0600 -- "$stage" || return 1
  mv -T -- "$stage" "$KW_SSH_KEYS" || return 1
  printf 'Đã xóa public key %s của %s.\n' "$fingerprint" "$account"
)

kw_ssh_choose_account() {
  local choice
  printf '1. root\n'
  getent passwd ubuntu >/dev/null && printf '2. ubuntu\n'
  printf '0. Quay lại\nChọn tài khoản SSH: '
  IFS= read -r choice || return 1
  case "$choice" in
    1) KW_SSH_CHOICE=root ;;
    2) getent passwd ubuntu >/dev/null || return 1; KW_SSH_CHOICE=ubuntu ;;
    *) return 1 ;;
  esac
}

kw_ssh_keys_interactive() {
  local account choice key index fingerprint
  kw_ssh_choose_account || return 0
  account=$KW_SSH_CHOICE
  kw_ssh_keys_list "$account" || return 2
  printf '1. Thêm public key ed25519\n2. Xóa public key theo số\n0. Quay lại\nChọn: '
  IFS= read -r choice || return 0
  case "$choice" in
    1)
      kw_prompt_validated 'Dán public key (một dòng): ' kw_ssh_key_valid 'Khóa ed25519 không hợp lệ' plain || return 0
      key=$KW_PROMPT_VALUE
      kw_prompt_yes_no_token "Thêm khóa $(kw_ssh_key_fingerprint "$key") cho $account?" ADD-SSH-KEY || return 0
      kw_ssh_key_add "$account" "$key" "$KW_PROMPT_VALUE" ;;
    2)
      kw_ssh_keys_collect "$account" || return 2
      ((${#KW_SSH_KEY_LINES[@]} > 1)) || { printf 'Cần giữ ít nhất một khóa.\n'; return 0; }
      printf 'Chọn số khóa cần xóa (0 quay lại): '
      IFS= read -r index || return 0
      [[ $index =~ ^[1-9][0-9]*$ ]] && ((index <= ${#KW_SSH_KEY_LINES[@]})) || return 0
      fingerprint=${KW_SSH_KEY_FINGERPRINTS[index-1]}
      kw_prompt_confirm_token "$fingerprint" "Nhập lại fingerprint $fingerprint để XÓA: " || return 0
      kw_ssh_key_remove "$account" "$index" "$fingerprint" ;;
    *) return 0 ;;
  esac
}

kw_ssh_password_interactive() {
  local account
  kw_ssh_choose_account || return 0
  account=$KW_SSH_CHOICE
  ((EUID == 0)) || { kw_log ERROR 'Cần root để đổi mật khẩu.'; return 2; }
  kw_prompt_yes_no_token "Chạy passwd cho $account? Mật khẩu sẽ do công cụ hệ thống hỏi trực tiếp." CHANGE-SSH-PASSWORD || return 0
  [[ $KW_PROMPT_VALUE == CHANGE-SSH-PASSWORD ]] || return 2
  passwd -- "$account"
}

kw_ssh_key_only_target=/etc/ssh/sshd_config.d/00-kwvps-key-only.conf

kw_ssh_key_only_status() {
  local effective
  effective=$(sshd -T) || return 1
  printf 'Xác thực SSH hiệu lực:\n'
  printf '%s\n' "$effective" | grep -e '^pubkeyauthentication ' -e '^passwordauthentication ' \
    -e '^kbdinteractiveauthentication ' -e '^authenticationmethods ' || return 1
  if [[ -f $kw_ssh_key_only_target && ! -L $kw_ssh_key_only_target ]]; then
    printf 'KwVPS đang quản lý cấu hình chỉ AuthKey.\n'
  else
    printf 'KwVPS chưa bật chế độ chỉ AuthKey.\n'
  fi
}

kw_ssh_key_only_rollback() {
  ((KW_SSH_AUTH_DONE == 0)) || return 0
  if [[ -n $KW_SSH_AUTH_OLD && -f $KW_SSH_AUTH_OLD ]]; then
    cp -a -- "$KW_SSH_AUTH_OLD" "$kw_ssh_key_only_target" || kw_log ERROR 'Không khôi phục được cấu hình AuthKey cũ.'
  elif ((KW_SSH_AUTH_CHANGED)); then
    rm -f -- "$kw_ssh_key_only_target" || kw_log ERROR 'Không gỡ được cấu hình AuthKey mới.'
  fi
  if sshd -t; then
    systemctl reload ssh || kw_log ERROR 'Cần kiểm tra SSH sau hoàn tác AuthKey.'
  else
    kw_log ERROR 'SSH vẫn lỗi sau hoàn tác AuthKey; dùng console cứu hộ.'
  fi
}

kw_ssh_key_only_apply() (
  local mode=${1:-} confirm=${2:-} stage='' old='' effective marker
  local KW_SSH_AUTH_DONE=0 KW_SSH_AUTH_CHANGED=0 KW_SSH_AUTH_OLD=''
  [[ $mode == enable || $mode == disable ]] || return 2
  [[ $confirm == "${mode}:SSH-KEY-ONLY" ]] || return 2
  ((EUID == 0)) && kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  for cmd in sshd systemctl flock mktemp; do kw_has "$cmd" || return 2; done
  [[ -d /etc/ssh/sshd_config.d && ! -L /etc/ssh/sshd_config.d &&
     $(stat -c %u -- /etc/ssh/sshd_config.d) == 0 ]] || return 2
  sshd -t && systemctl is-active --quiet ssh || return 2
  exec 9>/run/lock/kwvps-ssh-config.lock || return 2
  flock -n 9 || return 1
  if [[ -e $kw_ssh_key_only_target || -L $kw_ssh_key_only_target ]]; then
    [[ -f $kw_ssh_key_only_target && ! -L $kw_ssh_key_only_target &&
       $(stat -c %u:%a -- "$kw_ssh_key_only_target") == 0:644 ]] || return 2
    IFS= read -r marker < "$kw_ssh_key_only_target" || return 2
    [[ $marker == '# KwVPS SSH key-only authentication' ]] || return 2
  elif [[ $mode == disable ]]; then
    printf 'KwVPS chưa bật chế độ chỉ AuthKey.\n'
    return 0
  fi
  if [[ $mode == enable ]]; then
    [[ ! -e $kw_ssh_key_only_target ]] || { printf 'Chế độ chỉ AuthKey đã bật.\n'; return 0; }
    # Require a working root public-key path before changing authentication globally.
    kw_ssh_keys_collect root || return 2
    ((${#KW_SSH_KEY_LINES[@]} >= 1)) || {
      kw_log ERROR 'root chưa có public key ed25519; từ chối tắt đăng nhập mật khẩu.'
      return 2
    }
    effective=$(sshd -T) || return 2
    grep -Fxq 'pubkeyauthentication yes' <<< "$effective" || return 2
    stage=$(mktemp /etc/ssh/sshd_config.d/.kwvps-auth.XXXXXXXX) || return 1
    trap 'rm -f -- "$stage"; kw_ssh_key_only_rollback' EXIT
    printf '# KwVPS SSH key-only authentication\nPubkeyAuthentication yes\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nAuthenticationMethods publickey\n' > "$stage" || return 1
    chmod 0644 -- "$stage" || return 1
    mv -T -- "$stage" "$kw_ssh_key_only_target" || return 1
    KW_SSH_AUTH_CHANGED=1
    sshd -t || return 1
    effective=$(sshd -T) || return 1
    grep -Fxq 'pubkeyauthentication yes' <<< "$effective" || return 1
    grep -Fxq 'passwordauthentication no' <<< "$effective" || return 1
    grep -Fxq 'kbdinteractiveauthentication no' <<< "$effective" || return 1
    grep -Fxq 'authenticationmethods publickey' <<< "$effective" || return 1
    systemctl reload ssh || return 1
    systemctl is-active --quiet ssh || return 1
    KW_SSH_AUTH_DONE=1
    printf 'Đã bật chỉ AuthKey. Hãy thử một phiên SSH MỚI bằng key trước khi đóng phiên hiện tại.\n'
  else
    old=$(mktemp /run/kwvps-ssh-auth-old.XXXXXXXX) || return 1
    trap 'rm -f -- "$old"; kw_ssh_key_only_rollback' EXIT
    cp -a -- "$kw_ssh_key_only_target" "$old" || return 1
    KW_SSH_AUTH_OLD=$old
    rm -f -- "$kw_ssh_key_only_target" || return 1
    KW_SSH_AUTH_CHANGED=1
    sshd -t || return 1
    systemctl reload ssh || return 1
    systemctl is-active --quiet ssh || return 1
    KW_SSH_AUTH_DONE=1
    printf 'Đã tắt chế độ chỉ AuthKey do KwVPS quản lý. Chính sách mặc định của VPS được áp lại.\n'
  fi
)

kw_ssh_key_only_interactive() {
  local choice mode
  kw_ssh_key_only_status || return 1
  printf '1. Bật chỉ AuthKey\n2. Tắt và trở về chính sách SSH trước đó\n0. Quay lại\nChọn: '
  IFS= read -r choice || return 0
  case "$choice" in 1) mode=enable ;; 2) mode=disable ;; *) return 0 ;; esac
  printf 'CẢNH BÁO: Có thể mất đăng nhập mật khẩu. Phải giữ phiên SSH hiện tại và console cứu hộ.\n'
  kw_prompt_yes_no_token "$mode chỉ AuthKey cho TOÀN VPS?" "${mode}:SSH-KEY-ONLY" || return 0
  kw_ssh_key_only_apply "$mode" "$KW_PROMPT_VALUE"
}
