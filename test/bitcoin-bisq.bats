#!/usr/bin/env bats

setup() {
  export box="$BATS_TEST_TMPDIR/node" PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  mkdir -p "$box/admin" "$box/data/bitcoin" "$box/data/tor/bisq" "$box/tor" "$BATS_TEST_TMPDIR/bin"
  printf 'network=bitcoin\n' >"$box/admin/raspiblitz.info"
  touch "$box/data/raspiblitz.conf" "$box/tor/torrc"
  printf 'test-address\n' >"$box/data/tor/bisq/hostname"
  cp "$BATS_TEST_DIRNAME/../home.admin/assets/bitcoin.conf" "$box/data/bitcoin/bitcoin.conf"
  sed -e "s@/home/admin@$box/admin@g" -e "s@/mnt/hdd/app-data@$box/data@g" \
    -e "s@/run/raspiblitz-bisq@$box/temp.bisq@g" -e "s@/etc/tor@$box/tor@g" "$BATS_TEST_DIRNAME/../home.admin/99connectMenu.sh" >"$box/menu"
  printf '#!/bin/sh\nexit 0\n' >"$box/admin/_cache.sh"
  cat >"$BATS_TEST_TMPDIR/bin/sudo" <<'SH'
#!/bin/sh
if [ "$1" = -u ]; then shift 2; fi
exec "$@"
SH
  cat >"$BATS_TEST_TMPDIR/bin/bitcoin-cli" <<'SH'
#!/bin/sh
[ "${rpc_fail:-0}" = 0 ] || exit 1
if grep -qx peerbloomfilters=1 "$box/data/bitcoin/bitcoin.conf"; then
  echo '{"localservicesnames":["BLOOM"]}'
else
  echo '{"localservicesnames":[]}'
fi
SH
  printf '#!/bin/sh\necho "$*" >> "$box/services"\n[ "$*" != "${failed_service:-}" ]\n' >"$BATS_TEST_TMPDIR/bin/systemctl"
  printf '#!/bin/sh\nexit 0\n' >"$BATS_TEST_TMPDIR/bin/sleep"
  cat >"$BATS_TEST_TMPDIR/bin/dialog" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$box/dialogs"
case "$*" in *"Connect Options"*) echo BISQ >&2 ;; *) echo "$choice" >&2 ;; esac
SH
  chmod +x "$box/admin/_cache.sh" "$BATS_TEST_TMPDIR/bin/"*
}

menu() {
  export choice=$1 TERM=xterm
  run script -qec "bash '$box/menu' </dev/null" /dev/null
}

@test "new installs opt out; adding and removing Bisq changes only the managed defaults" {
  conf="$box/data/bitcoin/bitcoin.conf"
  run grep -q '^peerbloomfilters=1' "$conf"
  [ "$status" -eq 1 ]
  printf '\n# peerbloomfilters=1\npeerbloomfilters = 0\n[signet]\nport=38333\n' >>"$conf"
  menu ADDBISQ
  [ "$status" -eq 0 ]
  grep -q 'BIP37: OFF' "$box/dialogs"
  grep -qx peerbloomfilters=1 "$conf"
  grep -qx 'port=38333' "$conf"
  grep -q 'HiddenServiceDir' "$box/tor/torrc"

  menu REMOVEBISQ
  [ "$status" -eq 0 ]
  grep -q 'BIP37: ON' "$box/dialogs"
  grep -qx peerbloomfilters=0 "$conf"
  [ "$(grep -c '^restart bitcoind' "$box/services")" -eq 2 ]
  ! grep -q HiddenServiceDir "$box/tor/torrc"
}

@test "legacy BIP37 can be turned off even without a Bisq hidden service" {
  printf '\npeerbloomfilters=1 # previous=0\n' >>"$box/data/bitcoin/bitcoin.conf"
  menu DISABLEBLOOM
  [ "$status" -eq 0 ]
  grep -q 'DISABLEBLOOM' "$box/dialogs"
  grep -qx peerbloomfilters=0 "$box/data/bitcoin/bitcoin.conf"
}

@test "failed Tor setup does not enable BIP37" {
  rm "$box/data/tor/bisq/hostname"
  menu ADDBISQ
  [ "$status" -eq 1 ]
  run grep -q HiddenServiceDir "$box/tor/torrc"
  [ "$status" -eq 1 ]
  run grep -q '^peerbloomfilters=1' "$box/data/bitcoin/bitcoin.conf"
  [ "$status" -eq 1 ]
  run grep -q '^restart bitcoind' "$box/services"
  [ "$status" -eq 1 ]
}

@test "failed Tor reload restores torrc and failed Bitcoin restart restores bitcoin.conf" {
  conf="$box/data/bitcoin/bitcoin.conf"
  cp "$conf" "$box/previous"
  export failed_service='reload tor@default'
  menu ADDBISQ
  [ "$status" -eq 1 ]
  [ ! -s "$box/tor/torrc" ]
  cmp "$box/previous" "$conf"
  export failed_service='restart bitcoind'
  menu ADDBISQ
  [ "$status" -eq 1 ]
  cmp "$box/previous" "$conf"
}

@test "a failed live BIP37 check restores the Bitcoin and Tor configurations" {
  cp "$box/data/bitcoin/bitcoin.conf" "$box/before"
  export rpc_fail=1
  menu ADDBISQ
  [ "$status" -eq 1 ]
  cmp "$box/before" "$box/data/bitcoin/bitcoin.conf"
  run grep -q HiddenServiceDir "$box/tor/torrc"
  [ "$status" -eq 1 ]
}
