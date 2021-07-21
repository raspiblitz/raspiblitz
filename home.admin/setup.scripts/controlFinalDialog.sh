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
if [ "${lightning}" == "lnd" ]; then
  walletName="LND Wallet"
elif [ "${lightning}" == "cln" ]; then
  walletName="C-lightning Wallet"
fi
if [ "${setupPhase}" == "setup" ] && [ "${seedwords6x4NEW}" != "" ]; then
    ack=0
    while [ ${ack} -eq 0 ]
    do
      whiptail --title "IMPORTANT SEED WORDS - PLEASE WRITE DOWN" --msgbox "${walletName} got created. Store these numbered words in a safe location:\n\n${seedwords6x4NEW}" 12 76
      whiptail --title "Please Confirm" --yes-button "Show Again" --no-button "CONTINUE" --yesno "  Are you sure that you wrote down the word list?" 8 55
      if [ $? -eq 1 ]; then
        ack=1
      fi
    done
fi

############################################
# BLOCKCHAIN INFO & OPTIONS

# get fresh data
source <(sudo /home/admin/config.scripts/blitz.statusscan.sh)
syncProgressFull=$(echo "${syncProgress}" | cut -d "." -f1)
if [ "${syncProgressFull}" != "" ] && [ "${network}" == "bitcoin" ] && [ ${syncProgressFull} -lt 75 ]; then

  # offer choice to copy blockchain over LAN
  OPTIONS=()
  OPTIONS+=(SELFSYNC "Run full self sync/validation (takes long)")
  OPTIONS+=(COPY "Copy from Computer/RaspiBlitz over LAN (±6h)")
  CHOICESUB=$(dialog --backtitle "RaspiBlitz" --clear --title " Blockchain Sync/Validation " --menu "\nYour Blockchain sync is just at ${syncProgress}%\nThe full validation might take multiple days to finish.\n\nHow do you want to proceed:" 13 63 7 "${OPTIONS[@]}" 2>&1 >/dev/tty)

  if [ "${CHOICESUB}" == "COPY" ]; then
    /home/admin/config.scripts/blitz.copychain.sh target
  fi

fi

############# SCB activation

# check if there is a channel.backup to activate
gotSCB=$(ls /home/admin/channel.backup 2>/dev/null | grep -c 'channel.backup')
if [ "${gotSCB}" == "1" ]; then

  echo "*** channel.backup Recovery ***"
  lncli --chain=${network} restorechanbackup --multi_file=/home/admin/channel.backup 2>/home/admin/.error.tmp
  error=`cat /home/admin/.error.tmp`
  rm /home/admin/.error.tmp 2>/dev/null

  if [ ${#error} -gt 0 ]; then

    # output error message
    echo ""
    echo "!!! FAIL !!! SOMETHING WENT WRONG:"
    echo "${error}"

    # check if its possible to give background info on the error
    notMachtingSeed=$(echo $error | grep -c 'unable to unpack chan backup')
    if [ ${notMachtingSeed} -gt 0 ]; then
      echo "--> ERROR BACKGROUND:"
      echo "The WORD SEED is not matching the channel.backup file."
      echo "Either there was an error in the word seed list or"
      echo "or the channel.backup file is from another RaspiBlitz."
      echo 
    fi

    # basic info on error
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo 
    echo "You can try after full setup to restore channel.backup file again with:"
    echo "lncli --chain=${network} restorechanbackup --multi_file=/home/admin/channel.backup"
    echo
    echo "Press ENTER to continue for now ..."
    read key
  else
    mv /home/admin/channel.backup /home/admin/channel.backup.done
    dialog --title " OK channel.backup IMPORT " --msgbox "
LND accepted the channel.backup file you uploaded. 
It will now take around a hour until you can see,
if LND was able to recover funds from your channels.
    " 9 56
  fi
  
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

echo "Starting ... (please wait)"

# signal to backend that all is good and it can continue
sudo sed -i "s/^state=.*/state='ready'/g" /home/admin/raspiblitz.info 