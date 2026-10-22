#!/usr/bin/env bash
# Source-only backups for sites owned by KwVPS. No restore/delete in this module.

readonly KW_BACKUP_ROOT='/var/backups/kwvps'

kw_backup_source_plan() {
  local domain=${1,,}
  kw_site_lookup "$domain" || return 2
  printf 'Kế hoạch sao lưu source (chưa thay đổi hệ thống):\n'
  printf '  Domain: %s\n  Source: %s\n' "$domain" "$KW_SITE_PUBLIC"
  printf '  Nơi lưu: %s/source-%s-<thời gian>-<ngẫu nhiên>.tar.gz\n' \
    "$KW_BACKUP_ROOT" "${KW_SITE_OWNER#kw}"
  printf '  Gồm thư mục public; không gồm database, SSL, cấu hình Nginx/PHP hoặc file ngoài source.\n'
  printf '  Site đang chạy có thể thay đổi trong lúc sao lưu; đây chưa phải snapshot nhất quán.\n'
}

kw_backup_dir_safe() {
  local path=$1 allowed=$2 owner mode
  [[ -d $path && ! -L $path ]] || {
    kw_log ERROR "Thư mục sao lưu không hợp lệ: $path"; return 2;
  }
  owner=$(stat -c %u -- "$path") || return 2
  mode=$(stat -c %a -- "$path") || return 2
  [[ $owner == 0 && $mode =~ ^[0-7]{3,4}$ ]] || return 2
  (( (8#$mode & allowed) == 0 )) || {
    kw_log ERROR "Quyền thư mục sao lưu không an toàn: $path"; return 2;
  }
}

kw_backup_source_preflight() {
  local domain=$1 cmd
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để sao lưu source.'; return 2; }
  kw_os_supported '' || { kw_log ERROR 'Chỉ hỗ trợ Ubuntu 24.04.'; return 2; }
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id ]] || return 2
  [[ $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  kw_site_lookup "$domain" || return 2
  for cmd in tar sha256sum mktemp flock install stat mv chmod date python3; do
    kw_has "$cmd" || { kw_log ERROR "Thiếu $cmd."; return 2; }
  done
  kw_backup_dir_safe /var/backups 0022 || return 2
  if [[ -e $KW_BACKUP_ROOT || -L $KW_BACKUP_ROOT ]]; then
    kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  fi
}

kw_backup_archive_create() {
  local source_root=$1 output=$2 helper
  [[ -d $source_root/public && ! -L $source_root/public ]] || return 2
  tar --one-file-system -C "$source_root" -czf "$output" -- public || return 1
  tar -tzf "$output" >/dev/null || return 1
  helper=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../scripts" && pwd -P)/restore_source.py || return 1
  python3 "$helper" --check "$output" || {
    kw_log ERROR 'Source chứa entry không thể khôi phục an toàn.'; return 1;
  }
  [[ -s $output ]]
}

kw_backup_source_apply_locked() (
  local domain=$1 tmp='' check_tmp='' final='' digest='' id timestamp random
  kw_backup_source_preflight "$domain" || return 2
  trap '[[ -z $tmp ]] || rm -f -- "$tmp"; [[ -z $check_tmp ]] || rm -f -- "$check_tmp"' EXIT
  if [[ ! -e $KW_BACKUP_ROOT && ! -L $KW_BACKUP_ROOT ]]; then
    install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT" || return 1
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  id=${KW_SITE_OWNER#kw}
  timestamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
  tmp=$(mktemp "$KW_BACKUP_ROOT/.source-${id}.XXXXXXXX") || return 1
  chmod 0600 "$tmp" || return 1
  kw_backup_archive_create "$KW_SITE_ROOT" "$tmp" || {
    kw_log ERROR 'Không tạo/kiểm tra được gói source; giữ nguyên site.'
    return 1
  }
  digest=$(sha256sum -- "$tmp") || return 1
  digest=${digest%% *}
  [[ $digest =~ ^[0-9a-f]{64}$ ]] || return 1
  random=${tmp##*.}
  final="$KW_BACKUP_ROOT/source-${id}-${timestamp}-${random}.tar.gz"
  [[ ! -e $final && ! -L $final ]] || return 1
  mv -- "$tmp" "$final" || return 1
  tmp=''
  check_tmp=$(mktemp "$KW_BACKUP_ROOT/.checksum-${id}.XXXXXXXX") || {
    kw_log WARN "Gói đã lưu tại $final nhưng chưa tạo được checksum file."
    return 1
  }
  printf '%s  %s\n' "$digest" "${final##*/}" > "$check_tmp" || return 1
  chmod 0600 "$check_tmp" || return 1
  [[ ! -e $final.sha256 && ! -L $final.sha256 ]] || return 1
  mv -- "$check_tmp" "$final.sha256" || return 1
  check_tmp=''
  printf 'Đã sao lưu source: %s\nSHA-256: %s\n' "$final" "$digest"
  printf 'Không bao gồm database, SSL hoặc cấu hình web server.\n'
)

kw_backup_source() (
  local domain=${1,,} confirm=${2:-}
  kw_domain_valid "$domain" || return 2
  [[ $confirm == "$domain" ]] || {
    kw_log ERROR 'Xác nhận domain không khớp.'; return 2;
  }
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để sao lưu source.'; return 2; }
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || { kw_log ERROR 'Một thao tác site khác đang chạy.'; return 1; }
  kw_backup_source_apply_locked "$domain"
)

kw_backup_source_interactive() {
  local domain confirm
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_backup_source_plan "$domain" || return 2
  kw_prompt_yes_no_token "Sao lưu source của $domain?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_backup_source "$domain" "${confirm,,}"
}

kw_backup_basename_valid() {
  [[ ${1:-} =~ ^source-[a-z0-9]{1,29}-[0-9]{8}T[0-9]{6}Z-[[:alnum:]]{8}\.tar\.gz$ ]]
}

kw_backup_site_label() {
  local id=$1 file domain='' key value
  kw_site_id_valid "$id" || return 2
  file="/etc/kwvps/sites/$id.site"
  if [[ -f $file && ! -L $file && -r $file ]]; then
    while IFS='=' read -r key value; do [[ $key != domain ]] || domain=$value; done < "$file"
    if kw_domain_valid "$domain" && [[ $(kw_site_id "$domain") == "$id" ]]; then
      printf '%s' "$domain"
      return 0
    fi
  fi
  printf 'site %s (không còn trong registry)' "$id"
}

kw_backup_list() {
  local file name bytes count=0 id domain
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để xem backup.'; return 2; }
  if [[ ! -e $KW_BACKUP_ROOT && ! -L $KW_BACKUP_ROOT ]]; then
    printf 'Chưa có backup KwVPS.\n'
    return 0
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  printf 'Danh sách backup source/code:\n'
  for file in "$KW_BACKUP_ROOT"/source-*.tar.gz; do
    [[ -f $file && ! -L $file ]] || continue
    name=${file##*/}
    kw_backup_basename_valid "$name" || continue
    bytes=$(stat -c %s -- "$file") || return 1
    id=${name#source-}; id=${id%%-*}
    domain=$(kw_backup_site_label "$id") || return 2
    count=$((count + 1))
    printf '%2d. %-72s %s bytes | %s\n' "$count" "$name" "$bytes" "$domain"
  done
  ((count)) || printf 'Chưa có backup source hợp lệ.\n'
  printf 'Danh sách không tự kiểm tra nội dung; dùng mục Kiểm tra backup.\n'
}

kw_backup_verify() {
  local name=$1 path line expected stored actual
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để kiểm tra backup.'; return 2; }
  kw_backup_basename_valid "$name" || { kw_log ERROR 'Tên backup không hợp lệ.'; return 2; }
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  path="$KW_BACKUP_ROOT/$name"
  [[ -f $path && ! -L $path && -f $path.sha256 && ! -L $path.sha256 ]] || {
    kw_log ERROR 'Không tìm thấy gói hoặc checksum hợp lệ.'; return 2;
  }
  IFS= read -r line < "$path.sha256" || return 1
  expected=${line%%  *}
  stored=${line#*  }
  [[ $expected =~ ^[0-9a-f]{64}$ && $stored == "$name" && \
     $line == "$expected  $name" ]] || {
    kw_log ERROR 'Checksum file không đúng định dạng.'; return 1;
  }
  actual=$(sha256sum -- "$path") || return 1
  actual=${actual%% *}
  [[ $actual == "$expected" ]] || { kw_log ERROR 'Checksum không khớp.'; return 1; }
  tar -tzf "$path" >/dev/null || { kw_log ERROR 'Archive không đọc được.'; return 1; }
  printf 'Backup hợp lệ về checksum và cấu trúc tar: %s\n' "$name"
  printf 'Chưa thử restore; kết quả này không chứng minh dữ liệu ứng dụng nhất quán.\n'
}

kw_backup_verify_interactive() {
  local name
  kw_backup_choose_source '' || return 0
  name=$KW_BACKUP_CHOICE
  kw_backup_verify "$name"
}

kw_backup_choose_source() {
  local id=${1:-} file name choice count=0 backup_id domain
  local -a names=()
  ((EUID == 0)) || return 2
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  printf 'Chọn backup source:\n'
  for file in "$KW_BACKUP_ROOT"/source-*.tar.gz; do
    [[ -f $file && ! -L $file ]] || continue
    name=${file##*/}
    kw_backup_basename_valid "$name" || continue
    [[ -z $id || $name == source-${id}-* ]] || continue
    names+=("$name")
    count=$((count + 1))
    backup_id=${name#source-}; backup_id=${backup_id%%-*}
    domain=$(kw_backup_site_label "$backup_id") || return 2
    printf '%2d. %s | %s\n' "$count" "$name" "$domain"
  done
  if ((count == 0)); then printf 'Không có backup phù hợp.\n'; return 1; fi
  printf ' 0. Quay lại\nChọn số backup: '
  IFS= read -r choice || return 1
  [[ $choice =~ ^[1-9][0-9]*$ ]] && ((choice <= count)) || return 1
  KW_BACKUP_CHOICE=${names[choice-1]}
}

kw_restore_source_plan() {
  local domain=${1,,} name=$2 id
  kw_site_lookup "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  if ! kw_backup_basename_valid "$name" || [[ $name != source-${id}-* ]]; then
    kw_log ERROR 'Backup không thuộc site đã chọn.'; return 2;
  fi
  kw_backup_verify "$name" || return 2
  printf 'Kế hoạch khôi phục source:\n'
  printf '  Site: %s\n  Backup: %s\n  Thư mục thay thế: %s\n' "$domain" "$name" "$KW_SITE_PUBLIC"
  printf '  Source hiện tại được sao lưu trước và giữ lại cạnh thư mục public.\n'
  printf '  Chỉ khôi phục source; không đổi DB, SSL, Nginx, PHP hoặc cron.\n'
  printf '  File link/thiết bị/đường dẫn thoát ngoài archive sẽ bị từ chối.\n'
}

kw_restore_source_apply_locked() (
  local domain=$1 name=$2 stage='' old='' id suffix
  kw_backup_source_preflight "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  if ! kw_backup_basename_valid "$name" || [[ $name != source-${id}-* ]]; then return 2; fi
  kw_backup_verify "$name" >/dev/null || return 2
  kw_has python3 && kw_has chown && kw_has id || return 2
  [[ -f $KW_ROOT/scripts/restore_source.py && ! -L $KW_ROOT/scripts/restore_source.py ]] || return 2
  [[ -d /var/www/kwvps && ! -L /var/www/kwvps ]] || return 2
  getent passwd "$KW_SITE_OWNER" >/dev/null || return 2
  getent group www-data >/dev/null || return 2
  stage=$(mktemp -d /var/www/kwvps/.restore-XXXXXXXX) || return 1
  trap 'if [[ $stage == /var/www/kwvps/.restore-* && -d $stage && ! -L $stage ]]; then rm -rf -- "$stage"; fi' EXIT
  python3 "$KW_ROOT/scripts/restore_source.py" "$KW_BACKUP_ROOT/$name" "$stage" || return 2
  [[ -d $stage/public && ! -L $stage/public ]] || return 2
  chown -R -- "$KW_SITE_OWNER:www-data" "$stage/public" || return 1
  # A fresh backup must exist before the live tree is renamed.
  kw_backup_source_apply_locked "$domain" || return 1
  suffix=${stage##*-}
  old="$KW_SITE_ROOT/public-before-restore-$suffix"
  [[ ! -e $old && ! -L $old ]] || return 2
  mv -T -- "$KW_SITE_PUBLIC" "$old" || return 1
  if ! mv -T -- "$stage/public" "$KW_SITE_PUBLIC"; then
    mv -T -- "$old" "$KW_SITE_PUBLIC" || kw_log ERROR "Cần trả source thủ công từ $old."
    return 1
  fi
  printf 'Đã khôi phục source cho %s từ %s\n' "$domain" "$name"
  printf 'Source trước khi khôi phục giữ tại %s\n' "$old"
  printf 'Hãy tự kiểm tra ứng dụng; DB/SSL không được khôi phục.\n'
)

kw_restore_source() (
  local domain=${1,,} name=$2 confirm=${3:-}
  kw_domain_valid "$domain" || return 2
  [[ $confirm == "$domain" ]] || { kw_log ERROR 'Xác nhận domain không khớp.'; return 2; }
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để khôi phục source.'; return 2; }
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || { kw_log ERROR 'Một thao tác site khác đang chạy.'; return 1; }
  kw_restore_source_apply_locked "$domain" "$name"
)

kw_restore_source_interactive() {
  local domain name confirm
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_backup_choose_source "$(kw_site_id "$domain")" || return 0
  name=$KW_BACKUP_CHOICE
  kw_restore_source_plan "$domain" "$name" || return 2
  kw_prompt_yes_no_token "Khôi phục source của $domain từ bản đã chọn?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_restore_source "$domain" "$name" "${confirm,,}"
}
