#!/usr/bin/env bash

# A healthy Core may spend several minutes verifying blocks before RPC is ready.
cache="$(dirname "$0")/../_cache.sh"
case "${1:-main}" in
  main|mainnet) unit=bitcoind.service; port=8332 ;;
  test|testnet) unit=tbitcoind.service; port=18332 ;;
  sig|signet) unit=sbitcoind.service; port=38332 ;;
  *) echo "Unsupported default Bitcoin chain: $1"; exit 1 ;;
esac
stopped_polls=0
while true; do
  state=$(systemctl show "$unit" --property=ActiveState --value) || exit 1
  if [ "$state" = activating ]; then
    state=$(systemctl show "$unit" --property=SubState --value) || exit 1
  fi
  case "$state" in
    active)
      stopped_polls=0
      # A readiness value from before the service restarted can remain cached.
      if "$cache" get btc_default_ready | grep -Fxq 'btc_default_ready="1"' &&
        timeout 6 sudo -u bitcoin /usr/local/bin/bitcoin-cli -datadir=/home/bitcoin/.bitcoin \
          -rpcport="$port" -rpcclienttimeout=4 getblockcount >/dev/null 2>&1; then
        exit 0
      fi
      ;;
    failed|inactive|auto-restart)
      # Allow a minute for provisioning/systemd to schedule the service.
      (( ++stopped_polls ))
      if (( stopped_polls >= 30 )); then
        echo "$unit remained $state. Inspect journalctl -u $unit -b."
        systemctl show "$unit" --property=Result,ExecMainStatus
        exit 1
      fi
      ;;
    *) stopped_polls=0 ;;
  esac
  sleep 2
done
