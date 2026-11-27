#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_TMPDIR"
  export USER=bitcoin
  export PATH="$PWD/bin:$PATH"
  mkdir -p bin admin/config.scripts data/app-data/{bitcoin,lnd/data/chain/bitcoin/mainnet}
  sed -e "s|/mnt/hdd|$PWD/data|g" -e "s|/home/admin|$PWD/admin|g" \
    "$BATS_TEST_DIRNAME/../home.admin/config.scripts/lnd.check.sh" >prestart.sh
  cat >admin/config.scripts/network.aliases.sh <<'SH'
#!/bin/sh
echo "network=bitcoin chain=main CHAIN=mainnet lndConfFile=$PWD/data/app-data/lnd/lnd.conf"
SH
  printf '[Application Options]\n\n[tor]\ntor.control=192.0.2.1:9999\n' >data/app-data/lnd/lnd.conf
  printf 'rpcuser=fixture\nrpcpassword=fixture\n' >data/app-data/bitcoin/bitcoin.conf
  cat >bin/nc <<'SH'
#!/bin/sh
echo "$*" >>probes
test "$*" = '-n -z -w 1 127.0.0.1 9051' && test "$(wc -l <probes)" -ge "$READY_ON"
SH
  printf '#!/bin/sh\necho "$1" >>sleeps\n' >bin/sleep
  chmod +x admin/config.scripts/network.aliases.sh bin/*
}

prestart() {
  echo "runBehindTor=$1" >data/app-data/raspiblitz.conf
  bash prestart.sh prestart mainnet >stdout 2>stderr
  grep -q '^# OK PRESTART DONE$' stdout
}

@test "an already listening Tor controller adds no delay" {
  export READY_ON=1
  prestart on
  grep -Fxq 'tor.control=9051' data/app-data/lnd/lnd.conf
  [ "$(wc -l <probes)" -eq 1 ]
  [ ! -e sleeps ]
  ! grep -q 'control port .* unavailable' stderr
}

@test "a late listener can come up before LND starts" {
  export READY_ON=3
  prestart on
  [ "$(wc -l <probes)" -eq 3 ]
  [ "$(wc -l <sleeps)" -eq 2 ]
  ! grep -q 'control port .* unavailable' stderr
}

@test "a refused controller emits one diagnostic and lets LND attempt startup" {
  export READY_ON=99
  prestart on
  [ "$(wc -l <probes)" -eq 5 ]
  [ "$(wc -l <sleeps)" -eq 4 ]
  [ "$(grep -cF 'local Tor control port 127.0.0.1:9051 is unavailable' stderr)" -eq 1 ]
}

@test "a clearnet node does not probe Tor" {
  export READY_ON=99
  prestart off
  [ ! -e probes ]
  [ ! -e sleeps ]
}
