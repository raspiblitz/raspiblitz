#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to set alias of the C-lightning node "
 echo "cln.setname.sh [mainnet|testnet|signet] [?newName]"
 exit 1
fi

# 1. parameter [?newName]
newName=$2

# use default values from the raspiblitz.conf
source <(/home/admin/config.scripts/network.aliases.sh getvars $1)

# run interactive if 'turn on' && no further parameters
if [ ${#newName} -eq 0 ]; then

  sudo rm ./.tmp
  dialog --backtitle "Set CLN Name/Alias" --inputbox "ENTER the new Name/Alias for the C-lightning node:
(free to choose, one word up to 32 basic characters)
" 8 56 2>./.tmp
  newName=$( cat ./.tmp | tr -dc '[:alnum:]\n\r' )
  if [ ${#newName} -eq 0 ]; then
    echo "FAIL input cannot be empty"
    exit 1
  fi
fi

# config file
blitzConfig="/mnt/hdd/raspiblitz.conf"

# cln conf file
clnConfig="/home/bitcoin/.lightning/${netprefix}config"

# check if raspiblitz config file exists
if [ ! -f ${blitzConfig} ]; then
 echo "FAIL - missing ${blitzConfig}"
 exit 1
fi

# check if cln config file exists
if [ ! -f ${clnConfig} ]; then
 echo "FAIL - missing ${clnConfig}"
 exit 1
fi

# make sure entry line for 'alias' exists 
entryExists=$(cat ${clnConfig} | grep -c "alias=")
if [ ${entryExists} -eq 0 ]; then
  echo "alias=" >> ${clnConfig}
fi

# stop services
echo "making sure services are not running"
sudo systemctl stop ${netprefix}lightningd 2>/dev/null

# config: change name
sudo sed -i "s/^alias=.*/alias=${newName}/g" ${clnConfig}

source /home/admin/raspiblitz.info
if [ "${state}" == "ready" ]; then
  sudo systemctl start ${netprefix}lightningd
fi

exit 0
