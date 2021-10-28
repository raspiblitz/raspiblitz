#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to set a alias of LND (and hostname of raspi)"
 echo "lnd.setname.sh [mainnet|testnet|signet] [?newName] [?forceHostname]"
 exit 1
fi

# 1. parameter [?newName]
newName=$2

source <(/home/admin/config.scripts/network.aliases.sh getvars $2)

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

# lnd conf file
lndConfig="/mnt/hdd/lnd/${netprefix}lnd.conf"

# check if lnd config file exists
configExists=$(ls ${lndConfig} | grep -c '.conf')
if [ ${configExists} -eq 0 ]; then
 echo "FAIL - missing ${lndConfig}"
 exit 1
fi

# make sure entry line for 'alias' exists 
entryExists=$(cat ${lndConfig} | grep -c 'alias=')
if [ ${entryExists} -eq 0 ]; then
  echo "alias=" >> ${lndConfig}
fi

# stop services
echo "making sure services are not running"
sudo systemctl stop ${netprefix}lnd 2>/dev/null

# lnd.conf: change name
sudo sed -i "s/^alias=.*/alias=${newName}/g" ${lndConfig}

# raspiblitz.conf: change name
/home/admin/config.scripts/blitz.conf.sh set hostname "${newName}"

# set name in local network just if forced (not anymore by default)
# see https://github.com/rootzoll/raspiblitz/issues/819
if [ "$3" = "alsoNetwork" ]; then
  # OS: change hostname
  sudo raspi-config nonint do_hostname ${newName}
  /home/admin/config.scripts/blitz.conf.sh set setnetworkname "1"
else
  /home/admin/config.scripts/blitz.conf.sh set setnetworkname "0"
fi

#TODO - no need for full reboot only unlock LND
#if [ $# -lt 3 ];then
#  source <(/home/admin/config.scripts/blitz.cache.sh get state)
#  if [ "${state}" == "ready" ]; then
#    sudo systemctl start ${netprefix}lnd
#    # signal 1 to not reboot
#    exit 1
#  fi
#fi

echo "needs reboot to run normal again"
exit 0
