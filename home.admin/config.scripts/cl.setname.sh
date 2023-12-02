#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo 
  echo "Config script to set the alias of the Core Lightning node"
  echo "cl.setname.sh [mainnet|testnet|signet] [?newName]"
  echo
  exit 1
fi

# 1. parameter [?newName]
newName=$2

# use default values from the raspiblitz.conf
source <(/home/admin/config.scripts/network.aliases.sh getvars cl $1)

# run interactive if 'turn on' && no further parameters
if [ ${#newName} -eq 0 ]; then

  sudo rm ./.tmp
  dialog --backtitle "Set CL Name/Alias" --inputbox "ENTER the new Name/Alias for the Core Lightning node:
(free to choose, one word up to 32 basic characters)
" 8 56 2>./.tmp
  newName=$( cat ./.tmp | tr -dc '[:alnum:]\n\r' )
  if [ ${#newName} -eq 0 ]; then
    echo "FAIL input cannot be empty"
    exit 1
  fi
fi

# check if cl config file exists
if ! sudo ls ${CLCONF} 2>/dev/null; then
  echo "FAIL - missing ${CLCONF}"
  exit 1
fi

# make sure entry line for 'alias' exists 
entryExists=$(cat ${CLCONF} | grep -c "alias=")
if [ ${entryExists} -eq 0 ]; then
  echo "alias=" >> ${CLCONF}
fi

# stop services
echo "making sure services are not running"
sudo systemctl stop ${netprefix}lightningd 2>/dev/null

# config: change name
sudo sed -i "s/^alias=.*/alias=${newName}/g" ${CLCONF}

source <(/home/admin/_cache.sh get state)
if [ "${state}" == "ready" ]; then
  sudo systemctl start ${netprefix}lightningd
fi

exit 0
