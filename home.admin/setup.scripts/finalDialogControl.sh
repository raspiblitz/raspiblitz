#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

# SETUPFILE
# this key/value file contains the state during the setup process
SETUPFILE="/var/cache/raspiblitz/temp/raspiblitz.setup"
source ${SETUPFILE}

############################################
# SHOW SEED WORDS AFTER SETUP
if [ "${setupPhase}" == "setup" ] && [ "${seedwords6x4NEW}" != "" ]; then
    ack=0
    while [ ${ack} -eq 0 ]
    do
      whiptail --title "IMPORTANT SEED WORDS - PLEASE WRITE DOWN" --msgbox "LND Wallet got created. Store these numbered words in a safe location:\n\n${seedwords6x4NEW}" 12 76
      whiptail --title "Please Confirm" --yes-button "Show Again" --no-button "CONTINUE" --yesno "  Are you sure that you wrote down the word list?" 8 55
      if [ $? -eq 1 ]; then
        ack=1
      fi
    done
fi

############################################
# BLOCKCHAIN INFO & OPTIONS

if [ ${syncProgress} -lt 99 ] && [ "${network}" == "bitcoin" ]; then
  clear

  # offer choice to copy blockchain over LAN
  OPTIONS=()
  OPTIONS+=(VALIDATE "Run full self sync/validation (takes long)")
  OPTIONS+=(COPY "Copy from Computer/RaspiBlitz over LAN (~6h)")
  CHOICESUB=$(dialog --backtitle "RaspiBlitz" --clear --title " Blockchain Sync/Validation " --menu "\nYour Blockchain sync is just at ${syncProgress}%\nThe full validation might take multiple days to finish.\n\nHow do you want to proceed:" 13 63 7 "${OPTIONS[@]}" 2>&1 >/dev/tty)

  echo "CHOICESUB: ${CHOICESUB}"
  read key
fi

############################################
# SETUP DONE CONFIRMATION (Konfetti Moment)

# when coming from fresh setup
if [ "${setupPhase}" == "setup" ]; then
  clear
  whiptail --title " SetUp Done " --msgbox "\
Your RaspiBlitz Setup is done. Welcome new node operator! :D\n
There might now be some waiting time until your Blockchain is fully synced before you can enter the RaspiBlitz user menu.\n
Its safe to logout during sync and return later.\n
" 12 65

# when coming from migration from other node
elif [ "${setupPhase}" == "migration" ]; then
  clear
  whiptail --title " Migration Done " --msgbox "\
Your running now RaspiBlitz. Welcome to the family! :D\n
There might now be some waiting time until your Blockchain is fully synced before you can enter the RaspiBlitz user menu.\n
Its safe to logout during sync and return later.\n
" 12 65

# just in case then from another phase
else
  clear
  echo "Missing Final Done Dialog for: ${setupPhase}"
  echo "PRESS ENTER"
  read key
fi

echo "Starting ..."

# signal to backend that all is good and it can continue
sudo sed -i "s/^state=.*/state='finalready'/g" /home/admin/raspiblitz.info 