#!/bin/bash

# get raspiblitz config
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

askBackupCopy()
{
    whiptail --title "Lightning Data Backup" --yes-button "Backup" --no-button "Skip" --yesno "
Before deleting your data, do you want
to make a backup of all your Lightning Data
and download the file(s) to your laptop?

Download Lightning Data Backup now?
      " 12 44
    if [ $? -eq 0 ]; then
      if [ "${lightning}" == "lnd" ] || [ "${lnd}" = "on" ]; then
        clear
        echo "***********************************"
        echo "* PREPARING THE LND BACKUP DOWNLOAD"
        echo "***********************************"
        echo "please wait .."
        /home/admin/config.scripts/lnd.compact.sh interactive
        /home/admin/config.scripts/lnd.backup.sh lnd-export-gui
        echo
        echo "PRESS ENTER to continue once you're done downloading."
        read key
      fi
      if [ "${lightning}" == "cl" ] || [ "${cl}" = "on" ]; then
        clear
        echo "**********************************************"
        echo "* PREPARING THE CORE LIGHTNING BACKUP DOWNLOAD"
        echo "**********************************************"
        echo "please wait .."
        /home/admin/config.scripts/cl.backup.sh cl-export-gui
        echo
        echo "PRESS ENTER to continue once you're done downloading."
        read key
      fi
    else
      clear
      echo "*************************************"
      echo "* JUST MAKING A BACKUP TO THE SD CARD"
      echo "*************************************"
      echo "please wait .."
      sleep 2
      if [ "${lightning}" == "lnd" ] || [ "${lnd}" = "on" ]; then
        /home/admin/config.scripts/lnd.backup.sh lnd-export
      fi
      if [ "${lightning}" == "cl" ] || [ "${cl}" = "on" ]; then
        /home/admin/config.scripts/cl.backup.sh cl-export
      fi
      sleep 3
    fi
}

infoResetSDCard()
{
    whiptail --title "RESET DONE" --msgbox "
OK Reset of HDD is done.
System will now shutdown.

To start fresh please write a fresh 
RaspiBlitz image to your SD card.
" 12 40
}

# get status of txindex
source <(sudo /home/admin/config.scripts/network.txindex.sh status)

OPTIONS=()
#OPTIONS+=(HARDWARE "Run Hardwaretest")
OPTIONS+=(SOFTWARE "Run Softwaretest (DebugReport)")
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
  OPTIONS+=(REPAIR-LND "Repair/Backup LND")
fi
if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ]; then
  OPTIONS+=(REPAIR-CL "Repair/Backup Core Lightning")
fi
OPTIONS+=(MIGRATION "Migrate Blitz Data to new Hardware")
OPTIONS+=(COPY-SOURCE "Copy Blockchain Source Modus")
if [ "${txindex}" == "1" ]; then
  OPTIONS+=(DELETE-INDEX "Reindex Bitcoin Transaction-Index")
elif [ "${indexByteSize}" != "0" ]; then
  OPTIONS+=(DELETE-INDEX "Delete Bitcoin Transaction-Index")
fi
OPTIONS+=(REINDEX-UTXO "Redindex Just Bitcoin Chainstate (Fast)")
OPTIONS+=(REINDEX-FULL "Redindex Full Bitcoin Blockchain (Slow)")
OPTIONS+=(RESET-CHAIN "Delete Blockchain & Re-Download")
OPTIONS+=(RESET-HDD "Delete HDD Data but keep Blockchain")
OPTIONS+=(RESET-ALL "Delete HDD completely to start fresh")
OPTIONS+=(DELETE-ELEC "Delete Electrum Index")

CHOICE=$(whiptail --clear --title "Repair Options" --menu "" 19 62 12 "${OPTIONS[@]}" 2>&1 >/dev/tty)

clear
case $CHOICE in
#  HARDWARE)
#    ;;
  SOFTWARE)
    echo "Generating debug logs. Be patient, this should take maximum 2 minutes .."
    sudo rm /var/cache/raspiblitz/debug.log 2>/dev/null
    /home/admin/config.scripts/blitz.debug.sh > /var/cache/raspiblitz/debug.log
    echo "Redacting .."
    /home/admin/config.scripts/blitz.debug.sh redact /var/cache/raspiblitz/debug.log
    sudo chmod 640 /var/cache/raspiblitz/debug.log
    sudo chown root:sudo /var/cache/raspiblitz/debug.log
    cat /var/cache/raspiblitz/debug.log
    echo
    echo "Press ENTER to return to main menu."
    read key
    ;;
  REPAIR-LND)
    /home/admin/99lndRepairMenu.sh
    echo
    echo "Press ENTER to return to main menu."
    read key
    ;;
  REPAIR-CL)
    /home/admin/99clRepairMenu.sh
    echo
    echo "Press ENTER to return to main menu."
    read key
    ;;
  MIGRATION)
    if [ "${cl}" == "on" ] || [ "${cl}" == "1" ] && [ "${clEncryptedHSM}" != "on" ] ; then
      dialog \
       --title "Encrypt the Core Lightning wallet" \
       --msgbox "\nWill proceed to encrypt and lock the Core Lightning wallet to prevent it from starting automatically after the backup" 9 55
      sudo /home/admin/config.scripts/cl.hsmtool.sh encrypt mainnet
    fi
    if [ "${clAutoUnlock}" = "on" ]; then
      /home/admin/config.scripts/cl.hsmtool.sh autounlock-off mainnet
    fi
    /home/admin/config.scripts/cl.hsmtool.sh lock mainnet
    sudo /home/admin/config.scripts/blitz.migration.sh "export-gui"
    echo "Press ENTER to return to main menu."
    read key
    ;;
  RESET-CHAIN)
    /home/admin/XXcleanHDD.sh -blockchain
    /home/admin/98repairBlockchain.sh
    echo "For reboot type: sudo shutdown -r now"
    exit 1;
    ;;
  RESET-HDD)
    askBackupCopy
    /home/admin/XXcleanHDD.sh
    infoResetSDCard
    sudo shutdown now
    exit 1;
    ;;
  RESET-ALL)
    askBackupCopy
    /home/admin/XXcleanHDD.sh -all
    infoResetSDCard
    sudo shutdown now
    exit 1;
    ;;
  DELETE-ELEC)
    /home/admin/config.scripts/bonus.electrs.sh off deleteindex
    exit 0;
    ;;
  DELETE-INDEX)
    /home/admin/config.scripts/network.txindex.sh delete
    exit 0;
    ;;
  REINDEX-UTXO)
    /home/admin/config.scripts/network.reindex.sh reindex-chainstate mainnet
    exit 0;
    ;;
  REINDEX-FULL)
    /home/admin/config.scripts/network.reindex.sh reindex mainnet
    exit 0;
    ;;
  COPY-SOURCE)
    /home/admin/config.scripts/blitz.copychain.sh source
    ;;
esac

exit 0