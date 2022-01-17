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
        echo "*******************************************"
        echo "* PREPARING THE C-LIGHTNING BACKUP DOWNLOAD"
        echo "*******************************************"
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

OPTIONS=()
#OPTIONS+=(HARDWARE "Run Hardwaretest")
OPTIONS+=(SOFTWARE "Run Softwaretest (DebugReport)")
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
  OPTIONS+=(REPAIR-LND "Repair/Backup LND")
fi
if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ]; then
  OPTIONS+=(REPAIR-CL "Repair/Backup C-Lightning")
fi
OPTIONS+=(MIGRATION "Migrate Blitz Data to new Hardware")
OPTIONS+=(COPY-SOURCE "Copy Blockchain Source Modus")
OPTIONS+=(RESET-CHAIN "Delete Blockchain & Re-Download")
OPTIONS+=(RESET-HDD "Delete HDD Data but keep Blockchain")
OPTIONS+=(RESET-ALL "Delete HDD completely to start fresh")
OPTIONS+=(DELETE-ELEC "Delete Electrum Index")
OPTIONS+=(DELETE-INDEX "Delete Bitcoin Transaction-Index")

CHOICE=$(whiptail --clear --title "Repair Options" --menu "" 19 62 12 "${OPTIONS[@]}" 2>&1 >/dev/tty)

clear
case $CHOICE in
#  HARDWARE)
#    ;;
  SOFTWARE)
    sudo /home/admin/config.scripts/blitz.debug.sh
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
  COPY-SOURCE)
    /home/admin/config.scripts/blitz.copychain.sh source
    /home/admin/config.scripts/lnd.unlock.sh
    ;;
esac

exit 0