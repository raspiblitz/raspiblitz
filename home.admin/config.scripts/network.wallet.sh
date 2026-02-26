#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the Bitcoin Core wallet on or off"
 echo "network.wallet.sh [status|on|off]"
 exit 1
fi

source /mnt/hdd/app-data/raspiblitz.conf
source /home/admin/raspiblitz.info

# determine the correct bitcoind service name based on chain
# chain from raspiblitz.conf: main|test|sig
if [ "${chain}" = "test" ]; then
  bitcoind_service="tbitcoind"
elif [ "${chain}" = "sig" ]; then
  bitcoind_service="sbitcoind"
else
  bitcoind_service="bitcoind"
fi

# add disablewallet with default value (0) to bitcoin.conf if missing
if ! grep -Eq "^disablewallet=.*" /mnt/hdd/app-data/${network}/${network}.conf; then
  echo "disablewallet=0" | sudo tee -a /mnt/hdd/app-data/${network}/${network}.conf >/dev/null
fi

# set variable ${disablewallet}
source <(grep -E "^disablewallet=.*" /mnt/hdd/app-data/${network}/${network}.conf)


###################
# STATUS
###################
if [ "$1" = "status" ]; then

  echo "##### STATUS disablewallet"
  echo "disablewallet=${disablewallet}"

  exit 0
fi


###################
# switch on
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  
  # bitcoin config for wallet name & dir will be done by bitcoin.check.sh prestart

  if [ ${disablewallet} == 1 ]; then
    sudo sed -i "s/^disablewallet=.*/disablewallet=0/g" /mnt/hdd/app-data/${network}/${network}.conf
    echo "# Switching the ${network} core wallet on"
  else
    echo "# The ${network} core wallet is already on"    
  fi
  source <(/home/admin/_cache.sh get state)
  if [ ${state} != "recovering" ]; then
    echo "# Restarting ${bitcoind_service}"
    sudo systemctl restart ${bitcoind_service}
  fi
  exit 0
fi

###################
# switch off
###################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  sudo sed -i "s/^disablewallet=.*/disablewallet=1/g" /mnt/hdd/app-data/${network}/${network}.conf
  sudo systemctl restart ${bitcoind_service}
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
