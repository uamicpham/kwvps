#!/usr/bin/env bash
# Named MariaDB databases owned by KwVPS. Legacy per-site DBs remain supported.
readonly KW_DB_CUSTOM_DIR=/etc/kwvps/db-custom
readonly KW_DB_UPLOAD_DIR="$KW_BACKUP_ROOT"

kw_db_identifier_valid() { [[ ${1:-} =~ ^[a-zA-Z][a-zA-Z0-9_]{0,63}$ ]]; }
kw_db_user_valid() { [[ ${1:-} =~ ^[a-zA-Z][a-zA-Z0-9_]{0,31}$ ]]; }
kw_db_password_valid() {
  local password=${1:-}
  ((${#password} >= 12 && ${#password} <= 128)) && [[ $password =~ ^[a-zA-Z0-9_!@#%+=.\-]+$ ]]
}

kw_db_custom_meta() {
  local name=$1 file key value found_name='' found_user='' found_password='' found_domain=''
  kw_db_identifier_valid "$name" || return 2
  file="$KW_DB_CUSTOM_DIR/$name.db"
  [[ -f $file && ! -L $file && $(stat -c %u -- "$file") == 0 && \
     $(stat -c %a -- "$file") == 600 ]] || return 2
  while IFS='=' read -r key value; do
    case "$key" in
      database) found_name=$value ;;
      user) found_user=$value ;;
      password) found_password=$value ;;
      domain) found_domain=$value ;;
    esac
  done < "$file"
  [[ $found_name == "$name" ]] && kw_db_user_valid "$found_user" && \
    kw_db_password_valid "$found_password" && kw_domain_valid "$found_domain" || return 2
  KW_DB_SELECTED_USER=$found_user
  KW_DB_SELECTED_PASSWORD=$found_password
  KW_DB_SELECTED_DOMAIN=$found_domain
  KW_DB_SELECTED_META=$file
  KW_DB_SELECTED_KIND=custom
}

kw_db_legacy_meta() {
  local name=$1 id domain='' key value
  [[ $name =~ ^kwdb_([a-z0-9]{1,29})$ ]] || return 2
  id=${BASH_REMATCH[1]}
  [[ -f /etc/kwvps/sites/$id.site && ! -L /etc/kwvps/sites/$id.site ]] || return 2
  while IFS='=' read -r key value; do [[ $key != domain ]] || domain=$value; done < "/etc/kwvps/sites/$id.site"
  kw_domain_valid "$domain" && [[ $(kw_site_id "$domain") == "$id" ]] || return 2
  kw_db_meta_lookup "$domain" || return 2
  KW_DB_SELECTED_USER=$KW_DB_USER
  KW_DB_SELECTED_PASSWORD=$KW_DB_PASSWORD
  KW_DB_SELECTED_DOMAIN=$domain
  KW_DB_SELECTED_META=$KW_DB_META
  KW_DB_SELECTED_KIND=legacy
}

kw_db_select_meta() {
  local name=$1
  kw_db_custom_meta "$name" || kw_db_legacy_meta "$name"
}

kw_db_managed_names() {
  local file name
  for file in /etc/kwvps/db/*.db; do
    [[ -f $file && ! -L $file ]] || continue
    name=${file##*/}; name=${name%.db}
    kw_site_id_valid "$name" || continue
    kw_db_legacy_meta "kwdb_$name" >/dev/null 2>&1 || continue
    printf '%s\n' "kwdb_$name"
  done
  for file in "$KW_DB_CUSTOM_DIR"/*.db; do
    [[ -f $file && ! -L $file ]] || continue
    name=${file##*/}; name=${name%.db}
    kw_db_custom_meta "$name" >/dev/null 2>&1 || continue
    printf '%s\n' "$name"
  done
}

kw_db_managed_list() {
  local name count=0
  kw_db_ready || return 2
  while IFS= read -r name; do
    kw_db_select_meta "$name" || continue
    count=$((count + 1))
    printf '%d. %s\n' "$count" "$name"
  done < <(kw_db_managed_names)
  ((count)) || printf 'Chưa có database KwVPS quản lý.\n'
}

kw_db_users_list() {
  local name count=0
  kw_db_ready || return 2
  while IFS= read -r name; do
    kw_db_select_meta "$name" || continue
    count=$((count + 1))
    printf '%d. %s\n' "$count" "$KW_DB_SELECTED_USER"
  done < <(kw_db_managed_names)
  ((count)) || printf 'Chưa có user database KwVPS quản lý.\n'
}

kw_db_choose_managed() {
  local name choice count=0 domain_filter=${1:-}
  local -a names=()
  kw_db_ready || return 2
  [[ -z $domain_filter ]] || kw_domain_valid "$domain_filter" || return 2
  printf 'Chọn database:\n'
  while IFS= read -r name; do
    kw_db_select_meta "$name" || continue
    [[ -z $domain_filter || $KW_DB_SELECTED_DOMAIN == "$domain_filter" ]] || continue
    names+=("$name")
    count=$((count + 1))
    printf '%d. %s\n' "$count" "$name"
  done < <(kw_db_managed_names)
  if ((count == 0)); then printf 'Chưa có database KwVPS quản lý.\n'; return 1; fi
  printf ' 0. Quay lại\n'
  while :; do
    printf 'Chọn số database: '
    IFS= read -r choice || return 1
    [[ $choice != 0 ]] || return 1
    [[ $choice =~ ^[1-9][0-9]*$ ]] && ((choice <= count)) && break
    printf 'Số database không hợp lệ; nhập lại.\n'
  done
  KW_DB_MANAGED_CHOICE=${names[choice-1]}
}

kw_db_custom_create_locked() (
  local domain=$1 name=$2 user=$3 password=$4 count tmp='' created_db=0 created_user=0 committed=0
  kw_db_ready || return 2
  kw_site_lookup "$domain" || return 2
  kw_db_identifier_valid "$name" && kw_db_user_valid "$user" && kw_db_password_valid "$password" || return 2
  [[ $name != kwdb_* && $user != kwu_* ]] || return 2
  [[ ! -e $KW_DB_CUSTOM_DIR/$name.db && ! -L $KW_DB_CUSTOM_DIR/$name.db ]] || return 2
  count=$(mariadb --protocol=socket -uroot --batch --skip-column-names -e \
    "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$name'") || return 2
  [[ $count == 0 ]] || return 2
  count=$(mariadb --protocol=socket -uroot --batch --skip-column-names -e \
    "SELECT COUNT(*) FROM mysql.user WHERE User='$user' AND Host='localhost'") || return 2
  [[ $count == 0 ]] || return 2
  if [[ ! -e $KW_DB_CUSTOM_DIR && ! -L $KW_DB_CUSTOM_DIR ]]; then
    install -d -m 0700 -o root -g root -- "$KW_DB_CUSTOM_DIR" || return 1
  fi
  kw_backup_dir_safe "$KW_DB_CUSTOM_DIR" 0077 || return 2
  tmp=$(mktemp "$KW_DB_CUSTOM_DIR/.create.XXXXXXXX") || return 1
  chmod 0600 -- "$tmp" || return 1
  trap 'if ((committed == 0)); then if ((created_user)); then printf "DROP USER IF EXISTS '\''%s'\''@'\''localhost'\'';\n" "$user" | mariadb --protocol=socket -uroot || true; fi; if ((created_db)); then printf "DROP DATABASE IF EXISTS \`%s\`;\n" "$name" | mariadb --protocol=socket -uroot || true; fi; fi; [[ -z $tmp ]] || rm -f -- "$tmp"' EXIT
  printf 'database=%s\nuser=%s\npassword=%s\ndomain=%s\n' "$name" "$user" "$password" "$domain" > "$tmp" || return 1
  # shellcheck disable=SC2016 # SQL identifier backticks are literal.
  printf 'CREATE DATABASE `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\n' "$name" | mariadb --protocol=socket -uroot || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  created_db=1
  printf "CREATE USER '%s'@'localhost' IDENTIFIED BY '%s';\n" "$user" "$password" | mariadb --protocol=socket -uroot || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  created_user=1
  printf "GRANT ALL PRIVILEGES ON \`%s\`.* TO '%s'@'localhost';\n" "$name" "$user" | mariadb --protocol=socket -uroot || return 1
  mv -T -- "$tmp" "$KW_DB_CUSTOM_DIR/$name.db" || return 1
  tmp=''
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  committed=1
  printf 'Đã tạo database %s, user %s@localhost cho %s. Metadata root-only: %s\n' "$name" "$user" "$domain" "$KW_DB_CUSTOM_DIR/$name.db"
)

kw_db_custom_create() (
  local domain=${1,,} name=$2 user=$3 password=$4 confirm=${5:-}
  kw_domain_valid "$domain" && kw_db_identifier_valid "$name" && kw_db_user_valid "$user" && \
    kw_db_password_valid "$password" && [[ $confirm == "$name" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-db.lock || return 2
  flock -n 9 || return 1
  kw_db_custom_create_locked "$domain" "$name" "$user" "$password"
)

kw_db_custom_create_interactive() {
  local domain name user password confirm
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_prompt_validated 'Tên database (chữ/số/_; bắt đầu bằng chữ): ' \
    kw_db_identifier_valid 'Tên DB bắt đầu bằng chữ, chỉ dùng chữ/số/_ và tối đa 64 ký tự' plain || return 0
  name=$KW_PROMPT_VALUE
  kw_prompt_validated 'Tên user DB (tối đa 32 ký tự): ' \
    kw_db_user_valid 'Tên user bắt đầu bằng chữ, chỉ dùng chữ/số/_ và tối đa 32 ký tự' plain || return 0
  user=$KW_PROMPT_VALUE
  kw_prompt_validated 'Mật khẩu DB (12–128 ký tự; không hiển thị): ' \
    kw_db_password_valid 'Mật khẩu cần 12–128 ký tự trong tập chữ/số/_!@#%+=.-' secret || return 0
  password=$KW_PROMPT_VALUE
  KW_PROMPT_VALUE=''
  kw_prompt_yes_no_token "Tạo DB $name và user $user@localhost cho site $domain?" "$name" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_db_custom_create "$domain" "$name" "$user" "$password" "$confirm"
}

kw_db_password_change_locked() (
  local name=$1 password=$2 old user meta temp='' changed=0 committed=0
  kw_db_ready || return 2
  kw_db_select_meta "$name" || return 2
  old=$KW_DB_SELECTED_PASSWORD; user=$KW_DB_SELECTED_USER; meta=$KW_DB_SELECTED_META
  [[ $password != "$old" ]] || { printf 'Mật khẩu mới trùng mật khẩu hiện tại.\n'; return 2; }
  temp=$(mktemp "${meta}.new.XXXXXXXX") || return 1
  trap 'if ((changed == 1 && committed == 0)); then printf "ALTER USER '\''%s'\''@'\''localhost'\'' IDENTIFIED BY '\''%s'\'';\n" "$user" "$old" | mariadb --protocol=socket -uroot || kw_log ERROR "Cần phục hồi password cho $user"; fi; [[ -z $temp ]] || rm -f -- "$temp"' EXIT
  chmod 0600 -- "$temp" || return 1
  awk -F= -v replacement="$password" '$1 == "password" { print "password=" replacement; next } { print }' "$meta" > "$temp" || return 1
  [[ $(grep -c '^password=' "$temp") == 1 ]] || return 2
  printf "ALTER USER '%s'@'localhost' IDENTIFIED BY '%s';\n" "$user" "$password" | mariadb --protocol=socket -uroot || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  changed=1
  mv -T -- "$temp" "$meta" || return 1
  temp=''
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  committed=1
  printf 'Đã đổi mật khẩu user %s@localhost của database %s.\n' "$user" "$name"
)

kw_db_password_change() (
  local name=$1 password=$2 confirm=${3:-}
  kw_db_identifier_valid "$name" && kw_db_password_valid "$password" && [[ $confirm == "$name" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-db.lock || return 2
  flock -n 9 || return 1
  kw_db_password_change_locked "$name" "$password"
)

kw_db_password_change_interactive() {
  local name user password confirm
  kw_db_choose_managed || return 0
  name=$KW_DB_MANAGED_CHOICE
  kw_db_select_meta "$name" || return 2
  user=$KW_DB_SELECTED_USER
  kw_prompt_validated "Mật khẩu mới cho $user@localhost (không hiển thị): " \
    kw_db_password_valid 'Mật khẩu cần 12–128 ký tự trong tập chữ/số/_!@#%+=.-' secret || return 0
  password=$KW_PROMPT_VALUE
  KW_PROMPT_VALUE=''
  kw_prompt_yes_no_token "Đổi pass user $user của DB $name (ứng dụng có thể mất kết nối)?" "$name" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_db_password_change "$name" "$password" "$confirm"
}

kw_db_export_named_locked() (
  local name=$1 stamp tmp='' checksum_tmp='' final digest
  kw_db_ready || return 2
  kw_db_select_meta "$name" || return 2
  kw_has mariadb-dump && kw_has gzip && kw_has sha256sum || return 2
  kw_backup_dir_safe /var/backups 0022 || return 2
  if [[ ! -e $KW_BACKUP_ROOT && ! -L $KW_BACKUP_ROOT ]]; then
    install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT" || return 1
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  stamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
  tmp=$(mktemp "$KW_BACKUP_ROOT/.db-export.XXXXXXXX") || return 1
  trap '[[ -z $tmp ]] || rm -f -- "$tmp"; [[ -z $checksum_tmp ]] || rm -f -- "$checksum_tmp"' EXIT
  chmod 0600 -- "$tmp" || return 1
  if ! mariadb-dump --protocol=socket -uroot --single-transaction --quick \
    --routines --events --triggers "$name" | gzip -c > "$tmp"; then return 1; fi
  [[ -s $tmp ]] && gzip -t -- "$tmp" || return 1
  digest=$(sha256sum -- "$tmp") || return 1
  digest=${digest%% *}
  final="$KW_BACKUP_ROOT/db-export-${name}-${stamp}-${tmp##*.}.sql.gz"
  [[ ! -e $final && ! -L $final ]] || return 2
  mv -T -- "$tmp" "$final" || return 1
  tmp=''
  checksum_tmp=$(mktemp "$KW_BACKUP_ROOT/.db-checksum.XXXXXXXX") || return 1
  chmod 0600 -- "$checksum_tmp" || return 1
  printf '%s  %s\n' "$digest" "${final##*/}" > "$checksum_tmp" || return 1
  [[ ! -e $final.sha256 && ! -L $final.sha256 ]] || return 2
  mv -T -- "$checksum_tmp" "$final.sha256" || return 1
  checksum_tmp=''
  printf 'Đã export %s: %s\nSHA-256: %s\n' "$name" "$final" "$digest"
)

kw_db_export_named() (
  local name=$1 confirm=${2:-}
  kw_db_identifier_valid "$name" && [[ $confirm == "$name" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-db.lock || return 2
  flock -n 9 || return 1
  kw_db_export_named_locked "$name"
)

kw_db_export_named_interactive() {
  local name confirm
  kw_db_choose_managed || return 0
  name=$KW_DB_MANAGED_CHOICE
  kw_prompt_yes_no_token "Export database $name vào backup root-only?" "$name" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_db_export_named "$name" "$confirm"
}

kw_db_upload_valid() {
  local name=${1:-}
  [[ $name =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,199}\.sql(\.gz)?$ && $name != *..* ]]
}

kw_db_choose_upload() {
  local file name choice count=0
  local -a names=()
  ((EUID == 0)) || return 2
  [[ -d $KW_DB_UPLOAD_DIR && ! -L $KW_DB_UPLOAD_DIR ]] || {
    printf 'Chưa có thư mục %s. Hãy tạo backup trước hoặc tải file SQL vào đó bằng quyền root.\n' "$KW_DB_UPLOAD_DIR"; return 1;
  }
  kw_backup_dir_safe /var/backups 0022 || return 2
  kw_backup_dir_safe "$KW_DB_UPLOAD_DIR" 0077 || return 2
  printf 'Bước 1: Chọn file DB dump trong %s\n' "$KW_DB_UPLOAD_DIR"
  for file in "$KW_DB_UPLOAD_DIR"/*.sql "$KW_DB_UPLOAD_DIR"/*.sql.gz; do
    [[ -f $file && ! -L $file && -r $file ]] || continue
    name=${file##*/}
    kw_db_upload_valid "$name" || continue
    names+=("$name")
    count=$((count + 1))
  done
  printf 'Tìm thấy %d file .sql/.sql.gz trong %s. Chọn file cần import bên dưới.\n' "$count" "$KW_DB_UPLOAD_DIR"
  ((count)) || return 1
  for ((choice=0; choice<count; choice++)); do printf '%2d. %s\n' "$((choice + 1))" "${names[choice]}"; done
  printf ' 0. Quay lại\n'
  while :; do
    printf 'Chọn số file: '
    IFS= read -r choice || return 1
    [[ $choice != 0 ]] || return 1
    [[ $choice =~ ^[1-9][0-9]*$ ]] && ((choice <= count)) && break
    printf 'Số file không hợp lệ; nhập lại.\n'
  done
  KW_DB_UPLOAD_CHOICE=${names[choice-1]}
}

kw_db_import_uploaded_locked() (
  local filename=$1 name=$2 source staged='' options='' tables bytes
  kw_db_ready || return 2
  kw_db_upload_valid "$filename" || return 2
  kw_db_select_meta "$name" || return 2
  source="$KW_DB_UPLOAD_DIR/$filename"
  kw_backup_dir_safe /var/backups 0022 || return 2
  kw_backup_dir_safe "$KW_DB_UPLOAD_DIR" 0077 || return 2
  [[ -f $source && ! -L $source && -r $source ]] || return 2
  bytes=$(stat -c %s -- "$source") || return 2
  if [[ ! $bytes =~ ^[0-9]+$ ]] || ((bytes == 0 || bytes > 1073741824)); then
    kw_log ERROR 'Dump rỗng hoặc lớn hơn 1 GiB; chưa import.'; return 2;
  fi
  tables=$(mariadb --protocol=socket -uroot --batch --skip-column-names -e \
    "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$name'") || return 2
  [[ $tables =~ ^[0-9]+$ ]] || return 2
  kw_backup_dir_safe /var/backups 0022 || return 2
  if [[ ! -e $KW_BACKUP_ROOT && ! -L $KW_BACKUP_ROOT ]]; then
    install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT" || return 1
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  staged=$(mktemp "$KW_BACKUP_ROOT/.import.XXXXXXXX") || return 1
  options=$(mktemp /run/kwvps-import.XXXXXXXX) || return 1
  trap '[[ -z $staged ]] || rm -f -- "$staged"; [[ -z $options ]] || rm -f -- "$options"' EXIT
  chmod 0600 -- "$staged" "$options" || return 1
  cp -- "$source" "$staged" || return 1
  [[ $(stat -c %s -- "$staged") == "$bytes" ]] || return 1
  if [[ $filename == *.gz ]]; then gzip -t -- "$staged" || return 2; fi
  printf '[client]\nuser=%s\npassword="%s"\n' "$KW_DB_SELECTED_USER" "$KW_DB_SELECTED_PASSWORD" > "$options" || return 1
  # Preserve current contents first; SQL import itself is not atomic.
  kw_db_export_named_locked "$name" || return 1
  printf 'Đang import %s vào %s (%s bảng hiện có).\n' "$filename" "$name" "$tables"
  if [[ $filename == *.gz ]]; then
    gzip -cd -- "$staged" | mariadb --defaults-extra-file="$options" --protocol=socket "$name" || return 1
  else
    mariadb --defaults-extra-file="$options" --protocol=socket "$name" < "$staged" || return 1
  fi
  printf 'Import xong %s vào %s. Hãy kiểm tra dữ liệu ứng dụng.\n' "$filename" "$name"
)

kw_db_import_uploaded() (
  local filename=$1 name=$2 confirm=${3:-}
  kw_db_upload_valid "$filename" && kw_db_identifier_valid "$name" && [[ $confirm == "$name" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-db.lock || return 2
  flock -n 9 || return 1
  kw_db_import_uploaded_locked "$filename" "$name"
)

kw_db_import_uploaded_interactive() {
  local filename name tables confirm scope domain=''
  kw_db_choose_upload || return 0
  filename=$KW_DB_UPLOAD_CHOICE
  printf '\nBước 2: Chọn phạm vi database đích\n 1. Tất cả database\n 2. Theo site\n 0. Quay lại\n'
  while :; do
    printf 'Chọn: '
    IFS= read -r scope || return 0
    [[ $scope == 0 ]] && return 0
    [[ $scope == 1 || $scope == 2 ]] && break
    printf 'Lựa chọn không hợp lệ; nhập lại.\n'
  done
  case "$scope" in
    1) ;;
    2) kw_site_prompt_domain || return 0; domain=$KW_SITE_CHOICE ;;
    *) return 0 ;;
  esac
  printf '\nBước 3: Chọn database đích\n'
  kw_db_choose_managed "$domain" || return 0
  name=$KW_DB_MANAGED_CHOICE
  tables=$(mariadb --protocol=socket -uroot --batch --skip-column-names -e \
    "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$name'") || return 2
  printf 'File: %s/%s\nĐích: %s\n' "$KW_DB_UPLOAD_DIR" "$filename" "$name"
  if [[ $tables =~ ^[0-9]+$ ]] && ((tables > 0)); then
    printf 'CẢNH BÁO: database đích đã có %s bảng. Import có thể ghi đè/trộn dữ liệu; không thể rollback SQL tự động.\n' "$tables"
  fi
  kw_prompt_yes_no_token "Import vào $name (tự export hiện trạng trước)?" "$name" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_db_import_uploaded "$filename" "$name" "$confirm"
}

kw_db_drop_named_locked() (
  local name=$1 user kind meta archive
  kw_db_ready || return 2
  kw_db_select_meta "$name" || return 2
  user=$KW_DB_SELECTED_USER; kind=$KW_DB_SELECTED_KIND; meta=$KW_DB_SELECTED_META
  kw_db_export_named_locked "$name" || return 1
  # shellcheck disable=SC2016 # SQL identifier backticks are literal.
  printf 'DROP DATABASE `%s`;\n' "$name" | mariadb --protocol=socket -uroot || return 1
  printf "DROP USER '%s'@'localhost';\n" "$user" | mariadb --protocol=socket -uroot || {
    kw_log ERROR "Đã xóa DB $name nhưng còn user $user; cần xử lý thủ công."; return 1;
  }
  install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT/db-retired" || return 1
  kw_backup_dir_safe "$KW_BACKUP_ROOT/db-retired" 0077 || return 2
  archive="$KW_BACKUP_ROOT/db-retired/${name}-$(date -u +%Y%m%dT%H%M%SZ)-${BASHPID}.db"
  [[ ! -e $archive && ! -L $archive ]] || return 2
  mv -T -- "$meta" "$archive" || {
    kw_log ERROR "DB/user đã xóa, metadata chưa chuyển: $meta"; return 1;
  }
  printf 'Đã xóa DB %s và user %s (%s). Backup/metadata cũ trong %s.\n' "$name" "$user" "$kind" "$KW_BACKUP_ROOT"
)

kw_db_drop_named() (
  local name=$1 confirm=${2:-}
  kw_db_identifier_valid "$name" && [[ $confirm == YES ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-db.lock || return 2
  flock -n 9 || return 1
  kw_db_drop_named_locked "$name"
)

kw_db_drop_named_interactive() {
  local name
  kw_db_choose_managed || return 0
  name=$KW_DB_MANAGED_CHOICE
  kw_db_select_meta "$name" || return 2
  printf 'Sẽ xóa database %s và user %s@localhost của site %s. Source/site không bị xóa.\n' \
    "$name" "$KW_DB_SELECTED_USER" "$KW_DB_SELECTED_DOMAIN"
  printf 'Trước khi xóa sẽ export backup root-only. SQL DROP không thể hoàn tác trực tiếp.\n'
  kw_prompt_confirm_token "$name" 'Nhập lại đúng tên database để XÓA: ' || return 0
  kw_db_drop_named "$name" YES
}
