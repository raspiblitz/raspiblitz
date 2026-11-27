#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p admin/setup.scripts
  export USER=pi
  export BASH_ENV="$PWD/once.sh"
  # The first sleep after selecting a screen ends the LCD loop.
  printf 'sleep() { exit 0; }\n' >once.sh
  sed -e "s|/home/admin|$PWD/admin|g" -e "s|/mnt/hdd|$PWD/data|g" \
    "$BATS_TEST_DIRNAME/../home.admin/00infoLCD.sh" >lcd.sh
  touch admin/_version.info
  printf 'setupPhase=done\nstate=ready\n' >admin/raspiblitz.info
  cat >admin/_cache.sh <<'SH'
#!/bin/sh
case "$1" in
  get) shift; for key do grep -m1 "^$key=" cache || :; done ;;
  set) printf '%s=%s\n' "$2" "$3" >>written ;;
esac
SH
  chmod +x admin/_cache.sh
  for screen in 00infoBlitz.sh setup.scripts/eventBlockchainSync.sh setup.scripts/eventInfoWait.sh; do
    printf '#!/bin/sh\necho "%s $*" >selected\n' "$screen" >"admin/$screen"
    chmod +x "admin/$screen"
  done
}

lcd() {
  printf 'lightning=%s\nln_default_ready=%s\nln_default_sync_chain=%s\nln_default_sync_initial_done=%s\nln_default_locked=%s\n' \
    "$1" "$2" "$3" "$4" "$5" >cache
  printf 'btc_default_synced=1\nbtc_default_online=1\n' >>cache
  rm -f selected
  run timeout 3 bash lcd.sh --pause 0
  [ "$status" -eq 0 ]
}

@test "LCD selects sync while any Lightning readiness signal is zero" {
  for readiness in '0 1 1' '1 0 1' '1 1 0'; do
    lcd cl $readiness 0
    [ "$(cat selected)" = 'setup.scripts/eventBlockchainSync.sh lcd' ]
  done
}

@test "ready CLN, locked LND and Bitcoin-only keep their own screens" {
  lcd cl 1 1 1 0
  grep -q '^00infoBlitz.sh ' selected
  lcd lnd 0 0 0 1
  [ "$(cat selected)" = 'setup.scripts/eventInfoWait.sh walletlocked  lcd' ]
  lcd none 0 0 0 0
  grep -q '^00infoBlitz.sh ' selected
}

@test "the CLN scanner publishes peer and fee metrics independently" {
  # Run just the CLN info cache writer. A full scanner starts privileged services.
  sed -n '/_cache.sh set ln_cl_${CHAIN}net_alias/,/^[[:space:]]*else$/p' \
    "$BATS_TEST_DIRNAME/../home.admin/_background.scan.sh" |
    sed -e '$d' -e "s|/home/admin|$PWD/admin|g" >publish.sh
  # Apply the monitor's getinfo parser and output formatting to the same RPC values.
  sed -n -e '/^  cl_peers=/p' -e '/^  cl_fees_collected_msat=/p' \
    -e '/^  echo "ln_cl_peers=/p' -e '/^  echo "ln_cl_fees_total=/p' \
    "$BATS_TEST_DIRNAME/../home.admin/config.scripts/cl.monitor.sh" >parse.sh
  for peers in 0 1; do
    : >written
    ln_getInfo="{\"num_peers\":$peers,\"fees_collected_msat\":\"17msat\"}" bash parse.sh >metrics
    env CHAIN=main isDefaultLightning=1 isDefaultChain=1 bash -c 'source metrics && source publish.sh'
    grep -Fxq "ln_cl_mainnet_peers=$peers" written
    grep -Fxq "ln_default_peers=$peers" written
    grep -Fxq 'ln_default_fees_total=17' written
  done
}
