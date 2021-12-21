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
      echo "*****************************************"
      echo "* JUST MAKING A BACKUP TO THE OLD SD CARD"
      echo "*****************************************"
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
  OPTIONS+=(BACKUP-LND "Backup your LND data (Rescue-File)")
  OPTIONS+=(RESET-LND "Delete LND & start new node/wallet")
  OPTIONS+=(COMPACT "Compact the LND channel.db")
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
  BACKUP-LND)
    /home/admin/config.scripts/lnd.compact.sh interactive
    sudo /home/admin/config.scripts/lnd.backup.sh lnd-export-gui
    echo
    echo "Press ENTER when your backup download is done to shutdown."
    read key
    /home/admin/config.scripts/blitz.shutdown.sh
    ;;
  COMPACT)
    /home/admin/config.scripts/lnd.compact.sh interactive
    echo "# Starting lnd.service ..."
    sudo systemctl start lnd
    echo
    echo "Press ENTER to return to main menu."
    read key
    ;;
  REPAIR-CL)
    sudo /home/admin/99clRepairMenu.sh
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
  RESET-LND)
    askBackupCopy
    # ask for a new name so that network analysis has harder time to connect new node id with old
    result=""
    while [ ${#result} -eq 0 ]
    do
        trap 'rm -f "$_temp"' EXIT
        _temp=$(mktemp -p /dev/shm/)
        l1="Please enter the new name of your LND node:\n"
        l2="different name is better for a fresh identity\n"
        l3="one word, keep characters basic & not too long"
        dialog --backtitle "RaspiBlitz - Setup (${network}/${chain})" --inputbox "$l1$l2$l3" 13 52 2>$_temp
        result=$( cat $_temp | tr -dc '[:alnum:]-.' | tr -d ' ' )
        echo "processing ..."
        sleep 3
    done

    # make sure host is named like in the raspiblitz config
    echo "Setting the Name/Alias/Hostname .."
    sudo /home/admin/config.scripts/lnd.setname.sh mainnet ${result}
    /home/admin/config.scripts/blitz.conf.sh set hostname "${result}"

    echo "stopping lnd ..."
    sudo systemctl stop lnd
    sudo rm -r /mnt/hdd/lnd
    # create wallet
    /home/admin/config.scripts/lnd.install.sh on mainnet initwallet
    # display and delete the seed for mainnet
    sudo /home/admin/config.scripts/lnd.install.sh display-seed mainnet delete
    if [ "${tlnd}" == "on" ];then
      /home/admin/config.scripts/lnd.install.sh on testnet initwallet
    fi
    if [ "${slnd}" == "on" ];then
      /home/admin/config.scripts/lnd.install.sh on signet initwallet
    fi
    # go back to main menu (and show)
    /home/admin/00raspiblitz.sh
    exit 0;
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
