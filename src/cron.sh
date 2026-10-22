#!/usr/bin/env bash
# Root cron editing is delegated to crontab's parser and nano; no eval.

kw_cron_ready() {
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để xem/sửa cron hệ thống.'; return 2; }
  kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && \
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  kw_has crontab || return 2
}

kw_cron_system_list() {
  kw_cron_ready || return 2
  printf 'Lịch cron hệ thống (/etc/crontab):\n'
  [[ -f /etc/crontab && ! -L /etc/crontab && -r /etc/crontab ]] || return 2
  sed -n '1,200p' /etc/crontab || return 1
  printf '\nCrontab của root (tối đa 200 dòng):\n'
  local root_cron status=0
  root_cron=$(LC_ALL=C crontab -u root -l 2>&1) || status=$?
  if ((status == 0)); then
    sed -n '1,200p' <<< "$root_cron"
  elif [[ $root_cron == 'no crontab for root' ]]; then
    printf 'Root chưa có crontab riêng.\n'
  else
    kw_log ERROR 'Không đọc được crontab của root.'; return 1
  fi
  printf 'Không sửa /etc/crontab hoặc file trong /etc/cron.d từ menu này.\n'
}

kw_cron_nano_plan() {
  printf 'Mở crontab riêng của root bằng nano; crontab kiểm tra cú pháp khi lưu.\n'
  printf 'Giữ bản trước root-only tại /var/backups/kwvps (file rỗng nếu chưa có crontab).\n'
  printf 'Lệnh cron chạy với quyền root; kiểm tra kỹ nội dung trước khi lưu.\n'
}

kw_cron_nano() (
  local confirm=${1:-} backup timestamp root_cron status=0
  [[ $confirm == EDIT-ROOT-CRON ]] || return 2
  kw_cron_ready || return 2
  kw_has nano || { kw_log ERROR 'Nano chưa được cài.'; return 2; }
  [[ -r /dev/tty ]] || { kw_log ERROR 'Cần terminal tương tác.'; return 2; }
  kw_backup_dir_safe /var/backups 0022 || return 2
  if [[ ! -e $KW_BACKUP_ROOT && ! -L $KW_BACKUP_ROOT ]]; then
    install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT" || return 1
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  timestamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
  backup="$KW_BACKUP_ROOT/cron-root-${timestamp}-$$.txt"
  [[ ! -e $backup && ! -L $backup ]] || return 2
  (umask 077; : > "$backup") || return 1
  root_cron=$(LC_ALL=C crontab -u root -l 2>&1) || status=$?
  if ((status == 0)); then
    printf '%s\n' "$root_cron" > "$backup" || return 1
  elif [[ $root_cron != 'no crontab for root' ]]; then
    kw_log ERROR 'Không đọc được crontab trước khi sửa.'; return 1
  fi
  chmod 0600 -- "$backup" || return 1
  printf 'Bản cron trước khi sửa: %s\n' "$backup"
  VISUAL=nano EDITOR=nano crontab -u root -e
)

kw_cron_nano_interactive() {
  local confirm
  kw_cron_nano_plan
  kw_prompt_yes_no_token 'Mở root crontab bằng nano?' EDIT-ROOT-CRON || return 0
  confirm=$KW_PROMPT_VALUE
  kw_cron_nano "$confirm"
}
