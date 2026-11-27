#!/usr/bin/env bash

# A healthy Core may spend several minutes verifying blocks before RPC is ready.
cache="$(dirname "$0")/../_cache.sh"
stopped_polls=0
while true; do
  state=$(systemctl show bitcoind.service --property=ActiveState --value) || exit 1
  if [ "$state" = activating ]; then
    state=$(systemctl show bitcoind.service --property=SubState --value) || exit 1
  fi
  case "$state" in
    active)
      stopped_polls=0
      btc_default_ready=0
      source <("$cache" get btc_default_ready)
      [ "$btc_default_ready" = 1 ] && exit 0
      ;;
    failed|inactive|auto-restart)
      # Allow a minute for provisioning/systemd to schedule the service.
      (( ++stopped_polls ))
      if (( stopped_polls >= 30 )); then
        echo "bitcoind.service remained $state. Inspect journalctl -u bitcoind -b."
        systemctl show bitcoind.service --property=Result,ExecMainStatus
        exit 1
      fi
      ;;
    *) stopped_polls=0 ;;
  esac
  sleep 2
done
