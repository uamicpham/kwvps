#!/usr/bin/env bash
# Fetch a fixed-shape public GitHub Release and verify its SHA-256 before
# extracting or executing installer code. This script itself must be pinned
# by commit and SHA-256 in any published one-line command.
set -Eeuo pipefail
readonly KW_RELEASE_REPO=uamicpham/kwvps

usage() {
  printf 'Dùng: bash bootstrap-release.sh --check|--apply [--release=vX.Y.Z]\n' >&2
  exit 2
}
action='' requested_tag=''
for argument in "$@"; do
  case "$argument" in
    --check|--apply)
      [[ -z $action ]] || usage
      action=$argument ;;
    --release=*)
      [[ -z $requested_tag ]] || usage
      requested_tag=${argument#--release=}
      [[ $requested_tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage ;;
    *) usage ;;
  esac
done
[[ -n $action ]] || usage
for tool in curl python3 sha256sum tar mktemp uname; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'Thiếu công cụ %s. Chưa tải hoặc cài KwVPS.\n' "$tool" >&2
    exit 2
  }
done
[[ $(uname -m) == x86_64 ]] || {
  printf 'Kiến trúc chưa hỗ trợ; cần x86_64. Chưa tải hoặc cài KwVPS.\n' >&2
  exit 2
}

release_endpoint="https://api.github.com/repos/$KW_RELEASE_REPO/releases/latest"
if [[ -n $requested_tag ]]; then
  release_endpoint="https://api.github.com/repos/$KW_RELEASE_REPO/releases/tags/$requested_tag"
fi

release_json=$(curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
  --connect-timeout 10 --max-time 30 --max-filesize 1048576 \
  -H 'Accept: application/vnd.github+json' \
  "$release_endpoint") || {
    printf 'Không lấy được bản phát hành ổn định mới nhất từ GitHub.\n' >&2
    exit 1
  }

release_info=$(python3 -c 'import json,re,sys
try:
    release=json.load(sys.stdin)
    tag=release["tag_name"]
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+",tag): raise ValueError("tag")
    name="kwvps-"+tag[1:]+".tar.gz"
    assets=[asset for asset in release["assets"] if asset.get("name")==name]
    if len(assets)!=1: raise ValueError("asset")
    digest=assets[0].get("digest","")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}",digest): raise ValueError("SHA-256")
    print(tag+"|"+digest[7:])
except (KeyError,TypeError,ValueError) as error:
    print("GitHub Release thiếu thông tin hợp lệ: "+str(error),file=sys.stderr)
    sys.exit(2)' <<< "$release_json") || exit 2
tag=${release_info%%|*}
digest=${release_info#*|}
[[ -z $requested_tag || $tag == "$requested_tag" ]] || {
  printf 'GitHub trả về tag khác bản đã chọn; đã dừng.\n' >&2
  exit 2
}
version=${tag#v}
archive_name="kwvps-${version}.tar.gz"
[[ $digest =~ ^[0-9a-f]{64}$ ]] || exit 2

umask 077
stage=$(mktemp -d /tmp/kwvps-install.XXXXXXXX) || exit 1
[[ $stage == /tmp/kwvps-install.* && -d $stage && ! -L $stage ]] || exit 2
trap 'rm -rf -- "$stage"' EXIT
archive="$stage/$archive_name"
curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
  --connect-timeout 10 --max-time 120 --max-filesize 20971520 \
  -o "$archive" \
  "https://github.com/$KW_RELEASE_REPO/releases/download/$tag/$archive_name" || exit 1
actual=$(sha256sum -- "$archive") || exit 1
[[ ${actual%% *} == "$digest" ]] || {
  printf 'SHA-256 của gói không khớp GitHub Release; đã dừng.\n' >&2
  exit 2
}

python3 - "$archive" <<'PY' || exit 2
import pathlib, sys, tarfile
try:
    with tarfile.open(sys.argv[1], 'r:gz') as archive:
        members=archive.getmembers()
        if not members or len(members)>200:
            raise ValueError('số file không hợp lệ')
        total=0
        for member in members:
            path=pathlib.PurePosixPath(member.name)
            if (path.is_absolute() or '..' in path.parts or not path.parts
                or path.parts[0]!='kwvps' or not (member.isfile() or member.isdir())
                or member.mode & 0o022):
                raise ValueError('thành phần archive không an toàn')
            total += member.size
        if total>20*1024*1024:
            raise ValueError('archive quá lớn')
except (OSError, tarfile.TarError, ValueError) as error:
    print('Gói phát hành không hợp lệ: '+str(error),file=sys.stderr)
    sys.exit(2)
PY

tar -xzf "$archive" -C "$stage" --no-same-owner --no-same-permissions || exit 2
[[ -f $stage/kwvps/install.sh && ! -L $stage/kwvps/install.sh &&
   -f $stage/kwvps/release-repo && ! -L $stage/kwvps/release-repo ]] || exit 2
[[ $(< "$stage/kwvps/release-repo") == "$KW_RELEASE_REPO" ]] || exit 2
[[ $(bash "$stage/kwvps/kwvps" --version) == "KwVPS $version" ]] || exit 2
printf 'Đã xác minh KwVPS %s từ GitHub Release (%s).\n' "$version" "$KW_RELEASE_REPO"
bash "$stage/kwvps/install.sh" "$action"
