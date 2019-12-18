#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch txindex on or off"
 echo "network.txindex.sh [on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf
source /mnt/hdd/${network}/${network}.conf

# add default value to bitcoin.conf if needed
if [ ${#txindex} -eq 0 ]; then
  echo "txindex=0" >> /mnt/hdd/${network}/${network}.conf
  source /mnt/hdd/${network}/${network}.conf
fi

if [ "$1" = "status" ]; then

  echo "##### STATUS TXINDEX"

  echo "txindex=${txindex}"
  if [ ${txindex} -eq 0 ]; then
    exit 0
  fi

  # try to gather if still indexing
  indexedToBlock=$(sudo tail -n 100 /mnt/hdd/litecoin/debug.log | grep "Syncing txindex with block chain from height" | tail -n 1 | cut -d " " -f 9)
  blockchainHeight=$(sudo -u bitcoin ${network}-cli getblockchaininfo 2>/dev/null | jq -r '.blocks' | sed 's/[^0-9]*//g')
  if [ ${#indexedToBlock} -eq 0 ] || [ "${indexedToBlock}" = "${blockchainHeight}" ]; then
    echo "isSynced=1"
  else
    echo "isSynced=0"
  fi
  exit 0

fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  if [ ${txindex} == 0 ]; then
    sudo sed -i "s/^txindex=.*/txindex=1/g" /mnt/hdd/${network}/${network}.conf
    echo "switching txindex=1 and restarting ${network}d"
    sudo systemctl restart ${network}d
    echo "The indexing takes ~7h on an RPi4 with SSD"
    echo "monitor with: sudo tail -n 20 -f /mnt/hdd/${network}/debug.log"
    exit 0
  else
    echo "txindex is already active"
    exit 0
  fi
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  sudo sed -i "s/^txindex=.*/txindex=0/g" /mnt/hdd/${network}/${network}.conf
  sudo systemctl restart ${network}d
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1