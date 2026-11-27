#!/usr/bin/env bash

# A healthy Core may spend several minutes verifying blocks before RPC is ready.
cache="$(dirname "$0")/../_cache.sh"
case "${1:-main}" in
  main|mainnet) unit=bitcoind.service; chain_args=() ;;
  test|testnet) unit=tbitcoind.service; chain_args=(-testnet) ;;
  sig|signet) unit=sbitcoind.service; chain_args=(-signet) ;;
  *) echo "Unsupported default Bitcoin chain: $1"; exit 1 ;;
esac
stopped_polls=0
started=$(date +%s)
deadline=$(( started + 1800 ))
last_warmup=
warmup_changed=$started
last_instance=
probe_rpc() {
  # Match bitcoin.install.sh's service: chain-specific RPC settings and cookie.
  timeout 6 sudo -u bitcoin /usr/local/bin/bitcoin-cli "${chain_args[@]}" \
    -conf=/mnt/hdd/app-data/bitcoin/bitcoin.conf -datadir=/mnt/hdd/app-storage/bitcoin \
    -rpcclienttimeout=4 getblockcount
}
while true; do
  state=$(systemctl show "$unit" --property=ActiveState --value) || exit 1
  if [ "$state" = activating ]; then
    state=$(systemctl show "$unit" --property=SubState --value) || exit 1
  fi
  case "$state" in
    active)
      stopped_polls=0
      instance=$(systemctl show "$unit" --property=InvocationID --value) || exit 1
      if [ "$last_instance" != "$instance" ]; then
        last_instance=$instance
        observed=$(date +%s)
      fi
      # A readiness value from before the service restarted can remain cached.
      sample=$("$cache" meta btc_default_ready)
      updated=$(sed -n 's/^lasttouch="\([0-9]\{1,12\}\)"$/\1/p' <<< "$sample")
      if [[ -n "$instance" && "$updated" =~ ^[0-9]{1,12}$ ]] && (( 10#$updated > observed )) &&
        grep -Fxq 'value="1"' <<< "$sample" && probe_rpc >/dev/null 2>&1 &&
        [ "$instance" = "$(systemctl show "$unit" --property=InvocationID --value)" ]; then
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
  now=$(date +%s)
  if (( now >= deadline )); then
    # Core explicitly reports -28 while verifying/importing. Allow verified
    # warmup to continue. A missing monitor or crash loop needs attention.
    if detail=$(probe_rpc 2>&1); then
      echo "$unit answers RPC but setup has no current ready status. Check the background scanner."
      exit 1
    elif [[ "$detail" == *"error code: -28"* ]]; then
      if (( now - started >= 86400 )); then
        echo "$unit is still in warmup after 24 hours. Inspect journalctl -u $unit -b."
        exit 1
      fi
      if [ "$detail" != "$last_warmup" ]; then
        last_warmup=$detail
        warmup_changed=$now
      elif (( now - warmup_changed >= 3600 )); then
        echo "$unit reports the same RPC warmup for an hour. Inspect journalctl -u $unit -b."
        exit 1
      fi
      echo "$unit is still warming up; RPC returned -28."
      deadline=$(( now + 300 ))
    else
      echo "No ready RPC from $unit after the startup wait. Inspect journalctl -u $unit -b."
      exit 1
    fi
  fi
  sleep 2
done
