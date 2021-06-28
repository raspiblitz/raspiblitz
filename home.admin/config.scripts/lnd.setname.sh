#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to set a alias of LND (and hostname of raspi)"
 echo "lnd.setname.sh [?newName] [?forceHostname]"
 exit 1
fi

# 1. parameter [?newName]
newName=$1

# use default values from the raspiblitz.conf
source <(/home/admin/config.scripts/network.aliases.sh getvars)

# run interactive if 'turn on' && no further parameters
if [ ${#newName} -eq 0 ]; then

  sudo rm ./.tmp
  dialog --backtitle "Set LND Name/Alias" --inputbox "ENTER the new Name/Alias for LND node:
(free to choose, one word, use basic characters)
" 8 52 2>./.tmp
  newName=$( cat ./.tmp | tr -dc '[:alnum:]\n\r' )
  if [ ${#newName} -eq 0 ]; then
    echo "FAIL input cannot be empty"
    exit 1
  fi
fi

# config file
blitzConfig="/mnt/hdd/raspiblitz.conf"

# lnd conf file
lndConfig="/mnt/hdd/lnd/${netprefix}lnd.conf"

# check if raspibblitz config file exists
configExists=$(ls ${blitzConfig} | grep -c '.conf')
if [ ${configExists} -eq 0 ]; then
 echo "FAIL - missing ${blitzConfig}"
 exit 1
fi

# make sure entry line for 'hostname' exists 
entryExists=$(cat ${blitzConfig} | grep -c 'hostname=')
if [ ${entryExists} -eq 0 ]; then
  echo "hostname=" >> ${blitzConfig}
fi

# make sure entry line for 'setnetworkname' exists 
entryExists=$(cat ${blitzConfig} | grep -c 'setnetworkname=')
if [ ${entryExists} -eq 0 ]; then
  echo "setnetworkname=" >> ${blitzConfig}
fi

# check if lnd config file exists
configExists=$(ls ${lndConfig} | grep -c '.conf')
if [ ${configExists} -eq 0 ]; then
 echo "FAIL - missing ${lndConfig}"
 exit 1
fi

# make sure entry line for 'alias' exists 
entryExists=$(cat ${lndConfig} | grep -c 'alias=')
if [ ${entryExists} -eq 0 ]; then
  echo "alias=" >> ${blitzConfig}
fi

# stop services
echo "making sure services are not running"
sudo systemctl stop ${netprefix}lnd 2>/dev/null

# lnd.conf: change name
sudo sed -i "s/^alias=.*/alias=${newName}/g" ${lndConfig}

# raspiblitz.conf: change name
sudo sed -i "s/^hostname=.*/hostname=${newName}/g" ${blitzConfig}

# set name in local network just if forced (not anymore by default)
# see https://github.com/rootzoll/raspiblitz/issues/819
if [ "$2" = "alsoNetwork" ]; then
  # OS: change hostname
  sudo raspi-config nonint do_hostname ${newName}
  sudo sed -i "s/^setnetworkname=.*/setnetworkname=1/g" ${blitzConfig}
else
  sudo sed -i "s/^setnetworkname=.*/setnetworkname=0/g" ${blitzConfig}
fi

echo "needs reboot to run normal again"
exit 0
