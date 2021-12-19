#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "small config script to set a alias of LND (and hostname of raspi)"
  echo "lnd.setname.sh [mainnet|testnet|signet] [?newName] [?forceHostname]"
  exit 1
fi

# 1. parameter [?newName]
newName=$2

source <(/home/admin/config.scripts/network.aliases.sh getvars lnd $1)

function setting() # FILE LINENUMBER NAME VALUE
{
  FILE=$1
  LINENUMBER=$2
  NAME=$3
  VALUE=$4
  settingExists=$(cat ${FILE} | grep -c "^${NAME}=")
  echo "# setting ${FILE} ${LINENUMBER} ${NAME} ${VALUE}"
  echo "# ${NAME} exists->(${settingExists})"
  if [ "${settingExists}" == "0" ]; then
    echo "# adding setting (${NAME})"
    sudo -u bitcoin sed -i "${LINENUMBER}i${NAME}=" ${FILE}
  fi
  echo "# updating setting (${NAME}) with value(${VALUE})"
  sudo -u bitcoin sed -i "s/^${NAME}=.*/${NAME}=${VALUE}/g" ${FILE}
}

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
lndConfFile="/mnt/hdd/lnd/${netprefix}lnd.conf"

# check if lnd config file exists
configExists=$(ls ${lndConfFile} | grep -c '.conf')
if [ ${configExists} -eq 0 ]; then
  echo "FAIL - missing ${lndConfFile}"
  exit 1
fi

sectionLine=$(cat ${lndConfFile} | grep -n "^\[Application Options\]" | cut -d ":" -f1)
echo "# sectionLine(${sectionLine})"
insertLine=$(expr $sectionLine + 1)

# lnd.conf: change name
setting ${lndConfFile} ${insertLine} "alias" "${newName}"

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
#  source <(/home/admin/_cache.sh get state)
#  if [ "${state}" == "ready" ]; then
#    sudo systemctl start ${netprefix}lnd
#    # signal 1 to not reboot
#    exit 1
#  fi
#fi

echo
echo "# To activate the new alias:"
echo "# reboot or restart the lnd.service and unlock with:"
echo "'sudo systemctl restart lnd && lncli unlock'"
echo "# Either way it can take hours for the gossip to propagate."
exit 0
