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

  echo "txindex=${txindex}"
  if [ ${txindex} -eq 0 ]; then
    exit 0
  fi

  # try to gather if still indexing
  indexedToBlock=$(sudo tail -n 200 /mnt/hdd/${network}${pathAdd}/debug.log | grep "Syncing txindex with block chain from height" | tail -n 1 | cut -d " " -f 9 | sed 's/[^0-9]*//g')
  blockchainHeight=$(sudo -u bitcoin ${network}-cli getblockchaininfo 2>/dev/null | jq -r '.blocks' | sed 's/[^0-9]*//g')
  indexFinished=$(sudo tail -n 200 /mnt/hdd/${network}${pathAdd}/debug.log | grep -c "txindex is enabled at height")
  echo "indexedToBlock=${indexedToBlock}"
  echo "blockchainHeight=${blockchainHeight}"
  echo "indexFinished=${indexFinished}"
  if [ ${#indexedToBlock} -eq 0 ] || [ ${indexFinished} -gt 0 ] || [ "${indexedToBlock}" = "${blockchainHeight}" ]; then
    echo "isIndexed=1"
    indexInfo="OK"
  else
    echo "isIndexed=0"
    if [ ${#indexedToBlock} -gt 0 ] && [ ${#blockchainHeight} -gt 0 ]; then
      progressPercent=$(printf %.2f $(echo "${indexedToBlock}/${blockchainHeight}*100" | bc -l))
      indexInfo="Indexing is at ${progressPercent}% (please wait)"
    else
      indexInfo="Indexing is running (please wait)"
    fi
    echo "indexInfo='${indexInfo}'"
  fi
  exit 0

fi


###################
# switch on
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check txindex (parsed and sourced from bitcoin network config above)
  if [ ${txindex} == 0 ]; then
    sudo sed -i "s/^txindex=.*/txindex=1/g" /mnt/hdd/${network}/${network}.conf
    echo "switching txindex=1 and restarting ${network}d"
    sudo systemctl restart ${network}d
    echo "The indexing takes ~7h on an RPi4 with SSD"
    echo "monitor with: sudo tail -n 20 -f /mnt/hdd/${network}${pathAdd}/debug.log"
    exit 0
  else
    echo "txindex is already active"
    exit 0
  fi
fi


###################
# switch off
###################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  sudo sed -i "s/^txindex=.*/txindex=0/g" /mnt/hdd/${network}/${network}.conf
  sudo systemctl restart ${network}d
  exit 0
fi


###################
# delete (and make sure all using apps are deinstalled)
# on version update check all bonus scripts that this network.txindex.sh on
###################
if [ "$1" = "delete" ]; then
  echo "# deinstalling apps needing txindex ..."
  sudo -u admin /home/admin/config.scripts/bonus.btc-rpc-explorer.sh off
  echo "# changing config ..."
  sudo systemctl stop ${network}d
  sudo sed -i "s/^txindex=.*/txindex=0/g" /mnt/hdd/${network}/${network}.conf
  echo "# deleting tx index ..."
  sudo rm -r /mnt/hdd/${network}/indexes/txindex
  echo "# restarting bitcoind ..."
  sudo systemctl restart ${network}d
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
