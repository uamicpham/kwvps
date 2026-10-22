#!/usr/bin/env bash
# Per-site PHP-FPM selection. Package installation is intentionally separate.

kw_php_version_supported() {
  case "${1:-}" in 8.5|8.4|8.3|7.4) return 0 ;; *) return 1 ;; esac
}

# CVE-2026-109618/109619: upstream fixed in 8.3.36, 8.4.27, 8.5.12.
# Ubuntu Noble backports both fixes to the PHP 8.3.6 package revision .13.
kw_php_package_version_safe() {
  local version=${1:-} package=${2:-} raw upstream
  kw_php_version_supported "$version" || return 2
  [[ $package =~ ^[A-Za-z0-9.+:~_-]+$ ]] || return 2
  raw=${package#*:}
  [[ $raw =~ ^([0-9]+\.[0-9]+\.[0-9]+) ]] || return 2
  upstream=${BASH_REMATCH[1]}
  [[ $upstream == "$version".* ]] || return 2
  case "$version" in
    # Compare the full version without epoch: 8.5.12~rc1 is older than 8.5.12.
    8.5) dpkg --compare-versions "$raw" ge 8.5.12 ;;
    8.4) dpkg --compare-versions "$raw" ge 8.4.27 ;;
    8.3)
      if dpkg --compare-versions "$raw" ge 8.3.36; then return 0; fi
      [[ $package =~ ^8\.3\.6-0ubuntu0\.24\.04\.[0-9]+$ ]] || return 1
      dpkg --compare-versions "$package" ge 8.3.6-0ubuntu0.24.04.13 ;;
    7.4) return 1 ;; # EOL; no verified fixed Ubuntu 24.04 package yet.
  esac
}

kw_php_security_ready() {
  local version=${1:-} package
  kw_php_version_supported "$version" || return 2
  package=$(dpkg-query -W -f='${Version}' "php${version}-fpm" 2>/dev/null) || return 1
  if kw_php_package_version_safe "$version" "$package"; then return 0; fi
  kw_log ERROR "PHP $version ($package) chưa được xác minh có bản vá CVE-2026-109618/109619; không dùng cho site mới hoặc chuyển site."
  return 1
}

# PHP 7.4 is EOL and never qualifies as security-ready. Site workflows may use it
# only after an explicit per-operation acknowledgement from the administrator.
kw_php_site_ready() {
  local version=${1:-}
  if [[ $version == 7.4 ]]; then
    kw_php_version_installed 7.4 || {
      kw_log ERROR 'PHP 7.4 chưa được cài hoặc PHP-FPM chưa có cấu hình hợp lệ.'
      return 1
    }
    [[ ${KW_PHP_EOL_SITE_ACK:-0} == 1 ]] || {
      kw_log ERROR 'PHP 7.4 đã hết hỗ trợ; cần xác nhận cảnh báo EOL trước khi gắn vào site.'
      return 1
    }
    return 0
  fi
  kw_php_security_ready "$version"
}

kw_php_security_status() {
  local version package status
  printf 'Trạng thái bản vá PHP-FPM cho CVE-2026-109618/109619:\n'
  for version in 8.5 8.4 8.3 7.4; do
    if ! package=$(dpkg-query -W -f='${Version}' "php${version}-fpm" 2>/dev/null); then
      printf 'PHP %s: chưa cài\n' "$version"
      continue
    fi
    if kw_php_package_version_safe "$version" "$package"; then status='ĐẠT';
    else status='CHƯA XÁC MINH — không dùng cho site mới'; fi
    printf 'PHP %s: %s [%s]\n' "$version" "$package" "$status"
  done
  printf 'Ngưỡng upstream: 8.5.12 / 8.4.27 / 8.3.36. Ubuntu 24.04 PHP 8.3 backport: 8.3.6-0ubuntu0.24.04.13.\n'
  printf 'PHP 7.4 EOL; kho Debian deb.sury.org không dùng trực tiếp cho Ubuntu.\n'
}

kw_php_version_installed() {
  local version=$1 status
  kw_php_version_supported "$version" || return 2
  status=$(dpkg-query -W -f='${Status}' "php${version}-fpm" 2>/dev/null) || return 1
  [[ $status == 'install ok installed' && -x /usr/sbin/php-fpm${version} && \
     -d /etc/php/${version}/fpm/pool.d && ! -L /etc/php/${version}/fpm/pool.d ]]
}

kw_php_choose_version() {
  local choice version i=0
  local -a versions=(8.5 8.4 8.3 7.4)
  printf 'Chọn phiên bản PHP-FPM:\n'
  for version in "${versions[@]}"; do
    i=$((i + 1))
    if kw_php_version_installed "$version" && kw_php_security_ready "$version" >/dev/null 2>&1; then
      printf '%2d. PHP %s [đã cài, bản vá đạt]\n' "$i" "$version"
    elif kw_php_version_installed "$version"; then
      if [[ $version == 7.4 ]]; then
        printf '%2d. PHP 7.4 [đã cài, EOL — chỉ dùng nếu chấp nhận rủi ro]\n' "$i"
      else
        printf '%2d. PHP %s [đã cài, CHƯA xác minh bản vá]\n' "$i" "$version"
      fi
    else
      printf '%2d. PHP %s [chưa cài]\n' "$i" "$version"
    fi
  done
  printf ' 0. Quay lại\n'
  while :; do
    printf 'Chọn số phiên bản: '
    IFS= read -r choice || return 1
    [[ $choice != 0 ]] || return 1
    if [[ ! $choice =~ ^[1-4]$ ]]; then
      printf 'Số phiên bản không hợp lệ; nhập lại.\n'
      continue
    fi
    KW_PHP_CHOICE=${versions[choice-1]}
    if [[ $KW_PHP_CHOICE == 7.4 ]]; then
      if kw_php_version_installed 7.4; then
        printf 'CẢNH BÁO: PHP 7.4 đã hết hỗ trợ bảo mật. Dùng cho site có thể làm website dễ bị tấn công; hãy nâng cấp ứng dụng lên PHP còn hỗ trợ càng sớm càng tốt.\n'
        if kw_prompt_yes_no_token 'Tôi hiểu rủi ro EOL và vẫn muốn dùng PHP 7.4 cho site này?' 'USE-EOL-PHP:7.4'; then
          KW_PHP_EOL_SITE_ACK=1
          return 0
        fi
      fi
      printf 'PHP 7.4 chưa cài hoặc chưa xác nhận rủi ro; chọn lại hoặc 0 để quay lại.\n'
      continue
    fi
    if kw_php_version_installed "$KW_PHP_CHOICE" && kw_php_security_ready "$KW_PHP_CHOICE"; then return 0; fi
    printf 'PHP %s chưa cài hoặc chưa có bản vá được KwVPS xác minh; chọn phiên bản khác hoặc 0 để quay lại.\n' "$KW_PHP_CHOICE"
  done
}

kw_php_apt_candidate() {
  local version=$1 policy candidate
  kw_php_version_supported "$version" || return 2
  policy=$(LC_ALL=C apt-cache policy "php${version}-fpm") || return 2
  candidate=$(awk '/^[[:space:]]*Candidate:/ { print $2; exit }' <<< "$policy") || return 2
  [[ -n $candidate && $candidate != '(none)' ]] || return 1
  KW_PHP_APT_CANDIDATE=$candidate
}

kw_php_candidate_provenance() {
  local version=$1 candidate=$2 package listings verdict
  package=${3:-php${version}-fpm}
  [[ $package == "php${version}-fpm" || $package == php-common ]] || return 2
  listings=$(LC_ALL=C apt-cache madison "$package") || return 2
  verdict=$(awk -F '|' -v wanted="$candidate" '
    { version=$2; origin=$3;
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", version);
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", origin);
      if (version != wanted) next;
      count++;
      split(origin, fields, /[[:space:]]+/); url=fields[1];
      if (url ~ /^https?:\/\/([[:alnum:]-]+\.)*archive\.ubuntu\.com\/ubuntu\/?$/ ||
          url ~ /^https?:\/\/security\.ubuntu\.com\/ubuntu\/?$/ ||
          url ~ /^https?:\/\/ports\.ubuntu\.com\/ubuntu-ports\/?$/) kind="ubuntu";
      else if (url ~ /^https?:\/\/ppa\.launchpad(content)?\.net\/ondrej\/php\/ubuntu\/?$/) kind="ondrej";
      else { bad=1; next }
      seen[kind]=1;
      if (first == "") first=url
    }
    END {
      if (count == 0 || bad || (seen["ubuntu"] && seen["ondrej"])) exit 1;
      if (seen["ubuntu"]) print "ubuntu|" first;
      else if (seen["ondrej"]) print "ondrej|" first;
      else exit 1
    }
  ' <<< "$listings") || return 2
  KW_PHP_APT_ORIGIN_KIND=${verdict%%|*}
  KW_PHP_APT_ORIGIN_URL=${verdict#*|}
}

kw_php_ondrej_repo_present() {
  local source
  for source in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [[ -f $source ]] || continue
    if LC_ALL=C grep -Eq 'ppa\.launchpad(content)?\.net/ondrej/php/ubuntu/' "$source"; then return 0; fi
  done
  return 1
}

kw_php_debian_sury_repo_present() {
  local source
  for source in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [[ -f $source ]] || continue
    if LC_ALL=C grep -Eq 'https?://deb\.sury\.org/php' "$source"; then return 0; fi
  done
  return 1
}

kw_php_ondrej_pin_contents() {
  # Keep Ubuntu packages preferred: PPA packages remain installable when Ubuntu lacks them.
  printf 'Package: *\nPin: release o=LP-PPA-ondrej-php\nPin-Priority: 100\n'
}

kw_php_ondrej_pin_matches() {
  local pin=/etc/apt/preferences.d/kwvps-ondrej-php.pref
  [[ -f $pin && ! -L $pin && $(stat -c %u -- "$pin") == 0 ]] || return 1
  kw_php_ondrej_pin_contents | cmp -s - "$pin"
}

kw_php_ondrej_pin_install() {
  local pin=/etc/apt/preferences.d/kwvps-ondrej-php.pref tmp
  [[ -d /etc/apt/preferences.d && ! -L /etc/apt/preferences.d ]] || return 2
  if [[ -e $pin || -L $pin ]]; then
    [[ -f $pin && ! -L $pin && $(stat -c %u -- "$pin") == 0 ]] || return 2
    kw_php_ondrej_pin_contents | cmp -s - "$pin" || {
      kw_log ERROR "File $pin đã tồn tại với nội dung khác; không ghi đè."; return 2;
    }
    return 0
  fi
  tmp=$(mktemp /etc/apt/preferences.d/.kwvps-ondrej-php.XXXXXXXX) || return 1
  if ! kw_php_ondrej_pin_contents > "$tmp" ||
     ! chmod 0644 -- "$tmp" ||
     ! chown root:root -- "$tmp" ||
     ! mv -T -- "$tmp" "$pin"; then
    rm -f -- "$tmp"
    return 1
  fi
}

kw_php_ondrej_enable() {
  ((EUID == 0)) || return 2
  kw_php_ondrej_pin_install || return 2
  if kw_php_ondrej_repo_present; then
    printf 'PPA ppa:ondrej/php đã có trong nguồn APT; sẽ cập nhật danh mục gói.\n'
  else
    if ! kw_has add-apt-repository || ! /usr/bin/python3 -c 'import launchpadlib' >/dev/null 2>&1; then
      printf 'Cài software-properties-common và python3-launchpadlib từ kho Ubuntu để thêm PPA.\n'
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove --no-install-recommends software-properties-common python3-launchpadlib || return 1
    fi
    # Ubuntu/Launchpad adds its signed source; never use the Debian deb.sury.org repository.
    add-apt-repository --no-update -y ppa:ondrej/php || return 1
  fi
  apt-get update || return 1
}

kw_php_prepare_candidate() {
  local version=$1 candidate='' candidate_status
  if ! kw_php_version_supported "$version"; then return 2; fi
  if kw_php_apt_candidate "$version"; then
    candidate=$KW_PHP_APT_CANDIDATE
    kw_php_candidate_provenance "$version" "$candidate" || {
      kw_log ERROR "Candidate PHP $version ($candidate) có nguồn APT không được xác minh hoặc trùng giữa nhiều nguồn; không cài."; return 2;
    }
    if kw_php_package_version_safe "$version" "$candidate"; then
      if [[ $KW_PHP_APT_ORIGIN_KIND == ondrej ]] && ! kw_php_ondrej_pin_matches; then
        printf 'PHP %s hiện đến từ PPA Ondřej; cần ghim PPA ưu tiên thấp hơn kho Ubuntu trước khi cài.\n' "$version"
        kw_prompt_yes_no_token 'Áp ưu tiên APT an toàn cho PPA?' "PIN-PHP:$version" || return 1
        kw_php_ondrej_pin_install || return 2
        kw_php_apt_candidate "$version" || {
          kw_log ERROR 'Candidate thay đổi sau khi áp ưu tiên APT; không cài.'; return 2;
        }
        candidate=$KW_PHP_APT_CANDIDATE
        if ! kw_php_candidate_provenance "$version" "$candidate" ||
           ! kw_php_package_version_safe "$version" "$candidate"; then
          kw_log ERROR 'Candidate sau khi ghim PPA không còn đạt nguồn/bản vá; không cài.'
          return 2
        fi
      fi
      KW_PHP_APT_CANDIDATE=$candidate
      return 0
    fi
    printf 'APT hiện có PHP %s (%s), nhưng bản này chưa đạt ngưỡng vá.\n' "$version" "$candidate"
  else
    candidate_status=$?
    [[ $candidate_status == 1 ]] || {
      kw_log ERROR 'Không đọc được danh mục APT; chưa thay đổi nguồn gói.'; return 2;
    }
    printf 'APT hiện chưa có PHP %s-FPM.\n' "$version"
  fi
  [[ $version == 8.4 || $version == 8.5 || $version == 7.4 ]] || {
    kw_log ERROR "Không có candidate PHP $version đạt bản vá trong APT; không cài."; return 2;
  }
  printf 'Có thể dùng PPA Ubuntu ppa:ondrej/php (Ondřej Surý), KHÔNG dùng kho Debian deb.sury.org.\n'
  printf 'PPA có thể cung cấp gói PHP cho các phiên bản khác; KwVPS ghim ưu tiên PPA thấp hơn kho Ubuntu.\n'
  kw_prompt_yes_no_token 'Thêm/cập nhật PPA và kiểm tra lại PHP?' "PPA-PHP:$version" || return 1
  kw_php_ondrej_enable || return 2
  kw_php_apt_candidate "$version" || {
    kw_log ERROR "PPA đã cập nhật nhưng vẫn không có PHP $version-FPM."; return 2;
  }
  candidate=$KW_PHP_APT_CANDIDATE
  kw_php_candidate_provenance "$version" "$candidate" || {
    kw_log ERROR "Candidate PHP $version ($candidate) có nguồn APT không được xác minh hoặc trùng giữa nhiều nguồn; không cài."; return 2;
  }
  if [[ $version == 7.4 ]]; then
    [[ $KW_PHP_APT_ORIGIN_KIND == ondrej && $candidate =~ ^(1:)?7\.4\.[0-9]+[-+~A-Za-z0-9.]*$ ]] || {
      kw_log ERROR "PPA không cung cấp candidate PHP 7.4 có nguồn/định dạng phiên bản được xác minh; không cài."; return 2;
    }
    printf 'CẢNH BÁO BẢO MẬT: PHP 7.4 đã hết hỗ trợ; KwVPS không thể xác minh bản vá cho các lỗ hổng hiện tại. Chỉ cài cho tương thích ứng dụng cũ, không khuyến nghị đưa website Internet vào phiên bản này.\n'
  else
    kw_php_package_version_safe "$version" "$candidate" || {
      kw_log ERROR "PPA có PHP $version ($candidate) nhưng chưa đạt ngưỡng vá; không cài."; return 2;
    }
  fi
  printf 'Candidate sau cập nhật: PHP %s %s từ %s (%s)\n' "$version" "$candidate" "$KW_PHP_APT_ORIGIN_URL" "$KW_PHP_APT_ORIGIN_KIND"
  KW_PHP_APT_CANDIDATE=$candidate
}

kw_php_common_requirement() {
  local simulation=$1 requirements required best=''
  requirements=$(awk '
    match($0, /Depends: php-common \(>= [^)]+\)/) {
      value=substr($0, RSTART, RLENGTH)
      sub(/^.*\(>= /, "", value)
      sub(/\)$/, "", value)
      print value
    }
  ' <<< "$simulation") || return 2
  [[ -n $requirements ]] || return 1
  while IFS= read -r required; do
    [[ $required =~ ^[0-9]+:[0-9][A-Za-z0-9.+~_-]*$ ]] || return 2
    if [[ -z $best ]] || dpkg --compare-versions "$required" gt "$best"; then best=$required; fi
  done <<< "$requirements"
  KW_PHP_COMMON_REQUIRED=$best
}

kw_php_common_ppa_version() {
  local version=$1 required=$2 listings package candidate source best=''
  [[ $required =~ ^[0-9]+:[0-9][A-Za-z0-9.+~_-]*$ ]] || return 2
  listings=$(LC_ALL=C apt-cache madison php-common) || return 2
  while IFS='|' read -r package candidate source; do
    [[ $package =~ ^[[:space:]]*php-common[[:space:]]*$ ]] || continue
    candidate=${candidate//[[:space:]]/}
    [[ $candidate =~ ^[0-9]+:[0-9][A-Za-z0-9.+~_-]*$ ]] || continue
    [[ $source =~ https?://ppa\.launchpad(content)?\.net/ondrej/php/ubuntu/?([[:space:]]|$) ]] || continue
    if dpkg --compare-versions "$candidate" ge "$required"; then
      if [[ -z $best ]] || dpkg --compare-versions "$candidate" gt "$best"; then best=$candidate; fi
    fi
  done <<< "$listings"
  [[ -n $best ]] || return 1
  kw_php_candidate_provenance "$version" "$best" php-common || return 2
  [[ $KW_PHP_APT_ORIGIN_KIND == ondrej ]] || return 2
  KW_PHP_COMMON_VERSION=$best
  KW_PHP_COMMON_ORIGIN_URL=$KW_PHP_APT_ORIGIN_URL
}

kw_php_simulate_install() {
  local version=$1 required
  shift
  local -a packages=("$@")
  KW_PHP_INSTALL_PPA_COMMON=''
  if ! KW_PHP_INSTALL_SIMULATION=$(LC_ALL=C apt-get -s --no-remove --no-install-recommends install "${packages[@]}" 2>&1); then
    if [[ $KW_PHP_APT_ORIGIN_KIND != ondrej ]] || ! kw_php_common_requirement "$KW_PHP_INSTALL_SIMULATION"; then
      kw_log ERROR 'APT không mô phỏng được kế hoạch cài gói; chưa thay đổi VPS.'
      printf '%s\n' "$KW_PHP_INSTALL_SIMULATION"
      return 2
    fi
    required=$KW_PHP_COMMON_REQUIRED
    kw_php_common_ppa_version "$version" "$required" || {
      kw_log ERROR "Không tìm được php-common từ PPA Ondřej đạt phụ thuộc >= $required; không cài."
      return 2
    }
    packages=("php-common=$KW_PHP_COMMON_VERSION" "${packages[@]}")
    printf 'APT cần php-common >= %s; thử bản PPA %s từ %s.\n' "$required" "$KW_PHP_COMMON_VERSION" "$KW_PHP_COMMON_ORIGIN_URL"
    KW_PHP_INSTALL_PPA_COMMON=$KW_PHP_COMMON_VERSION
    KW_PHP_INSTALL_SIMULATION=$(LC_ALL=C apt-get -s --no-remove --no-install-recommends install "${packages[@]}" 2>&1) || {
      kw_log ERROR 'APT vẫn không mô phỏng được sau khi chọn php-common PPA; không cài.'
      printf '%s\n' "$KW_PHP_INSTALL_SIMULATION"
      return 2
    }
  fi
  if grep -Eq '^Remv[[:space:]]' <<< "$KW_PHP_INSTALL_SIMULATION"; then
    kw_log ERROR 'Kế hoạch APT có gỡ package; không cài.'
    return 2
  fi
  KW_PHP_INSTALL_PACKAGES=("${packages[@]}")
}

kw_php_install_interactive() {
  local choice version candidate candidate_status current_common
  local -a versions=(8.5 8.4 8.3 7.4) packages
  if ((EUID != 0)) || ! kw_os_supported ''; then
    kw_log ERROR 'Cần root trên Ubuntu 24.04.'
    return 2
  fi
  if kw_php_debian_sury_repo_present; then
    kw_log ERROR 'Đã phát hiện nguồn Debian deb.sury.org trong APT. Gỡ hoặc vô hiệu hóa nguồn này trước khi cài PHP trên Ubuntu.'
    return 2
  fi
  printf 'Cài PHP-FPM và extension từ APT; PHP 8.4/8.5 có thể dùng PPA Ubuntu ppa:ondrej/php sau xác nhận.\n'
  printf '1. PHP 8.5\n2. PHP 8.4\n3. PHP 8.3\n4. PHP 7.4 (EOL, chỉ PPA Ondřej; không khuyến nghị)\n0. Quay lại\nChọn: '
  IFS= read -r choice || return 0
  [[ $choice =~ ^[1-4]$ ]] || return 0
  version=${versions[choice-1]}
  if [[ $version == 7.4 ]]; then
    printf '\nPHP 7.4 đã hết hỗ trợ bảo mật. Cài đặt chỉ phục vụ tương thích ứng dụng cũ; KwVPS sẽ không đánh dấu phiên bản này an toàn để tạo/chuyển site.\n'
    kw_prompt_yes_no_token 'Tôi hiểu rủi ro và vẫn muốn cài PHP 7.4 từ PPA Ubuntu Ondřej?' 'INSTALL-EOL-PHP:7.4' || return 0
    if ! kw_php_ondrej_repo_present; then
      printf 'PHP 7.4 chỉ được lấy từ PPA Ubuntu ppa:ondrej/php; cần thêm nguồn này.\n'
      kw_prompt_yes_no_token 'Thêm/cập nhật PPA Ondřej cho PHP 7.4?' 'PPA-PHP:7.4' || return 0
      kw_php_ondrej_enable || return 2
    fi
  fi
  if kw_php_version_installed "$version" && kw_php_security_ready "$version"; then
    printf 'PHP %s đã cài và đạt kiểm tra bản vá; sẽ kiểm tra/bổ sung extension còn thiếu.\n' "$version"
  fi
  if kw_php_prepare_candidate "$version"; then
    :
  else
    candidate_status=$?
    if [[ $candidate_status == 1 ]]; then return 0; fi
    return "$candidate_status"
  fi
  candidate=$KW_PHP_APT_CANDIDATE
  kw_php_candidate_provenance "$version" "$candidate" || {
    kw_log ERROR 'Không kiểm tra được nguồn package của candidate PHP; không cài.'; return 2;
  }
  packages=("php${version}-fpm=$candidate")
  local extension
  for extension in cli mysql mbstring xml curl zip gd intl bcmath; do
    packages+=("php${version}-${extension}")
  done
  kw_php_simulate_install "$version" "${packages[@]}" || return 2
  kw_php_candidate_provenance "$version" "$candidate" || return 2
  printf 'PHP %s candidate: %s\nNguồn gói: %s (%s)\nGói sẽ cài: %s\n' "$version" "$candidate" "$KW_PHP_APT_ORIGIN_URL" "$KW_PHP_APT_ORIGIN_KIND" "${KW_PHP_INSTALL_PACKAGES[*]}"
  if [[ -n $KW_PHP_INSTALL_PPA_COMMON ]]; then
    current_common=$(dpkg-query -W -f='${Version}' php-common 2>/dev/null) || current_common='chưa cài'
    printf 'LƯU Ý: sẽ đổi php-common dùng chung từ %s sang %s (PPA Ondřej); có thể ảnh hưởng mọi phiên bản PHP.\n' "$current_common" "$KW_PHP_INSTALL_PPA_COMMON"
  fi
  printf 'LƯU Ý: APT có thể đổi lệnh php CLI mặc định toàn VPS; PHP-FPM của từng site vẫn độc lập.\n'
  printf '%s\n' "$KW_PHP_INSTALL_SIMULATION" | awk '/^(Inst|Remv|Conf) / { print }'
  kw_prompt_yes_no_token "Cài PHP $version và extension trên VPS?" "INSTALL-PHP:$version" || return 0
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove --no-install-recommends "${KW_PHP_INSTALL_PACKAGES[@]}" || return 1
  if ! kw_php_version_installed "$version" ||
     { [[ $version != 7.4 ]] && ! kw_php_security_ready "$version"; } ||
     ! "php-fpm${version}" -t ||
     ! systemctl is-active --quiet "php${version}-fpm"; then
    kw_log ERROR "Đã chạy APT nhưng PHP $version chưa qua kiểm tra; không dùng cho site. Kiểm tra package và service."
    return 1
  fi
  if [[ $version == 7.4 ]]; then
    printf 'Đã cài PHP 7.4 từ PPA Ondřej; PHP-FPM hoạt động. Đây là phiên bản EOL, không được KwVPS xác nhận an toàn để chạy site Internet.\n'
  else
    printf 'Đã cài PHP %s, bản vá đạt và PHP-FPM hoạt động.\n' "$version"
  fi
}

kw_php_backup_file() {
  local file=$1 label=$2 stamp target
  [[ -f $file && ! -L $file && $(stat -c %u -- "$file") == 0 ]] || return 2
  [[ $label =~ ^[a-z0-9-]{1,50}$ ]] || return 2
  kw_backup_dir_safe /var/backups 0022 || return 2
  kw_backup_dir_safe "$KW_BACKUP_ROOT" 0077 || return 2
  stamp=$(date -u +%Y%m%dT%H%M%SZ) || return 1
  target="$KW_BACKUP_ROOT/php-${label}-${stamp}-${BASHPID}.bak"
  [[ ! -e $target && ! -L $target ]] || return 2
  cp -p -- "$file" "$target" || return 1
  chmod 0600 -- "$target" || return 1
  KW_PHP_BACKUP=$target
}

kw_php_switch_plan() {
  local domain=${1,,} version=$2
  kw_php_version_supported "$version" || return 2
  kw_site_lookup "$domain" || return 2
  printf 'Đổi %s: PHP %s → %s.\n' "$domain" "$KW_SITE_PHP" "$version"
  printf 'Giữ socket theo site và vhost hiện tại. Tạm dừng pool cũ, bật pool mới rồi cập nhật metadata.\n'
  printf 'Có thể có gián đoạn ngắn; sao lưu pool/metadata và thử rollback khi lỗi.\n'
  [[ $version != 7.4 ]] || printf 'CẢNH BÁO: PHP 7.4 đã hết hỗ trợ bảo mật; chỉ dùng khi thực sự cần.\n'
  if kw_php_version_installed "$version"; then printf 'PHP mục tiêu đã cài.\n';
  else printf 'PHP mục tiêu chưa cài; KwVPS sẽ không tự thêm nguồn package ngoài.\n'; fi
}

kw_php_switch_locked() (
  local domain=$1 version=$2 old old_pool new_pool meta backup_pool backup_meta tmp='' old_removed=0 new_added=0 meta_changed=0 committed=0 attempt
  ((EUID == 0)) || return 2
  kw_php_version_supported "$version" && kw_php_version_installed "$version" &&
    kw_php_site_ready "$version" || return 2
  kw_site_lookup "$domain" || return 2
  old=$KW_SITE_PHP; old_pool=$KW_SITE_POOL; meta=$KW_SITE_META
  [[ $old != "$version" ]] || { printf 'Site đã dùng PHP %s.\n' "$version"; return 0; }
  new_pool="/etc/php/${version}/fpm/pool.d/kwvps-${KW_SITE_OWNER#kw}.conf"
  [[ -f $old_pool && ! -L $old_pool && ! -e $new_pool && ! -L $new_pool && \
     -f $meta && ! -L $meta && $(stat -c %u -- "$meta") == 0 ]] || return 2
  systemctl is-active --quiet "php${old}-fpm" || return 2
  systemctl is-active --quiet "php${version}-fpm" || return 2
  "php-fpm${old}" -t >/dev/null 2>&1 && "php-fpm${version}" -t >/dev/null 2>&1 || return 2
  kw_php_backup_file "$old_pool" "pool-${KW_SITE_OWNER#kw}" || return 1
  backup_pool=$KW_PHP_BACKUP
  kw_php_backup_file "$meta" "meta-${KW_SITE_OWNER#kw}" || return 1
  backup_meta=$KW_PHP_BACKUP
  trap 'if ((committed == 0)); then if ((meta_changed)); then install -m 0644 -o root -g root -- "$backup_meta" "$meta" || kw_log ERROR "Cần phục hồi metadata: $backup_meta"; fi; if ((new_added)); then rm -f -- "$new_pool"; systemctl reload "php${version}-fpm" || true; fi; if ((old_removed)); then install -m 0644 -o root -g root -- "$backup_pool" "$old_pool"; systemctl reload "php${old}-fpm" || kw_log ERROR "Cần phục hồi pool cũ: $backup_pool"; fi; fi; [[ -z $tmp ]] || rm -f -- "$tmp"' EXIT
  rm -f -- "$old_pool" || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  old_removed=1
  "php-fpm${old}" -t >/dev/null || return 1
  systemctl reload "php${old}-fpm" || return 1
  install -m 0644 -o root -g root -- "$backup_pool" "$new_pool" || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  new_added=1
  "php-fpm${version}" -t >/dev/null || return 1
  systemctl reload "php${version}-fpm" || return 1
  for ((attempt=0; attempt<5; attempt++)); do
    [[ -S $KW_SITE_SOCKET ]] && break
    sleep 1
  done
  [[ -S $KW_SITE_SOCKET ]] || { kw_log ERROR 'PHP socket mới chưa hoạt động.'; return 1; }
  tmp=$(mktemp /etc/kwvps/sites/.php-switch.XXXXXXXX) || return 1
  sed "s/^php_version=${old}$/php_version=${version}/" "$meta" > "$tmp" || return 1
  [[ $(grep -c '^php_version=' "$tmp") == 1 ]] || return 1
  chmod 0644 -- "$tmp" || return 1
  mv -T -- "$tmp" "$meta" || return 1
  tmp=''
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  meta_changed=1
  kw_site_lookup "$domain" || return 1
  [[ $KW_SITE_PHP == "$version" ]] || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  committed=1
  printf 'Đã chuyển %s sang PHP %s. Backup: %s, %s\n' "$domain" "$version" "$backup_pool" "$backup_meta"
)

kw_php_switch() (
  local domain=${1,,} version=$2 confirm=${3:-}
  kw_domain_valid "$domain" && kw_php_version_supported "$version" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || return 1
  kw_php_switch_locked "$domain" "$version"
)

kw_php_switch_interactive() {
  local domain version confirm KW_PHP_EOL_SITE_ACK=0
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_php_choose_version || return 0
  version=$KW_PHP_CHOICE
  kw_php_switch_plan "$domain" "$version" || return 2
  kw_prompt_yes_no_token "Đổi PHP của $domain sang $version?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_php_switch "$domain" "$version" "${confirm,,}"
}

kw_php_pool_value_valid() {
  local field=$1 value=$2 max
  case "$field" in
    pm.max_children) max=128 ;;
    pm.max_requests) max=10000 ;;
    *) return 2 ;;
  esac
  [[ $value =~ ^[1-9][0-9]*$ ]] && ((${#value} <= 5 && value <= max))
}

kw_php_pool_current() {
  local field=$1 pool=$2
  [[ $field == pm.max_children || $field == pm.max_requests ]] || return 2
  [[ -f $pool && ! -L $pool ]] || return 2
  [[ $(grep -Ec "^[[:space:]]*${field//./\.}[[:space:]]*=" "$pool") == 1 ]] || return 2
  KW_POOL_CURRENT=$(awk -F= -v key="$field" '
    { name=$1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", name);
      if (name == key) { value=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); print value } }
  ' "$pool") || return 2
  kw_php_pool_value_valid "$field" "$KW_POOL_CURRENT"
}

kw_php_pool_tune_locked() (
  local domain=$1 field=$2 value=$3 pool version backup temp='' swapped=0 committed=0
  ((EUID == 0)) || return 2
  kw_site_lookup "$domain" || return 2
  pool=$KW_SITE_POOL; version=$KW_SITE_PHP
  [[ -f $pool && ! -L $pool && $(stat -c %u -- "$pool") == 0 ]] || return 2
  kw_php_pool_current "$field" "$pool" || return 2
  [[ $KW_POOL_CURRENT != "$value" ]] || { printf 'Giá trị đã là %s.\n' "$value"; return 0; }
  kw_php_backup_file "$pool" "tune-${KW_SITE_OWNER#kw}" || return 1
  backup=$KW_PHP_BACKUP
  temp=$(mktemp "/etc/php/${version}/fpm/pool.d/.kwvps-tune.XXXXXXXX") || return 1
  trap 'if ((swapped == 1 && committed == 0)); then install -m 0644 -o root -g root -- "$backup" "$pool" && "php-fpm${version}" -t && systemctl reload "php${version}-fpm" || kw_log ERROR "Cần phục hồi pool thủ công: $backup"; fi; [[ -z $temp ]] || rm -f -- "$temp"' EXIT
  awk -F= -v key="$field" -v replacement="$value" '
    { name=$1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", name);
      if (name == key) print key " = " replacement; else print $0 }
  ' "$pool" > "$temp" || return 1
  chmod 0644 -- "$temp" || return 1
  mv -T -- "$temp" "$pool" || return 1
  temp=''
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  swapped=1
  "php-fpm${version}" -t || return 1
  systemctl reload "php${version}-fpm" || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  committed=1
  printf 'Đã đặt %s = %s cho %s. Backup: %s\n' "$field" "$value" "$domain" "$backup"
)

kw_php_pool_tune() (
  local domain=${1,,} field=$2 value=$3 confirm=${4:-}
  kw_domain_valid "$domain" && kw_php_pool_value_valid "$field" "$value" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || return 1
  kw_php_pool_tune_locked "$domain" "$field" "$value"
)

kw_php_pool_interactive() {
  local domain choice field value confirm
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_site_php_pool_info "$domain" || return 2
  printf '\n1. Đổi pm.max_children (1–128)\n2. Đổi pm.max_requests (1–10000)\n0. Quay lại\nChọn: '
  IFS= read -r choice || return 0
  case "$choice" in 1) field=pm.max_children ;; 2) field=pm.max_requests ;; 0) return 0 ;; *) return 2 ;; esac
  kw_prompt_validated 'Giá trị mới: ' kw_php_pool_value_valid \
    'Giá trị ngoài giới hạn của pool' plain "$field" || return 0
  value=$KW_PROMPT_VALUE
  kw_prompt_yes_no_token "Đổi $field cho $domain thành $value?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_php_pool_tune "$domain" "$field" "$value" "${confirm,,}"
}

kw_php_pool_identity() {
  local file=$1
  [[ -f $file && ! -L $file ]] || return 2
  awk '
    /^\[kwvps-[a-z0-9]+\]$/ { print; section++; next }
    /^[[:space:]]*[#;]/ { next }
    index($0, "=") {
      split($0, pieces, "="); key=pieces[1]; value=substr($0, index($0, "=")+1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (key ~ /^(user|group|listen|listen\.owner|listen\.group|listen\.mode|clear_env|security\.limit_extensions)$/) {
        seen[key]++; print key "=" value
      }
    }
    END {
      if (section != 1) exit 2
      split("user group listen listen.owner listen.group listen.mode clear_env security.limit_extensions", required, " ")
      for (i in required) if (seen[required[i]] != 1) exit 2
    }
  ' "$file" | LC_ALL=C sort
}

kw_php_pool_custom_locked() (
  local domain=$1 pool version backup temp='' swapped=0 committed=0 original_identity edited_identity
  ((EUID == 0)) || return 2
  [[ -t 0 && -t 1 ]] || { kw_log ERROR 'nano cần terminal tương tác.'; return 2; }
  kw_has nano || return 2
  kw_site_lookup "$domain" || return 2
  pool=$KW_SITE_POOL; version=$KW_SITE_PHP
  [[ -f $pool && ! -L $pool && $(stat -c %u -- "$pool") == 0 ]] || return 2
  original_identity=$(kw_php_pool_identity "$pool") || return 2
  kw_php_backup_file "$pool" "custom-${KW_SITE_OWNER#kw}" || return 1
  backup=$KW_PHP_BACKUP
  temp=$(mktemp "/etc/php/${version}/fpm/pool.d/.kwvps-custom.XXXXXXXX") || return 1
  trap 'if ((swapped == 1 && committed == 0)); then install -m 0644 -o root -g root -- "$backup" "$pool" && "php-fpm${version}" -t && systemctl reload "php${version}-fpm" || kw_log ERROR "Cần phục hồi pool thủ công: $backup"; fi; [[ -z $temp ]] || rm -f -- "$temp"' EXIT
  cp -- "$pool" "$temp" || return 1
  chmod 0644 -- "$temp" || return 1
  nano "$temp" || return 1
  edited_identity=$(kw_php_pool_identity "$temp") || return 2
  [[ $edited_identity == "$original_identity" ]] || {
    kw_log ERROR 'Không được đổi user/group/socket hoặc các ràng buộc an toàn của pool.'; return 2;
  }
  cmp -s -- "$pool" "$temp" && { printf 'Không có thay đổi.\n'; return 0; }
  mv -T -- "$temp" "$pool" || return 1
  temp=''
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  swapped=1
  "php-fpm${version}" -t || return 1
  systemctl reload "php${version}-fpm" || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  committed=1
  printf 'Đã lưu pool %s. Backup: %s\n' "$domain" "$backup"
)

kw_php_pool_custom() (
  local domain=${1,,} confirm=${2:-}
  kw_domain_valid "$domain" && [[ $confirm == "$domain" ]] || return 2
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-sites.lock || return 2
  flock -n 9 || return 1
  kw_php_pool_custom_locked "$domain"
)

kw_php_pool_custom_interactive() {
  local domain confirm
  kw_site_prompt_domain || return 0
  domain=$KW_SITE_CHOICE
  kw_prompt_yes_no_token "Mở bản sao pool của $domain trong nano?" "$domain" || return 0
  confirm=$KW_PROMPT_VALUE
  kw_php_pool_custom "$domain" "${confirm,,}"
}

# ionCube is a Zend extension shared by every FPM pool of one PHP version.
# The operator supplies an official, independently verified loader and digest.
kw_php_ioncube_path() {
  kw_php_version_supported "$1" || return 2
  printf '/etc/php/%s/fpm/conf.d/00-kwvps-ioncube.ini\n' "$1"
}

kw_php_ioncube_status() {
  local version path
  for version in 8.5 8.4 8.3 7.4; do
    path=$(kw_php_ioncube_path "$version") || return 2
    if [[ -f $path && ! -L $path ]]; then
      printf 'PHP %s: ionCube do KwVPS quản lý đang bật\n' "$version"
    elif [[ -e $path || -L $path ]]; then
      printf 'PHP %s: cấu hình ionCube có xung đột; không chỉnh sửa\n' "$version"
    else
      printf 'PHP %s: chưa bật bằng KwVPS\n' "$version"
    fi
  done
}

kw_php_ioncube_digest_valid() { [[ ${1:-} =~ ^[a-fA-F0-9]{64}$ ]]; }

kw_php_ioncube_enable() (
  local version=$1 digest=${2,,} source_file target ini tmp='' installed=0
  ((EUID == 0)) || return 2
  kw_php_version_supported "$version" && kw_php_ioncube_digest_valid "$digest" || return 2
  exec 9>/run/lock/kwvps-ioncube.lock || return 2
  flock -n 9 || return 1
  kw_php_version_installed "$version" && kw_php_security_ready "$version" || return 2
  [[ $(uname -m) == x86_64 ]] || { kw_log ERROR 'Loader hiện chỉ hỗ trợ Linux x86_64.'; return 2; }
  source_file="/root/kwvps-loaders/ioncube_loader_lin_${version}.so"
  target="/usr/local/lib/kwvps/ioncube/ioncube_loader_lin_${version}.so"
  ini=$(kw_php_ioncube_path "$version") || return 2
  [[ -d /root/kwvps-loaders && ! -L /root/kwvps-loaders &&
     $(stat -c %u -- /root/kwvps-loaders) == 0 &&
     -f $source_file && ! -L $source_file &&
     $(stat -c %u -- "$source_file") == 0 &&
     ! -e $target && ! -L $target && ! -e $ini && ! -L $ini ]] || {
    kw_log ERROR "Cần file chính thức, root-owned tại $source_file; không ghi đè loader/cấu hình đã có."
    return 2
  }
  [[ $(sha256sum -- "$source_file" | awk '{print $1}') == "$digest" ]] || {
    kw_log ERROR 'SHA-256 không khớp; dừng trước khi cài.'; return 2;
  }
  command -v "php${version}" >/dev/null 2>&1 || return 2
  "php${version}" -n -d "zend_extension=$source_file" -v 2>&1 | grep -Fq 'ionCube PHP Loader' || {
    kw_log ERROR 'Loader không chạy được với PHP CLI tương ứng.'; return 2;
  }
  "php-fpm${version}" -t >/dev/null || return 2
  systemctl is-active --quiet "php${version}-fpm" || return 2
  install -d -m 0755 -o root -g root /usr/local/lib/kwvps /usr/local/lib/kwvps/ioncube || return 1
  install -m 0644 -o root -g root -- "$source_file" "$target" || return 1
  installed=1
  trap 'if ((installed)); then rm -f -- "$ini" "$target"; systemctl reload "php${version}-fpm" || true; fi; [[ -z $tmp ]] || rm -f -- "$tmp"' EXIT
  [[ $(sha256sum -- "$target" | awk '{print $1}') == "$digest" ]] || return 1
  tmp=$(mktemp "/etc/php/${version}/fpm/conf.d/.kwvps-ioncube.XXXXXXXX") || return 1
  printf 'zend_extension=%s\n' "$target" > "$tmp" || return 1
  chmod 0644 -- "$tmp" || return 1
  mv -T -- "$tmp" "$ini" || return 1
  tmp=''
  "php-fpm${version}" -t >/dev/null || return 1
  systemctl reload "php${version}-fpm" || return 1
  systemctl is-active --quiet "php${version}-fpm" || return 1
  # shellcheck disable=SC2034 # Read by the EXIT rollback trap.
  installed=0
  printf 'Đã bật ionCube cho PHP-FPM %s. SHA-256: %s\n' "$version" "$digest"
)

kw_php_ioncube_disable() (
  local version=$1 ini target backup
  ((EUID == 0)) || return 2
  exec 9>/run/lock/kwvps-ioncube.lock || return 2
  flock -n 9 || return 1
  ini=$(kw_php_ioncube_path "$version") || return 2
  target="/usr/local/lib/kwvps/ioncube/ioncube_loader_lin_${version}.so"
  [[ -f $ini && ! -L $ini && $(stat -c %u -- "$ini") == 0 &&
     $(< "$ini") == "zend_extension=$target" ]] || return 2
  kw_php_backup_file "$ini" "ioncube-${version//./-}" || return 1
  backup=$KW_PHP_BACKUP
  rm -- "$ini" || return 1
  if ! "php-fpm${version}" -t >/dev/null || ! systemctl reload "php${version}-fpm"; then
    install -m 0644 -o root -g root -- "$backup" "$ini" || return 1
    systemctl reload "php${version}-fpm" || true
    kw_log ERROR "Đã phục hồi cấu hình từ $backup."
    return 1
  fi
  printf 'Đã tắt ionCube cho PHP-FPM %s. Giữ file loader để đối chiếu; backup: %s\n' "$version" "$backup"
)

kw_php_ioncube_interactive() {
  local choice version digest
  kw_php_ioncube_status
  printf '\n1. Bật ionCube\n2. Tắt ionCube\n0. Quay lại\nChọn: '
  IFS= read -r choice || return 0
  [[ $choice == 1 || $choice == 2 ]] || return 0
  if [[ $choice == 1 ]]; then
    kw_php_choose_version || return 0
    version=$KW_PHP_CHOICE
    printf 'Đặt loader chính thức tại /root/kwvps-loaders/ioncube_loader_lin_%s.so (root-owned).\n' "$version"
    kw_prompt_validated 'SHA-256 từ nguồn tin cậy: ' kw_php_ioncube_digest_valid 'cần 64 ký tự hex' plain || return 0
    digest=$KW_PROMPT_VALUE
    kw_prompt_yes_no_token "Bật ionCube cho tất cả site PHP-FPM $version?" "$version" || return 0
    kw_php_ioncube_enable "$version" "$digest"
  else
    printf 'Nhập PHP version cần tắt (8.5/8.4/8.3/7.4), 0 để quay lại: '
    IFS= read -r version || return 0
    [[ $version != 0 ]] || return 0
    kw_php_version_supported "$version" || return 2
    kw_prompt_yes_no_token "Tắt ionCube cho tất cả site PHP-FPM $version?" "$version" || return 0
    kw_php_ioncube_disable "$version"
  fi
}
