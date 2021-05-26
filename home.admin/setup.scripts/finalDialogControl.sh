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
if [ "${setupPhase}" == "setup" ]; then
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

if [ ${syncProgress} -lt 99 ]; then
  clear
  echo "Your Blockchain is at ${syncProgress}% - this might take multiple days to validate."
  echo "TODO: Option COPY OVER LAN IF BITCOIN"
  echo "TODO: MAKE SURE THAT background.service is running from beginng!"
  echo "PRESS ENTER"
  read key
fi

############################################
# SETUP DONE CONFIRMATION (Konfetti Moment)

# when coming from fresh setup
if [ "${setupPhase}" == "setup" ]; then
  clear
  echo "Hooray :) Everything is Setup!"
  echo "PRESS ENTER"
  read key

# when coming from migration from other node
elif [ "${setupPhase}" == "migration" ]; then
  clear
  echo "Hooray :) Your Migration to RaspiBlitz is Done!"
  echo "PRESS ENTER"
  read key

# just in case then from another phase
else
  clear
  echo "Missing Final Done Dialog for: ${setupPhase}"
  echo "PRESS ENTER"
  read key
fi

# signal to backend that all is good and it can continue
sudo sed -i "s/^state=.*/state='finalready'/g" /home/admin/raspiblitz.info 