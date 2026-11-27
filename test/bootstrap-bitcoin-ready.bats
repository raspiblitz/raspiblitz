#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p setup.scripts bin
  cp "$BATS_TEST_DIRNAME/../home.admin/setup.scripts/waitBitcoinReady.sh" setup.scripts/
  export PATH="$PWD/bin:$PATH"
  export READY_AFTER=0 STOPPED_UNTIL=0 RPC_AFTER=0 EXPECT_UNIT=bitcoind.service EXPECT_CHAIN=
  echo 0 > tick
  cat > bin/systemctl <<'SH'
#!/bin/bash
case "$*" in
  "show $EXPECT_UNIT --property=ActiveState --value")
    if (( $(cat tick) < STOPPED_UNTIL )); then echo inactive; else echo active; fi ;;
  "show $EXPECT_UNIT --property=InvocationID --value") echo instance ;;
  "show $EXPECT_UNIT --property=Result,ExecMainStatus") echo 'Result=exit-code' ;;
  *) echo "$*" > unexpected; exit 1 ;;
esac
SH
  cat > bin/sleep <<'SH'
#!/bin/bash
echo "$(( $(cat tick) + 1 ))" > tick
SH
  cat > bin/date <<'SH'
#!/bin/bash
echo "$(( $(cat tick) * ${TICK_SECONDS:-2} ))"
SH
  cat > _cache.sh <<'SH'
#!/bin/bash
if (( $(cat tick) >= READY_AFTER )); then echo 'value="1"'; else echo 'value="0"'; fi
if (( $(cat tick) < ${STALE_UNTIL:-0} )); then echo 'lasttouch="0"'; else printf 'lasttouch="%s"\n' "$(date +%s)"; fi
SH
  cat > bin/sudo <<'SH'
#!/bin/bash
[[ "$*" = "-u bitcoin /usr/local/bin/bitcoin-cli ${EXPECT_CHAIN:+$EXPECT_CHAIN }-conf=/mnt/hdd/app-data/bitcoin/bitcoin.conf -datadir=/mnt/hdd/app-storage/bitcoin -rpcclienttimeout=4 getblockcount" ]] || exit 1
if (( $(cat tick) < RPC_AFTER )); then
  echo "${RPC_ERROR:-RPC unavailable}" >&2
  exit 1
fi
SH
  chmod +x bin/* _cache.sh
}

@test "an active service may warm up past the old restart threshold" {
  export READY_AFTER=72
  run bash setup.scripts/waitBitcoinReady.sh
  [ "$status" -eq 0 ]
  [ "$(cat tick)" -eq 72 ]
  [ ! -e unexpected ]
}

@test "a cached ready flag cannot complete setup while Core is stopped" {
  export STOPPED_UNTIL=40
  run bash setup.scripts/waitBitcoinReady.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"Result=exit-code"* ]]
  [ ! -e unexpected ]
}

@test "a service scheduled during the initial grace period can become ready" {
  export STOPPED_UNTIL=12
  run bash setup.scripts/waitBitcoinReady.sh
  [ "$status" -eq 0 ]
  [ "$(cat tick)" -eq 13 ]
}

@test "a stale active-service cache waits for live RPC using the configured signet service settings" {
  export RPC_AFTER=5 EXPECT_UNIT=sbitcoind.service EXPECT_CHAIN=-signet
  run bash setup.scripts/waitBitcoinReady.sh sig
  [ "$status" -eq 0 ]
  [ "$(cat tick)" -eq 5 ]
}

@test "unavailable scanner is reported, explicit -28 warmup can still complete" {
  export TICK_SECONDS=900 READY_AFTER=9
  run bash setup.scripts/waitBitcoinReady.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"background scanner"* ]]
  echo 0 > tick
  export READY_AFTER=4 RPC_AFTER=4 RPC_ERROR="error code: -28"
  run bash setup.scripts/waitBitcoinReady.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"warming up"* ]]
}

@test "persistent identical warmup becomes an actionable error without resetting Core" {
  export TICK_SECONDS=1800 RPC_AFTER=20 RPC_ERROR="error code: -28"
  run bash setup.scripts/waitBitcoinReady.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"same RPC warmup for an hour"* ]]
  [ ! -e unexpected ]
}

@test "even a healthy RPC waits for a sample newer than this service observation" {
  export STALE_UNTIL=6
  run bash setup.scripts/waitBitcoinReady.sh
  [ "$status" -eq 0 ]
  [ "$(cat tick)" -eq 6 ]
}
