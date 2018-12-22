#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to autounlock lnd after restart"
 echo "lnd.autounlock.sh [on|off] [?passwordC]"
 exit 1
fi

# 1. parameter [on|off]
turn="off"
if [ "$1" = "1" ] || [ "$1" = "on" ]; then turn="on"; fi

# 2. parameter [?passwordC]
passwordC=$2

# run interactive if 'turn on' && no further parameters
if [ "${turn}" = "on" ] && [ ${#passwordC} -eq 0 ]; then

  dialog --backtitle "LND Auto-Unlock" --inputbox "ENTER your PASSWORD C:

For more details see chapter in GitHub README 
'Auto-unlock LND on startup'
https://github.com/rootzoll/raspiblitz

Password C will be stored on the device.
" 13 52 2>./.tmp
  passwordC=$( cat ./.tmp )
  if [ ${#passwordC} -eq 0 ]; then
    echo "FAIL input cannot be empty"
    exit 1
  fi
  shred ./.tmp
fi

# config file
configFile="/mnt/hdd/raspiblitz.conf"

# lnd conf file
lndConfig="/mnt/hdd/lnd/lnd.conf"

# check if config file exists
configExists=$(ls ${configFile} | grep -c '.conf')
if [ ${configExists} -eq 0 ]; then
 echo "FAIL - missing ${configFile}"
 exit 1
fi

# make sure entry line for 'autoUnlock' exists 
entryExists=$(cat ${configFile} | grep -c 'autoUnlock=')
if [ ${entryExists} -eq 0 ]; then
  echo "autoUnlock=" >> ${configFile}
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check if lnd has REST in config
  restActive=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep -c 'restlisten=0.0.0.0:8080')
  if [ ${restActive} -eq 0 ]; then
    echo "FAIL: /mnt/hdd/lnd/lnd.conf needs to include the line 'restlisten=0.0.0.0:8080'"
    exit 1
  fi

  echo "switching the Auto-Unlock ON"

  # setting value in raspi blitz config
  sudo sed -i "s/^autoUnlock=.*/autoUnlock=on/g" /mnt/hdd/raspiblitz.conf

  # password C needs to be stored on RaspiBlitz
  echo "storing password for root in /root/lnd.autounlock.pwd"
  sudo sh -c "echo \"${passwordC}\" > /root/lnd.autounlock.pwd"

  echo "Auto-Unlock is now ON"
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "switching the Auto-Unlock OFF"

  # setting value in raspi blitz config
  sudo sed -i "s/^autoUnlock=.*/autoUnlock=off/g" /mnt/hdd/raspiblitz.conf

  # delete password C securly
  echo "shredding password on RaspiBlitz"
  sudo shred -u /root/lnd.autounlock.pwd

  echo "Auto-Unlock is now OFF"
fi