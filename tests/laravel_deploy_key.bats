#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  source src/core.sh
  source src/sites.sh
  source src/laravel.sh

  command -v ssh-keygen >/dev/null || skip 'openssh-client is required'
  mkdir -p "$BATS_TEST_TMPDIR/site/source" "$BATS_TEST_TMPDIR/site/deploy"
  KW_SITE_ROOT=$BATS_TEST_TMPDIR/site
  KW_SITE_OWNER=$(id -un)

  # Run the site-user commands as this unprivileged CI user, with the same
  # ownership semantics as the real site account but no VPS/root access.
  runuser() {
    [[ ${1:-} == -u && ${2:-} == "$KW_SITE_OWNER" ]] || return 2
    shift 2
    if [[ ${1:-} == -g ]]; then shift 2; fi
    [[ ${1:-} == -- ]] || return 2
    shift
    "$@"
  }
  kw_laravel_layout_ready() {
    KW_SITE_ROOT=$BATS_TEST_TMPDIR/site
    KW_SITE_OWNER=$(id -un)
  }
}

@test "Git deploy key is created for the site without printing the private key" {
  run kw_laravel_deploy_key_prepare example.com
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/site/.ssh/id_ed25519" ]
  [ -f "$BATS_TEST_TMPDIR/site/.ssh/id_ed25519.pub" ]
  [[ "$output" == *'ssh-ed25519 '* ]]
  [[ "$output" != *'BEGIN OPENSSH PRIVATE KEY'* ]]
  [[ "$output" != *'END OPENSSH PRIVATE KEY'* ]]
  [ "$(stat -c %a "$BATS_TEST_TMPDIR/site/.ssh")" = 700 ]
  [ "$(stat -c %a "$BATS_TEST_TMPDIR/site/.ssh/id_ed25519")" = 600 ]
  [ "$(stat -c %U "$BATS_TEST_TMPDIR/site/.ssh")" = "$KW_SITE_OWNER" ]
  [ "$(stat -c %U "$BATS_TEST_TMPDIR/site/.ssh/id_ed25519")" = "$KW_SITE_OWNER" ]
}

@test "Git deploy key is redisplayed on retry without replacing the private key" {
  kw_laravel_deploy_key_prepare example.com >/dev/null
  before=$(sha256sum "$BATS_TEST_TMPDIR/site/.ssh/id_ed25519")
  public=$(< "$BATS_TEST_TMPDIR/site/.ssh/id_ed25519.pub")

  run kw_laravel_deploy_key_prepare example.com
  [ "$status" -eq 0 ]
  [ "$(sha256sum "$BATS_TEST_TMPDIR/site/.ssh/id_ed25519")" = "$before" ]
  [[ "$output" == *"${public% *}"* ]]
  [[ "$output" != *'BEGIN OPENSSH PRIVATE KEY'* ]]
}

@test "Git deploy key recovers public text if the pub file is missing" {
  kw_laravel_deploy_key_prepare example.com >/dev/null
  before=$(sha256sum "$BATS_TEST_TMPDIR/site/.ssh/id_ed25519")
  public=$(< "$BATS_TEST_TMPDIR/site/.ssh/id_ed25519.pub")
  rm -- "$BATS_TEST_TMPDIR/site/.ssh/id_ed25519.pub"

  run kw_laravel_deploy_key_prepare example.com
  [ "$status" -eq 0 ]
  [ "$(sha256sum "$BATS_TEST_TMPDIR/site/.ssh/id_ed25519")" = "$before" ]
  # A public key may be regenerated as a file or printed directly; either is
  # sufficient to let the operator add it to GitHub without losing identity.
  [[ "$output" == *"${public% *}"* ]]
}

@test "Git deploy key displays the private-key identity when pub file is stale" {
  kw_laravel_deploy_key_prepare example.com >/dev/null
  private=$BATS_TEST_TMPDIR/site/.ssh/id_ed25519
  public_file=$private.pub
  before=$(sha256sum "$private")
  expected=$(ssh-keygen -y -P '' -f "$private")
  read -r expected_type expected_blob _ <<< "$expected"
  expected="$expected_type $expected_blob"
  stale='ssh-ed25519 AAAAoldkeythatmustnotbedisplayed'
  printf '%s\n' "$stale" > "$public_file"

  run kw_laravel_deploy_key_prepare example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"$expected"* ]]
  [[ "$output" == *'File .pub không khớp'* ]]
  [[ "$output" != *"$stale"* ]]
  [ "$(< "$public_file")" = "$stale" ]
  [ "$(sha256sum "$private")" = "$before" ]
}

@test "Git deploy key accepts a matching pub file without trailing newline" {
  kw_laravel_deploy_key_prepare example.com >/dev/null
  private=$BATS_TEST_TMPDIR/site/.ssh/id_ed25519
  public_file=$private.pub
  before=$(sha256sum "$private")
  public=$(< "$public_file")
  printf '%s' "$public" > "$public_file"

  run kw_laravel_deploy_key_prepare example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"${public% *}"* ]]
  [[ "$output" != *'File .pub không khớp'* ]]
  [ "$(sha256sum "$private")" = "$before" ]
  [ "$(< "$public_file")" = "$public" ]
}

@test "Git deploy key rejects an existing symlink instead of following it" {
  mkdir -m 700 "$BATS_TEST_TMPDIR/site/.ssh"
  printf 'keep this file\n' > "$BATS_TEST_TMPDIR/external-key"
  ln -s "$BATS_TEST_TMPDIR/external-key" "$BATS_TEST_TMPDIR/site/.ssh/id_ed25519"

  run kw_laravel_deploy_key_prepare example.com
  [ "$status" -ne 0 ]
  [ "$(< "$BATS_TEST_TMPDIR/external-key")" = 'keep this file' ]
  [ -L "$BATS_TEST_TMPDIR/site/.ssh/id_ed25519" ]
}

@test "Clone Git menu shows an SSH deploy key before cloning and permits return" {
  kw_site_prompt_domain() { KW_SITE_CHOICE=example.com; }
  kw_prompt_validated() { KW_PROMPT_VALUE=git@github.com:example/private.git; }
  kw_laravel_with_lock() {
    if [[ $1 == deploy-key ]]; then
      kw_laravel_deploy_key_prepare "$2"
    else
      printf 'UNEXPECTED_CLONE\n'
    fi
  }

  run kw_laravel_interactive clone <<< '0'
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/site/.ssh/id_ed25519" ]
  [[ "$output" == *'ssh-ed25519 '* ]]
  [[ "$output" == *'Settings → Deploy keys'* ]]
  [[ "$output" != *'UNEXPECTED_CLONE'* ]]
  [[ "$output" != *'BEGIN OPENSSH PRIVATE KEY'* ]]
}

@test "Clone Git menu proceeds after public key has been added" {
  kw_site_prompt_domain() { KW_SITE_CHOICE=example.com; }
  kw_prompt_validated() {
    if [[ $1 == 'Git URL'* ]]; then
      KW_PROMPT_VALUE=git@github.com:example/private.git
    else
      KW_PROMPT_VALUE=main
    fi
  }
  kw_prompt_yes_no_token() { return 0; }
  kw_laravel_with_lock() {
    if [[ $1 == deploy-key ]]; then
      kw_laravel_deploy_key_prepare "$2"
    else
      printf 'ACTION:%s\n' "$1"
    fi
  }

  run kw_laravel_interactive clone <<< ''
  [ "$status" -eq 0 ]
  [[ "$output" == *'ssh-ed25519 '*'ACTION:clone'* ]]
  [[ "$output" == *'Allow write access'* ]]
}

@test "Clone Git menu does not create a deploy key for HTTPS" {
  kw_site_prompt_domain() { KW_SITE_CHOICE=example.com; }
  kw_prompt_validated() {
    if [[ $1 == 'Git URL'* ]]; then
      KW_PROMPT_VALUE=https://github.com/example/public.git
    else
      KW_PROMPT_VALUE=main
    fi
  }
  kw_prompt_yes_no_token() { return 0; }
  kw_laravel_with_lock() { printf 'ACTION:%s\n' "$1"; }

  run kw_laravel_interactive clone
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/site/.ssh" ]
  [[ "$output" == *'ACTION:clone'* ]]
  [[ "$output" != *'ACTION:deploy-key'* ]]
}
