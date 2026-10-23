#!/usr/bin/env bash
# A single catalog drives both rendering and dispatch. No eval or dynamic commands.
kw_catalog() {
  case "$1" in
    main)
      printf '%s\n' 'Quản lý site|@sites' 'Quản lý SSL|@ssl' 'Quản lý SSH/AuthKey|@ssh' \
        'Quản lý DB|@db' 'Quản lý PHP|@php' 'Quản lý Nginx|@nginx' \
        'Quản lý Fail2ban|@fail2ban' 'Quản lý Tiện ích|@utilities' 'Quản lý cron|@cron' \
        'Quản lý cache|@cache' 'Quản lý swap|@swap' 'Quản lý Firewall|@firewall' \
        'Quản lý Disk|@disk' 'Quản lý Logs|@logs' 'Quản lý Update|@update' \
        'Sao lưu/phục hồi|@backup' 'Quản lý Cloudflare Tunnel|@tunnel' 'Công cụ nâng cao|@advanced' ;;
    sites) printf '%s\n' 'Danh sách Site|site-list' 'Thêm domain|site-add' 'Đổi tên miền|site-rename' 'Nhân bản site|site-clone' 'Xóa Site|site-remove' 'Phân lại quyền hạn|site-permissions' 'Laravel theo site|@laravel' ;;
    laravel) printf '%s\n' 'Chuẩn bị thư mục Laravel|site-laravel' 'Kiểm tra trạng thái/công cụ|laravel-status' 'Clone Git vào source|laravel-clone' 'Pull code|laravel-pull' 'Sửa .env riêng của site|laravel-env' 'Deploy release Laravel|laravel-deploy' ;;
    ssl) printf '%s\n' 'Xem SSL|ssl-status' 'Cấp SSL ACME|ssl-issue' 'Thêm paid SSL|ssl-paid' 'Domain không SSL|ssl-unsecured' 'Đổi ACME provider|acme-provider' ;;
    ssh) printf '%s\n' 'Đổi port SSH|pending' 'Đổi mật khẩu tài khoản SSH|ssh-password' 'Giới hạn đăng nhập|ssh-limits' 'Quản lý public key|ssh-keys' 'Chỉ cho phép AuthKey|pending' ;;
    db) printf '%s\n' 'Danh sách DB|db-managed-list' 'Danh sách User DB|db-users-list' 'Đổi Pass Database (User DB)|db-password' 'Tạo DB|db-custom-create' 'Xóa DB|db-drop-named' 'Import DB|db-import-upload' 'Export DB|db-export-named' ;;
    php) printf '%s\n' 'Danh sách PHP/package|packages' 'Kiểm tra bản vá PHP|php-security' 'Cấu hình PHP pool từng site|php-pool' 'Đổi PHP version theo site|php-switch' 'ionCube theo version|php-ioncube' 'Custom pool (nano)|php-custom' 'Cài gói PHP-FPM|php-install' ;;
    nginx) printf '%s\n' 'Phục hồi vhost HTTP của domain|nginx-restore' 'Áp baseline global|nginx-baseline' 'Kiểm tra cấu hình web server|nginx-check' 'Sửa vhost theo domain (nano)|nginx-vhost-custom' ;;
    fail2ban) printf '%s\n' 'Trạng thái và jail|fail2ban' 'Xem IP bị khóa|f2b-banned' 'Khóa IPv4 thủ công|f2b-ban' 'Mở khóa IPv4|f2b-unban' ;;
    utilities) printf '%s\n' 'Cài/kiểm tra quyền phpMyAdmin|pma-permissions' 'phpMyAdmin theo site|pma-site' 'phpMyAdmin admin tất cả DB|pma-admin' ;;
    cron) printf '%s\n' 'Xem crontab tài khoản hiện tại|cron' 'Xem crontab chung/root|cron-system' 'Custom root crontab (nano)|cron-nano' ;;
    cache) printf '%s\n' 'Xóa cache domain|cache-clear' 'Quản lý cache domain|cache-status' 'Quản lý Redis|cache-redis' 'Quản lý FastCGI|cache-fcgi' ;;
    swap) printf '%s\n' 'Xem swap|swap' 'Thêm swapfile KwVPS|swap-add' 'Xóa swapfile KwVPS|swap-remove' ;;
    firewall) printf '%s\n' 'Port listen và trạng thái UFW|ports' 'Mở port|fw-open-port' 'Khóa port|fw-close-port' 'Rule UFW/IP bị khóa|fw-list-ip' 'Khóa IPv4|fw-ban-ip' 'Mở khóa IPv4 KwVPS|fw-unban-ip' 'Bật Firewall UFW|fw-enable' 'Tắt Firewall UFW|fw-disable' ;;
    disk) printf '%s\n' 'Kiểm tra disk domain|site-disk' 'Tìm file lớn domain|site-large' ;;
    logs) printf '%s\n' 'Logs Nginx của domain|site-log' 'Nginx service journal|nginx-log' 'Journal PHP-FPM theo site|site-php-log' 'Database service journal|db-log' 'Dọn toàn bộ log|logs-cleanup' ;;
    update) printf '%s\n' 'Kiểm tra / cập nhật KwVPS|kwvps-update' 'Kiểm tra / cập nhật Ubuntu|ubuntu-update' 'Cập nhật service|@service-update' 'Cấu hình GitHub repository|github-repo' ;;
    service-update) printf '%s\n' 'Kiểm tra version package|packages' 'Package đang chờ update|pending-updates' 'Cập nhật service package an toàn|service-update-apply' ;;
    backup) printf '%s\n' 'Backup cấu hình domain|config-backup' 'Restore cấu hình domain|config-restore' 'Backup source/code|source-backup' 'Restore source/code|source-restore' 'Phục hồi site đã xóa|site-retired' 'Xóa Sạch site đã giữ|site-purge' 'Danh sách backup source/code|backup-list' 'Danh sách backup cấu hình domain|config-list' 'Kiểm tra backup source/code|backup-verify' 'Kiểm tra backup cấu hình domain|config-verify' ;;
    tunnel) printf '%s\n' 'Cấu hình Tunnel|tunnel-config' 'Trạng thái service|tunnel-status' 'Restart|tunnel-restart' 'Log Tunnel|tunnel-log' 'Xem version cloudflared|tunnel-version' 'Inbound 80/443|tunnel-inbound' ;;
    advanced) printf '%s\n' 'Bảo mật/Cloudflare|@cloudflare' ;;
    cloudflare) printf '%s\n' 'Cập nhật Cloudflare Real IP|cf-realip' 'AntiDDoS theo domain|cf-antiddos' 'Bật/tắt Under Attack|cf-under-attack' 'Cấu hình API token|@cf-token' ;;
    cf-token) printf '%s\n' 'Trạng thái API token|cf-token-status' 'Thêm/thay token theo site|cf-site-token-save' 'Hướng dẫn lấy token và cấp quyền|cf-token-guide' 'Xem/lưu Zone ID theo site|cf-zone-id' ;;
    *) return 2 ;;
  esac
}

kw_action() {
  local action=$1
  if [[ $action == pending ]]; then
    printf 'CHƯA TRIỂN KHAI: không thực hiện thay đổi nào.\n'
    return 3
  fi
  if ((KW_PREVIEW)); then
    printf 'PREVIEW: không thực thi truy vấn quản trị.\n'
    return 0
  fi
  case "$action" in
    packages) kw_packages ;;
    site-list) kw_site_list ;;
    site-add) kw_site_add_interactive ;;
    site-rename) kw_site_rename_interactive ;;
    site-clone) kw_site_clone_interactive ;;
    site-remove) kw_site_remove_interactive ;;
    site-permissions) kw_site_permissions_interactive ;;
    site-laravel) kw_site_laravel_interactive ;;
    laravel-status) kw_laravel_interactive status ;;
    laravel-clone) kw_laravel_interactive clone ;;
    laravel-pull) kw_laravel_interactive pull ;;
    laravel-env) kw_laravel_interactive env ;;
    laravel-deploy) kw_laravel_interactive deploy ;;
    site-retired) kw_site_retired_interactive ;;
    site-purge) kw_site_purge_interactive ;;
    site-disk) kw_site_disk_interactive ;;
    site-large) kw_site_large_interactive ;;
    site-log) kw_site_log_interactive ;;
    site-php-pool) kw_site_php_pool_interactive ;;
    php-pool) kw_php_pool_interactive ;;
    php-custom) kw_php_pool_custom_interactive ;;
    site-php-log) kw_site_php_log_interactive ;;
    php-switch) kw_php_switch_interactive ;;
    php-security) kw_php_security_status ;;
    php-install) kw_php_install_interactive ;;
    php-ioncube) kw_php_ioncube_interactive ;;
    db-list) kw_db_list ;;
    db-create) kw_db_create_interactive ;;
    db-export) kw_db_export_interactive ;;
    db-import) kw_db_import_interactive ;;
    db-drop) kw_db_drop_interactive ;;
    db-remote) kw_db_remote_interactive ;;
    db-managed-list) kw_db_managed_list ;;
    db-users-list) kw_db_users_list ;;
    db-password) kw_db_password_change_interactive ;;
    db-custom-create) kw_db_custom_create_interactive ;;
    db-drop-named) kw_db_drop_named_interactive ;;
    db-import-upload) kw_db_import_uploaded_interactive ;;
    db-export-named) kw_db_export_named_interactive ;;
    source-backup) kw_backup_source_interactive ;;
    source-restore) kw_restore_source_interactive ;;
    backup-list) kw_backup_list ;;
    backup-verify) kw_backup_verify_interactive ;;
    config-backup) kw_config_backup_interactive ;;
    config-restore) kw_config_restore_interactive ;;
    config-list) kw_config_backup_list ;;
    config-verify) kw_config_backup_verify_interactive ;;
    nginx-check) kw_nginx_check ;;
    nginx-restore) kw_nginx_restore_interactive ;;
    nginx-baseline) kw_nginx_baseline_interactive ;;
    nginx-vhost-custom) kw_nginx_vhost_custom_interactive ;;
    ssl-status) kw_ssl_status ;;
    ssl-unsecured) kw_ssl_status unsecured ;;
    ssl-issue) kw_ssl_issue_interactive ;;
    ssl-paid) kw_ssl_paid_interactive ;;
    acme-provider) kw_acme_provider_interactive ;;
    pending-updates) kw_pending ;;
    service-update-apply) kw_update_service_interactive ;;
    ubuntu-update) kw_update_ubuntu_interactive ;;
    kwvps-update) kw_update_kwvps_interactive ;;
    github-repo) kw_github_repo_interactive ;;
    cf-realip) kw_cf_realip_interactive ;;
    cf-antiddos) kw_cf_antiddos_interactive ;;
    cf-under-attack) kw_cf_under_attack_interactive ;;
    cf-token-status) kw_cf_token_status ;;
    cf-site-token-save) kw_cf_site_token_save_interactive ;;
    cf-token-guide) kw_cf_token_guide ;;
    cf-zone-id) kw_cf_zone_id_interactive ;;
    ssh-password) kw_ssh_password_interactive ;;
    ssh-limits) kw_ssh_limits_interactive ;;
    ssh-keys) kw_ssh_keys_interactive ;;
    ssh-key-only) kw_ssh_key_only_interactive ;;
    cache-redis) kw_cache_redis_interactive ;;
    cache-clear) kw_cache_clear_interactive ;;
    cache-status) kw_cache_status ;;
    cache-fcgi) kw_cache_manage_interactive ;;
    pma-permissions) kw_pma_permissions_interactive ;;
    pma-site) kw_pma_site_interactive ;;
    pma-admin) kw_pma_admin_interactive ;;
    ports) kw_ports ;;
    fw-open-port) kw_fw_port_interactive open ;;
    fw-close-port) kw_fw_port_interactive close ;;
    fw-enable) kw_fw_toggle_interactive enable ;;
    fw-disable) kw_fw_toggle_interactive disable ;;
    fw-list-ip) kw_fw_ip_list ;;
    fw-ban-ip) kw_fw_ip_interactive ban ;;
    fw-unban-ip) kw_fw_ip_interactive unban ;;
    swap) kw_swap ;;
    swap-add) kw_swap_change_interactive add ;;
    swap-remove) kw_swap_change_interactive remove ;;
    fail2ban) kw_fail2ban ;;
    f2b-banned) kw_f2b_banned_interactive ;;
    f2b-ban) kw_f2b_change_interactive banip ;;
    f2b-unban) kw_f2b_change_interactive unbanip ;;
    cron) kw_cron ;;
    cron-system) kw_cron_system_list ;;
    cron-nano) kw_cron_nano_interactive ;;
    nginx-log) kw_journal nginx ;;
    db-log) kw_journal mariadb ;;
    logs-cleanup) kw_logs_cleanup_interactive ;;
    tunnel-log) kw_journal cloudflared ;;
    tunnel-status) kw_tunnel_status ;;
    tunnel-config) kw_tunnel_config_interactive ;;
    tunnel-restart) kw_tunnel_restart_interactive ;;
    tunnel-version) kw_read_command cloudflared --version ;;
    tunnel-inbound) kw_tunnel_inbound_interactive ;;
    *) return 2 ;;
  esac
}

kw_menu_title() {
  case "$1" in
    main) printf 'Menu chính' ;; sites) printf 'Quản lý Sites' ;; laravel) printf 'Laravel theo site' ;;
    ssl) printf 'Quản lý SSL' ;; ssh) printf 'Quản lý SSH / AuthKey' ;;
    db) printf 'Quản lý Database' ;; php) printf 'Quản lý PHP' ;;
    nginx) printf 'Quản lý Nginx' ;; fail2ban) printf 'Quản lý Fail2ban' ;;
    utilities) printf 'Quản lý Tiện ích' ;; cron) printf 'Quản lý cron' ;;
    cache) printf 'Quản lý cache' ;; swap) printf 'Quản lý swap' ;;
    firewall) printf 'Quản lý Firewall' ;; disk) printf 'Quản lý Disk' ;;
    logs) printf 'Quản lý Logs' ;; update) printf 'Quản lý Update' ;;
    service-update) printf 'Cập nhật service' ;; backup) printf 'Sao lưu / phục hồi' ;;
    tunnel) printf 'Quản lý Cloudflare Tunnel' ;; advanced) printf 'Công cụ nâng cao' ;;
    cloudflare) printf 'Bảo mật / Cloudflare' ;; cf-token) printf 'Cấu hình API token' ;;
    *) return 2 ;;
  esac
}

kw_menu() {
  local page=$1 parent=${2:-} choice item title action i code first second page_title breadcrumb
  local -a entries quick_entries
  mapfile -t entries < <(kw_catalog "$page")
  page_title=$(kw_menu_title "$page") || return 2
  breadcrumb=$page_title
  [[ -z $parent ]] || breadcrumb="$parent / $page_title"
  while :; do
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then printf '\033[2J\033[H'; fi
    if [[ $page == main ]]; then kw_header; fi
    printf '\n%s\n' "$breadcrumb"
    printf '%s\n' '────────────────────────────────────────'
    i=0
    for item in "${entries[@]}"; do
      i=$((i + 1))
      title=${item%%|*}; action=${item#*|}
      [[ $action != pending ]] || title+=' [chưa triển khai]'
      printf '%2d. %s\n' "$i" "$title"
    done
    printf '%2d. %s\n' 0 "$([[ $page == main ]] && printf 'Thoát' || printf 'Quay lại')"
    printf '%s\n' '────────────────────────────────────────'
    if [[ $page == main ]]; then printf 'Gõ nhanh dạng 1.2 để vào menu 1, mục 2.\n'; fi
    printf 'Ctrl+C: thoát.\n'
    printf 'Chọn: '
    if ! IFS= read -r choice; then exit 0; fi
    [[ $choice != 0 ]] || return 0
    if [[ $page == main && $choice =~ ^([1-9][0-9]?)\.([1-9][0-9]?)$ ]]; then
      first=${BASH_REMATCH[1]}; second=${BASH_REMATCH[2]}
      if ((first > ${#entries[@]})); then printf 'Lựa chọn không hợp lệ.\n'; continue; fi
      item=${entries[first-1]}; action=${item#*|}
      if [[ $action != @* ]]; then printf 'Lựa chọn không hợp lệ.\n'; continue; fi
      mapfile -t quick_entries < <(kw_catalog "${action#@}")
      if ((second > ${#quick_entries[@]})); then printf 'Lựa chọn không hợp lệ.\n'; continue; fi
      item=${quick_entries[second-1]}; action=${item#*|}
    else
      if [[ ! $choice =~ ^[1-9][0-9]?$ ]] || ((choice > ${#entries[@]})); then
        printf 'Lựa chọn không hợp lệ.\n'
        continue
      fi
      item=${entries[choice-1]}; action=${item#*|}
    fi
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then printf '\033[2J\033[H'; fi
    if [[ $action == @* ]]; then
      kw_menu "${action#@}" "$breadcrumb"
    else
      code=0
      printf '%s / %s\n\n' "$breadcrumb" "${item%%|*}"
      kw_action "$action" || code=$?
      if ((code != 0 && code != 3)); then
        printf 'Không hoàn thành truy vấn (mã %d); xem thông báo phía trên.\n' "$code"
      fi
      if [[ $action == laravel-status && $code == 0 ]]; then continue; fi
      printf '\nEnter để quay lại: '
      if ! IFS= read -r choice; then exit 0; fi
    fi
  done
}
