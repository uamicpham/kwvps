#!/usr/bin/env bash
# Rename a pristine HTTP site while preserving its source and numeric UID/GID.
# External DNS, application URLs, certificates and independent backups are not rewritten.

kw_site_rename_plan() {
  local old=${1,,} new=${2,,} old_id new_id php file name count=0
  kw_site_lookup "$old" || return 2
  old_id=${KW_SITE_OWNER#kw}; php=$KW_SITE_PHP
  kw_site_new_domain_valid "$new" && [[ $old != "$new" ]] || return 2
  new_id=$(kw_site_id "$new") || return 2
  [[ $old_id != "$new_id" ]] || return 2
  printf 'Đổi domain %s → %s (PHP %s).\n' "$old" "$new" "$php"
  printf 'Site ID/user: %s → %s. Source, pool, socket, vhost và metadata sẽ chuyển theo ID mới.\n' "$old_id" "$new_id"
  printf 'Chỉ hỗ trợ vhost HTTP nguyên bản. Nhãn DNS và Nginx rate limit local (nếu có) sẽ chuyển theo tên miền; SSL, DNS bên ngoài, URL ứng dụng, cron, Tunnel và backup độc lập không tự đổi.\n'
  local ingress_mode
  ingress_mode=$(kw_tunnel_site_mode "$old") || return 2
  if [[ $ingress_mode != dns ]]; then
    printf 'Ingress hiện tại: %s. Route Tunnel/DNS ngoài VPS KHÔNG tự đổi; site có thể gián đoạn cho đến khi bạn cập nhật Cloudflare.\n' "$ingress_mode"
  fi
  if [[ -f /etc/kwvps/cloudflare/antiddos/$old.rate ]]; then
    printf 'Nginx rate limit local: %s req/s → %s.\n' "$(< "/etc/kwvps/cloudflare/antiddos/$old.rate")" "$new"
  fi
  if [[ -f /etc/kwvps/db/$old_id.db ]]; then
    printf 'Có DB legacy gắn ID cũ; cần xử lý riêng, thao tác sẽ từ chối.\n'
  fi
  for file in /etc/kwvps/db-custom/*.db; do
    [[ -f $file && ! -L $file ]] || continue
    grep -Fxq "domain=$old" "$file" || continue
    name=${file##*/}; name=${name%.db}; count=$((count + 1))
    printf 'DB liên kết sẽ chuyển metadata (không đổi tên DB/user): %s\n' "$name"
  done
  ((count)) || printf 'Không có DB tự đặt tên gắn domain này.\n'
  printf 'Có thể gián đoạn HTTP/PHP ngắn trong lúc đổi. Bản cấu hình cũ được giữ root-only.\n'
}

kw_site_rename_preflight() {
  local old=$1 new=$2 old_id new_id old_owner old_root old_pool old_vhost old_meta old_link php file name zone_cache rate_state digest root_cron cron_status=0 ingress ingress_file new_ingress_file old_local_rate new_local_rate rate_value
  ((EUID == 0)) && kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  kw_site_lookup "$old" || return 2
  old_id=${KW_SITE_OWNER#kw}; old_owner=$KW_SITE_OWNER; old_root=$KW_SITE_ROOT
  old_pool=$KW_SITE_POOL; old_vhost=$KW_SITE_VHOST; old_meta=$KW_SITE_META; old_link=$KW_SITE_ENABLED; php=$KW_SITE_PHP
  kw_site_new_domain_valid "$new" && [[ $old != "$new" ]] || return 2
  new_id=$(kw_site_id "$new") || return 2
  [[ $new_id != "$old_id" ]] || return 2
  # A rename cannot leave the old hostname in external Cloudflare rules,
  # tunnel routes, local rate states or independent backup references.
  digest=$(printf '%s' "$old" | sha256sum) || return 2
  digest=${digest%% *}
  zone_cache="/etc/kwvps/cloudflare/zone-${digest}.id"
  rate_state="/etc/kwvps/cloudflare/kwvps-rate-${digest:0:16}.state"
  for file in \
    "/etc/kwvps/cloudflare/antiddos/$old.push" \
    "$zone_cache" "$rate_state"; do
    [[ ! -e $file && ! -L $file ]] || {
      kw_log ERROR "Đổi tên chưa hỗ trợ tài nguyên phụ thuộc: $file. Giữ nguyên site để tránh cấu hình cũ sót lại."
      return 2
    }
  done
  old_local_rate="/etc/kwvps/cloudflare/antiddos/$old.rate"
  new_local_rate="/etc/kwvps/cloudflare/antiddos/$new.rate"
  [[ ! -e $new_local_rate && ! -L $new_local_rate ]] || {
    kw_log ERROR 'Domain đích đã có Nginx rate limit; không ghi đè.'; return 2;
  }
  if [[ -e $old_local_rate || -L $old_local_rate ]]; then
    [[ -f $old_local_rate && ! -L $old_local_rate &&
       $(stat -c %u:%a -- "$old_local_rate") == 0:600 ]] || return 2
    IFS= read -r rate_value < "$old_local_rate" || return 2
    kw_cf_antiddos_rate_valid "$rate_value" && [[ $rate_value != off ]] || return 2
    # shellcheck disable=SC2154 # Defined by sourced cloudflare.sh.
    [[ -f $kw_cf_antiddos_conf && ! -L $kw_cf_antiddos_conf &&
       $(stat -c %u -- "$kw_cf_antiddos_conf") == 0 ]] || return 2
    cmp -s -- "$kw_cf_antiddos_conf" <(kw_cf_antiddos_render) || {
      kw_log ERROR 'Cấu hình anti-DDoS Nginx đã tùy chỉnh; không đổi tên tự động.'; return 2;
    }
  fi
  ingress=$(kw_tunnel_site_mode "$old") || return 2
  if [[ $ingress != dns && ( -e $old_local_rate || -L $old_local_rate ) ]]; then
    kw_log ERROR 'Site có Nginx rate limit nhưng không xác nhận DNS trực tiếp; cần tắt rate limit hoặc ghi nhận ingress trước khi đổi.'
    return 2
  fi
  ingress_file="/etc/kwvps/ingress/$old.mode"
  new_ingress_file="/etc/kwvps/ingress/$new.mode"
  [[ ! -e $new_ingress_file && ! -L $new_ingress_file ]] || {
    kw_log ERROR 'Domain đích đã có nhãn ingress; không ghi đè.'; return 2;
  }
  if [[ -e $ingress_file || -L $ingress_file ]]; then
    [[ -f $ingress_file && ! -L $ingress_file &&
       $(stat -c %u:%a -- "$ingress_file") == 0:600 &&
       ( $(< "$ingress_file") == dns || $(< "$ingress_file") == tunnel ) ]] || return 2
  fi
  root_cron=$(LC_ALL=C crontab -u root -l 2>&1) || cron_status=$?
  if ((cron_status != 0)) && [[ $root_cron != 'no crontab for root' ]]; then
    kw_log ERROR 'Không đọc được root cron; từ chối đổi tên để tránh bỏ sót lịch chạy.'
    return 2
  fi
  if [[ $root_cron == *"$old"* || $root_cron == *"$old_id"* ]]; then
    kw_log ERROR 'Root cron có tham chiếu site cũ; cần chỉnh cron có kiểm soát trước khi đổi tên.'
    return 2
  fi
  cmp -s -- "$old_vhost" <(kw_site_render_vhost "$old" "$old_id") || {
    kw_log ERROR 'Đổi tên chỉ hỗ trợ vhost HTTP nguyên bản; không đụng SSL/cấu hình tùy biến.'; return 2;
  }
  cmp -s -- "$old_pool" <(kw_site_render_pool "$old_id" "$old_owner") || {
    kw_log ERROR 'Pool PHP đã tùy chỉnh; cần sao lưu và đưa về mẫu trước khi đổi tên.'; return 2;
  }
  [[ -L $old_link && $(readlink -- "$old_link") == "$old_vhost" && \
     -f $old_meta && ! -L $old_meta && $(stat -c %u -- "$old_meta") == 0 ]] || return 2
  [[ -d $old_root && ! -L $old_root && $(stat -c %U -- "$old_root") == "$old_owner" ]] || return 2
  [[ $(getent passwd "$old_owner" | cut -d: -f6) == "$old_root" ]] || return 2
  getent group "$old_owner" >/dev/null || return 2
  [[ ! -e /etc/kwvps/db/$old_id.db && ! -L /etc/kwvps/db/$old_id.db ]] || {
    kw_log ERROR 'Site có DB legacy gắn site ID cũ; chưa thể đổi tên an toàn.'; return 2;
  }
  kw_site_find_retired "$new" || return 2
  ((${#KW_RETIRED_MATCHES[@]} == 0)) || { kw_log ERROR 'Domain đích đang trong vùng giữ.'; return 2; }
  for file in /etc/kwvps/db-custom/*.db; do
    [[ -f $file && ! -L $file ]] || continue
    grep -Fxq "domain=$old" "$file" || continue
    name=${file##*/}; name=${name%.db}
    kw_db_custom_meta "$name" || return 2
    [[ $KW_DB_SELECTED_DOMAIN == "$old" && $(grep -Fc 'domain=' "$file") == 1 ]] || return 2
  done
  kw_site_preflight "$new" "$php" "$new_id" || return 2
  nginx -t >/dev/null 2>&1 && "php-fpm${php}" -t >/dev/null 2>&1 || return 2
}

kw_site_rename_rollback() {
  ((KW_RENAME_DONE == 0)) || return 0
  local file name
  if [[ -f $KW_RENAME_STAGE/local-rate && ! -L $KW_RENAME_STAGE/local-rate ]]; then
    [[ ! -e $KW_RENAME_NEW_RATE && ! -L $KW_RENAME_NEW_RATE ]] || rm -f -- "$KW_RENAME_NEW_RATE"
    install -m 0600 -o root -g root -- "$KW_RENAME_STAGE/local-rate" "$KW_RENAME_OLD_RATE" ||
      kw_log ERROR 'Cần phục hồi Nginx rate state.'
    install -m 0644 -o root -g root -- "$KW_RENAME_STAGE/antiddos.conf" "$kw_cf_antiddos_conf" ||
      kw_log ERROR 'Cần phục hồi Nginx anti-DDoS global.'
  fi
  if [[ -d $KW_RENAME_STAGE/db ]]; then
    for file in "$KW_RENAME_STAGE"/db/*.db; do
      [[ -f $file && ! -L $file ]] || continue
      name=${file##*/}
      install -m 0600 -o root -g root -- "$file" "/etc/kwvps/db-custom/$name" ||
        kw_log ERROR "Cần khôi phục DB metadata: $file"
    done
  fi
  if [[ -f $KW_RENAME_STAGE/ingress.mode && ! -L $KW_RENAME_STAGE/ingress.mode ]]; then
    [[ ! -e $KW_RENAME_NEW_INGRESS && ! -L $KW_RENAME_NEW_INGRESS ]] ||
      rm -f -- "$KW_RENAME_NEW_INGRESS"
    [[ -e $KW_RENAME_OLD_INGRESS || -L $KW_RENAME_OLD_INGRESS ]] ||
      install -m 0600 -o root -g root -- "$KW_RENAME_STAGE/ingress.mode" "$KW_RENAME_OLD_INGRESS"
  fi
  [[ ! -L $KW_RENAME_NEW_LINK ]] || rm -f -- "$KW_RENAME_NEW_LINK"
  [[ ! -f $KW_RENAME_NEW_VHOST ]] || rm -f -- "$KW_RENAME_NEW_VHOST"
  [[ ! -f $KW_RENAME_NEW_META ]] || rm -f -- "$KW_RENAME_NEW_META"
  [[ ! -f $KW_RENAME_NEW_POOL ]] || rm -f -- "$KW_RENAME_NEW_POOL"
  if [[ -d $KW_RENAME_NEW_ROOT && ! -e $KW_RENAME_OLD_ROOT ]]; then
    mv -T -- "$KW_RENAME_NEW_ROOT" "$KW_RENAME_OLD_ROOT" || kw_log ERROR "Cần trả source: $KW_RENAME_NEW_ROOT"
  fi
  if ((KW_RENAME_HOME)); then
    usermod --home "$KW_RENAME_OLD_ROOT" -- "$KW_RENAME_NEW_OWNER" || kw_log ERROR 'Cần trả home của user site.'
  fi
  if ((KW_RENAME_GROUP)); then
    groupmod --new-name "$KW_RENAME_OLD_OWNER" -- "$KW_RENAME_NEW_OWNER" || kw_log ERROR 'Cần trả group site.'
  fi
  if ((KW_RENAME_USER)); then
    usermod --login "$KW_RENAME_OLD_OWNER" -- "$KW_RENAME_NEW_OWNER" || kw_log ERROR 'Cần trả tên user site.'
  fi
  for name in pool vhost meta link; do
    case "$name" in
      pool) file=$KW_RENAME_OLD_POOL ;;
      vhost) file=$KW_RENAME_OLD_VHOST ;;
      meta) file=$KW_RENAME_OLD_META ;;
      link) file=$KW_RENAME_OLD_LINK ;;
    esac
    [[ ! -e $file && ! -L $file ]] || continue
    [[ ! -e $KW_RENAME_STAGE/$name && ! -L $KW_RENAME_STAGE/$name ]] ||
      mv -T -- "$KW_RENAME_STAGE/$name" "$file" || kw_log ERROR "Cần trả file: $file"
  done
  if ! { "php-fpm${KW_RENAME_PHP}" -t >/dev/null 2>&1 && systemctl reload "php${KW_RENAME_PHP}-fpm"; }; then
    kw_log ERROR 'Cần kiểm tra PHP-FPM sau rollback đổi tên.'
  fi
  if ! { nginx -t >/dev/null 2>&1 && systemctl reload nginx; }; then
    kw_log ERROR 'Cần kiểm tra Nginx sau rollback đổi tên.'
  fi
  kw_log WARN "Giữ bản cấu hình cũ tại $KW_RENAME_STAGE để kiểm tra."
}

kw_site_rename_locked() (
  local old=$1 new=$2 old_id new_id file name temp
  # shellcheck disable=SC2034 # Rollback trap reads these variables.
  local KW_RENAME_DONE=0 KW_RENAME_USER=0 KW_RENAME_GROUP=0 KW_RENAME_HOME=0
  local KW_RENAME_STAGE='' KW_RENAME_OLD_OWNER='' KW_RENAME_NEW_OWNER=''
  local KW_RENAME_OLD_ROOT='' KW_RENAME_NEW_ROOT='' KW_RENAME_OLD_POOL='' KW_RENAME_NEW_POOL=''
  local KW_RENAME_OLD_VHOST='' KW_RENAME_NEW_VHOST='' KW_RENAME_OLD_META='' KW_RENAME_NEW_META=''
  local KW_RENAME_OLD_LINK='' KW_RENAME_NEW_LINK='' KW_RENAME_PHP=''
  local KW_RENAME_OLD_INGRESS="/etc/kwvps/ingress/$old.mode"
  local KW_RENAME_NEW_INGRESS="/etc/kwvps/ingress/$new.mode"
  local KW_RENAME_OLD_RATE="/etc/kwvps/cloudflare/antiddos/$old.rate"
  local KW_RENAME_NEW_RATE="/etc/kwvps/cloudflare/antiddos/$new.rate"
  kw_site_rename_preflight "$old" "$new" || return 2
  kw_site_lookup "$old" || return 2
  old_id=${KW_SITE_OWNER#kw}; KW_RENAME_PHP=$KW_SITE_PHP
  KW_RENAME_OLD_OWNER=$KW_SITE_OWNER; KW_RENAME_OLD_ROOT=$KW_SITE_ROOT
  KW_RENAME_OLD_POOL=$KW_SITE_POOL; KW_RENAME_OLD_VHOST=$KW_SITE_VHOST
  KW_RENAME_OLD_META=$KW_SITE_META; KW_RENAME_OLD_LINK=$KW_SITE_ENABLED
  new_id=$(kw_site_id "$new") || return 2
  kw_site_paths "$new_id" "$KW_RENAME_PHP"
  KW_RENAME_NEW_OWNER=$KW_SITE_OWNER; KW_RENAME_NEW_ROOT=$KW_SITE_ROOT
  KW_RENAME_NEW_POOL=$KW_SITE_POOL; KW_RENAME_NEW_VHOST=$KW_SITE_VHOST
  KW_RENAME_NEW_META=$KW_SITE_META; KW_RENAME_NEW_LINK=$KW_SITE_ENABLED
  if [[ ! -e $KW_BACKUP_ROOT && ! -L $KW_BACKUP_ROOT ]]; then
    install -d -m 0700 -o root -g root -- "$KW_BACKUP_ROOT" || return 1
  fi
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  KW_RENAME_STAGE=$(mktemp -d "$KW_BACKUP_ROOT/rename-${old_id}-XXXXXXXX") || return 1
  chmod 0700 -- "$KW_RENAME_STAGE" || return 1
  trap kw_site_rename_rollback EXIT
  kw_site_render_pool "$new_id" "$KW_RENAME_NEW_OWNER" > "$KW_RENAME_STAGE/new-pool" || return 1
  kw_site_render_vhost "$new" "$new_id" > "$KW_RENAME_STAGE/new-vhost" || return 1
  printf 'domain=%s\nsite_id=%s\nphp_version=%s\nowner=%s\n' \
    "$new" "$new_id" "$KW_RENAME_PHP" "$KW_RENAME_NEW_OWNER" > "$KW_RENAME_STAGE/new-meta" || return 1
  install -d -m 0700 -- "$KW_RENAME_STAGE/db" || return 1
  for file in /etc/kwvps/db-custom/*.db; do
    [[ -f $file && ! -L $file ]] || continue
    grep -Fxq "domain=$old" "$file" || continue
    name=${file##*/}
    install -m 0600 -o root -g root -- "$file" "$KW_RENAME_STAGE/db/$name" || return 1
  done
  if [[ -f $KW_RENAME_OLD_INGRESS ]]; then
    install -m 0600 -o root -g root -- "$KW_RENAME_OLD_INGRESS" "$KW_RENAME_STAGE/ingress.mode" || return 1
  fi
  if [[ -f $KW_RENAME_OLD_RATE ]]; then
    install -m 0600 -o root -g root -- "$KW_RENAME_OLD_RATE" "$KW_RENAME_STAGE/local-rate" || return 1
    install -m 0644 -o root -g root -- "$kw_cf_antiddos_conf" "$KW_RENAME_STAGE/antiddos.conf" || return 1
  fi
  printf 'Đang đổi site; bản cấu hình cũ sẽ giữ tại %s\n' "$KW_RENAME_STAGE"
  mv -T -- "$KW_RENAME_OLD_LINK" "$KW_RENAME_STAGE/link" || return 1
  mv -T -- "$KW_RENAME_OLD_VHOST" "$KW_RENAME_STAGE/vhost" || return 1
  mv -T -- "$KW_RENAME_OLD_POOL" "$KW_RENAME_STAGE/pool" || return 1
  mv -T -- "$KW_RENAME_OLD_META" "$KW_RENAME_STAGE/meta" || return 1
  nginx -t >/dev/null || return 1
  systemctl reload nginx || return 1
  "php-fpm${KW_RENAME_PHP}" -t >/dev/null || return 1
  systemctl reload "php${KW_RENAME_PHP}-fpm" || return 1
  usermod --login "$KW_RENAME_NEW_OWNER" -- "$KW_RENAME_OLD_OWNER" || return 1
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  KW_RENAME_USER=1
  groupmod --new-name "$KW_RENAME_NEW_OWNER" -- "$KW_RENAME_OLD_OWNER" || return 1
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  KW_RENAME_GROUP=1
  usermod --home "$KW_RENAME_NEW_ROOT" -- "$KW_RENAME_NEW_OWNER" || return 1
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  KW_RENAME_HOME=1
  mv -T -- "$KW_RENAME_OLD_ROOT" "$KW_RENAME_NEW_ROOT" || return 1
  install -m 0644 -o root -g root -- "$KW_RENAME_STAGE/new-pool" "$KW_RENAME_NEW_POOL" || return 1
  install -m 0644 -o root -g root -- "$KW_RENAME_STAGE/new-vhost" "$KW_RENAME_NEW_VHOST" || return 1
  ln -s -- "$KW_RENAME_NEW_VHOST" "$KW_RENAME_NEW_LINK" || return 1
  install -m 0644 -o root -g root -- "$KW_RENAME_STAGE/new-meta" "$KW_RENAME_NEW_META" || return 1
  for file in "$KW_RENAME_STAGE"/db/*.db; do
    [[ -f $file && ! -L $file ]] || continue
    name=${file##*/}
    temp=$(mktemp "$KW_DB_CUSTOM_DIR/.rename.XXXXXXXX") || return 1
    awk -F= -v old="$old" -v new="$new" '
      $1 == "domain" && $2 == old { print "domain=" new; next } { print }
    ' "$file" > "$temp" || return 1
    chmod 0600 -- "$temp" || return 1
    mv -T -- "$temp" "$KW_DB_CUSTOM_DIR/$name" || return 1
  done
  if [[ -f $KW_RENAME_STAGE/ingress.mode ]]; then
    install -m 0600 -o root -g root -- "$KW_RENAME_STAGE/ingress.mode" "$KW_RENAME_NEW_INGRESS" || return 1
    rm -f -- "$KW_RENAME_OLD_INGRESS" || return 1
  fi
  if [[ -f $KW_RENAME_STAGE/local-rate ]]; then
    install -m 0600 -o root -g root -- "$KW_RENAME_STAGE/local-rate" "$KW_RENAME_NEW_RATE" || return 1
    rm -f -- "$KW_RENAME_OLD_RATE" || return 1
    temp=$(mktemp /etc/nginx/conf.d/.kwvps-antiddos-rename.XXXXXXXX) || return 1
    kw_cf_antiddos_render > "$temp" || return 1
    chmod 0644 -- "$temp" || return 1
    mv -T -- "$temp" "$kw_cf_antiddos_conf" || return 1
  fi
  "php-fpm${KW_RENAME_PHP}" -t >/dev/null || return 1
  nginx -t >/dev/null || return 1
  systemctl reload "php${KW_RENAME_PHP}-fpm" || return 1
  systemctl reload nginx || return 1
  curl --fail --silent --show-error --noproxy '*' --max-time 8 -H "Host: $new" http://127.0.0.1/ >/dev/null || return 1
  kw_site_lookup "$new" || return 1
  [[ $KW_SITE_OWNER == "$KW_RENAME_NEW_OWNER" ]] || return 1
  # shellcheck disable=SC2034 # Read by EXIT rollback trap.
  KW_RENAME_DONE=1
  printf 'Đã đổi %s → %s. Cập nhật DNS/route Tunnel và URL ứng dụng; cấp SSL riêng cho domain mới.\n' "$old" "$new"
)

kw_site_rename() (
  local old=${1,,} new=${2,,} confirm=${3:-}
  kw_domain_valid "$old" && kw_domain_valid "$new" && [[ $old != "$new" && $confirm == yes ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || return 1
  exec 8>/run/lock/kwvps-nginx.lock || return 2
  flock -n 8 || return 1
  exec 7>/run/lock/kwvps-cloudflare.lock || return 2
  flock -n 7 || return 1
  kw_site_rename_locked "$old" "$new"
)

kw_site_rename_interactive() {
  # shellcheck disable=SC2034 # Read by the nested rename preflight/transaction.
  local old new KW_PHP_EOL_SITE_ACK=0
  kw_site_prompt_domain || return 0
  old=$KW_SITE_CHOICE
  kw_site_lookup "$old" || return 2
  if [[ $KW_SITE_PHP == 7.4 ]]; then
    printf 'CẢNH BÁO: site đang chạy PHP 7.4 đã hết hỗ trợ. Đổi tên sẽ giữ nguyên phiên bản EOL và rủi ro bảo mật của nó.\n'
    kw_prompt_yes_no_token 'Tôi hiểu và vẫn muốn đổi tên site đang dùng PHP 7.4?' 'RENAME-EOL-PHP:7.4' || return 0
    KW_PHP_EOL_SITE_ACK=1
  fi
  while :; do
    printf 'Domain mới (0 để quay lại): '
    IFS= read -r new || return 0
    [[ $new != 0 && -n $new ]] || return 0
    new=${new,,}
    kw_site_new_domain_valid "$new" && [[ $new != "$old" ]] && break
    printf 'Domain không hợp lệ, quá dài hoặc đã tồn tại/trùng site ID. Nhập lại.\n'
  done
  kw_site_rename_plan "$old" "$new" || return 2
  kw_site_rename_preflight "$old" "$new" || return 2
  kw_prompt_yes_no_token "Đổi tên $old thành $new?" yes || return 0
  kw_site_rename "$old" "$new" "$KW_PROMPT_VALUE"
}
