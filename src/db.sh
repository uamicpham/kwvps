#!/usr/bin/env bash
# KwVPS-owned MariaDB databases. Credentials stay in root-only metadata.

kw_db_names() {
  local id=$1
  kw_site_id_valid "$id" || return 2
  KW_DB_NAME="kwdb_${id}"
  KW_DB_USER="kwu_${id}"
  KW_DB_META="/etc/kwvps/db/${id}.db"
}

kw_db_sql_create() {
  local id=$1 password=$2
  kw_db_names "$id" || return 2
  [[ $password =~ ^[0-9a-f]{48}$ ]] || return 2
  # shellcheck disable=SC2016 # SQL identifier backticks are literal.
  printf 'CREATE DATABASE `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\n' "$KW_DB_NAME"
  printf "CREATE USER '%s'@'localhost' IDENTIFIED BY '%s';\n" "$KW_DB_USER" "$password"
  printf "GRANT ALL PRIVILEGES ON \`%s\`.* TO '%s'@'localhost';\n" "$KW_DB_NAME" "$KW_DB_USER"
}

kw_db_ready() {
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root để quản lý MariaDB.'; return 2; }
  kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && \
     $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  if ! kw_has mariadb || ! kw_has openssl || ! kw_has flock; then
    kw_log ERROR 'Thiếu MariaDB client, openssl hoặc flock.'; return 2;
  fi
  systemctl is-active --quiet mariadb || { kw_log ERROR 'MariaDB chưa hoạt động.'; return 2; }
  mariadb --protocol=socket -uroot --batch --skip-column-names -e 'SELECT 1' >/dev/null || return 2
}

kw_db_exists() {
  local id=$1 count
  kw_db_names "$id" || return 2
  count=$(mariadb --protocol=socket -uroot --batch --skip-column-names \
    -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='${KW_DB_NAME}'") || return 2
  [[ $count == 1 ]]
}

kw_db_plan() {
  local domain=${1,,} id
  kw_site_lookup "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  kw_db_names "$id" || return 2
  printf 'Kế hoạch tạo MariaDB cho site (chưa thay đổi hệ thống):\n'
  printf '  Domain: %s\n  Database: %s\n  User: %s@localhost\n' "$domain" "$KW_DB_NAME" "$KW_DB_USER"
  printf '  Mật khẩu ngẫu nhiên lưu root-only tại %s; không bật truy cập từ xa.\n' "$KW_DB_META"
}

kw_db_rollback() {
  ((KW_DB_DONE == 0)) || return 0
  if ((KW_DB_USER_CREATED)); then
    printf "DROP USER IF EXISTS '%s'@'localhost';\n" "$KW_DB_USER" | \
      mariadb --protocol=socket -uroot >/dev/null || kw_log WARN 'Cần gỡ user DB thủ công.'
  fi
  if ((KW_DB_CREATED)); then
    # shellcheck disable=SC2016 # SQL identifier backticks are literal.
    printf 'DROP DATABASE IF EXISTS `%s`;\n' "$KW_DB_NAME" | \
      mariadb --protocol=socket -uroot >/dev/null || kw_log WARN 'Cần gỡ DB thủ công.'
  fi
  if [[ -n $KW_DB_TMP && -f $KW_DB_TMP && ! -L $KW_DB_TMP ]]; then
    rm -f -- "$KW_DB_TMP"
  fi
}

kw_db_create_locked() (
  local domain=$1 id count password
  local KW_DB_DONE=0 KW_DB_CREATED=0 KW_DB_USER_CREATED=0 KW_DB_TMP=''
  kw_db_ready || return 2
  kw_site_lookup "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  kw_db_names "$id" || return 2
  [[ ! -e $KW_DB_META && ! -L $KW_DB_META ]] || { kw_log ERROR 'Site đã có metadata DB.'; return 2; }
  local exists_status=0
  kw_db_exists "$id" || exists_status=$?
  if ((exists_status == 0)); then kw_log ERROR 'Database đã tồn tại.'; return 2; fi
  ((exists_status == 1)) || return 2
  count=$(mariadb --protocol=socket -uroot --batch --skip-column-names \
    -e "SELECT COUNT(*) FROM mysql.user WHERE User='${KW_DB_USER}' AND Host='localhost'") || return 2
  [[ $count == 0 ]] || { kw_log ERROR 'User DB đã tồn tại.'; return 2; }
  [[ -d /etc/kwvps && ! -L /etc/kwvps && $(stat -c %u /etc/kwvps) == 0 ]] || return 2
  install -d -m 0700 -o root -g root -- /etc/kwvps/db || return 1
  [[ -d /etc/kwvps/db && ! -L /etc/kwvps/db && \
     $(stat -c %u /etc/kwvps/db) == 0 && $(stat -c %a /etc/kwvps/db) == 700 ]] || return 2
  password=$(openssl rand -hex 24) || return 1
  [[ $password =~ ^[0-9a-f]{48}$ ]] || return 1
  KW_DB_TMP=$(mktemp "/etc/kwvps/db/.${id}.XXXXXXXX") || return 1
  trap kw_db_rollback EXIT
  chmod 0600 -- "$KW_DB_TMP" || return 1
  printf 'site_id=%s\ndatabase=%s\nuser=%s\npassword=%s\n' \
    "$id" "$KW_DB_NAME" "$KW_DB_USER" "$password" > "$KW_DB_TMP" || return 1
  # shellcheck disable=SC2016 # SQL identifier backticks are literal.
  printf 'CREATE DATABASE `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\n' "$KW_DB_NAME" | \
    mariadb --protocol=socket -uroot || return 1
  KW_DB_CREATED=1
  printf "CREATE USER '%s'@'localhost' IDENTIFIED BY '%s';\n" "$KW_DB_USER" "$password" | \
    mariadb --protocol=socket -uroot || return 1
  KW_DB_USER_CREATED=1
  printf "GRANT ALL PRIVILEGES ON \`%s\`.* TO '%s'@'localhost';\n" "$KW_DB_NAME" "$KW_DB_USER" | \
    mariadb --protocol=socket -uroot || return 1
  mv -T -- "$KW_DB_TMP" "$KW_DB_META" || return 1
  KW_DB_TMP=''
  KW_DB_DONE=1
  printf 'Đã tạo %s cho %s. Thông tin kết nối ở %s (root-only).\n' \
    "$KW_DB_NAME" "$domain" "$KW_DB_META"
)

kw_db_create() (
  local domain=${1,,} confirm=${2:-}
  kw_domain_valid "$domain" || return 2
  [[ $confirm == "$domain" ]] || { kw_log ERROR 'Xác nhận domain không khớp.'; return 2; }
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-db.lock || return 2
  flock -n 9 || { kw_log ERROR 'Một thao tác DB khác đang chạy.'; return 1; }
  kw_db_create_locked "$domain"
)

kw_db_list() {
  local file id database user key value
  kw_db_ready || return 2
  printf '%-30s %-30s %s\n' 'SITE ID' 'DATABASE' 'USER'
  for file in /etc/kwvps/db/*.db; do
    [[ -f $file && ! -L $file ]] || continue
    id=''; database=''; user=''
    while IFS='=' read -r key value; do
      case "$key" in
        site_id) id=$value ;;
        database) database=$value ;;
        user) user=$value ;;
      esac
    done < "$file"
    if ! kw_site_id_valid "$id" ||
       [[ $database != "kwdb_${id}" || $user != "kwu_${id}" ||
          $file != "/etc/kwvps/db/${id}.db" ]]; then
      kw_log WARN "Bỏ qua metadata DB không hợp lệ: $file"; continue;
    fi
    printf '%-30s %-30s %s\n' "$id" "$database" "$user"
  done
  printf 'Danh sách chỉ gồm DB có metadata KwVPS; không in mật khẩu.\n'
}

kw_db_prompt_domain() {
  local file id domain key value choice count=0
  local -a domains=()
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo để xem database.'; return 2; }
  printf 'Chọn database KwVPS:\n'
  for file in /etc/kwvps/db/*.db; do
    [[ -f $file && ! -L $file ]] || continue
    id=${file##*/}; id=${id%.db}
    kw_site_id_valid "$id" || continue
    [[ -f /etc/kwvps/sites/$id.site && ! -L /etc/kwvps/sites/$id.site ]] || continue
    domain=''
    while IFS='=' read -r key value; do
      [[ $key != domain ]] || domain=$value
    done < "/etc/kwvps/sites/$id.site"
    kw_domain_valid "$domain" || continue
    [[ $(kw_site_id "$domain") == "$id" ]] || continue
    kw_db_meta_lookup "$domain" >/dev/null 2>&1 || continue
    domains+=("$domain")
    count=$((count + 1))
    printf '%2d. %-28s %s\n' "$count" "kwdb_$id" "$domain"
  done
  if ((count == 0)); then printf 'Chưa có database KwVPS.\n'; return 1; fi
  printf ' 0. Quay lại\nChọn số database: '
  IFS= read -r choice || return 1
  [[ $choice =~ ^[1-9][0-9]*$ ]] && ((choice <= count)) || return 1
  KW_DB_CHOICE=${domains[choice-1]}
}

kw_db_meta_lookup() {
  local domain=${1,,} id key value meta_id='' database='' user='' password=''
  kw_site_lookup "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  kw_db_names "$id" || return 2
  [[ -f $KW_DB_META && ! -L $KW_DB_META && \
     $(stat -c %u "$KW_DB_META") == 0 && $(stat -c %a "$KW_DB_META") == 600 ]] || return 2
  while IFS='=' read -r key value; do
    case "$key" in
      site_id) meta_id=$value ;;
      database) database=$value ;;
      user) user=$value ;;
      password) password=$value ;;
    esac
  done < "$KW_DB_META"
  [[ $meta_id == "$id" && $database == "$KW_DB_NAME" && \
     $user == "$KW_DB_USER" && $password =~ ^[a-zA-Z0-9_!@#%+=.\-]{12,128}$ ]] || return 2
  KW_DB_PASSWORD=$password
}

kw_db_export_plan() {
  local domain=${1,,}
  kw_db_ready || return 2
  kw_db_meta_lookup "$domain" || return 2
  printf 'Kế hoạch export MariaDB (chưa thay đổi hệ thống):\n'
  printf '  Domain: %s\n  Database: %s\n  Nơi lưu: %s/db-%s-YYYYMMDD-HHMMSS.sql.gz\n' \
    "$domain" "$KW_DB_NAME" "$KW_BACKUP_ROOT" "$KW_DB_NAME"
  printf '  Dump root-only, không chứa mật khẩu kết nối; không tạo file checksum riêng.\n'
}

kw_db_export_locked() (
  local domain=$1 id timestamp tmp='' final='' suffix=1
  kw_db_ready || return 2
  kw_db_meta_lookup "$domain" || return 2
  kw_db_exists "${KW_SITE_OWNER#kw}" || return 2
  kw_has mariadb-dump && kw_has gzip || return 2
  kw_backup_dir_safe /var/backups 0022 || return 2
  if [[ ! -e $KW_BACKUP_ROOT && ! -L $KW_BACKUP_ROOT ]]; then
    install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT" || return 1
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  id=${KW_SITE_OWNER#kw}
  timestamp=$(date -u +%Y%m%d-%H%M%S) || return 1
  tmp=$(mktemp "$KW_BACKUP_ROOT/.db-${id}.XXXXXXXX") || return 1
  trap '[[ -z $tmp ]] || rm -f -- "$tmp"' EXIT
  chmod 0600 -- "$tmp" || return 1
  if ! mariadb-dump --protocol=socket -uroot --single-transaction --quick \
      --routines --events --triggers "$KW_DB_NAME" | gzip -c > "$tmp"; then
    kw_log ERROR 'Export MariaDB thất bại; không công bố gói.'; return 1
  fi
  [[ -s $tmp ]] && gzip -t -- "$tmp" || return 1
  final="$KW_BACKUP_ROOT/db-${KW_DB_NAME}-${timestamp}.sql.gz"
  while [[ -e $final || -L $final || -e $final.sha256 || -L $final.sha256 ]]; do
    suffix=$((suffix + 1))
    ((suffix <= 9999)) || return 1
    final="$KW_BACKUP_ROOT/db-${KW_DB_NAME}-${timestamp}-${suffix}.sql.gz"
  done
  # The root-only backup directory and DB lock prevent normal concurrent writes.
  # ln still refuses a destination created between the check and publication.
  ln -- "$tmp" "$final" || return 1
  rm -f -- "$tmp" || return 1
  tmp=''
  printf 'Đã export %s: %s\n' "$KW_DB_NAME" "$final"
  printf 'Chưa thử import; file trên cùng VPS không thay thế backup ngoài máy.\n'
)

kw_db_export() (
  local domain=${1,,} confirm=${2:-}
  kw_domain_valid "$domain" || return 2
  [[ $confirm == "$domain" ]] || { kw_log ERROR 'Xác nhận domain không khớp.'; return 2; }
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-db.lock || return 2
  flock -n 9 || return 1
  kw_db_export_locked "$domain"
)

kw_db_export_interactive() {
  local domain confirm
  kw_db_prompt_domain || return 0
  domain=$KW_DB_CHOICE
  kw_db_export_plan "$domain" || return 2
  kw_prompt_yes_no_token "Export DB của $domain?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_db_export "$domain" "${confirm,,}"
}

kw_db_backup_name_valid() {
  local name=${1:-}
  [[ $name =~ ^db-kwdb_[a-z0-9]{1,29}-[0-9]{8}-[0-9]{6}(-[2-9]|-[1-9][0-9]+)?\.sql\.gz$ ]] ||
    [[ $name =~ ^db-[a-z0-9]{1,29}-[0-9]{8}T[0-9]{6}Z-[[:alnum:]]{8}\.sql\.gz$ ]]
}

kw_db_backup_for_site() {
  local id=$1 name=$2
  kw_site_id_valid "$id" && kw_db_backup_name_valid "$name" || return 1
  [[ $name == "db-kwdb_${id}-"* || $name == "db-${id}-"* ]]
}

kw_db_backup_list() {
  local file name
  ((EUID == 0)) || return 2
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  for file in "$KW_BACKUP_ROOT"/db-*.sql.gz; do
    [[ -f $file && ! -L $file ]] || continue
    name=${file##*/}
    kw_db_backup_name_valid "$name" || continue
    printf '%s\n' "$name"
  done
}

kw_db_choose_backup() {
  local id=$1 file name choice count=0
  local -a names=()
  kw_site_id_valid "$id" || return 2
  ((EUID == 0)) || return 2
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  printf 'Chọn backup database:\n'
  for file in "$KW_BACKUP_ROOT"/"db-kwdb_${id}-"*.sql.gz "$KW_BACKUP_ROOT"/"db-${id}-"*.sql.gz; do
    [[ -f $file && ! -L $file ]] || continue
    name=${file##*/}
    kw_db_backup_for_site "$id" "$name" || continue
    names+=("$name")
    count=$((count + 1))
    printf '%2d. %s\n' "$count" "$name"
  done
  if ((count == 0)); then printf 'Không có backup DB phù hợp.\n'; return 1; fi
  printf ' 0. Quay lại\nChọn số backup: '
  IFS= read -r choice || return 1
  [[ $choice =~ ^[1-9][0-9]*$ ]] && ((choice <= count)) || return 1
  KW_DB_BACKUP_CHOICE=${names[choice-1]}
}

kw_db_backup_verify() {
  local name=$1 path line expected stored actual had_checksum=0
  ((EUID == 0)) || return 2
  kw_db_backup_name_valid "$name" || return 2
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  path="$KW_BACKUP_ROOT/$name"
  [[ -f $path && ! -L $path ]] || return 2
  if [[ -e $path.sha256 || -L $path.sha256 ]]; then
    [[ -f $path.sha256 && ! -L $path.sha256 ]] || return 2
    IFS= read -r line < "$path.sha256" || return 2
    expected=${line%%  *}; stored=${line#*  }
    [[ $expected =~ ^[0-9a-f]{64}$ && $line == "$expected  $name" && $stored == "$name" ]] || return 2
    actual=$(sha256sum -- "$path") || return 2
    [[ ${actual%% *} == "$expected" ]] || return 2
    had_checksum=1
  fi
  gzip -t -- "$path" || return 2
  if ((had_checksum)); then
    printf 'Backup DB đạt kiểm tra SHA-256 và gzip: %s\n' "$name"
  else
    printf 'Backup DB đọc được bằng gzip (không có checksum riêng): %s\n' "$name"
  fi
  printf 'Chưa chứng minh SQL import hoặc dữ liệu ứng dụng nhất quán.\n'
}

kw_db_import_plan() {
  local domain=${1,,} name=$2 id
  kw_db_ready || return 2
  kw_db_meta_lookup "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  kw_db_backup_for_site "$id" "$name" || return 2
  kw_db_backup_verify "$name" || return 2
  printf 'Kế hoạch import DB: %s → %s (%s)\n' "$name" "$KW_DB_NAME" "$domain"
  printf 'Không tự export DB hiện tại. Hãy tự backup nếu cần trước khi xác nhận.\n'
  printf 'Import không nguyên tử và không tự hoàn tác; nếu SQL lỗi, DB có thể chỉ được khôi phục một phần.\n'
}

kw_db_import_locked() (
  local domain=$1 name=$2 id option_file=''
  kw_db_ready || return 2
  kw_db_meta_lookup "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  kw_db_backup_for_site "$id" "$name" || return 2
  kw_db_backup_verify "$name" >/dev/null || return 2
  kw_db_exists "$id" || return 2
  option_file=$(mktemp /run/kwvps-db-client.XXXXXXXX) || return 1
  trap '[[ -z $option_file ]] || rm -f -- "$option_file"' EXIT
  chmod 0600 -- "$option_file" || return 1
  printf '[client]\nuser=%s\npassword=%s\n' "$KW_DB_USER" "$KW_DB_PASSWORD" > "$option_file" || return 1
  if ! gzip -cd -- "$KW_BACKUP_ROOT/$name" | \
      mariadb --defaults-extra-file="$option_file" --protocol=socket "$KW_DB_NAME"; then
    kw_log ERROR 'Import lỗi; DB có thể ở trạng thái một phần và không có bản export tự động để hoàn tác.'
    return 1
  fi
  printf 'Đã import %s vào %s. Cần kiểm tra dữ liệu ứng dụng.\n' "$name" "$KW_DB_NAME"
)

kw_db_import() (
  local domain=${1,,} name=$2 confirm=${3:-}
  kw_domain_valid "$domain" || return 2
  [[ $confirm == "$domain" ]] || { kw_log ERROR 'Xác nhận domain không khớp.'; return 2; }
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-db.lock || return 2
  flock -n 9 || return 1
  kw_db_import_locked "$domain" "$name"
)

kw_db_import_interactive() {
  local domain name confirm
  kw_db_prompt_domain || return 0
  domain=$KW_DB_CHOICE
  kw_db_choose_backup "$(kw_site_id "$domain")" || return 0
  name=$KW_DB_BACKUP_CHOICE
  kw_db_import_plan "$domain" "$name" || return 2
  kw_prompt_yes_no_token "Import DB cho $domain?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_db_import "$domain" "$name" "${confirm,,}"
}

kw_db_drop_plan() {
  local domain=${1,,}
  kw_db_ready || return 2
  kw_db_meta_lookup "$domain" || return 2
  printf 'Kế hoạch xóa DB KwVPS: %s (%s)\n' "$KW_DB_NAME" "$domain"
  printf 'Tự export trước khi DROP; giữ metadata cũ trong vùng root-only.\n'
  printf 'Source site, Nginx, PHP và các backup khác không bị xóa.\n'
}

kw_db_drop_locked() (
  local domain=$1 id archive
  kw_db_ready || return 2
  kw_db_meta_lookup "$domain" || return 2
  id=${KW_SITE_OWNER#kw}
  kw_db_exists "$id" || return 2
  kw_db_export_locked "$domain" || return 1
  install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT/db-retired" || return 1
  kw_backup_dir_safe "$KW_BACKUP_ROOT/db-retired" 0077 || return 2
  archive="$KW_BACKUP_ROOT/db-retired/${id}-$(date -u +%Y%m%dT%H%M%SZ).db"
  [[ ! -e $archive && ! -L $archive ]] || return 2
  # shellcheck disable=SC2016 # SQL identifier backticks are literal.
  printf 'DROP DATABASE `%s`;\n' "$KW_DB_NAME" | mariadb --protocol=socket -uroot || return 1
  printf "DROP USER '%s'@'localhost';\n" "$KW_DB_USER" | mariadb --protocol=socket -uroot || {
    kw_log ERROR 'DB đã xóa nhưng user DB còn lại; cần xử lý thủ công trước khi tạo lại.'
    return 1
  }
  mv -T -- "$KW_DB_META" "$archive" || {
    kw_log ERROR 'DB và user đã xóa nhưng metadata chưa chuyển được; cần xử lý thủ công.'
    return 1
  }
  printf 'Đã xóa DB %s; metadata cũ giữ tại %s\n' "$KW_DB_NAME" "$archive"
  printf 'Backup trước khi xóa nằm trong %s.\n' "$KW_BACKUP_ROOT"
)

kw_db_drop() (
  local domain=${1,,} confirm=${2:-}
  kw_domain_valid "$domain" || return 2
  [[ $confirm == "$domain" ]] || { kw_log ERROR 'Xác nhận domain không khớp.'; return 2; }
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-db.lock || return 2
  flock -n 9 || return 1
  kw_db_drop_locked "$domain"
)

kw_db_drop_interactive() {
  local domain confirm
  kw_db_prompt_domain || return 0
  domain=$KW_DB_CHOICE
  kw_db_drop_plan "$domain" || return 2
  kw_prompt_confirm_domain "$domain" 'Nhập lại đúng domain để xóa DB: ' || return 0
  confirm=$KW_PROMPT_VALUE
  kw_db_drop "$domain" "${confirm,,}"
}

kw_db_create_interactive() {
  local domain confirm
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_db_plan "$domain" || return 2
  kw_prompt_yes_no_token "Tạo DB cho $domain?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_db_create "$domain" "${confirm,,}"
}

# Remote administration uses an SSH local forward. MariaDB remains bound to
# loopback and the per-site account remains restricted to localhost.
kw_db_remote_plan() {
  local domain=${1,,} local_port=${2:-3307}
  kw_domain_valid "$domain" || return 2
  kw_port_valid "$local_port" || return 2
  kw_db_ready || return 2
  kw_db_meta_lookup "$domain" || return 2
  kw_db_exists "${KW_SITE_OWNER#kw}" || return 2
  printf 'Truy cập DB từ xa qua SSH tunnel cho %s (không thay đổi VPS):\n' "$domain"
  printf '  Database: %s\n  User: %s\n' "$KW_DB_NAME" "$KW_DB_USER"
  printf '  Trên máy tính của bạn: ssh -N -L %s:127.0.0.1:3306 <ssh-user>@<vps-ip>\n' "$local_port"
  printf '  Ứng dụng DB trên máy tính: host 127.0.0.1, port %s.\n' "$local_port"
  printf '  Đọc mật khẩu trên VPS bằng sudo tại %s; không gửi qua chat.\n' "$KW_DB_META"
  printf 'MariaDB vẫn chỉ nghe loopback. Không mở UFW/3306; tunnel cần SSH hoạt động.\n'
}

kw_db_remote_interactive() {
  local domain local_port
  kw_db_prompt_domain || return 0
  domain=$KW_DB_CHOICE
  printf 'Cổng cục bộ trên máy tính [3307]: '
  IFS= read -r local_port || return 0
  kw_db_remote_plan "$domain" "${local_port:-3307}"
}
