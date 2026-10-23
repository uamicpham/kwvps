#!/usr/bin/env bash
# Constrained package updates for services already managed by KwVPS.

kw_update_apt_refresh() {
  ((EUID == 0)) || { kw_log ERROR 'Cần root để làm mới danh mục APT.'; return 2; }
  kw_os_supported '' || return 2
  printf 'Đang làm mới danh mục gói từ các kho APT đã cấu hình...\n'
  apt-get update || { kw_log ERROR 'Không làm mới được APT; từ chối kết luận về bản cập nhật mới.'; return 1; }
}

kw_update_php_candidates_safe() {
  local package version candidate installed
  for version in 8.5 8.4 8.3 7.4; do
    package="php${version}-fpm"
    dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -Fqx 'install ok installed' || continue
    installed=$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null) || return 2
    candidate=$(kw_apt_candidate "$package") || return 2
    dpkg --compare-versions "$candidate" gt "$installed" || continue
    if ! kw_php_package_version_safe "$version" "$candidate"; then
      kw_log ERROR "$package có candidate $candidate chưa được xác minh an toàn; dừng cập nhật."
      return 2
    fi
  done
}

# APT maintainer scripts decide whether a package upgrade restarts a unit.
# Remember managed units that were running before APT and verify that they
# remain healthy afterwards, without forcing a second restart on a live VPS.
kw_update_active_units() {
  local unit
  kw_has systemctl || return 2
  KW_UPDATE_ACTIVE_UNITS=()
  for unit in nginx php8.5-fpm php8.4-fpm php8.3-fpm php7.4-fpm mariadb redis-server fail2ban cloudflared cron ssh; do
    if systemctl is-active --quiet "$unit"; then
      KW_UPDATE_ACTIVE_UNITS+=("$unit")
    fi
  done
}

kw_update_service_postflight() {
  local unit version
  nginx -t >/dev/null 2>&1 || {
    kw_log ERROR 'Nginx không đạt kiểm tra cấu hình sau cập nhật; cần xử lý ngay.'
    return 1
  }
  for unit in "${KW_UPDATE_ACTIVE_UNITS[@]}"; do
    if [[ $unit == php*-fpm ]]; then
      version=${unit#php}; version=${version%-fpm}
      if ! kw_has "php-fpm${version}" || ! "php-fpm${version}" -t >/dev/null 2>&1; then
        kw_log ERROR "Cấu hình $unit không đạt sau cập nhật; cần xử lý ngay."
        return 1
      fi
    fi
    if ! systemctl is-active --quiet "$unit"; then
      kw_log ERROR "$unit đã chạy trước cập nhật nhưng không active sau APT; cần xử lý ngay."
      return 1
    fi
  done
  printf 'Đã kiểm tra cấu hình Nginx và trạng thái các dịch vụ trước đó đang chạy.\n'
}

kw_update_service_candidates() {
  local data line package candidate
  KW_UPDATE_PACKAGES=()
  data=$(LC_ALL=C apt list --upgradable 2>/dev/null) || return 1
  while IFS= read -r line; do
    package=${line%%/*}
    [[ $package == "$line" ]] && continue
    kw_service_package "$package" || continue
    [[ $package =~ ^[a-z0-9.+-]+$ ]] || return 2
    KW_UPDATE_PACKAGES+=("$package")
  done <<< "$data"
}

kw_update_service_simulate() {
  local data line package candidate found=0 allowed
  ((${#KW_UPDATE_PACKAGES[@]})) || return 0
  data=$(LC_ALL=C apt-get -s install --only-upgrade --no-install-recommends --no-remove -- "${KW_UPDATE_PACKAGES[@]}" 2>&1) || {
    kw_log ERROR 'Apt không lập được kế hoạch nâng cấp an toàn.'; return 2;
  }
  while IFS= read -r line; do
    case "$line" in
      'Remv '*|'Purg '*) kw_log ERROR 'Kế hoạch apt định gỡ package; đã từ chối.'; return 2 ;;
      'Inst '*)
        package=${line#Inst }; package=${package%% *}; allowed=0
        for candidate in "${KW_UPDATE_PACKAGES[@]}"; do
          [[ $package != "$candidate" ]] || { allowed=1; break; }
        done
        ((allowed)) || { kw_log ERROR "Apt muốn thay package ngoài phạm vi: $package"; return 2; }
        found=1 ;;
    esac
  done <<< "$data"
  ((found)) || { kw_log WARN 'Apt không lên lịch nâng package nào.'; return 1; }
  printf '%s\n' "$data"
}

kw_update_service_plan() {
  kw_os_supported '' || return 2
  kw_update_service_candidates || return 2
  if ((${#KW_UPDATE_PACKAGES[@]} == 0)); then
    printf 'Không có package dịch vụ chờ cập nhật trong danh mục APT hiện tại.\n'
    return 0
  fi
  printf 'Package dịch vụ chờ cập nhật: %s\n' "${KW_UPDATE_PACKAGES[*]}"
  printf 'Kế hoạch apt (chưa thay đổi hệ thống):\n'
  kw_update_service_simulate || return 2
  printf 'Chỉ nâng package trong danh sách; không nâng phiên bản Ubuntu.\n'
  printf 'Sau áp dụng cần kiểm tra website; package apt không có rollback tự động.\n'
}

kw_update_service_apply() (
  local confirm=${1:-} candidate
  [[ $confirm == UPDATE-SERVICE-PACKAGES ]] || return 2
  ((EUID == 0)) || { kw_log ERROR 'Cần root để cập nhật package.'; return 2; }
  kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  for candidate in apt apt-get dpkg-query flock; do kw_has "$candidate" || return 2; done
  exec 9>/run/lock/kwvps-update.lock || return 2
  flock -n 9 || { kw_log ERROR 'Một lần cập nhật khác đang chạy.'; return 1; }
  kw_update_php_candidates_safe || return 2
  kw_update_service_candidates || return 2
  ((${#KW_UPDATE_PACKAGES[@]})) || { printf 'Không có package dịch vụ cần cập nhật.\n'; return 0; }
  kw_update_service_simulate >/dev/null || return 2
  kw_update_active_units || return 2
  printf 'Đang cập nhật đúng package: %s\n' "${KW_UPDATE_PACKAGES[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade --no-install-recommends --no-remove -- "${KW_UPDATE_PACKAGES[@]}" || return 1
  kw_update_service_postflight || return 1
  printf 'Đã cập nhật package. Kiểm tra từng service và website; apt không tự rollback.\n'
)

kw_update_service_interactive() {
  kw_update_apt_refresh || return 2
  kw_update_php_candidates_safe || return 2
  kw_update_service_plan || return 2
  ((${#KW_UPDATE_PACKAGES[@]})) || return 0
  kw_prompt_yes_no_token 'Áp dụng cập nhật package dịch vụ trong kế hoạch?' UPDATE-SERVICE-PACKAGES || return 0
  kw_update_service_apply "$KW_PROMPT_VALUE"
}

kw_update_ubuntu_simulate() {
  local data line found=0
  data=$(LC_ALL=C apt-get -s --no-remove upgrade 2>&1) || {
    kw_log ERROR 'Apt không lập được kế hoạch cập nhật Ubuntu.'; return 2;
  }
  while IFS= read -r line; do
    case "$line" in
      'Remv '*|'Purg '*) kw_log ERROR 'Kế hoạch apt muốn gỡ package; đã từ chối.'; return 2 ;;
      'Inst '*) found=1 ;;
    esac
  done <<< "$data"
  if ((found)); then printf '%s\n' "$data"; else printf 'Không có package nào được apt lên lịch nâng.\n'; fi
}

kw_update_ubuntu_plan() {
  kw_os_supported '' || return 2
  printf 'Cập nhật package của Ubuntu 24.04 hiện tại, KHÔNG nâng phiên bản hệ điều hành.\n'
  printf 'Dựa trên danh mục APT hiện có; menu tương tác làm mới danh mục trước khi lập kế hoạch.\n'
  kw_update_ubuntu_simulate || return 2
  printf 'Có thể restart dịch vụ hoặc cần reboot; apt không tự rollback. Hãy giữ snapshot/console cứu hộ.\n'
}

kw_update_ubuntu_apply() (
  local confirm=${1:-} plan
  [[ $confirm == UPDATE-UBUNTU-PACKAGES ]] || return 2
  ((EUID == 0)) || return 2
  kw_os_supported '' || return 2
  [[ -f /etc/kwvps/install-id && ! -L /etc/kwvps/install-id && $(< /etc/kwvps/install-id) == kwvps-v1 ]] || return 2
  kw_has apt-get && kw_has flock || return 2
  exec 9>/run/lock/kwvps-update.lock || return 2
  flock -n 9 || return 1
  kw_update_php_candidates_safe || return 2
  plan=$(LC_ALL=C apt-get -s --no-remove upgrade 2>&1) || return 2
  [[ $plan != *$'\nRemv '* && $plan != Remv\ * && $plan != *$'\nPurg '* && $plan != Purg\ * ]] || return 2
  [[ $plan == *$'\nInst '* || $plan == Inst\ * ]] || { printf 'Không có package cần nâng.\n'; return 0; }
  kw_update_active_units || return 2
  DEBIAN_FRONTEND=noninteractive apt-get -y --no-remove \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade || return 1
  kw_update_service_postflight || return 1
  printf 'Đã cập nhật package Ubuntu 24.04. Kiểm tra website/dịch vụ và reboot thủ công nếu hệ thống yêu cầu.\n'
)

kw_update_ubuntu_interactive() {
  local plan
  kw_update_apt_refresh || return 2
  kw_update_php_candidates_safe || return 2
  kw_update_ubuntu_plan || return 2
  plan=$(LC_ALL=C apt-get -s --no-remove upgrade 2>&1) || return 2
  [[ $plan == *$'\nInst '* || $plan == Inst\ * ]] || return 0
  kw_prompt_yes_no_token 'Áp dụng cập nhật package Ubuntu 24.04?' UPDATE-UBUNTU-PACKAGES || return 0
  kw_update_ubuntu_apply "$KW_PROMPT_VALUE"
}

# A public GitHub repository may be configured without an API token. The
# release asset digest must come from GitHub's release API over HTTPS.
kw_github_repo_valid() {
  [[ ${1:-} =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}/[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$ &&
     $1 != *..* ]]
}

kw_github_repo_read() {
  local file=/etc/kwvps/github-repo value mode
  [[ -d /etc/kwvps && ! -L /etc/kwvps &&
     $(stat -c %u -- /etc/kwvps) == 0 ]] || return 2
  mode=$(stat -c %a -- /etc/kwvps) || return 2
  [[ $mode =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0022) == 0 )) || return 2
  [[ -f $file && ! -L $file && $(stat -c %u:%a -- "$file") == 0:600 ]] || return 1
  IFS= read -r value < "$file" || return 1
  kw_github_repo_valid "$value" || return 2
  KW_GITHUB_REPO=$value
}

kw_github_repo_interactive() {
  local repo tmp
  ((EUID == 0)) || return 2
  if kw_github_repo_read; then printf 'Repository hiện tại: %s\n' "$KW_GITHUB_REPO";
  else printf 'Chưa cấu hình GitHub repository công khai.\n'; fi
  printf 'Nhập owner/repo (ví dụ: tenban/kwvps); Enter để quay lại. Không nhập token.\n'
  kw_prompt_validated 'Repository: ' kw_github_repo_valid 'đúng dạng owner/repo' plain || return 0
  repo=$KW_PROMPT_VALUE
  kw_prompt_yes_no_token "Lưu $repo làm nguồn bản phát hành KwVPS?" SAVE-GITHUB-REPO || return 0
  [[ -d /etc/kwvps && ! -L /etc/kwvps && $(stat -c %u -- /etc/kwvps) == 0 ]] || return 2
  tmp=$(mktemp /etc/kwvps/.github-repo.XXXXXXXX) || return 1
  if ! printf '%s\n' "$repo" > "$tmp" ||
     ! chown root:root -- "$tmp" || ! chmod 0600 -- "$tmp" ||
     ! mv -T -- "$tmp" /etc/kwvps/github-repo; then
    rm -f -- "$tmp"
    return 1
  fi
  printf 'Đã lưu. Menu cập nhật sẽ kiểm tra bản release mới nhất từ GitHub này.\n'
}

kw_github_release_info() {
  local json info tag digest version asset
  kw_github_repo_read || { kw_log ERROR 'Chưa cấu hình GitHub repository trong menu Update.'; return 2; }
  kw_has curl && kw_has python3 && kw_has dpkg || return 2
  json=$(curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 10 --max-time 30 --max-filesize 1048576 \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$KW_GITHUB_REPO/releases/latest") || {
      kw_log ERROR 'Không đọc được release mới nhất từ GitHub (kiểm tra repo công khai, mạng hoặc API rate limit).'
      return 1
    }
  info=$(python3 -c 'import json,re,sys
try:
    data=json.load(sys.stdin)
    tag=data["tag_name"]
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+",tag): raise ValueError("invalid tag")
    name="kwvps-"+tag[1:]+".tar.gz"
    assets=[a for a in data["assets"] if a.get("name")==name]
    if len(assets)!=1: raise ValueError("missing release asset")
    digest=assets[0].get("digest","")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}",digest): raise ValueError("missing SHA-256 digest")
    print(tag+"|"+digest[7:])
except (KeyError,TypeError,ValueError) as error:
    print("Release thiếu tag/asset/SHA-256 hợp lệ: "+str(error),file=sys.stderr)
    sys.exit(2)' <<< "$json") || return 2
  tag=${info%%|*}; digest=${info#*|}; version=${tag#v}; asset="kwvps-${version}.tar.gz"
  [[ $digest =~ ^[0-9a-f]{64}$ ]] || return 2
  KW_GITHUB_RELEASE_TAG=$tag
  KW_GITHUB_RELEASE_VERSION=$version
  KW_GITHUB_RELEASE_DIGEST=$digest
  KW_GITHUB_RELEASE_ASSET=$asset
}

kw_github_archive_safe() {
  python3 - "$1" <<'PY'
import pathlib, sys, tarfile
try:
    with tarfile.open(sys.argv[1], 'r:gz') as archive:
        members = archive.getmembers()
        if not members or len(members) > 200:
            raise ValueError('wrong file count')
        total = 0
        for member in members:
            path = pathlib.PurePosixPath(member.name)
            if (path.is_absolute() or '..' in path.parts or not path.parts
                or path.parts[0] != 'kwvps' or not (member.isfile() or member.isdir())
                or member.mode & 0o022):
                raise ValueError('unsafe archive member')
            total += member.size
        if total > 20 * 1024 * 1024:
            raise ValueError('archive too large')
except (OSError, tarfile.TarError, ValueError) as error:
    print('Gói phát hành không an toàn: ' + str(error), file=sys.stderr)
    sys.exit(2)
PY
}

kw_update_kwvps_github() (
  local current temp bundle actual url version
  ((EUID == 0)) || return 2
  kw_github_release_info || return 2
  version=$KW_GITHUB_RELEASE_VERSION
  current=$(/opt/kwvps/kwvps --version) || return 2
  current=${current#KwVPS }
  if ! dpkg --compare-versions "$version" gt "$current"; then
    printf 'Bản đang cài: %s | GitHub mới nhất: %s. Không có bản mới hơn.\n' "$current" "$version"
    return 0
  fi
  printf 'Bản đang cài: %s | GitHub mới nhất: %s\n' "$current" "$version"
  printf 'Nguồn: %s, release %s. Chỉ chấp nhận gói có SHA-256 do GitHub API công bố.\n' "$KW_GITHUB_REPO" "$KW_GITHUB_RELEASE_TAG"
  kw_prompt_yes_no_token "Tải, xác minh và cập nhật lên $version?" UPDATE-KWVPS-GITHUB || return 0
  umask 077
  temp=$(mktemp -d /tmp/kwvps-release.XXXXXXXX) || return 1
  [[ $temp == /tmp/kwvps-release.* && -d $temp && ! -L $temp ]] || return 2
  trap 'rm -rf -- "$temp"' EXIT
  bundle="$temp/$KW_GITHUB_RELEASE_ASSET"
  url="https://github.com/$KW_GITHUB_REPO/releases/download/$KW_GITHUB_RELEASE_TAG/$KW_GITHUB_RELEASE_ASSET"
  curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 10 --max-time 120 --max-filesize 20971520 \
    -o "$bundle" "$url" || return 1
  actual=$(sha256sum -- "$bundle") || return 1
  [[ ${actual%% *} == "$KW_GITHUB_RELEASE_DIGEST" ]] || {
    kw_log ERROR 'SHA-256 gói tải không khớp GitHub release; không chạy mã.'; return 2;
  }
  kw_github_archive_safe "$bundle" || return 2
  tar -xzf "$bundle" -C "$temp" --no-same-owner --no-same-permissions || return 2
  [[ -f $temp/kwvps/upgrade.sh && ! -L $temp/kwvps/upgrade.sh ]] || return 2
  [[ $(bash "$temp/kwvps/kwvps" --version) == "KwVPS $version" ]] || return 2
  bash "$temp/kwvps/upgrade.sh" --check || return 2
  bash "$temp/kwvps/upgrade.sh" --apply --confirm=UPGRADE-KWVPS || return 1
  printf 'Đã cập nhật. Thoát menu và mở lại kwvps để dùng bản mới.\n'
)

# The same checked upgrade path can also be invoked from a root-only local bundle.
readonly KW_UPDATE_BUNDLE=/root/kwvps-update

kw_update_kwvps_bundle_ready() {
  local unsafe
  ((EUID == 0)) || return 2
  [[ -d $KW_UPDATE_BUNDLE && ! -L $KW_UPDATE_BUNDLE &&
     $(stat -c %u -- "$KW_UPDATE_BUNDLE") == 0 ]] || return 2
  unsafe=$(find "$KW_UPDATE_BUNDLE" -xdev \
    \( -type l -o ! -user root -o -perm /022 \) -print -quit) || return 2
  [[ -z $unsafe ]] || { kw_log ERROR "Gói update có symlink hoặc quyền/owner không an toàn: $unsafe"; return 2; }
  [[ -f $KW_UPDATE_BUNDLE/upgrade.sh && -f $KW_UPDATE_BUNDLE/kwvps &&
     ! -L $KW_UPDATE_BUNDLE/upgrade.sh && ! -L $KW_UPDATE_BUNDLE/kwvps ]] || return 2
  bash -n "$KW_UPDATE_BUNDLE/upgrade.sh" "$KW_UPDATE_BUNDLE/kwvps" || return 2
}

kw_update_kwvps_interactive() {
  local current target
  if [[ -e /etc/kwvps/github-repo || -L /etc/kwvps/github-repo ]] && ! kw_github_repo_read; then
    kw_log ERROR 'Cấu hình GitHub repository không an toàn hoặc không hợp lệ; cần kiểm tra trước khi cập nhật.'
    return 2
  fi
  if kw_github_repo_read; then
    kw_update_kwvps_github
    return
  fi
  printf 'Bản đang cài: '
  /opt/kwvps/kwvps --version || return 2
  if ! kw_update_kwvps_bundle_ready; then
    printf 'Chưa có gói update tin cậy tại %s.\n' "$KW_UPDATE_BUNDLE"
    printf 'Đặt toàn bộ source KwVPS từ bản phát hành bạn tin cậy vào thư mục root-only này.\n'
    printf 'Để kiểm tra bản mới trên GitHub, cấu hình owner/repo trong menu Update. Không cần token nếu repo công khai.\n'
    return 0
  fi
  current=$(/opt/kwvps/kwvps --version) || return 2
  target=$(bash "$KW_UPDATE_BUNDLE/kwvps" --version) || return 2
  [[ $current != "$target" ]] || { printf 'Gói local cùng version; không cập nhật.\n'; return 0; }
  printf 'Bản trong gói local: %s\n' "$target"
  bash "$KW_UPDATE_BUNDLE/upgrade.sh" --check || return 2
  printf 'Chỉ cập nhật bộ mã; bản cũ được giữ tại /opt/kwvps-previous-*.\n'
  kw_prompt_yes_no_token "Áp dụng $target từ gói local root-only?" UPDATE-KWVPS-LOCAL || return 0
  kw_update_kwvps_bundle_ready || return 2
  bash "$KW_UPDATE_BUNDLE/upgrade.sh" --apply --confirm=UPGRADE-KWVPS || return 1
  printf 'Menu hiện tại vẫn chạy mã cũ; thoát và mở lại kwvps để dùng bản mới.\n'
}
