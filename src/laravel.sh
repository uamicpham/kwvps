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

kw_laravel_migrate_valid() { [[ ${1:-} == 0 || ${1:-} == 1 ]]; }

kw_laravel_migrate_prompt() {
  local answer
  while :; do
    printf 'Chạy migration cho database của site? [y/N]: '
    IFS= read -r answer || return 1
    case "$answer" in
      y|Y|yes|YES) KW_LARAVEL_MIGRATE=1; return 0 ;;
      ''|n|N|no|NO|0) KW_LARAVEL_MIGRATE=0; return 0 ;;
      *) printf 'Chỉ nhập y hoặc N.\n' ;;
    esac
  done
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
    if ! { [[ $mode =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0022) == 0 )); }; then
      kw_log ERROR "Thư mục Laravel có quyền ghi nhóm/khách không an toàn: $path"; return 2;
    fi
  done
}

kw_laravel_root_directory_safe() {
  local path=$1 owner mode
  [[ -d $path && ! -L $path ]] || return 1
  owner=$(stat -c %u -- "$path") || return 1
  mode=$(stat -c %a -- "$path") || return 1
  [[ $owner == 0 && $mode =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0022) == 0 ))
}

kw_laravel_root_file_safe() {
  local path=$1 owner mode
  [[ -f $path && ! -L $path ]] || return 1
  owner=$(stat -c %u -- "$path") || return 1
  mode=$(stat -c %a -- "$path") || return 1
  [[ $owner == 0 && $mode =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0022) == 0 ))
}

kw_laravel_private_node_ready() {
  local base=/usr/local/lib/kwvps/nodejs release runtime version npm_version
  kw_laravel_root_directory_safe /usr/local/lib/kwvps || return 1
  kw_laravel_root_directory_safe "$base" || return 1
  [[ -L $base/current ]] || return 1
  release=$(readlink -- "$base/current") || return 1
  [[ $release =~ ^24\.[0-9]+\.[0-9]+-[0-9A-Za-z.+~_-]+$ && $release != *..* ]] || return 1
  runtime=$base/$release
  kw_laravel_root_directory_safe "$runtime" || return 1
  kw_laravel_root_directory_safe "$runtime/bin" || return 1
  kw_laravel_root_directory_safe "$runtime/usr" || return 1
  kw_laravel_root_directory_safe "$runtime/usr/bin" || return 1
  kw_laravel_root_directory_safe "$runtime/usr/lib" || return 1
  kw_laravel_root_directory_safe "$runtime/usr/lib/node_modules" || return 1
  kw_laravel_root_directory_safe "$runtime/usr/lib/node_modules/npm" || return 1
  kw_laravel_root_directory_safe "$runtime/usr/lib/node_modules/npm/bin" || return 1
  kw_laravel_root_file_safe "$runtime/usr/bin/node" || return 1
  kw_laravel_root_file_safe "$runtime/usr/lib/node_modules/npm/bin/npm-cli.js" || return 1
  [[ -L $runtime/bin/node && $(readlink -- "$runtime/bin/node") == ../usr/bin/node ]] || return 1
  [[ -L $runtime/bin/npm && $(readlink -- "$runtime/bin/npm") == ../usr/lib/node_modules/npm/bin/npm-cli.js ]] || return 1
  version=$(env PATH="$runtime/bin:/usr/local/bin:/usr/bin:/bin" "$runtime/bin/node" --version 2>/dev/null) || return 1
  npm_version=$(env PATH="$runtime/bin:/usr/local/bin:/usr/bin:/bin" "$runtime/bin/npm" --version 2>/dev/null) || return 1
  [[ $version =~ ^v24\.[0-9]+\.[0-9]+$ && $npm_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  KW_LARAVEL_PRIVATE_NODE_BIN=$runtime/bin
}

kw_laravel_global_node_ready() {
  local version major minor npm_version
  kw_has node && kw_has npm || return 1
  version=$(node --version 2>/dev/null) || return 1
  npm_version=$(npm --version 2>/dev/null) || return 1
  [[ $version =~ ^v([0-9]+)\.([0-9]+)\.[0-9]+$ ]] || return 1
  major=${BASH_REMATCH[1]}; minor=${BASH_REMATCH[2]}
  [[ $npm_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  ((major >= 22 && major % 2 == 0 && (major != 22 || minor >= 12)))
}

kw_laravel_node_ready() {
  kw_laravel_private_node_ready || kw_laravel_global_node_ready
}

kw_laravel_frontend_command_ready() {
  local tool=$1
  if kw_laravel_private_node_ready; then
    [[ -x $KW_LARAVEL_PRIVATE_NODE_BIN/$tool ]]
  else
    kw_laravel_global_node_ready && kw_has "$tool"
  fi
}

kw_laravel_run_frontend() {
  local owner=$1 command=$2
  shift 2
  if kw_laravel_private_node_ready; then
    runuser -u "$owner" -- env PATH="$KW_LARAVEL_PRIVATE_NODE_BIN:/usr/local/bin:/usr/bin:/bin" "$command" "$@"
  elif kw_laravel_global_node_ready; then
    runuser -u "$owner" -- "$command" "$@"
  else
    kw_log ERROR 'Node.js/npm phù hợp chưa sẵn sàng; kiểm tra mục Công cụ Laravel.'
    return 2
  fi
}

kw_laravel_tool_ready() {
  local tool=$1 php=$2
  case "$tool" in
    php-cli) kw_has "php$php" ;;
    node-npm) kw_laravel_node_ready ;;
    pnpm|yarn) kw_laravel_frontend_command_ready "$tool" ;;
    *) kw_has "$tool" ;;
  esac
}

kw_laravel_tool_label() {
  local tool=$1 php=$2
  case "$tool" in
    php-cli) printf 'PHP %s CLI' "$php" ;;
    node-npm) printf 'Node.js/npm cho build (Node >= 22.12; cài riêng nếu cần)' ;;
    git) printf 'Git' ;; composer) printf 'Composer' ;;
    pnpm) printf 'pnpm (Corepack)' ;; yarn) printf 'Yarn (Corepack)' ;;
    tar) printf 'tar' ;; curl) printf 'curl' ;; nano) printf 'nano' ;;
    gpg) printf 'GnuPG (xác minh gói NodeSource riêng)' ;;
    *) return 2 ;;
  esac
}

kw_laravel_collect_missing_tools() {
  local php=$1 tool
  KW_LARAVEL_MISSING_TOOLS=()
  for tool in git composer php-cli tar curl nano node-npm gpg pnpm yarn; do
    if [[ $tool == gpg ]] && kw_laravel_node_ready; then continue; fi
    if ! kw_laravel_tool_ready "$tool" "$php"; then
      KW_LARAVEL_MISSING_TOOLS+=("$tool")
    fi
  done
}

kw_laravel_status() {
  local domain=$1 tool current label
  kw_site_lookup "$domain" || return 2
  printf 'Laravel: %s (PHP %s)\n' "$domain" "$KW_SITE_PHP"
  printf 'Công cụ cần cho Git/Composer và tùy chọn build frontend:\n'
  for tool in git composer php-cli tar curl nano node-npm gpg pnpm yarn; do
    if [[ $tool == gpg ]] && kw_laravel_node_ready; then continue; fi
    label=$(kw_laravel_tool_label "$tool" "$KW_SITE_PHP") || return 2
    if kw_laravel_tool_ready "$tool" "$KW_SITE_PHP"; then
      printf '  %s: sẵn sàng\n' "$label"
    else
      printf '  %s: thiếu hoặc chưa phù hợp\n' "$label"
    fi
  done
  if kw_laravel_private_node_ready; then
    printf '  Node build: bản riêng KwVPS (%s); Node/npm toàn VPS không đổi.\n' \
      "$("$KW_LARAVEL_PRIVATE_NODE_BIN/node" --version)"
  elif kw_has node; then
    printf '  Node toàn VPS: %s; nếu quá cũ, chọn cài Node riêng ở danh sách bên dưới.\n' \
      "$(node --version 2>/dev/null || printf 'không đọc được')"
  fi
  if [[ ! -d $KW_SITE_ROOT/deploy || ! -d $KW_SITE_ROOT/source ]]; then
    printf '  Cấu trúc: chưa chuẩn bị; dùng mục Chuẩn bị thư mục Laravel.\n'
  fi
  if [[ -d $KW_SITE_ROOT/source/.git && ! -L $KW_SITE_ROOT/source/.git ]]; then
    printf '  Git source: đã clone\n'
  else
    printf '  Git source: chưa clone\n'
  fi
  if kw_laravel_env_safe "$KW_SITE_ROOT/deploy/shared/.env" "$KW_SITE_OWNER"; then
    printf '  .env: đã có, quyền an toàn (không hiển thị nội dung)\n'
  elif [[ -e $KW_SITE_ROOT/deploy/shared/.env || -L $KW_SITE_ROOT/deploy/shared/.env ]]; then
    printf '  .env: có nhưng owner/quyền chưa an toàn; dùng mục Sửa .env\n'
  else
    printf '  .env: chưa có\n'
  fi
  current=$KW_SITE_ROOT/deploy/current
  if [[ -L $current ]]; then
    printf '  Release hiện tại: %s\n' "$(readlink -- "$current")"
  else
    printf '  Release hiện tại: chưa kích hoạt\n'
  fi
  printf 'Chỉ cần cài npm/pnpm/Yarn nếu dự án dùng build frontend tương ứng.\n'
}

kw_laravel_apt_package() {
  local tool=$1 php=$2
  case "$tool" in
    php-cli) printf 'php%s-cli' "$php" ;;
    git|composer|tar|curl|nano|gpg) printf '%s' "$tool" ;;
    *) return 2 ;;
  esac
}

kw_laravel_apt_plan() {
  local package=$1 candidate=$2 plan
  plan=$(LC_ALL=C apt-get -s --no-remove --no-install-recommends install "$package=$candidate" 2>&1) || {
    kw_log ERROR "APT không mô phỏng được gói $package; chưa thay đổi VPS."
    printf '%s\n' "$plan" >&2
    return 2
  }
  if grep -Eq '^Remv[[:space:]]' <<< "$plan"; then
    kw_log ERROR 'Kế hoạch APT cần gỡ gói khác; không cài tự động.'
    return 2
  fi
  KW_LARAVEL_APT_PLAN=$plan
}

kw_laravel_ubuntu_candidate_origin() {
  local package=$1 candidate=$2 listings
  listings=$(LC_ALL=C apt-cache madison "$package") || return 2
  awk -F '|' -v wanted="$candidate" '
    { version=$2; origin=$3;
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", version);
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", origin);
      if (version != wanted) next;
      split(origin, parts, /[[:space:]]+/); url=parts[1];
      if (url ~ /^https?:\/\/([[:alnum:]-]+\.)*archive\.ubuntu\.com\/ubuntu\/?$/ ||
          url ~ /^https?:\/\/security\.ubuntu\.com\/ubuntu\/?$/ ||
          url ~ /^https?:\/\/ports\.ubuntu\.com\/ubuntu-ports\/?$/) {
        trusted=1; if (first == "") first=url
      } else untrusted=1
    }
    END { if (!trusted || untrusted) exit 1; print first }
  ' <<< "$listings"
}

kw_laravel_apt_install_tool() {
  local tool=$1 php=$2 package candidate label origin
  package=$(kw_laravel_apt_package "$tool" "$php") || return 2
  label=$(kw_laravel_tool_label "$tool" "$php") || return 2
  candidate=$(kw_apt_candidate "$package") || {
    kw_log ERROR "APT chưa có candidate cho $package. Kiểm tra nguồn gói và apt-get update."
    return 2
  }
  if [[ $tool == php-cli ]]; then
    if kw_php_debian_sury_repo_present; then
      kw_log ERROR 'Nguồn Debian deb.sury.org không dùng cho Ubuntu; không cài PHP CLI.'; return 2
    fi
    kw_php_candidate_provenance "$php" "$candidate" "$package" || {
      kw_log ERROR 'Không xác minh được nguồn Ubuntu/PPA Ondřej của PHP CLI.'; return 2
    }
    if [[ $KW_PHP_APT_ORIGIN_KIND == ondrej ]] && ! kw_php_ondrej_pin_matches; then
      kw_log ERROR 'PPA Ondřej chưa có ưu tiên APT KwVPS an toàn; dùng menu Cài gói PHP-FPM để cấu hình nguồn trước.'
      return 2
    fi
    if [[ $php == 7.4 ]]; then
      [[ $KW_PHP_APT_ORIGIN_KIND == ondrej ]] || {
        kw_log ERROR 'PHP 7.4 CLI chỉ chấp nhận PPA Ubuntu Ondřej.'; return 2;
      }
      printf 'CẢNH BÁO: PHP 7.4 đã hết hỗ trợ bảo mật; chỉ dùng cho ứng dụng cũ cần tương thích.\n'
    elif ! kw_php_package_version_safe "$php" "$candidate"; then
      kw_log ERROR "PHP $php CLI candidate chưa đạt bản vá KwVPS yêu cầu; không cài."
      return 2
    fi
    printf 'Nguồn PHP CLI: %s (%s).\n' "$KW_PHP_APT_ORIGIN_URL" "$KW_PHP_APT_ORIGIN_KIND"
  else
    origin=$(kw_laravel_ubuntu_candidate_origin "$package" "$candidate") || {
      kw_log ERROR "Candidate $package không từ kho Ubuntu chính thức; không cài tự động."
      return 2
    }
    printf 'Nguồn APT: %s.\n' "$origin"
  fi
  kw_laravel_apt_plan "$package" "$candidate" || return 2
  printf 'Cài %s từ APT: %s=%s\n' "$label" "$package" "$candidate"
  printf '%s\n' "$KW_LARAVEL_APT_PLAN" | awk '/^(Inst|Remv|Conf) / { print }'
  kw_prompt_yes_no_token "Cài $label trên VPS?" "LARAVEL-TOOL:$tool" || return 0
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove --no-install-recommends "$package=$candidate" || return 1
  kw_laravel_tool_ready "$tool" "$php" || {
    kw_log ERROR "APT đã chạy nhưng $label vẫn chưa sẵn sàng; kiểm tra package thủ công."
    return 1
  }
  printf 'Đã cài %s.\n' "$label"
}

kw_laravel_nodesource_source() {
  printf 'Types: deb\nURIs: https://deb.nodesource.com/node_24.x\nSuites: nodistro\nComponents: main\nSigned-By: %s\n' "${1:-/etc/apt/keyrings/kwvps-nodesource.gpg}"
}

kw_laravel_nodesource_fingerprint() {
  local key=$1 output
  output=$(gpg --batch --quiet --show-keys --with-colons -- "$key" 2>/dev/null) || return 1
  awk -F: '$1 == "fpr" && !found { print $10; found=1 }' <<< "$output"
}

kw_laravel_nodesource_candidate() {
  local candidate listings
  candidate=$(kw_apt_candidate nodejs) || return 2
  [[ $candidate == 24.* ]] || return 2
  listings=$(LC_ALL=C apt-cache madison nodejs) || return 2
  awk -F '|' -v wanted="$candidate" '
    { version=$2; origin=$3;
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", version);
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", origin);
      if (version != wanted) next;
      split(origin, parts, /[[:space:]]+/);
      if (parts[1] ~ /^https:\/\/deb\.nodesource\.com\/node_24\.x\/?$/) trusted=1;
      else untrusted=1
    }
    END { if (!trusted || untrusted) exit 1 }
  ' <<< "$listings" || return 2
  KW_LARAVEL_NODE_CANDIDATE=$candidate
}

kw_laravel_nodesource_repo_check() {
  local source key fingerprint
  source=/etc/apt/sources.list.d/kwvps-nodesource.sources
  key=/etc/apt/keyrings/kwvps-nodesource.gpg
  [[ -f $source && ! -L $source && -f $key && ! -L $key ]] || return 1
  kw_laravel_nodesource_source | cmp -s - "$source" || return 1
  fingerprint=$(kw_laravel_nodesource_fingerprint "$key") || return 1
  [[ $fingerprint == 6F71F525282841EEDAF851B42F59B5F99B1BE0B4 ]]
}

kw_laravel_nodesource_repo_add() {
  local source key file tmpdir fingerprint
  source=/etc/apt/sources.list.d/kwvps-nodesource.sources
  key=/etc/apt/keyrings/kwvps-nodesource.gpg
  [[ -d /etc/apt/sources.list.d && ! -L /etc/apt/sources.list.d ]] || return 2
  if [[ ! -e /etc/apt/keyrings && ! -L /etc/apt/keyrings ]]; then
    install -d -m 0755 -o root -g root /etc/apt/keyrings || return 1
  fi
  [[ -d /etc/apt/keyrings && ! -L /etc/apt/keyrings ]] || return 2
  [[ ! -e $source && ! -L $source && ! -e $key && ! -L $key ]] || return 2
  for file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [[ -f $file ]] || continue
    if grep -Fq 'deb.nodesource.com' "$file"; then
      kw_log ERROR "Đã có nguồn NodeSource tại $file; không tạo bản trùng hoặc ghi đè."
      return 2
    fi
  done
  tmpdir=$(mktemp -d /tmp/kwvps-nodesource.XXXXXXXX) || return 1
  if ! curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
      --connect-timeout 10 --max-time 30 --max-filesize 1048576 \
      -o "$tmpdir/key.asc" 'https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key'; then
    rm -rf -- "$tmpdir"
    return 1
  fi
  fingerprint=$(kw_laravel_nodesource_fingerprint "$tmpdir/key.asc") || {
    rm -rf -- "$tmpdir"; return 2;
  }
  if [[ $fingerprint != 6F71F525282841EEDAF851B42F59B5F99B1BE0B4 ]]; then
    kw_log ERROR 'Fingerprint khóa NodeSource không khớp; không thêm nguồn.'
    rm -rf -- "$tmpdir"
    return 2
  fi
  if ! gpg --batch --yes --dearmor -o "$tmpdir/key.gpg" "$tmpdir/key.asc" ||
     ! install -m 0644 -o root -g root -- "$tmpdir/key.gpg" "$key" ||
     ! kw_laravel_nodesource_source > "$tmpdir/nodesource.sources" ||
     ! install -m 0644 -o root -g root -- "$tmpdir/nodesource.sources" "$source"; then
    rm -f -- "$source" "$key"
    rm -rf -- "$tmpdir"
    return 1
  fi
  rm -rf -- "$tmpdir"
}

kw_laravel_nodesource_isolated_candidate() {
  local listings candidate policy
  # Consume all of apt-cache before selecting Candidate. With pipefail, an
  # early awk exit can SIGPIPE apt-cache when NodeSource lists many versions.
  policy=$(LC_ALL=C apt-cache "${KW_LARAVEL_NODE_APT_OPTS[@]}" policy nodejs) || return 2
  candidate=$(awk '$1 == "Candidate:" && !found { print $2; found=1 }' <<< "$policy") || return 2
  [[ $candidate =~ ^24\.[0-9]+\.[0-9]+-[0-9A-Za-z.+~_-]+$ && $candidate != *..* ]] || return 2
  listings=$(LC_ALL=C apt-cache "${KW_LARAVEL_NODE_APT_OPTS[@]}" madison nodejs) || return 2
  awk -F '|' -v wanted="$candidate" '
    { version=$2; origin=$3;
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", version);
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", origin);
      if (version != wanted) next;
      split(origin, parts, /[[:space:]]+/);
      if (parts[1] ~ /^https:\/\/deb\.nodesource\.com\/node_24\.x\/?$/) trusted=1;
      else untrusted=1
    }
    END { if (!trusted || untrusted) exit 1 }
  ' <<< "$listings" || return 2
  KW_LARAVEL_NODE_CANDIDATE=$candidate
}

kw_laravel_nodesource_isolated_hash() {
  local candidate=$1 records
  records=$(LC_ALL=C apt-cache "${KW_LARAVEL_NODE_APT_OPTS[@]}" show "nodejs=$candidate") || return 2
  awk -v wanted="$candidate" '
    BEGIN { RS=""; FS="\n" }
    { version=""; arch=""; hash="";
      for (i=1; i<=NF; i++) {
        if ($i ~ /^Version: /) version=substr($i, 10);
        if ($i ~ /^Architecture: /) arch=substr($i, 15);
        if ($i ~ /^SHA256: /) hash=substr($i, 9)
      }
      if (version != wanted || arch != "amd64") next;
      if (length(hash) != 64 || hash !~ /^[0-9a-f]+$/) bad=1;
      else if (expected != "" && expected != hash) bad=1;
      else expected=hash
    }
    END { if (bad || expected == "") exit 1; print expected }
  ' <<< "$records"
}

kw_laravel_node_extract_private() (
  local archive=$1 candidate=$2 owner=$3 base=/usr/local/lib/kwvps/nodejs stage='' runtime tmp_link
  # runuser inherits cwd; the menu may have been launched from /root (0700).
  cd -- / || return 1
  runtime=$base/$candidate
  kw_laravel_root_directory_safe /usr/local/lib/kwvps || return 2
  if [[ ! -e $base && ! -L $base ]]; then
    install -d -m 0755 -o root -g root -- "$base" || return 1
  fi
  kw_laravel_root_directory_safe "$base" || {
    kw_log ERROR 'Thư mục Node riêng có owner/quyền không an toàn; chưa cài.'; return 2;
  }
  [[ ! -e $runtime && ! -L $runtime ]] || {
    kw_log ERROR 'Phiên bản Node riêng đã tồn tại; không ghi đè.'; return 2;
  }
  [[ ! -e $base/current || -L $base/current ]] || {
    kw_log ERROR 'Đường dẫn Node riêng đã tồn tại bất thường; không ghi đè.'; return 2;
  }
  stage=$(mktemp -d "$base/.stage.XXXXXXXX") || return 1
  trap 'if [[ -n $stage && -d $stage ]]; then rm -rf -- "$stage"; fi' EXIT
  dpkg-deb -x -- "$archive" "$stage" || return 1
  kw_laravel_root_directory_safe "$stage/usr" || return 2
  kw_laravel_root_directory_safe "$stage/usr/bin" || return 2
  kw_laravel_root_directory_safe "$stage/usr/lib" || return 2
  kw_laravel_root_directory_safe "$stage/usr/lib/node_modules" || return 2
  kw_laravel_root_directory_safe "$stage/usr/lib/node_modules/npm" || return 2
  kw_laravel_root_directory_safe "$stage/usr/lib/node_modules/npm/bin" || return 2
  kw_laravel_root_file_safe "$stage/usr/bin/node" || return 2
  kw_laravel_root_file_safe "$stage/usr/lib/node_modules/npm/bin/npm-cli.js" || return 2
  install -d -m 0755 -o root -g root -- "$stage/bin" || return 1
  ln -s ../usr/bin/node "$stage/bin/node" || return 1
  ln -s ../usr/lib/node_modules/npm/bin/npm-cli.js "$stage/bin/npm" || return 1
  chmod 0755 -- "$stage" || return 1
  if ! runuser -u "$owner" -- env PATH="$stage/bin:/usr/local/bin:/usr/bin:/bin" node --version |
       grep -Eq '^v24\.[0-9]+\.[0-9]+$' ||
     ! runuser -u "$owner" -- env PATH="$stage/bin:/usr/local/bin:/usr/bin:/bin" npm --version |
       grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    kw_log ERROR 'Gói NodeSource không chạy được dưới user site; chưa kích hoạt.'
    return 2
  fi
  mv -T -- "$stage" "$runtime" || return 1
  stage=''
  tmp_link=$base/.current.$$
  [[ ! -e $tmp_link && ! -L $tmp_link ]] || return 2
  ln -s "$candidate" "$tmp_link" || return 1
  if ! mv -Tf -- "$tmp_link" "$base/current"; then
    rm -f -- "$tmp_link"
    return 1
  fi
  kw_laravel_private_node_ready || {
    kw_log ERROR 'Node riêng đã giải nén nhưng chưa đạt kiểm tra an toàn; chưa thể build.'; return 2;
  }
)

kw_laravel_node_download_dir() {
  local dir=$1 parent=${1%/*}
  [[ -d $parent && ! -L $parent && ! -e $dir && ! -L $dir ]] || return 2
  install -d -m 0700 -o _apt -g root -- "$dir" || return 1
  runuser -u _apt -- test -w "$dir" || {
    kw_log ERROR 'User _apt không ghi được thư mục tải Node.js riêng; chưa tải gói.'
    return 2
  }
}

kw_laravel_node_install() (
  local candidate key fingerprint tmpdir download_dir expected actual owner=${1:-}
  local -a packages
  [[ -n $owner ]] || return 2
  if ! { kw_has curl && kw_has gpg && kw_has dpkg-deb && kw_has sha256sum; }; then
    kw_log ERROR 'Cần curl, GnuPG, dpkg-deb và sha256sum để cài Node riêng.'
    return 2
  fi
  if [[ -e /usr/local/lib/kwvps || -L /usr/local/lib/kwvps ]]; then
    kw_laravel_root_directory_safe /usr/local/lib/kwvps || {
      kw_log ERROR '/usr/local/lib/kwvps không an toàn; chưa cài Node riêng.'; return 2;
    }
  else
    install -d -m 0755 -o root -g root -- /usr/local/lib/kwvps || return 1
  fi
  if [[ -e /usr/local/lib/kwvps/nodejs || -L /usr/local/lib/kwvps/nodejs ]]; then
    kw_laravel_root_directory_safe /usr/local/lib/kwvps/nodejs || {
      kw_log ERROR 'Thư mục Node riêng không an toàn; chưa cài.'; return 2;
    }
  fi
  tmpdir=$(mktemp -d /tmp/kwvps-node24.XXXXXXXX) || return 1
  trap 'rm -rf -- "$tmpdir"' EXIT
  chmod 0755 -- "$tmpdir" || return 1
  key=$tmpdir/nodesource.asc
  curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 10 --max-time 30 --max-filesize 1048576 \
    -o "$key" 'https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key' || return 1
  fingerprint=$(kw_laravel_nodesource_fingerprint "$key") || return 2
  [[ $fingerprint == 6F71F525282841EEDAF851B42F59B5F99B1BE0B4 ]] || {
    kw_log ERROR 'Fingerprint NodeSource không khớp; chưa cài.'; return 2;
  }
  gpg --batch --yes --dearmor -o "$tmpdir/nodesource.gpg" "$key" || return 1
  chmod 0644 -- "$tmpdir/nodesource.gpg" || return 1
  kw_laravel_nodesource_source "$tmpdir/nodesource.gpg" > "$tmpdir/nodesource.sources" || return 1
  chmod 0644 -- "$tmpdir/nodesource.sources" || return 1
  install -d -m 0755 -- "$tmpdir/lists/partial" "$tmpdir/archives/partial" || return 1
  KW_LARAVEL_NODE_APT_OPTS=(
    -o "Dir::Etc::sourcelist=$tmpdir/nodesource.sources"
    -o 'Dir::Etc::sourceparts=-'
    -o "Dir::State::lists=$tmpdir/lists"
    -o 'Dir::State::status=/dev/null'
    -o "Dir::Cache::archives=$tmpdir/archives"
    -o 'Dir::Cache::pkgcache='
    -o 'Dir::Cache::srcpkgcache='
  )
  apt-get "${KW_LARAVEL_NODE_APT_OPTS[@]}" -o APT::Update::Error-Mode=any update || {
    kw_log ERROR 'APT không xác minh được kho NodeSource riêng; không đổi APT toàn VPS.'; return 2;
  }
  kw_laravel_nodesource_isolated_candidate || {
    kw_log ERROR 'Không tìm được Node.js 24 amd64 từ NodeSource.'; return 2;
  }
  candidate=$KW_LARAVEL_NODE_CANDIDATE
  expected=$(kw_laravel_nodesource_isolated_hash "$candidate") || {
    kw_log ERROR 'Không đọc được SHA-256 từ chỉ mục APT đã ký.'; return 2;
  }
  printf 'Node.js/npm hiện tại toàn VPS: '
  if kw_has node; then node --version 2>/dev/null || printf 'không đọc được\n'; else printf 'chưa có\n'; fi
  printf 'NodeSource candidate: %s. Sẽ giải nén riêng vào /usr/local/lib/kwvps/nodejs.\n' "$candidate"
  printf 'Không thay node/npm toàn VPS, không đổi PATH chung và không cài package hệ thống.\n'
  kw_prompt_yes_no_token 'Cài Node.js 24 riêng cho build Laravel của KwVPS?' 'LARAVEL-NODE24-PRIVATE' || return 0
  download_dir=$tmpdir/download
  kw_laravel_node_download_dir "$download_dir" || return 2
  (
    cd -- "$download_dir" || exit 1
    apt-get "${KW_LARAVEL_NODE_APT_OPTS[@]}" download "nodejs=$candidate"
  ) || return 1
  chown root:root -- "$download_dir" || return 1
  packages=("$download_dir"/nodejs_*.deb)
  [[ ${#packages[@]} -eq 1 && -f ${packages[0]} && ! -L ${packages[0]} ]] || {
    kw_log ERROR 'APT không tải đúng một gói nodejs; chưa cài.'; return 2;
  }
  actual=$(sha256sum -- "${packages[0]}") || return 1
  [[ ${actual%% *} == "$expected" ]] || {
    kw_log ERROR 'SHA-256 gói NodeSource không khớp chỉ mục APT đã ký; chưa cài.'; return 2;
  }
  kw_laravel_node_extract_private "${packages[0]}" "$candidate" "$owner" || return $?
  printf 'Đã cài Node.js 24 riêng cho KwVPS; Node toàn VPS vẫn giữ nguyên.\n'
)

kw_laravel_frontend_install() {
  local tool=$1 version runtime bin
  [[ $tool == pnpm || $tool == yarn ]] || return 2
  kw_laravel_node_ready || {
    kw_log ERROR 'Cần Node.js/npm phù hợp trước khi kích hoạt pnpm/Yarn.'; return 2;
  }
  if kw_laravel_private_node_ready; then
    bin=$KW_LARAVEL_PRIVATE_NODE_BIN
    runtime=${bin%/bin}
    [[ ! -e $bin/$tool && ! -L $bin/$tool ]] || {
      kw_log ERROR "Node riêng đã có $tool; không ghi đè."; return 2;
    }
    if [[ ! -x $bin/corepack ]]; then
      version=$(env PATH="$bin:/usr/local/bin:/usr/bin:/bin" "$bin/npm" \
        --registry=https://registry.npmjs.org view corepack dist-tags.latest 2>/dev/null) || return 1
      [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
        kw_log ERROR 'Không xác minh được phiên bản Corepack từ npmjs.org.'; return 2;
      }
      printf 'Cài corepack@%s chỉ vào Node riêng của KwVPS; không đổi npm toàn VPS.\n' "$version"
      kw_prompt_yes_no_token 'Cài Corepack riêng cho KwVPS?' 'LARAVEL-COREPACK-PRIVATE' || return 0
      env PATH="$bin:/usr/local/bin:/usr/bin:/bin" "$bin/npm" \
        --registry=https://registry.npmjs.org install --global --prefix "$runtime" \
        --ignore-scripts --no-audit --no-fund "corepack@$version" || return 1
      [[ -x $bin/corepack ]] || return 1
    fi
    printf 'Corepack sẽ tạo shim %s chỉ trong Node riêng; không đổi /usr/local/bin.\n' "$tool"
    kw_prompt_yes_no_token "Kích hoạt $tool trong Node riêng?" "LARAVEL-COREPACK-PRIVATE:$tool" || return 0
    env PATH="$bin:/usr/local/bin:/usr/bin:/bin" "$bin/corepack" enable --install-directory "$bin" "$tool" || return 1
    [[ -x $bin/$tool ]] || return 1
    printf 'Đã kích hoạt %s trong Node riêng.\n' "$tool"
    return 0
  fi
  [[ ! -e /usr/local/bin/$tool && ! -L /usr/local/bin/$tool ]] || {
    kw_log ERROR "/usr/local/bin/$tool đã có; không ghi đè."; return 2;
  }
  if ! kw_has corepack; then
    version=$(npm --registry=https://registry.npmjs.org view corepack dist-tags.latest 2>/dev/null) || return 1
    [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
      kw_log ERROR 'Không xác minh được phiên bản Corepack từ npmjs.org.'; return 2;
    }
    printf 'Corepack chưa có; sẽ cài corepack@%s từ registry.npmjs.org, bỏ qua lifecycle scripts.\n' "$version"
    kw_prompt_yes_no_token 'Cài Corepack toàn VPS?' 'LARAVEL-COREPACK' || return 0
    npm --registry=https://registry.npmjs.org install --global --ignore-scripts --no-audit --no-fund "corepack@$version" || return 1
    kw_has corepack || return 1
  fi
  printf 'Corepack sẽ tạo shim %s trong /usr/local/bin; phiên bản package manager của dự án được lấy theo packageManager khi deploy.\n' "$tool"
  kw_prompt_yes_no_token "Kích hoạt $tool qua Corepack?" "LARAVEL-COREPACK:$tool" || return 0
  corepack enable --install-directory /usr/local/bin "$tool" || return 1
  kw_has "$tool" || return 1
  printf 'Đã kích hoạt %s qua Corepack.\n' "$tool"
}

kw_laravel_install_tool_locked() {
  local domain=$1 tool=$2 php
  if ! { ((EUID == 0)) && kw_os_supported '' && [[ $(uname -m) == x86_64 ]]; }; then
    kw_log ERROR 'Cần root trên Ubuntu 24.04 x86_64 để cài công cụ.'
    return 2
  fi
  kw_has apt-get && kw_has apt-cache && kw_has dpkg-query || return 2
  kw_site_lookup "$domain" || return 2
  php=$KW_SITE_PHP
  if kw_laravel_tool_ready "$tool" "$php"; then
    printf '%s đã sẵn sàng; không cài lại.\n' "$(kw_laravel_tool_label "$tool" "$php")"
    return 0
  fi
  case "$tool" in
    git|composer|php-cli|tar|curl|nano|gpg) kw_laravel_apt_install_tool "$tool" "$php" ;;
    node-npm) kw_laravel_node_install "$KW_SITE_OWNER" ;;
    pnpm|yarn) kw_laravel_frontend_install "$tool" ;;
    *) return 2 ;;
  esac
}

kw_laravel_install_tool() (
  kw_has flock || { kw_log ERROR 'Thiếu flock để khóa thao tác cài package.'; return 2; }
  exec 9>/run/lock/kwvps-laravel-tools.lock || return 2
  flock -n 9 || { kw_log ERROR 'Đang có lượt cài công cụ Laravel khác; thử lại sau.'; return 1; }
  kw_laravel_install_tool_locked "$@"
)

kw_laravel_status_interactive() {
  local domain=$1 choice tool i php code
  while :; do
    kw_laravel_status "$domain" || return 2
    php=$KW_SITE_PHP
    kw_laravel_collect_missing_tools "$php"
    printf '\nCài công cụ còn thiếu (chọn từng mục):\n'
    i=0
    for tool in "${KW_LARAVEL_MISSING_TOOLS[@]}"; do
      i=$((i + 1))
      printf '%2d. %s\n' "$i" "$(kw_laravel_tool_label "$tool" "$php")"
    done
    if ((i == 0)); then printf 'Không còn công cụ thiếu trong danh sách.\n'; fi
    printf ' 0. Quay lại\nChọn: '
    IFS= read -r choice || return 0
    [[ $choice != 0 ]] || return 0
    if [[ ! $choice =~ ^[1-9][0-9]?$ ]] || ((choice > i)); then
      printf 'Chọn số trong danh sách.\n'
      continue
    fi
    tool=${KW_LARAVEL_MISSING_TOOLS[choice-1]}
    code=0
    kw_laravel_install_tool "$domain" "$tool" || code=$?
    if ((code != 0)); then
      printf 'Chưa cài được công cụ (mã %d); xem thông báo phía trên.\n' "$code"
    fi
    printf '\n'
  done
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

kw_laravel_deploy_key_prepare() {
  local domain=$1 ssh_dir private public_file mode derived key_type key_blob
  local file_type='' file_blob=''
  kw_laravel_layout_ready "$domain" || return 2
  if ! { kw_has ssh-keygen && kw_has runuser; }; then
    kw_log ERROR 'Thiếu ssh-keygen/runuser để tạo Deploy Key cho site.'
    return 2
  fi
  ssh_dir=$KW_SITE_ROOT/.ssh
  private=$ssh_dir/id_ed25519
  public_file=$private.pub
  if [[ ! -e $ssh_dir && ! -L $ssh_dir ]]; then
    runuser -u "$KW_SITE_OWNER" -- mkdir -m 0700 -- "$ssh_dir" || return 1
  fi
  [[ -d $ssh_dir && ! -L $ssh_dir &&
     $(stat -c %U -- "$ssh_dir") == "$KW_SITE_OWNER" ]] || {
    kw_log ERROR "Thư mục SSH của site không an toàn: $ssh_dir"; return 2;
  }
  mode=$(stat -c %a -- "$ssh_dir") || return 2
  if ! { [[ $mode =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0077) == 0 )); }; then
    kw_log ERROR "Thư mục SSH phải chỉ user site được truy cập: $ssh_dir"
    return 2
  fi

  if [[ ! -e $private && ! -L $private ]]; then
    [[ ! -e $public_file && ! -L $public_file ]] || {
      kw_log ERROR "Chỉ có public key nhưng thiếu private key: $public_file. Không ghi đè."; return 2;
    }
    runuser -u "$KW_SITE_OWNER" -- ssh-keygen -q -t ed25519 -N '' \
      -f "$private" -C "kwvps-$domain" || return 1
    printf 'Đã tạo SSH Deploy Key riêng cho %s.\n' "$domain"
  else
    printf 'Dùng lại SSH Deploy Key đã có của %s; không tạo khóa mới.\n' "$domain"
  fi
  [[ -f $private && ! -L $private &&
     $(stat -c %U -- "$private") == "$KW_SITE_OWNER" ]] || {
    kw_log ERROR "Private key của site không an toàn: $private"; return 2;
  }
  mode=$(stat -c %a -- "$private") || return 2
  if ! { [[ $mode =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0077) == 0 )); }; then
    kw_log ERROR "Private key có quyền đọc quá rộng: $private"
    return 2
  fi
  derived=$(runuser -u "$KW_SITE_OWNER" -- ssh-keygen -y -P '' -f "$private" 2>/dev/null) || {
    kw_log ERROR 'Không đọc được SSH Deploy Key Ed25519 không mật khẩu của site; không thay key cũ.'
    return 2
  }
  read -r key_type key_blob _ <<< "$derived"
  [[ $key_type == ssh-ed25519 && $key_blob =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || {
    kw_log ERROR 'Deploy Key hiện có không phải Ed25519 hợp lệ; không thay key cũ.'; return 2;
  }
  if [[ -e $public_file || -L $public_file ]]; then
    [[ -f $public_file && ! -L $public_file &&
       $(stat -c %U -- "$public_file") == "$KW_SITE_OWNER" ]] || {
      kw_log ERROR "Public key của site không an toàn: $public_file"; return 2;
    }
    IFS=' ' read -r file_type file_blob _ < "$public_file" || true
    if [[ $file_type != "$key_type" || $file_blob != "$key_blob" ]]; then
      kw_log WARN 'File .pub không khớp private key; hiển thị key đúng suy ra từ private key, không ghi đè file cũ.'
    fi
  fi
  printf '\nDeploy Key CÔNG KHAI của %s (có thể sao chép):\n%s %s\n\n' \
    "$domain" "$key_type" "$key_blob"
  printf 'Private key giữ tại %s (không sao chép hoặc gửi đi).\n' "$private"
}

# Git must use the key generated for this site, even if the administrator has
# another SSH agent or identity configured on the VPS. Never print key content.
kw_laravel_site_git() {
  local owner=$1 url=$2 private uid mode key_mode
  shift 2
  if [[ $url == git@* || $url == ssh://git@* ]]; then
    private=$KW_SITE_ROOT/.ssh/id_ed25519
    uid=$(id -u "$owner") || return 2
    [[ $private =~ ^/[A-Za-z0-9._/-]+$ &&
       -d $KW_SITE_ROOT/.ssh && ! -L $KW_SITE_ROOT/.ssh &&
       -f $private && ! -L $private &&
       $(stat -c %u -- "$KW_SITE_ROOT/.ssh") == "$uid" &&
       $(stat -c %u -- "$private") == "$uid" ]] || {
      kw_log ERROR "Deploy Key riêng của site thiếu hoặc không an toàn: $private. Mở mục Clone Git để xem/tạo public key trước."
      return 2
    }
    mode=$(stat -c %a -- "$KW_SITE_ROOT/.ssh") || return 2
    key_mode=$(stat -c %a -- "$private") || return 2
    if [[ ! $mode =~ ^[0-7]{3,4}$ || ! $key_mode =~ ^[0-7]{3,4}$ ]] ||
       (( (8#$mode & 0077) != 0 || (8#$key_mode & 0177) != 0 ||
          (8#$key_mode & 0400) == 0 )); then
      return 2
    fi
    runuser -u "$owner" -- env \
      GIT_SSH_COMMAND="ssh -i $private -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes" \
      git "$@"
  else
    runuser -u "$owner" -- git "$@"
  fi
}

kw_laravel_clone_locked() (
  local domain=$1 url=$2 branch=$3 source
  kw_laravel_layout_ready "$domain" || return 2
  if ! kw_laravel_git_url_valid "$url" || ! kw_laravel_branch_valid "$branch"; then
    kw_log ERROR 'URL Git hoặc tên nhánh không hợp lệ. Dùng HTTPS công khai hoặc SSH git@host.'; return 2;
  fi
  if ! kw_has git || ! kw_has runuser; then
    kw_log ERROR 'Thiếu git/runuser trên VPS.'; return 2;
  fi
  source=$KW_SITE_ROOT/source
  [[ -z $(find "$source" -mindepth 1 -maxdepth 1 -print -quit) ]] || {
    kw_log ERROR 'source/ không rỗng; không ghi đè repository đã có.'; return 2;
  }
  printf 'Đang clone nhánh %s cho %s bằng user %s...\n' "$branch" "$domain" "$KW_SITE_OWNER"
  if ! kw_laravel_site_git "$KW_SITE_OWNER" "$url" clone --branch "$branch" --single-branch -- "$url" "$source"; then
    if [[ $url == git@* || $url == ssh://git@* ]]; then
      kw_log ERROR 'Clone SSH thất bại: kiểm tra Deploy Key trong repository, quyền truy cập và host key. Vào lại mục Clone để xem cùng public key.'
    fi
    return 1
  fi
  kw_laravel_git_source || return 1
  printf 'Đã clone vào %s. Không chạy script từ repository hoặc đổi website.\n' "$source"
)

kw_laravel_pull_locked() (
  local domain=$1 branch=${2:-} source current origin status
  kw_laravel_layout_ready "$domain" && kw_laravel_git_source || return 2
  source=$KW_SITE_ROOT/source
  current=$(runuser -u "$KW_SITE_OWNER" -- git -C "$source" symbolic-ref --quiet --short HEAD) || return 2
  [[ -n $branch ]] || branch=$current
  kw_laravel_branch_valid "$branch" || return 2
  [[ $current == "$branch" ]] || {
    kw_log ERROR "Checkout đang ở nhánh $current; không tự chuyển nhánh."; return 2;
  }
  origin=$(runuser -u "$KW_SITE_OWNER" -- git -C "$source" remote get-url origin) || return 2
  kw_laravel_git_url_valid "$origin" || {
    kw_log ERROR 'Git origin có URL không được hỗ trợ hoặc có thể chứa credential.'; return 2;
  }
  status=$(runuser -u "$KW_SITE_OWNER" -- git -C "$source" status --porcelain) || return 2
  [[ -z $status ]] || { kw_log ERROR 'source/ có thay đổi chưa commit; không pull đè.'; return 2; }
  if ! kw_laravel_site_git "$KW_SITE_OWNER" "$origin" -C "$source" fetch --no-tags origin "$branch"; then
    if [[ $origin == git@* || $origin == ssh://git@* ]]; then
      kw_log ERROR "GitHub từ chối Deploy Key của user site $KW_SITE_OWNER. Kiểm tra khóa trong Settings → Deploy keys của đúng repository ($origin); mục Clone Git sẽ hiện lại public key mà không thay private key."
    fi
    return 1
  fi
  runuser -u "$KW_SITE_OWNER" -- git -C "$source" merge --ff-only FETCH_HEAD || return 1
  printf 'Đã cập nhật source/ tới commit %s. Website chưa đổi cho đến khi triển khai.\n' \
    "$(runuser -u "$KW_SITE_OWNER" -- git -C "$source" rev-parse --short=12 HEAD)"
)

kw_laravel_env_safe() {
  local env_file=$1 owner=$2 uid
  [[ -f $env_file && ! -L $env_file ]] || return 1
  uid=$(id -u "$owner") || return 1
  [[ $(stat -c '%u:%a:%h' -- "$env_file") == "$uid:600:1" ]]
}

kw_laravel_env_repair_fd() {
  local site_root=$1 owner=$2
  kw_has python3 || {
    kw_log ERROR 'Thiếu python3 để sửa owner/quyền .env an toàn; chưa thay đổi file.'; return 2;
  }
  python3 - "$site_root" "$owner" <<'PY'
import os
import pwd
import stat
import sys
from contextlib import ExitStack

site_root, owner = sys.argv[1:]
directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
file_flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC

try:
    user = pwd.getpwnam(owner)
    with ExitStack() as stack:
        site_fd = os.open(site_root, directory_flags)
        stack.callback(os.close, site_fd)
        deploy_fd = os.open('deploy', directory_flags, dir_fd=site_fd)
        stack.callback(os.close, deploy_fd)
        shared_fd = os.open('shared', directory_flags, dir_fd=deploy_fd)
        stack.callback(os.close, shared_fd)
        for directory_fd in (site_fd, deploy_fd, shared_fd):
            info = os.fstat(directory_fd)
            if (not stat.S_ISDIR(info.st_mode) or info.st_uid != user.pw_uid
                    or info.st_mode & 0o022):
                raise ValueError('thư mục site/deploy/shared không an toàn')
        env_fd = os.open('.env', file_flags, dir_fd=shared_fd)
        stack.callback(os.close, env_fd)
        info = os.fstat(env_fd)
        if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
                or info.st_uid not in (0, user.pw_uid)):
            raise ValueError('.env không phải file thường một liên kết của root/site')
        current = os.stat('.env', dir_fd=shared_fd, follow_symlinks=False)
        if current.st_dev != info.st_dev or current.st_ino != info.st_ino:
            raise ValueError('.env đã thay đổi trước khi sửa')
        # Restrict access before handing a root-owned file to the site user.
        os.fchmod(env_fd, 0o600)
        if info.st_uid == 0:
            os.fchown(env_fd, user.pw_uid, user.pw_gid)
        current = os.stat('.env', dir_fd=shared_fd, follow_symlinks=False)
        if (current.st_dev != info.st_dev or current.st_ino != info.st_ino
                or not stat.S_ISREG(current.st_mode)
                or current.st_nlink != 1 or current.st_uid != user.pw_uid
                or stat.S_IMODE(current.st_mode) != 0o600):
            raise ValueError('.env đã thay đổi trong lúc sửa; cần kiểm tra lại')
except (OSError, ValueError, KeyError) as exc:
    print(f'Không sửa được quyền .env an toàn: {exc}', file=sys.stderr)
    sys.exit(2)
PY
}

kw_laravel_env_prepare() {
  local domain=$1 env_file example owner_uid links details
  KW_LARAVEL_ENV_READY=0
  kw_laravel_layout_ready "$domain" || return 2
  env_file=$KW_SITE_ROOT/deploy/shared/.env
  example=$KW_SITE_ROOT/source/.env.example
  [[ ! -L $env_file ]] || {
    kw_log ERROR '.env là symlink; không mở hoặc tự sửa.'; return 2;
  }
  if [[ ! -e $env_file ]]; then
    if [[ -f $example && ! -L $example ]]; then
      runuser -u "$KW_SITE_OWNER" -- install -m 0600 -- "$example" "$env_file" || return 1
    else
      runuser -u "$KW_SITE_OWNER" -- install -m 0600 /dev/null "$env_file" || return 1
    fi
    printf 'Đã tạo .env cho %s; hãy điền APP_KEY, DB và cấu hình ứng dụng.\n' "$domain"
  fi
  if ! kw_laravel_env_safe "$env_file" "$KW_SITE_OWNER"; then
    [[ -f $env_file && ! -L $env_file ]] || {
      kw_log ERROR '.env không phải file thường; không tự sửa.'; return 2;
    }
    links=$(stat -c %h -- "$env_file") || return 2
    owner_uid=$(stat -c %u -- "$env_file") || return 2
    details=$(stat -c 'owner=%U:%G mode=%a links=%h' -- "$env_file") || return 2
    printf '.env của %s hiện có %s (không hiển thị nội dung).\n' "$domain" "$details"
    [[ $links == 1 && ( $owner_uid == 0 || $owner_uid == "$(id -u "$KW_SITE_OWNER")" ) ]] || {
      kw_log ERROR 'Chỉ tự sửa file thường một liên kết thuộc root hoặc user site; cần kiểm tra thủ công.'
      return 2
    }
    kw_prompt_yes_no_token "Chỉ sửa owner/quyền .env của $domain thành $KW_SITE_OWNER:600, giữ nguyên nội dung?" "$domain" || return 0
    kw_laravel_env_repair_fd "$KW_SITE_ROOT" "$KW_SITE_OWNER" || return 2
  fi
  kw_laravel_env_safe "$env_file" "$KW_SITE_OWNER" || {
    kw_log ERROR '.env vẫn chưa an toàn sau khi tạo/sửa; không mở file.'; return 2;
  }
  KW_LARAVEL_ENV_READY=1
}

kw_laravel_env_edit_locked() (
  local domain=$1 env_file
  kw_laravel_layout_ready "$domain" || return 2
  if ! { [[ -t 0 && -t 1 ]] && kw_has nano; }; then
    kw_log ERROR 'Cần terminal tương tác và nano để sửa .env.'; return 2;
  fi
  kw_laravel_env_prepare "$domain" || return 2
  ((KW_LARAVEL_ENV_READY)) || return 0
  env_file=$KW_SITE_ROOT/deploy/shared/.env
  runuser -u "$KW_SITE_OWNER" -- nano "$env_file" || return 1
  kw_laravel_env_safe "$env_file" "$KW_SITE_OWNER" || {
    kw_log ERROR '.env không còn owner/quyền an toàn sau khi sửa; Deploy sẽ từ chối file này.'
    return 2
  }
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
    if kw_site_vhost_matches "$KW_SITE_VHOST" "$domain" "$id" kw_laravel_vhost_template "$kind" "$domain" "$id"; then
      KW_LARAVEL_VHOST_KIND=$kind
      KW_LARAVEL_FIRST=1
      return 0
    fi
    if kw_site_vhost_matches "$KW_SITE_VHOST" "$domain" "$id" kw_laravel_render_vhost "$kind" "$domain" "$id"; then
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
  [[ $code =~ ^[1-4][0-9][0-9]$ || $code == 503 ]] || {
    kw_log ERROR "Health check trả HTTP $code; sẽ quay lại release cũ."; return 1;
  }
  if [[ $code == 503 ]]; then
    printf 'Health check %s: HTTP 503 (chế độ bảo trì / maintenance mode)\n' "$domain"
  else
    printf 'Health check %s: HTTP %s\n' "$domain" "$code"
  fi
}

kw_laravel_run_migrations() {
  local owner=$1 php=$2 release=$3
  printf 'Đang chạy migration bằng PHP %s trong release mới (trước khi đổi current)...\n' "$php"
  if ! runuser -u "$owner" -- "php$php" "$release/artisan" migrate --force --no-interaction; then
    kw_log ERROR 'Migration thất bại; chưa đổi current. Database có thể đã thay đổi một phần, cần kiểm tra trước khi thử lại.'
    return 1
  fi
}

# PHP-FPM is shared by all sites on the same PHP version. Reload it after the
# new release passes its first HTTP check, then probe HTTP again with fresh
# workers so a stale OPcache result cannot mark the deploy successful.
kw_laravel_php_reload_checked() {
  local php=$1 unit
  kw_site_php_valid "$php" || return 2
  unit="php${php}-fpm"
  if ! "php-fpm${php}" -t; then
    kw_log ERROR "Cấu hình $unit không hợp lệ; chưa reload PHP-FPM."
    return 1
  fi
  if ! systemctl reload "$unit"; then
    kw_log ERROR "Không reload được $unit; release sẽ được hoàn tác."
    return 1
  fi
  if ! systemctl is-active --quiet "$unit"; then
    kw_log ERROR "$unit không active sau reload; release sẽ được hoàn tác."
    return 1
  fi
  printf 'Đã reload %s và xác nhận dịch vụ active. Các site cùng phiên bản PHP dùng chung dịch vụ này.\n' "$unit"
}

kw_laravel_deploy_locked() (
  local domain=$1 frontend=${2:-auto} migrate=${3:-0} id source deploy releases shared owner php commit short stamp stage='' release='' archive='' changes command lock_count=0 \
    current next='' previous='' kind first vhost_backup='' vhost_temp='' activated=0 success=0 migration_attempted=0 reload_attempted=0
  # All paths below are absolute. Site-user commands must not inherit /root.
  cd -- / || return 1
  kw_laravel_frontend_valid "$frontend" && kw_laravel_migrate_valid "$migrate" || return 2
  kw_laravel_layout_ready "$domain" && kw_laravel_git_source || return 2
  kw_nginx_ready || return 2
  for command in git tar composer curl runuser "php$KW_SITE_PHP" "php-fpm$KW_SITE_PHP"; do
    kw_has "$command" || { kw_log ERROR "Thiếu $command; chưa đổi website. Cài công cụ này trước."; return 2; }
  done
  id=${KW_SITE_OWNER#kw}; source=$KW_SITE_ROOT/source; deploy=$KW_SITE_ROOT/deploy
  releases=$deploy/releases; shared=$deploy/shared; owner=$KW_SITE_OWNER; php=$KW_SITE_PHP
  current=$deploy/current
  [[ -f $KW_SITE_VHOST && ! -L $KW_SITE_VHOST && $(stat -c %u -- "$KW_SITE_VHOST") == 0 &&
     -L $KW_SITE_ENABLED && $(readlink -- "$KW_SITE_ENABLED") == "$KW_SITE_VHOST" ]] || return 2
  kw_laravel_vhost_kind "$domain" "$id" || return 2
  kind=$KW_LARAVEL_VHOST_KIND; first=$KW_LARAVEL_FIRST
  kw_laravel_env_safe "$shared/.env" "$owner" || {
    kw_log ERROR 'deploy/shared/.env thiếu hoặc owner/quyền chưa an toàn; dùng menu Sửa .env trước (Deploy không tự sửa file).'
    return 2
  }
  if ((first)); then
    [[ ! -e $current && ! -L $current ]] || return 2
  else
    [[ -L $current ]] || return 2
    previous=$(readlink -- "$current") || return 2
    [[ $previous == releases/* && $previous != *..* && -d $deploy/$previous ]] || return 2
  fi
  # The menu's Deploy action is self-contained: update source first, then build that commit.
  kw_laravel_pull_locked "$domain" || return $?
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
      if ! { [[ -f $stage/package.json && -f $stage/package-lock.json && ! -L $stage/package-lock.json ]] &&
             kw_laravel_frontend_command_ready npm; }; then
        kw_log ERROR 'Cần package.json, package-lock.json và npm.'; return 2;
      fi
      kw_laravel_run_frontend "$owner" npm ci --prefix "$stage" || return 1
      kw_laravel_run_frontend "$owner" npm run build --prefix "$stage" || return 1 ;;
    pnpm)
      if ! { [[ -f $stage/package.json && -f $stage/pnpm-lock.yaml && ! -L $stage/pnpm-lock.yaml ]] &&
             kw_laravel_frontend_command_ready pnpm; }; then
        kw_log ERROR 'Cần package.json, pnpm-lock.yaml và pnpm.'; return 2;
      fi
      kw_laravel_run_frontend "$owner" pnpm --dir "$stage" install --frozen-lockfile || return 1
      kw_laravel_run_frontend "$owner" pnpm --dir "$stage" run build || return 1 ;;
    yarn)
      if ! { [[ -f $stage/package.json && -f $stage/yarn.lock && ! -L $stage/yarn.lock ]] &&
             kw_laravel_frontend_command_ready yarn; }; then
        kw_log ERROR 'Cần package.json, yarn.lock và yarn.'; return 2;
      fi
      kw_laravel_run_frontend "$owner" yarn --cwd "$stage" install --frozen-lockfile || return 1
      kw_laravel_run_frontend "$owner" yarn --cwd "$stage" build || return 1 ;;
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
    kw_laravel_render_vhost "$kind" "$domain" "$id" |
      kw_cf_realip_render_for_site "$domain" "$id" > "$vhost_temp" || return 1
    chmod 0644 -- "$vhost_temp" || return 1
  fi
  trap 'if ((!success && migration_attempted)); then kw_log WARN "Migration có thể đã thay đổi database; rollback release không hoàn tác dữ liệu."; fi; if ((activated && ! success)); then if [[ -n $previous ]]; then ln -sfn -- "$previous" "$next" && mv -Tf -- "$next" "$current" || kw_log ERROR "Không thể quay lại release cũ: $current"; else rm -f -- "$current" || kw_log ERROR "Không thể bỏ current: $current"; fi; if [[ -n $vhost_backup ]]; then install -m 0644 -o root -g root -- "$vhost_backup" "$KW_SITE_VHOST" || kw_log ERROR "Cần phục hồi vhost từ $vhost_backup"; fi; kw_nginx_test_restart || kw_log ERROR "Cần kiểm tra Nginx sau rollback: $domain"; if ((reload_attempted)); then kw_laravel_php_reload_checked "$php" || kw_log ERROR "Cần kiểm tra $php-FPM sau rollback: $domain"; fi; fi; [[ -z $vhost_temp ]] || rm -f -- "$vhost_temp"; [[ -z $next ]] || rm -f -- "$next"' EXIT
  if ((migrate)); then
    # shellcheck disable=SC2034 # Read by the EXIT rollback warning trap.
    migration_attempted=1
    kw_laravel_run_migrations "$owner" "$php" "$release" || return 1
  fi
  runuser -u "$owner" -- mv -Tf -- "$next" "$current" || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  activated=1
  if ((first)); then
    mv -Tf -- "$vhost_temp" "$KW_SITE_VHOST" || return 1
    vhost_temp=''
  fi
  kw_nginx_test_restart || return 1
  kw_laravel_health "$domain" "$kind" || return 1
  # shellcheck disable=SC2034 # EXIT rollback trap may reload old workers.
  reload_attempted=1
  kw_laravel_php_reload_checked "$php" || return 1
  kw_laravel_health "$domain" "$kind" || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
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
    deploy-key) kw_laravel_deploy_key_prepare "$domain" ;;
    clone) kw_laravel_clone_locked "$domain" "$@" ;;
    pull) kw_laravel_pull_locked "$domain" "$@" ;;
    env) kw_laravel_env_edit_locked "$domain" ;;
    deploy) kw_laravel_deploy_locked "$domain" "$@" ;;
    *) return 2 ;;
  esac
)

kw_laravel_deploy_confirm() {
  local domain=$1 frontend=$2 migrate=$3 frontend_note
  kw_domain_valid "$domain" && kw_laravel_frontend_valid "$frontend" &&
    kw_laravel_migrate_valid "$migrate" || return 2
  case "$frontend" in
    auto) frontend_note='tự nhận công cụ build frontend từ lockfile' ;;
    none) frontend_note='bỏ qua build frontend' ;;
    *) frontend_note="build frontend bằng $frontend" ;;
  esac
  printf 'Deploy %s: pull nhánh hiện tại, chạy Composer, %s, tạo release, kiểm tra Nginx/HTTP, reload PHP-FPM của phiên bản site rồi thử HTTP lần nữa.\n' "$domain" "$frontend_note"
  printf 'PHP-FPM dùng chung theo phiên bản; reload có thể ảnh hưởng ngắn các site khác đang dùng cùng PHP.\n'
  if ((migrate)); then
    printf 'Có chạy php artisan migrate --force trên release mới trước khi đổi current.\n'
    printf 'CẢNH BÁO: migration có thể không đảo ngược; rollback code không phục hồi database. Hãy backup DB trước.\n'
    printf 'Migration cần tương thích với release đang chạy vì website vẫn phục vụ trong lúc migrate.\n'
  else
    printf 'Không chạy migration. Nếu bản mới cần thay đổi schema, hãy chọn --migrate hoặc trả lời y ở menu.\n'
  fi
  printf 'Composer/build chạy script của repository dưới user site; chỉ dùng Git repo đáng tin cậy.\n'
  kw_prompt_yes_no_token "Triển khai $domain?" "$domain" || return 0
  kw_laravel_with_lock deploy "$domain" "$frontend" "$migrate"
}

kw_laravel_interactive() {
  local action=$1 domain url branch frontend choice migrate
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  if [[ $action != status ]]; then kw_laravel_layout_ready "$domain" || return 2; fi
  case "$action" in
    status) kw_laravel_status_interactive "$domain" ;;
    clone)
      kw_prompt_validated 'Git URL (HTTPS công khai hoặc git@host): ' kw_laravel_git_url_valid \
        'Không chứa token/userinfo/query' plain || return 0
      url=$KW_PROMPT_VALUE
      if [[ $url == git@* || $url == ssh://git@* ]]; then
        kw_laravel_with_lock deploy-key "$domain" || return 2
        if [[ $url == git@github.com:* || $url == ssh://git@github.com/* ]]; then
          printf 'GitHub: vào repository → Settings → Deploy keys → Add deploy key, dán key công khai phía trên.\n'
          printf 'Chỉ cần quyền đọc; không bật Allow write access. KwVPS không tự gửi key lên GitHub.\n'
          printf 'Nếu SSH hỏi xác nhận máy chủ GitHub lần đầu, đối chiếu fingerprint tại\n'
          printf 'https://docs.github.com/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints\n'
        else
          printf 'Thêm key công khai vào mục Deploy keys của Git host tương ứng (chỉ đọc).\n'
        fi
        while :; do
          printf 'Thêm key xong, nhấn Enter để tiếp tục; nhập 0 để quay lại: '
          IFS= read -r choice || return 0
          case "$choice" in
            '') break ;;
            0) return 0 ;;
            *) printf 'Chỉ nhấn Enter hoặc nhập 0.\n' ;;
          esac
        done
      fi
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
      printf '  1. Tự nhận từ lockfile (khuyến nghị)\n'
      printf '  2. Bỏ qua; assets đã có sẵn\n  3. Chọn công cụ thủ công (nâng cao)\n  0. Quay lại\n'
      while :; do
        printf 'Chọn: '
        IFS= read -r choice || return 0
        case "$choice" in
          1) frontend=auto; break ;; 2) frontend=none; break ;;
          3)
            printf '  1. npm\n  2. pnpm\n  3. yarn\n  0. Quay lại\nChọn: '
            IFS= read -r choice || return 0
            case "$choice" in
              1) frontend=npm; break ;; 2) frontend=pnpm; break ;;
              3) frontend=yarn; break ;; 0) return 0 ;;
              *) printf 'Chọn số 0–3.\n' ;;
            esac ;;
          0) return 0 ;;
          *) printf 'Chọn số 0–3.\n' ;;
        esac
      done
      kw_laravel_migrate_prompt || return 0
      migrate=$KW_LARAVEL_MIGRATE
      kw_laravel_deploy_confirm "$domain" "$frontend" "$migrate" ;;
    *) return 2 ;;
  esac
}
