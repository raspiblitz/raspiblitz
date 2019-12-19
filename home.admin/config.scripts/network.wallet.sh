#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the Bitcoin Core wallet on or off"
 echo "network.wallet.sh [on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf
source /mnt/hdd/${network}/${network}.conf

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  if [ ${disablewallet} == 1 ]; then
    sudo sed -i "s/^disablewallet=.*/disablewallet=0/g" /mnt/hdd/${network}/${network}.conf
    echo "switching the ${network} core wallet on and restarting ${network}d"
    sudo systemctl restart ${network}d
    exit 0
  else
    echo "The ${network} core wallet is already on"    
    exit 0
  fi
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  sudo sed -i "s/^disablewallet=.*/disablewallet=1/g" /mnt/hdd/${network}/${network}.conf
  sudo systemctl restart ${network}d
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1