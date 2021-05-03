#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/var/cache/raspiblitz/raspiblitz.setup"
source <($SETUPFILE)

# debug test
echo "setPasswordA(${setPasswordA})"
sleep 4

####################################################
# INPUT PASSWORDS (based on flags from raspiblitz.setup)

# dynamic info string on what passwords need to be changed
passwordinfo="A" # always so far
if [ "${setPasswordB}" == "1" ]; then
  passwordinfo = "${passwordinfo}, B"
fi
if [ "${setPasswordC}" == "1" ]; then
  passwordinfo = "${passwordinfo}, C"
fi

# if passwords are set in a migration situation, use different info text
if [ "${migrationOS}" == "" ]; then

    # info text on normal setup
    dialog --backtitle "RaspiBlitz - Setup" --msgbox "RaspiBlitz uses 3 different passwords.
Referenced as password A, B & C.

PASSWORD A) Main User Password (SSH & WebUI, sudo)
PASSWORD B) APP Password (Additional Apps & API)
PASSWORD C) Lightning Wallet Password for Unlock

You will need to set now Password: ${passwordinfo}

Follow Password Rule: Minimal of 8 chars,,
no spaces and only special characters - or .
Write them down & store them in a safe place.
" 16 54

else

    # info text on migration setup
    dialog --backtitle "RaspiBlitz - Migration Setup" --msgbox "You will need to set new passwords.

RaspiBlitz works with 3 different passwords:
PASSWORD A) Main User Password (SSH & WebUI, sudo)
PASSWORD B) APP Password (Additional Apps & API)
PASSWORD C) Lightning Wallet Password for Unlock

You will need to set now Password: ${passwordinfo}
(other passwords might stay like on your old node)

Follow Password Rules: Minimal of 8 chars,
no spaces and only special characters - or .
Write them down & store them in a safe place.
" 17 64

fi

# temp file for password results
_temp="/var/cache/raspiblitz/.temp.tmp"

# PASSWORD A
if [ "${setPasswordA}" == "1" ]; then
  clear
  sudo /home/admin/config.scripts/blitz.setpassword.sh x "PASSWORD A - Main User Password" $_temp
  password=$(sudo cat $_temp)
  sudo rm $_temp
  echo "passwordA='${password}'" >> $SETUPFILE
  dialog --backtitle "RaspiBlitz - Setup" --msgbox "\n Password A set" 7 20
fi

# PASSWORD B
if [ "${setPasswordB}" == "1" ]; then
  clear
  sudo /home/admin/config.scripts/blitz.setpassword.sh x "PASSWORD B - APP Password" $_temp
  password=$(sudo cat $_temp)
  sudo rm $_temp
  echo "passwordB='${password}'" >> $SETUPFILE
  dialog --backtitle "RaspiBlitz - Setup" --msgbox "\n Password B set" 7 20
fi

# PASSWORD C
if [ "${setPasswordC}" == "1" ]; then
  clear
  sudo /home/admin/config.scripts/blitz.setpassword.sh x "PASSWORD C - Lightning Wallet Password" $_temp
  password=$(sudo cat $_temp)
  sudo rm $_temp
  echo "passwordC='${password}'" >> $SETUPFILE
  dialog --backtitle "RaspiBlitz - Setup" --msgbox "\n Password C set" 7 20
fi

# debug info
clear
echo "# data from dialogs stored in to be further processed:"
echo "${SETUPFILE}"
exit 0
