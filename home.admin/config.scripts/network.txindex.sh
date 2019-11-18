#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch txindex on or off"
 echo "bitcoin.txindex.sh [on|off]"
 exit 1
fi

source /mnt/hdd/bitcoin/bitcoin.conf

# add default value to bitcoin.conf if needed
if [ ${#txindex} -eq 0 ]; then
  echo "txindex=0" >> /mnt/hdd/bitcoin/bitcoin.conf
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  if [ "${#txindex}" -eq 0 ]; then
    sudo sed -i "s/^txindex=.*/txindex=1/g" /mnt/hdd/bitcoin/bitcoin.conf
    echo "switching txindex=1 and restarting bitcoind"
    sudo systemctl restart bitcoind
    echo "The indexing takes ~7h on an RPi4 with SSD"
    echo "monitor with: sudo tail -n 20 -f /mnt/hdd/bitcoin/debug.log"
    exit 0
  else
    echo "txindex is already active"
    exit 0
  fi
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  sudo sed -i "s/^txindex=.*/txindex=0/g" /mnt/hdd/bitcoin/bitcoin.conf
  sudo systemctl restart bitcoind
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1