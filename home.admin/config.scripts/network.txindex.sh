#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch txindex on or off"
 echo "network.txindex.sh [status|on|off|delete]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add txindex with default value (0) to bitcoin.conf if missing
if ! grep -Eq "^txindex=.*" /mnt/hdd/${network}/${network}.conf; then
  echo "txindex=0" | sudo tee -a /mnt/hdd/${network}/${network}.conf >/dev/null
fi

# set variable ${txindex}
source <(grep -E "^txindex=.*" /mnt/hdd/${network}/${network}.conf)

# check for testnet and set pathAdd (e.g. for debug.log)
pathAdd=""
if [ "${chain}" = "test" ]; then
	  pathAdd="/testnet3"
fi

###################
# STATUS
###################
if [ "$1" = "status" ]; then

  echo "##### STATUS TXINDEX"

  # check user is root
  if [ "$EUID" -ne 0 ]; then
    logger "FAIL: network.txindex.sh status needs sudo"
    echo "error='missing sudo'"
    exit 1
  fi

  indexByteSize=$(du -s /mnt/hdd/bitcoin/indexes/txindex 2>/dev/null | cut -f1)
  if [ "${indexByteSize}" == "" ]; then
    indexByteSize=0
  fi

  echo "txindex=${txindex}"
  echo "indexByteSize=${indexByteSize}"
  if [ ${txindex} -eq 0 ]; then
    exit 0
  fi

  # try to gather if still indexing
  source <(/home/admin/_cache.sh get btc_mainnet_blocks_headers)
  blockchainHeight="${btc_mainnet_blocks_headers}"
  indexedToBlock=$(tail -n 200 /mnt/hdd/${network}${pathAdd}/debug.log | grep "Syncing txindex with block chain from height" | tail -n 1 | cut -d " " -f 9 | sed 's/[^0-9]*//g')
  indexFinished=$(tail -n 200 /mnt/hdd/${network}${pathAdd}/debug.log | grep -c "txindex is enabled at height")

  if [ ${#indexedToBlock} -eq 0 ] || [ ${indexFinished} -gt 0 ] || [ "${indexedToBlock}" = "${blockchainHeight}" ]; then
    echo "isIndexed=1"
    indexedToBlock=$blockchainHeight
    indexFinished=1
    indexInfo="OK"
  else
    echo "isIndexed=0"
    progressPercent="0.00%"
    if [ ${#indexedToBlock} -gt 0 ] && [ ${#blockchainHeight} -gt 0 ]; then
      progressPercentRaw=$(echo "${indexedToBlock}/${blockchainHeight}*100" | bc -l 2>/dev/null)
      progressPercent=$(printf "%.2f" "${progressPercentRaw}" 2>/dev/null)
      indexInfo="Building ${progressPercent}% (please wait)"
    else
      indexInfo="Building (please wait)"
    fi
    echo "indexInfo='${indexInfo}'"
    echo "indexPrecent='${progressPercent}'"
  fi  

  echo "indexFinished=${indexFinished}"
  echo "indexedToBlock=${indexedToBlock}"
  echo "blockchainHeight=${blockchainHeight}"

  exit 0

fi

###################
# switch on
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  # check txindex (parsed and sourced from bitcoin network config above)
  if [ ${txindex} == 0 ]; then
    sudo sed -i "s/^txindex=.*/txindex=1/g" /mnt/hdd/${network}/${network}.conf
    echo "# switching txindex=1"
    isBitcoinRunning=$(systemctl is-active ${network}d | grep -c "^active")
    if [ ${isBitcoinRunning} -eq 1 ]; then
      echo "# ${network}d is running - so restarting"
      sudo systemctl restart ${network}d
    else
      echo "# ${network}d is not running - so NOT restarting"
    fi
    echo "# The indexing takes ~7h on an RPi4 with SSD"
    echo "# monitor with: sudo tail -n 20 -f /mnt/hdd/${network}${pathAdd}/debug.log"
    exit 0
  else
    echo "# txindex is already active"
    exit 0
  fi
fi

###################
# switch off
###################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# changing config ..."
  sudo sed -i "s/^txindex=.*/txindex=0/g" /mnt/hdd/${network}/${network}.conf
  echo "# deinstalling apps needing txindex ..."
  sudo -u admin /home/admin/config.scripts/bonus.btc-rpc-explorer.sh off
  echo "# restarting bitcoind ..."
  sudo systemctl restart ${network}d
  exit 0
fi

###################
# delete (and make sure all using apps are deinstalled)
# on version update check all bonus scripts that this network.txindex.sh on
###################
if [ "$1" = "delete" ]; then
  echo "# stopping bitcoind ..."
  sudo systemctl stop ${network}d
  echo "# deleting tx index ..."
  sudo rm -r /mnt/hdd/${network}/indexes/txindex
  echo "# restarting bitcoind ..."
  sudo systemctl restart ${network}d
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
