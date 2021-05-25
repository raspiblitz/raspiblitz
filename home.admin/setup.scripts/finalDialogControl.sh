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
      whiptail --title "IMPORTANT SEED WORDS - PLEASE WRITE DOWN" --msgbox "LND Wallet got created. Store these numbered words in a safe location:\n\n${seedwords6x4}" 12 76
      whiptail --title "Please Confirm" --yes-button "Show Again" --no-button "CONTINUE" --yesno "  Are you sure that you wrote down the word list?" 8 55
      if [ $? -eq 1 ]; then
        ack=1
      fi
    done
fi

############################################
# SETUP DONE CONFIRMATION (Konfetti Moment)

# when coming from fresh setup
if [ "${setupPhase}" == "setup" ]; 
  clear
  echo "Hooray :) Everything is Setup!"
  echo "PRESS ENTER"
  read key2

# when coming from migration from other node
elif [ "${setupPhase}" == "migration" ]; then
  clear
  echo "Hooray :) Your Migration to RaspiBlitz is Done!"
  echo "PRESS ENTER"
  read key2

# just in case then from another phase
else
  clear
  echo "Missing Final Done Dialog for: ${setupPhase}"
  echo "PRESS ENTER"
  read key2
fi

sleep 2