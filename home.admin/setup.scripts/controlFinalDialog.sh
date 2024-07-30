#!/bin/bash

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info

# SETUPFILE
# this key/value file contains the state during the setup process
source /var/cache/raspiblitz/temp/raspiblitz.setup

# make sure also admin user can write to log
sudo chmod 777 /home/admin/raspiblitz.log

############################################
# SHOW SEED WORDS AFTER SETUP
if [ "${lightning}" == "lnd" ]; then
  walletName="LND"
elif [ "${lightning}" == "cl" ]; then
  walletName="Core Lightning"
fi
if [ "${setupPhase}" == "setup" ] && [ "${seedwords6x4NEW}" != "" ]; then
    ack=0
    while [ ${ack} -eq 0 ]
    do
      whiptail --title "IMPORTANT SEED WORDS - PLEASE WRITE DOWN" \
        --msgbox "Created the ${walletName} wallet.\nStore these numbered words in a safe location:\n\n${seedwords6x4NEW}" 13 76
      whiptail --title "Please Confirm" --yes-button "Show Again" --no-button "CONTINUE" --yesno "  Are you sure that you wrote down the word list?" 8 55
      if [ $? -eq 1 ]; then
        ack=1
      fi
    done
fi

############################################
# BLOCKCHAIN INFO & OPTIONS

# get fresh data
source <(/home/admin/_cache.sh get btc_default_sync_percentage btc_default_blocks_data_kb network)
#syncProgressFull=$(echo "${btc_default_sync_percentage}" | cut -d "." -f1)
#if [ "${syncProgressFull}" != "" ] && [ "${network}" == "bitcoin" ] && [ ${syncProgressFull} -lt 75 ]; then
if [ "${btc_default_blocks_data_kb}" != "" ] && [ ${btc_default_blocks_data_kb} -lt 250000000 ]; then

  # offer choice to copy blockchain over LAN
  OPTIONS=()
  OPTIONS+=(SELFSYNC "Run full self sync/validation (takes long)")
  OPTIONS+=(COPY "Copy from Computer/RaspiBlitz over LAN (3-10h)")
  OPTIONS+=(TESTNET "Sync smaller Testnet (ONLY DEVELOPER)")
  CHOICESUB=$(dialog --backtitle "RaspiBlitz" --clear --title " Blockchain Sync/Validation " --menu "\nYour Blockchain is not fully synced yet.\nThe full validation might take multiple days to finish.\n\nHow do you want to proceed:" 13 66 7 "${OPTIONS[@]}" 2>&1 >/dev/tty)

  if [ "${CHOICESUB}" == "COPY" ]; then
    /home/admin/config.scripts/blitz.copychain.sh target
  fi

  if [ "${CHOICESUB}" == "TESTNET" ]; then
    sudo /home/admin/config.scripts/bitcoin.testnet.sh activate
  fi

fi

############################################
# SETUP DONE CONFIRMATION (Konfetti Moment)

# when coming from fresh setup
if [ "${setupPhase}" == "setup" ]; then
  clear
  whiptail --title " Setup Done " --msgbox "\
Your RaspiBlitz setup is done. Welcome new Node Operator! :D\n
After the final reboot there can be some waiting time until your blockchain is fully synced before you can enter the RaspiBlitz user menu.\n
It is safe to log out during the sync and return later.\n
" 13 65

# when coming from migration from other node
elif [ "${setupPhase}" == "migration" ]; then
  clear
  whiptail --title " Migration Done " --msgbox "\
Your running now RaspiBlitz. Welcome to the family! :D\n
After the final reboot there might now be some waiting time until your Blockchain is fully synced before you can enter the RaspiBlitz user menu.\n
Its safe to logout during sync and return later.\n
" 13 65

# just in case then from another phase
else
  clear
  whiptail --title " Recovery/Update Done " --msgbox "\
Your RaspiBlitz is now ready again :D\n
After the final reboot there might now be some waiting time until your Blockchain sync has catched up before you can enter the RaspiBlitz user menu.\n
" 11 65
fi

# trigger after final setup tasks & reboot
/home/admin/_cache.sh set state "donefinal"

sleep 2
clear
echo "***********************************************************"
echo "RaspiBlitz is about to reboot"
echo "***********************************************************"
echo "This is the final setup reboot - you will get disconnected."
echo "Connect via SSH again after the restart."
echo "Use your password A"
echo "***********************************************************"
sleep 5
echo "When green activity light stays dark and LCD turns white then shutdown is complete."
sleep 10
echo "Please wait for shutdown ..."
sleep 120
echo "FAIL: automatic final reboot didnt worked .. please report to dev team and try to reboot manually"
exit 0