#!/usr/bin/env bats

setup() {
  [ "$(id -u)" -ne 0 ] || skip "Run this suite as an unprivileged user to exercise directory traversal."
  mountRoot="$BATS_TEST_TMPDIR/data"
  root="$mountRoot/app-data"
  dir="$root/bitcoin/wallets"
  mkdir -p "$dir/wallet.dat"
  printf 'disposable wallet bytes' > "$dir/wallet.dat/wallet.dat"
  device=$(stat -c '%Hd:%Ld' "$mountRoot")
  chmod 600 "$dir/wallet.dat/wallet.dat"
  before=$(sha256sum "$dir/wallet.dat/wallet.dat")
  sed -e "s|/mnt/hdd/app-data|$root|g" -e "s/!= bitcoin ]/!= $(id -un) ]/" \
    "$BATS_TEST_DIRNAME/../home.admin/config.scripts/bitcoin.check.sh" > "$BATS_TEST_TMPDIR/check.sh"
}

@test "recovery restores only owner traversal on the legacy wallet directories" {
  chmod 600 "$dir/wallet.dat" "$dir"
  run bash "$BATS_TEST_TMPDIR/check.sh" recover-wallet-access "$mountRoot" "$device"
  [ "$status" = 0 ]
  [ "$(stat -c %a "$dir")" = 700 ]
  [ "$(stat -c %a "$dir/wallet.dat")" = 700 ]
  [ "$(stat -c %a "$dir/wallet.dat/wallet.dat")" = 600 ]
  [ "$(sha256sum "$dir/wallet.dat/wallet.dat")" = "$before" ]
}

@test "foreign symlink targets retain their own permission policy" {
  mv "$dir/wallet.dat" "$root/custom"
  ln -s "$root/custom" "$dir/wallet.dat"
  chmod 600 "$root/custom"
  run bash "$BATS_TEST_TMPDIR/check.sh" recover-wallet-access "$mountRoot" "$device"
  [ "$status" -ne 0 ]
  [ "$(stat -c %a "$root/custom")" = 600 ]
  chmod 700 "$root/custom"
}

@test "flat legacy wallet files and an absent wallet remain valid" {
  mv "$dir/wallet.dat" "$root/saved"
  mv "$root/saved/wallet.dat" "$dir/wallet.dat"
  run bash "$BATS_TEST_TMPDIR/check.sh" recover-wallet-access "$mountRoot" "$device"
  [ "$status" = 0 ]
  [ "$(stat -c %a "$dir/wallet.dat")" = 600 ]
  mv "$dir" "$root/inactive"
  run bash "$BATS_TEST_TMPDIR/check.sh" recover-wallet-access "$mountRoot" "$device"
  [ "$status" = 0 ]
  [ ! -e "$dir" ]
}
