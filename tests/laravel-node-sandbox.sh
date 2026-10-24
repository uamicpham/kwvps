#!/usr/bin/env bash
# Exercise APT's _apt sandbox with the same temporary download layout as KwVPS.
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
source src/laravel.sh
((EUID == 0)) || { printf 'Run this test as root.\n' >&2; exit 2; }

temp=$(mktemp -d /tmp/kwvps-apt-perms.XXXXXXXX)
trap 'rm -rf -- "$temp"' EXIT
chmod 0755 -- "$temp"
kw_laravel_node_download_dir "$temp/download"
[[ $(stat -c %U:%G:%a -- "$temp/download") == _apt:root:700 ]]

policy=$(LC_ALL=C apt-cache policy bash)
candidate=$(awk '$1 == "Candidate:" && !found { print $2; found=1 }' <<< "$policy")
[[ -n $candidate && $candidate != '(none)' ]]
if ! (cd -- "$temp/download" && apt-get download "bash=$candidate") >"$temp/apt.log" 2>&1; then
  cat -- "$temp/apt.log" >&2
  exit 1
fi
if grep -qi 'unsandboxed' "$temp/apt.log"; then
  cat -- "$temp/apt.log" >&2
  exit 1
fi
chown root:root -- "$temp/download"
packages=("$temp"/download/bash_*.deb)
[[ ${#packages[@]} -eq 1 && -f ${packages[0]} && ! -L ${packages[0]} ]]
sha256sum -- "${packages[0]}" >/dev/null
if runuser -u _apt -- test -w "$temp/download"; then
  printf '_apt retained write access after download.\n' >&2
  exit 1
fi
printf 'APT downloaded in the _apt sandbox without an unsandboxed warning.\n'
