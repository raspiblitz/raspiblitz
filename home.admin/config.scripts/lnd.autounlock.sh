#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# small config script to autounlock lnd after restart"
 echo "# lnd.autounlock.sh [on|off] [?passwordC]"
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
 
  wasCancel=$( echo $? )
  passwordC=$( cat ./.tmp )
  
  if [ ${wasCancel} -eq 1 ]; then
    echo "# CANCEL LND Auto-Unlock"
    sleep 2
    exit 1
  fi
  if [ ${#passwordC} -eq 0 ]; then
    echo "# input cannot be empty - repeat"
    sleep 3
    sudo /home/admin/config.scripts/lnd.autounlock.sh on
    exit $?
  fi

  # test if correct
  echo "# testing password .. please wait"
  echo "SYSTEMD RESTART LOG: lightning (LND)" > /home/admin/systemd.lightning.log
  sudo systemctl restart lnd
  sleep 4
  error=""
  source <(sudo /home/admin/config.scripts/lnd.unlock.sh unlock "$passwordC")
  if [ "${error}" != "" ];then
    echo "# PASSWORD C is wrong - try again or cancel"
    sleep 3
    sudo /home/admin/config.scripts/lnd.autounlock.sh on
    exit $?
  fi
  shred -u ./.tmp
fi

# lnd conf file
lndConfig="/mnt/hdd/lnd/lnd.conf"

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "# switching the Auto-Unlock ON"

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set autoUnlock "on"

  # password C needs to be stored on RaspiBlitz
  echo "# storing password for root in /root/lnd.autounlock.pwd"
  sudo sh -c "echo \"${passwordC}\" > /root/lnd.autounlock.pwd"
  sudo chmod 660 /root/lnd.autounlock.pwd
  sudo chown root:sudo /root/lnd.autounlock.pwd

  echo "# Auto-Unlock is now ON"
  echo "# NOTE: you may need to reconnect mobile/external wallets (macaroon/tls)"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# switching the Auto-Unlock OFF"

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set autoUnlock "off"

  # delete password C securely
  echo "# shredding password on for RaspiBlitz Auto-Unlock"
  sudo shred -u /root/lnd.autounlock.pwd 2>/dev/null

  echo "# Auto-Unlock is now OFF"
  exit 0
fi
