#!/usr/bin/env bash
# Source-only backups for sites owned by KwVPS. No restore/delete in this module.

readonly KW_BACKUP_ROOT='/var/backups/kwvps'
readonly KW_SOURCE_BACKUP_DOMAIN_RE='^source-([a-z0-9.-]+)-[0-9]{8}-[0-9]{6}(-[1-9][0-9]*)?\.tar\.gz$'
readonly KW_SOURCE_BACKUP_ID_RE='^source-([a-z0-9]{1,29})-[0-9]{8}-[0-9]{6}(-[1-9][0-9]*)?\.tar\.gz$'
readonly KW_SOURCE_BACKUP_LEGACY_RE='^source-([a-z0-9]{1,29})-[0-9]{8}T[0-9]{6}Z-[[:alnum:]]{8}\.tar\.gz$'

kw_backup_source_plan() {
  local domain=${1,,} label
  kw_site_lookup "$domain" || return 2
  label=$domain
  if ((${#label} > 205)); then label=${KW_SITE_OWNER#kw}; fi
  printf 'Kế hoạch sao lưu source (chưa thay đổi hệ thống):\n'
  printf '  Domain: %s\n  Source: %s\n' "$domain" "$KW_SITE_PUBLIC"
  printf '  Nơi lưu: %s/source-%s-YYYYMMDD-HHMMSS[-N].tar.gz (UTC)\n' \
    "$KW_BACKUP_ROOT" "$label"
  if [[ $label != "$domain" ]]; then
    printf '  Domain dài hơn 205 ký tự nên dùng site ID để không vượt giới hạn tên file Linux.\n'
  fi
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
  for cmd in tar sha256sum mktemp flock install stat mv ln chmod date python3; do
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
  local domain=$1 tmp='' check_tmp='' final='' digest='' id timestamp label suffix=1
  kw_backup_source_preflight "$domain" || return 2
  trap '[[ -z $tmp ]] || rm -f -- "$tmp"; [[ -z $check_tmp ]] || rm -f -- "$check_tmp"' EXIT
  if [[ ! -e $KW_BACKUP_ROOT && ! -L $KW_BACKUP_ROOT ]]; then
    install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT" || return 1
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  id=${KW_SITE_OWNER#kw}
  label=$domain
  if ((${#label} > 205)); then label=$id; fi
  timestamp=$(date -u +%Y%m%d-%H%M%S) || return 1
  tmp=$(mktemp "$KW_BACKUP_ROOT/.source-${id}.XXXXXXXX") || return 1
  chmod 0600 "$tmp" || return 1
  kw_backup_archive_create "$KW_SITE_ROOT" "$tmp" || {
    kw_log ERROR 'Không tạo/kiểm tra được gói source; giữ nguyên site.'
    return 1
  }
  digest=$(sha256sum -- "$tmp") || return 1
  digest=${digest%% *}
  [[ $digest =~ ^[0-9a-f]{64}$ ]] || return 1
  while :; do
    final="$KW_BACKUP_ROOT/source-${label}-${timestamp}"
    ((suffix == 1)) || final="${final}-${suffix}"
    final+='.tar.gz'
    if [[ ! -e $final.sha256 && ! -L $final.sha256 ]] &&
       ln -- "$tmp" "$final" 2>/dev/null; then break; fi
    [[ -e $final || -L $final || -e $final.sha256 || -L $final.sha256 ]] || return 1
    ((suffix < 1000)) || return 2
    suffix=$((suffix + 1))
  done
  rm -f -- "$tmp" || return 1
  tmp=''
  check_tmp=$(mktemp "$KW_BACKUP_ROOT/.checksum-${id}.XXXXXXXX") || {
    kw_log WARN "Gói đã lưu tại $final nhưng chưa tạo được checksum file."
    return 1
  }
  printf '%s  %s\n' "$digest" "${final##*/}" > "$check_tmp" || return 1
  chmod 0600 "$check_tmp" || return 1
  ln -- "$check_tmp" "$final.sha256" || return 1
  rm -f -- "$check_tmp" || return 1
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
  local name=${1:-} embedded
  if [[ $name =~ $KW_SOURCE_BACKUP_DOMAIN_RE ]]; then
    embedded=${BASH_REMATCH[1]}
    if kw_domain_valid "$embedded"; then return 0; fi
  fi
  [[ $name =~ $KW_SOURCE_BACKUP_ID_RE || $name =~ $KW_SOURCE_BACKUP_LEGACY_RE ]]
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

kw_backup_source_label() {
  local name=$1 embedded id
  kw_backup_basename_valid "$name" || return 2
  if [[ $name =~ $KW_SOURCE_BACKUP_DOMAIN_RE ]]; then
    embedded=${BASH_REMATCH[1]}
    if kw_domain_valid "$embedded"; then printf '%s' "$embedded"; return 0; fi
  fi
  if [[ $name =~ $KW_SOURCE_BACKUP_ID_RE ]]; then
    id=${BASH_REMATCH[1]}
  elif [[ $name =~ $KW_SOURCE_BACKUP_LEGACY_RE ]]; then
    id=${BASH_REMATCH[1]}
  else
    return 2
  fi
  kw_backup_site_label "$id"
}

kw_backup_source_matches_site() {
  local name=$1 domain=$2 id=$3 embedded
  kw_backup_basename_valid "$name" || return 1
  if [[ $name =~ $KW_SOURCE_BACKUP_DOMAIN_RE ]]; then
    embedded=${BASH_REMATCH[1]}
    if kw_domain_valid "$embedded"; then [[ $embedded == "$domain" ]]; return; fi
  fi
  if [[ $name =~ $KW_SOURCE_BACKUP_ID_RE ]]; then
    [[ ${BASH_REMATCH[1]} == "$id" ]]
  elif [[ $name =~ $KW_SOURCE_BACKUP_LEGACY_RE ]]; then
    [[ ${BASH_REMATCH[1]} == "$id" ]]
  else
    return 1
  fi
}

kw_backup_list() {
  local file name bytes count=0 domain
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
    domain=$(kw_backup_source_label "$name") || return 2
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
  local site_domain=${1:-} site_id='' file name choice count=0 domain
  local -a names=()
  ((EUID == 0)) || return 2
  if [[ -n $site_domain ]]; then
    kw_domain_valid "$site_domain" || return 2
    site_id=$(kw_site_id "$site_domain") || return 2
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  printf 'Chọn backup source:\n'
  for file in "$KW_BACKUP_ROOT"/source-*.tar.gz; do
    [[ -f $file && ! -L $file ]] || continue
    name=${file##*/}
    kw_backup_basename_valid "$name" || continue
    if [[ -n $site_domain ]]; then
      kw_backup_source_matches_site "$name" "$site_domain" "$site_id" || continue
    fi
    names+=("$name")
    count=$((count + 1))
    domain=$(kw_backup_source_label "$name") || return 2
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
  if ! kw_backup_source_matches_site "$name" "$domain" "$id"; then
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
  kw_backup_source_matches_site "$name" "$domain" "$id" || return 2
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
  kw_backup_choose_source "$domain" || return 0
  name=$KW_BACKUP_CHOICE
  kw_restore_source_plan "$domain" "$name" || return 2
  kw_prompt_yes_no_token "Khôi phục source của $domain từ bản đã chọn?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_restore_source "$domain" "$name" "${confirm,,}"
}
