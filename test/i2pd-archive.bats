#!/usr/bin/env bats

setup_file() {
  export GNUPGHOME="$BATS_FILE_TMPDIR/gnupg"
  mkdir -m 700 "$GNUPGHOME"
  gpg --batch --passphrase '' --quick-generate-key 'Fixture Archive <test@example.invalid>' ed25519 sign 0
  gpg --batch --export >"$BATS_FILE_TMPDIR/key"
  printf 'Suite: trixie\n' | gpg --batch --clearsign >"$BATS_FILE_TMPDIR/InRelease"
}

setup() {
  export box="$BATS_TEST_TMPDIR/node" PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  mkdir -p "$box/apt/keyrings" "$box/apt/trusted.gpg.d" "$box/apt/preferences.d" "$box/apt/sources.list.d" "$BATS_TEST_TMPDIR/bin"
  printf 'ID=debian\nVERSION_CODENAME=trixie\n' >"$box/os-release"
  touch "$box/raspiblitz.conf"
  echo 'deb https://repo.i2pd.xyz/debian trixie main' >"$box/apt/sources.list.d/i2pd.list"
  cp "$BATS_FILE_TMPDIR/key" "$box/apt/trusted.gpg.d/i2pd.gpg"
  export fingerprint
  fingerprint=$(gpg --with-colons --show-keys "$BATS_FILE_TMPDIR/key" | awk -F: '$1=="fpr"{print $10;exit}')
  printf '#!/bin/sh\nexec "$@"\n' >"$BATS_TEST_TMPDIR/bin/sudo"
  cat >"$BATS_TEST_TMPDIR/bin/curl" <<'SH'
#!/bin/bash
[ "${fetch:-ok}" = ok ] || exit 22
case "$*" in
  *'/InRelease '*) cp "${index:-$BATS_FILE_TMPDIR/InRelease}" "${!#}" ;;
  *) cp "$BATS_FILE_TMPDIR/key" "${!#}" ;;
esac
SH
  printf '#!/bin/sh\necho "$*" >> "$box/calls"\nexit "${apt_rc:-0}"\n' >"$BATS_TEST_TMPDIR/bin/apt-get"
  printf '#!/bin/sh\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/dpkg-query"
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  sed -e "s@/etc/os-release@$box/os-release@g" -e "s@/etc/apt@$box/apt@g" -e "s@/mnt/hdd/app-data/raspiblitz.conf@$box/raspiblitz.conf@g" \
    -e "s/951928BB317024EFD053D73C66F6C87B98EBCFE2/$fingerprint/" \
    "$BATS_TEST_DIRNAME/../home.admin/config.scripts/blitz.i2pd.sh" >"$box/installer"
}

@test "install migrates legacy trust and repeats with identical scoped source" {
  for attempt in 1 2; do
    run bash "$box/installer" install
    [ "$status" -eq 0 ]
    [ "$(grep -Fc "signed-by=$box/apt/keyrings/i2pd.gpg" "$box/apt/sources.list.d/i2pd.list")" -eq 2 ]
    [ -s "$box/apt/keyrings/i2pd.gpg" ]
    [ ! -e "$box/apt/trusted.gpg.d/i2pd.gpg" ]
  done
  grep -q 'APT::Update::Error-Mode=any update' "$box/calls"
  grep -qx 'install -y i2pd' "$box/calls"
}

@test "download or fingerprint failure preserves prior sources and cannot call apt" {
  local list="$box/apt/sources.list.d/i2pd.list"
  cp "$list" "$box/before"
  export fetch=fail
  run bash "$box/installer" install
  [ "$status" -ne 0 ]; cmp "$box/before" "$list"
  export fetch=ok
  sed -i "s/$fingerprint/0000000000000000000000000000000000000000/" "$box/installer"
  run bash "$box/installer" install
  [ "$status" -ne 0 ]; cmp "$box/before" "$list"
  [ ! -e "$box/calls" ]
  [ -s "$box/apt/trusted.gpg.d/i2pd.gpg" ]
}

@test "a failed authenticated index refresh stops before package install" {
  export apt_rc=100
  run bash "$box/installer" install
  [ "$status" -ne 0 ]
  run grep -q '^install ' "$box/calls"
  [ "$status" -eq 1 ]
  [ -f "$box/apt/keyrings/.raspiblitz-i2pd-pending" ]
  unset apt_rc
  run bash "$box/installer" install
  [ "$status" -eq 0 ]; [ ! -f "$box/apt/keyrings/.raspiblitz-i2pd-pending" ]
}

@test "an already installed daemon is kept and an administrator's mixed keyring is preserved" {
  local legacy="$box/apt/trusted.gpg.d/i2pd.gpg"
  local other="$BATS_TEST_TMPDIR/other"
  mkdir -m 700 "$other"
  gpg --batch --homedir "$other" --passphrase '' --quick-generate-key 'Other Archive <other@example.invalid>' ed25519 sign 0
  gpg --batch --homedir "$other" --export >>"$legacy"
  cp "$legacy" "$box/before"
  printf '#!/bin/sh\necho installed\n' >"$BATS_TEST_TMPDIR/bin/dpkg-query"
  run bash "$box/installer" install
  [ "$status" -eq 0 ]
  [[ "$output" == *"globally trusted in $legacy"* ]]
  cmp "$box/before" "$legacy"
  ! grep -q '^install ' "$box/calls"
}

@test "an invalid signed release or custom source is preserved without activating trust" {
  export index="$box/unsigned"
  echo 'Suite: trixie' >"$index"
  run bash "$box/installer" install
  [ "$status" -ne 0 ]
  [ ! -e "$box/apt/keyrings/i2pd.gpg" ]
  [ -f "$box/apt/trusted.gpg.d/i2pd.gpg" ]
  unset index
  echo 'deb [arch=arm64] https://repo.i2pd.xyz/debian trixie main' >"$box/apt/sources.list.d/i2pd.list"
  run bash "$box/installer" install
  [ "$status" -ne 0 ]
  grep -Fq '[arch=arm64]' "$box/apt/sources.list.d/i2pd.list"
  [ ! -e "$box/calls" ]
}

@test "an installed distro package keeps its provider" {
  rm "$box/apt/sources.list.d/i2pd.list"
  printf '#!/bin/sh\necho installed\n' >"$BATS_TEST_TMPDIR/bin/dpkg-query"
  run bash "$box/installer" install
  [ "$status" -eq 0 ]
  [ ! -f "$box/apt/sources.list.d/i2pd.list" ]
  [ ! -f "$box/apt/keyrings/i2pd.gpg" ]
  [ ! -f "$box/calls" ]
}

@test "a Deb822 source pointing at the archive is preserved" {
  echo 'URIs: https://repo.i2pd.xyz/debian' >"$box/apt/sources.list.d/existing.sources"
  run bash "$box/installer" install
  [ "$status" -ne 0 ]
  [[ "$output" == *existing.sources* ]]
  [ ! -e "$box/apt/keyrings/i2pd.gpg" ]
}
