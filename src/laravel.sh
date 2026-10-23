#!/usr/bin/env bash
# Generic, per-site Laravel releases. Never execute an application-provided deploy.sh.

kw_laravel_git_url_valid() {
  local url=${1:-}
  [[ $url =~ ^https://[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+([.]git)?$ ||
     $url =~ ^git@[A-Za-z0-9.-]+:[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+([.]git)?$ ||
     $url =~ ^ssh://git@[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+([.]git)?$ ]] || return 1
  [[ $url != *..* && $url != *'@'*'@'* ]]
}

kw_laravel_branch_valid() {
  local branch=${1:-}
  [[ $branch =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,100}$ &&
     $branch != *..* && $branch != *//* && $branch != */ &&
     $branch != *.lock && $branch != *'@{'* ]]
}

kw_laravel_frontend_valid() {
  case "${1:-}" in auto|none|npm|pnpm|yarn) return 0 ;; *) return 1 ;; esac
}

kw_laravel_layout_ready() {
  local domain=$1 path mode
  kw_site_lookup "$domain" || return 2
  for path in "$KW_SITE_ROOT" "$KW_SITE_ROOT/source" "$KW_SITE_ROOT/deploy" \
    "$KW_SITE_ROOT/deploy/releases" "$KW_SITE_ROOT/deploy/shared" \
    "$KW_SITE_ROOT/deploy/shared/storage"; do
    [[ -d $path && ! -L $path && $(stat -c %U -- "$path") == "$KW_SITE_OWNER" ]] || {
      kw_log ERROR "Thiếu cấu trúc Laravel an toàn: $path. Chạy 'Chuẩn bị thư mục Laravel' trước."
      return 2
    }
    mode=$(stat -c %a -- "$path") || return 2
    [[ $mode =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0022) == 0 )) || {
      kw_log ERROR "Thư mục Laravel có quyền ghi nhóm/khách không an toàn: $path"; return 2;
    }
  done
}

kw_laravel_status() {
  local domain=$1 tool current
  kw_laravel_layout_ready "$domain" || return 2
  printf 'Laravel: %s (PHP %s)\n' "$domain" "$KW_SITE_PHP"
  for tool in git composer "php$KW_SITE_PHP" npm pnpm yarn; do
    if kw_has "$tool"; then printf '  %-12s sẵn sàng\n' "$tool"
    else printf '  %-12s chưa cài\n' "$tool"; fi
  done
  if [[ -d $KW_SITE_ROOT/source/.git && ! -L $KW_SITE_ROOT/source/.git ]]; then
    printf '  Git source: đã clone\n'
  else
    printf '  Git source: chưa clone\n'
  fi
  if [[ -f $KW_SITE_ROOT/deploy/shared/.env && ! -L $KW_SITE_ROOT/deploy/shared/.env ]]; then
    printf '  .env: đã có (không hiển thị nội dung)\n'
  else
    printf '  .env: chưa có\n'
  fi
  current=$KW_SITE_ROOT/deploy/current
  if [[ -L $current ]]; then
    printf '  Release hiện tại: %s\n' "$(readlink -- "$current")"
  else
    printf '  Release hiện tại: chưa kích hoạt\n'
  fi
  printf 'Composer cần gói composer của Ubuntu hoặc bản chính thức; frontend cần công cụ khớp lockfile dự án.\n'
}

kw_laravel_git_source() {
  local source=$KW_SITE_ROOT/source owner=$KW_SITE_OWNER
  [[ -d $source/.git && ! -L $source/.git &&
     $(stat -c %U -- "$source/.git") == "$owner" ]] || {
    kw_log ERROR 'Source chưa phải Git checkout KwVPS quản lý.'; return 2;
  }
  runuser -u "$owner" -- git -C "$source" rev-parse --is-inside-work-tree 2>/dev/null |
    grep -Fxq true || return 2
}

kw_laravel_clone_locked() (
  local domain=$1 url=$2 branch=$3 source
  kw_laravel_layout_ready "$domain" || return 2
  kw_laravel_git_url_valid "$url" && kw_laravel_branch_valid "$branch" || {
    kw_log ERROR 'URL Git hoặc tên nhánh không hợp lệ. Dùng HTTPS công khai hoặc SSH git@host.'; return 2;
  }
  kw_has git && kw_has runuser || { kw_log ERROR 'Thiếu git/runuser trên VPS.'; return 2; }
  source=$KW_SITE_ROOT/source
  [[ -z $(find "$source" -mindepth 1 -maxdepth 1 -print -quit) ]] || {
    kw_log ERROR 'source/ không rỗng; không ghi đè repository đã có.'; return 2;
  }
  printf 'Đang clone nhánh %s cho %s bằng user %s...\n' "$branch" "$domain" "$KW_SITE_OWNER"
  runuser -u "$KW_SITE_OWNER" -- git clone --branch "$branch" --single-branch -- "$url" "$source" || return 1
  kw_laravel_git_source || return 1
  printf 'Đã clone vào %s. Không chạy script từ repository hoặc đổi website.\n' "$source"
)

kw_laravel_pull_locked() (
  local domain=$1 branch=$2 source current origin status
  kw_laravel_layout_ready "$domain" && kw_laravel_git_source || return 2
  kw_laravel_branch_valid "$branch" || return 2
  source=$KW_SITE_ROOT/source
  current=$(runuser -u "$KW_SITE_OWNER" -- git -C "$source" symbolic-ref --quiet --short HEAD) || return 2
  [[ $current == "$branch" ]] || {
    kw_log ERROR "Checkout đang ở nhánh $current; không tự chuyển nhánh."; return 2;
  }
  origin=$(runuser -u "$KW_SITE_OWNER" -- git -C "$source" remote get-url origin) || return 2
  kw_laravel_git_url_valid "$origin" || {
    kw_log ERROR 'Git origin có URL không được hỗ trợ hoặc có thể chứa credential.'; return 2;
  }
  status=$(runuser -u "$KW_SITE_OWNER" -- git -C "$source" status --porcelain) || return 2
  [[ -z $status ]] || { kw_log ERROR 'source/ có thay đổi chưa commit; không pull đè.'; return 2; }
  runuser -u "$KW_SITE_OWNER" -- git -C "$source" fetch --no-tags origin "$branch" || return 1
  runuser -u "$KW_SITE_OWNER" -- git -C "$source" merge --ff-only FETCH_HEAD || return 1
  printf 'Đã cập nhật source/ tới commit %s. Website chưa đổi cho đến khi triển khai.\n' \
    "$(runuser -u "$KW_SITE_OWNER" -- git -C "$source" rev-parse --short=12 HEAD)"
)

kw_laravel_env_edit_locked() (
  local domain=$1 env_file example
  kw_laravel_layout_ready "$domain" || return 2
  [[ -t 0 && -t 1 ]] && kw_has nano || {
    kw_log ERROR 'Cần terminal tương tác và nano để sửa .env.'; return 2;
  }
  env_file=$KW_SITE_ROOT/deploy/shared/.env
  example=$KW_SITE_ROOT/source/.env.example
  [[ ! -L $env_file ]] || return 2
  if [[ ! -e $env_file ]]; then
    if [[ -f $example && ! -L $example ]]; then
      runuser -u "$KW_SITE_OWNER" -- install -m 0600 -- "$example" "$env_file" || return 1
    else
      runuser -u "$KW_SITE_OWNER" -- install -m 0600 /dev/null "$env_file" || return 1
    fi
  fi
  [[ -f $env_file && $(stat -c '%U:%a' -- "$env_file") == "$KW_SITE_OWNER:600" ]] || {
    kw_log ERROR '.env có owner/quyền không an toàn; không mở file.'; return 2;
  }
  runuser -u "$KW_SITE_OWNER" -- nano "$env_file"
)

kw_laravel_vhost_template() {
  local kind=$1 domain=$2 id=$3
  case "$kind" in
    http) kw_site_render_vhost "$domain" "$id" ;;
    letsencrypt) kw_ssl_render_vhost "$domain" "$id" letsencrypt ;;
    zerossl) kw_ssl_render_vhost "$domain" "$id" zerossl ;;
    paid) kw_ssl_render_paid_vhost "$domain" "$id" ;;
    *) return 2 ;;
  esac
}

kw_laravel_render_vhost() {
  local kind=$1 domain=$2 id=$3 old new
  old="/var/www/kwvps/$id/public"
  new="/var/www/kwvps/$id/deploy/current/public"
  printf '# KwVPS Laravel release root\n'
  kw_laravel_vhost_template "$kind" "$domain" "$id" | awk -v old="$old" -v new="$new" '
    $0 == "  root " old ";" { print "  root " new ";"; next }
    $0 == "  location ^~ /.well-known/acme-challenge/ {" {
      print; print "    root " old ";"; next
    }
    { print }
  '
}

kw_laravel_vhost_kind() {
  local domain=$1 id=$2 kind
  for kind in http letsencrypt zerossl paid; do
    if cmp -s -- "$KW_SITE_VHOST" <(kw_laravel_vhost_template "$kind" "$domain" "$id"); then
      KW_LARAVEL_VHOST_KIND=$kind
      KW_LARAVEL_FIRST=1
      return 0
    fi
    if cmp -s -- "$KW_SITE_VHOST" <(kw_laravel_render_vhost "$kind" "$domain" "$id"); then
      KW_LARAVEL_VHOST_KIND=$kind
      KW_LARAVEL_FIRST=0
      return 0
    fi
  done
  kw_log ERROR 'Vhost đã tùy chỉnh hoặc không thuộc mẫu KwVPS; không tự đổi document root.'
  return 2
}

kw_laravel_health() {
  local domain=$1 kind=$2 code url
  if [[ $kind == http ]]; then
    url="http://$domain/"
    code=$(curl --silent --show-error --noproxy '*' --max-time 12 \
      --resolve "$domain:80:127.0.0.1" -o /dev/null -w '%{http_code}' "$url") || return 1
  else
    url="https://$domain/"
    code=$(curl --silent --show-error --noproxy '*' --max-time 12 \
      --resolve "$domain:443:127.0.0.1" -o /dev/null -w '%{http_code}' "$url") || return 1
  fi
  [[ $code =~ ^[1-4][0-9][0-9]$ ]] || {
    kw_log ERROR "Health check trả HTTP $code; sẽ quay lại release cũ."; return 1;
  }
  printf 'Health check %s: HTTP %s\n' "$domain" "$code"
}

kw_laravel_deploy_locked() (
  local domain=$1 frontend=${2:-auto} id source deploy releases shared owner php commit short stamp stage='' release='' archive='' changes command lock_count=0 \
    current next='' previous='' kind first vhost_backup='' vhost_temp='' activated=0 success=0
  kw_laravel_frontend_valid "$frontend" || return 2
  kw_laravel_layout_ready "$domain" && kw_laravel_git_source || return 2
  kw_nginx_ready || return 2
  for command in git tar composer curl "php$KW_SITE_PHP"; do
    kw_has "$command" || { kw_log ERROR "Thiếu $command; chưa đổi website. Cài công cụ này trước."; return 2; }
  done
  id=${KW_SITE_OWNER#kw}; source=$KW_SITE_ROOT/source; deploy=$KW_SITE_ROOT/deploy
  releases=$deploy/releases; shared=$deploy/shared; owner=$KW_SITE_OWNER; php=$KW_SITE_PHP
  current=$deploy/current
  [[ -f $KW_SITE_VHOST && ! -L $KW_SITE_VHOST && $(stat -c %u -- "$KW_SITE_VHOST") == 0 &&
     -L $KW_SITE_ENABLED && $(readlink -- "$KW_SITE_ENABLED") == "$KW_SITE_VHOST" ]] || return 2
  kw_laravel_vhost_kind "$domain" "$id" || return 2
  kind=$KW_LARAVEL_VHOST_KIND; first=$KW_LARAVEL_FIRST
  [[ -f $shared/.env && ! -L $shared/.env &&
     $(stat -c '%U:%a' -- "$shared/.env") == "$owner:600" ]] || {
    kw_log ERROR 'Thiếu deploy/shared/.env an toàn; dùng menu Sửa .env trước.'; return 2;
  }
  if ((first)); then
    [[ ! -e $current && ! -L $current ]] || return 2
  else
    [[ -L $current ]] || return 2
    previous=$(readlink -- "$current") || return 2
    [[ $previous == releases/* && $previous != *..* && -d $deploy/$previous ]] || return 2
  fi
  [[ ! -e $source/.gitmodules && ! -L $source/.gitmodules ]] || {
    kw_log ERROR 'Repository dùng Git submodule; chưa hỗ trợ triển khai tự động.'; return 2;
  }
  changes=$(runuser -u "$owner" -- git -C "$source" status --porcelain) || return 2
  [[ -z $changes ]] || {
    kw_log ERROR 'source/ có thay đổi chưa commit; không triển khai.'; return 2;
  }
  commit=$(runuser -u "$owner" -- git -C "$source" rev-parse --verify HEAD) || return 2
  short=${commit:0:12}; stamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
  release=$releases/$stamp-$short
  [[ ! -e $release && ! -L $release ]] || { kw_log ERROR 'Tên release đã tồn tại; thử lại sau một giây.'; return 2; }
  stage=$(runuser -u "$owner" -- mktemp -d "$releases/.build-XXXXXXXX") || return 1
  [[ $stage == "$releases"/.build-* && -d $stage && ! -L $stage ]] || return 2
  # Keep a failed staging directory for inspection. Never delete application files implicitly.
  printf 'Đang tạo release %s từ commit %s...\n' "$release" "$short"
  archive=$stage/.kwvps-source.tar
  runuser -u "$owner" -- git -C "$source" archive --format=tar --output="$archive" HEAD || return 1
  runuser -u "$owner" -- tar -C "$stage" -xf "$archive" || return 1
  runuser -u "$owner" -- rm -f -- "$archive" || return 1
  [[ -f $stage/artisan && -f $stage/public/index.php && -f $stage/composer.json && ! -L $stage/composer.json &&
     -f $stage/composer.lock && ! -L $stage/composer.lock &&
     ! -L $stage/public && ! -L $stage/artisan && ! -e $stage/.env && ! -L $stage/.env ]] || {
    kw_log ERROR 'Cần cấu trúc Laravel chuẩn, composer.lock và không commit .env; không kích hoạt.'; return 2;
  }
  [[ -z $(find -P "$stage/public" -type l -print -quit) ]] || {
    kw_log ERROR 'public/ chứa symlink chưa được xác minh; không triển khai để tránh lộ file riêng.'; return 2;
  }
  [[ ! -L $stage/package.json ]] || {
    kw_log ERROR 'package.json là symlink; không chạy build từ đường dẫn bên ngoài release.'; return 2;
  }
  if [[ -e $stage/storage || -L $stage/storage ]]; then
    [[ -d $stage/storage && ! -L $stage/storage &&
       -z $(find "$stage/storage" -type f ! -name .gitignore -print -quit) ]] || {
      kw_log ERROR 'Repository chứa dữ liệu storage; không tự thay bằng storage dùng chung.'; return 2;
    }
    runuser -u "$owner" -- rm -rf -- "$stage/storage" || return 1
  fi
  [[ ! -e $stage/public/storage && ! -L $stage/public/storage ]] || {
    kw_log ERROR 'public/storage đã tồn tại; không ghi đè.'; return 2;
  }
  runuser -u "$owner" -- ln -s ../../shared/.env "$stage/.env" || return 1
  runuser -u "$owner" -- ln -s ../../shared/storage "$stage/storage" || return 1
  runuser -u "$owner" -- ln -s ../../../shared/storage/app/public "$stage/public/storage" || return 1
  runuser -u "$owner" -- "php$php" "$(command -v composer)" install --working-dir="$stage" \
    --no-dev --prefer-dist --optimize-autoloader --no-interaction || return 1
  if [[ $frontend == auto && -f $stage/package.json ]]; then
    [[ ! -f $stage/package-lock.json ]] || { frontend=npm; lock_count=$((lock_count + 1)); }
    [[ ! -f $stage/pnpm-lock.yaml ]] || { frontend=pnpm; lock_count=$((lock_count + 1)); }
    [[ ! -f $stage/yarn.lock ]] || { frontend=yarn; lock_count=$((lock_count + 1)); }
    ((lock_count == 1)) || {
      kw_log ERROR 'Không xác định được một lockfile frontend; chọn cách build cụ thể hoặc bỏ qua.'; return 2;
    }
  elif [[ $frontend == auto ]]; then
    frontend=none
  fi
  case "$frontend" in
    none)
      [[ ! -f $stage/package.json ]] || printf 'Bỏ qua frontend theo lựa chọn; cần bảo đảm assets đã có trong public/.\n' ;;
    npm)
      [[ -f $stage/package.json && -f $stage/package-lock.json && ! -L $stage/package-lock.json ]] && kw_has npm || {
        kw_log ERROR 'Cần package.json, package-lock.json và npm.'; return 2;
      }
      runuser -u "$owner" -- npm ci --prefix "$stage" || return 1
      runuser -u "$owner" -- npm run build --prefix "$stage" || return 1 ;;
    pnpm)
      [[ -f $stage/package.json && -f $stage/pnpm-lock.yaml && ! -L $stage/pnpm-lock.yaml ]] && kw_has pnpm || {
        kw_log ERROR 'Cần package.json, pnpm-lock.yaml và pnpm.'; return 2;
      }
      runuser -u "$owner" -- pnpm --dir "$stage" install --frozen-lockfile || return 1
      runuser -u "$owner" -- pnpm --dir "$stage" run build || return 1 ;;
    yarn)
      [[ -f $stage/package.json && -f $stage/yarn.lock && ! -L $stage/yarn.lock ]] && kw_has yarn || {
        kw_log ERROR 'Cần package.json, yarn.lock và yarn.'; return 2;
      }
      runuser -u "$owner" -- yarn --cwd "$stage" install --frozen-lockfile || return 1
      runuser -u "$owner" -- yarn --cwd "$stage" build || return 1 ;;
  esac
  [[ -z $(find -P "$stage/public" -type l ! -path "$stage/public/storage" -print -quit) ]] || {
    kw_log ERROR 'Build tạo symlink trong public/; không kích hoạt để tránh lộ file riêng.'; return 2;
  }
  [[ -f $stage/vendor/autoload.php && -f $stage/public/index.php ]] || return 2
  chown -h -- "$owner:www-data" "$stage" || return 1
  runuser -u "$owner" -- chmod 0750 "$stage" || return 1
  find -P "$stage/public" -type d -exec chown -h -- "$owner:www-data" '{}' + || return 1
  find -P "$stage/public" -type f -exec chown -h -- "$owner:www-data" '{}' + || return 1
  runuser -u "$owner" -- find "$stage/public" -type d -exec chmod 0750 '{}' + || return 1
  runuser -u "$owner" -- find "$stage/public" -type f -exec chmod 0640 '{}' + || return 1
  runuser -u "$owner" -- mv -T -- "$stage" "$release" || return 1
  stage=''
  next=$deploy/.current-next-$$
  [[ ! -e $next && ! -L $next ]] || return 2
  runuser -u "$owner" -- ln -s "releases/${release##*/}" "$next" || return 1
  if ((first)); then
    nginx -t >/dev/null || return 2
    kw_nginx_backup_file "$KW_SITE_VHOST" "laravel-$id" || return 1
    vhost_backup=$KW_NGINX_BACKUP
    vhost_temp=$(mktemp /etc/nginx/sites-available/.kwvps-laravel.XXXXXXXX) || return 1
    kw_laravel_render_vhost "$kind" "$domain" "$id" > "$vhost_temp" || return 1
    chmod 0644 -- "$vhost_temp" || return 1
  fi
  trap 'if ((activated && ! success)); then if [[ -n $previous ]]; then ln -sfn -- "$previous" "$next" && mv -Tf -- "$next" "$current" || kw_log ERROR "Không thể quay lại release cũ: $current"; else rm -f -- "$current" || kw_log ERROR "Không thể bỏ current: $current"; fi; if [[ -n $vhost_backup ]]; then install -m 0644 -o root -g root -- "$vhost_backup" "$KW_SITE_VHOST" || kw_log ERROR "Cần phục hồi vhost từ $vhost_backup"; fi; kw_nginx_test_restart || kw_log ERROR "Cần kiểm tra Nginx sau rollback: $domain"; fi; [[ -z $vhost_temp ]] || rm -f -- "$vhost_temp"; [[ -z $next ]] || rm -f -- "$next"' EXIT
  runuser -u "$owner" -- mv -Tf -- "$next" "$current" || return 1
  activated=1
  if ((first)); then
    mv -Tf -- "$vhost_temp" "$KW_SITE_VHOST" || return 1
    vhost_temp=''
  fi
  kw_nginx_test_restart || return 1
  kw_laravel_health "$domain" "$kind" || return 1
  success=1
  printf 'Đã triển khai %s: %s. Release trước vẫn được giữ để quay lại nếu cần.\n' "$domain" "$release"
)

kw_laravel_with_lock() (
  local action=$1 domain=$2
  shift 2
  ((EUID == 0)) || { kw_log ERROR 'Cần sudo/root.'; return 2; }
  kw_domain_valid "$domain" && kw_has flock || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || return 1
  if [[ $action == deploy ]]; then
    exec 8>/run/lock/kwvps-nginx.lock || return 2
    flock -n 8 || return 1
  fi
  case "$action" in
    clone) kw_laravel_clone_locked "$domain" "$@" ;;
    pull) kw_laravel_pull_locked "$domain" "$@" ;;
    env) kw_laravel_env_edit_locked "$domain" ;;
    deploy) kw_laravel_deploy_locked "$domain" "$@" ;;
    *) return 2 ;;
  esac
)

kw_laravel_interactive() {
  local action=$1 domain url branch frontend choice
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_laravel_layout_ready "$domain" || return 2
  case "$action" in
    status) kw_laravel_status "$domain" ;;
    clone)
      kw_prompt_validated 'Git URL (HTTPS công khai hoặc git@host): ' kw_laravel_git_url_valid \
        'Không chứa token/userinfo/query' plain || return 0
      url=$KW_PROMPT_VALUE
      kw_prompt_validated 'Nhánh (ví dụ main): ' kw_laravel_branch_valid 'Tên nhánh Git hợp lệ' plain || return 0
      branch=$KW_PROMPT_VALUE
      kw_prompt_yes_no_token "Clone $branch vào source/ của $domain?" "$domain" || return 0
      kw_laravel_with_lock clone "$domain" "$url" "$branch" ;;
    pull)
      kw_laravel_git_source || return 2
      branch=$(runuser -u "$KW_SITE_OWNER" -- git -C "$KW_SITE_ROOT/source" symbolic-ref --quiet --short HEAD) || return 2
      kw_prompt_yes_no_token "Pull nhánh $branch của $domain?" "$domain" || return 0
      kw_laravel_with_lock pull "$domain" "$branch" ;;
    env)
      printf 'Sửa .env riêng cho %s; file này chứa bí mật và không được commit vào Git.\n' "$domain"
      kw_prompt_yes_no_token 'Mở nano?' "$domain" || return 0
      kw_laravel_with_lock env "$domain" ;;
    deploy)
      printf 'Build frontend cho %s:\n' "$domain"
      printf '  1. Tự nhận từ lockfile (npm/pnpm/yarn)\n'
      printf '  2. Bỏ qua; assets đã có sẵn\n  3. npm\n  4. pnpm\n  5. yarn\n  0. Quay lại\n'
      while :; do
        printf 'Chọn: '
        IFS= read -r choice || return 0
        case "$choice" in
          1) frontend=auto; break ;; 2) frontend=none; break ;;
          3) frontend=npm; break ;; 4) frontend=pnpm; break ;;
          5) frontend=yarn; break ;; 0) return 0 ;;
          *) printf 'Chọn số 0–5.\n' ;;
        esac
      done
      printf 'Deploy %s: chạy Composer và %s (nếu chọn), kích hoạt release mới, kiểm tra Nginx/HTTP.\n' "$domain" "$frontend"
      printf 'Không tự chạy migration/seed, không đổi DB, không gọi deploy.sh của ứng dụng.\n'
      printf 'Composer/công cụ frontend có thể chạy script của repository dưới user site. Hãy chỉ dùng Git repo bạn tin cậy.\n'
      kw_prompt_yes_no_token "Triển khai $domain?" "$domain" || return 0
      kw_laravel_with_lock deploy "$domain" "$frontend" ;;
    *) return 2 ;;
  esac
}
