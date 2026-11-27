#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p setup.scripts bin
  cp "$BATS_TEST_DIRNAME/../home.admin/setup.scripts/waitBitcoinReady.sh" setup.scripts/
  export PATH="$PWD/bin:$PATH"
  export READY_AFTER=0 STOPPED_UNTIL=0 RPC_AFTER=0 EXPECT_UNIT=bitcoind.service EXPECT_PORT=8332
  echo 0 > tick
  cat > bin/systemctl <<'SH'
#!/bin/bash
case "$*" in
  "show $EXPECT_UNIT --property=ActiveState --value")
    if (( $(cat tick) < STOPPED_UNTIL )); then echo inactive; else echo active; fi ;;
  "show $EXPECT_UNIT --property=Result,ExecMainStatus") echo 'Result=exit-code' ;;
  *) echo "$*" > unexpected; exit 1 ;;
esac
SH
  cat > bin/sleep <<'SH'
#!/bin/bash
echo "$(( $(cat tick) + 1 ))" > tick
SH
  cat > _cache.sh <<'SH'
#!/bin/bash
if (( $(cat tick) >= READY_AFTER )); then echo 'btc_default_ready="1"'; else echo 'btc_default_ready="0"'; fi
SH
  cat > bin/sudo <<'SH'
#!/bin/bash
[[ "$*" = "-u bitcoin /usr/local/bin/bitcoin-cli -datadir=/home/bitcoin/.bitcoin -rpcport=$EXPECT_PORT -rpcclienttimeout=4 getblockcount" ]] || exit 1
(( $(cat tick) >= RPC_AFTER ))
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
  [ "$(cat tick)" -eq 12 ]
}

@test "a stale active-service cache waits for live RPC on the configured signet port" {
  export RPC_AFTER=5 EXPECT_UNIT=sbitcoind.service EXPECT_PORT=38332
  run bash setup.scripts/waitBitcoinReady.sh sig
  [ "$status" -eq 0 ]
  [ "$(cat tick)" -eq 5 ]
}
