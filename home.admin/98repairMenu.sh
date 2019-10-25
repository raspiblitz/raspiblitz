#!/bin/bash

# get raspiblitz config
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

askBackupCopy()
{
    whiptail --title "LND Data Backup" --yes-button "Backup" --no-button "Skip" --yesno "
Before deleting your data, do you want
to make a backup of all your LND Data
and download that file to your laptop?

Download LND Data Backup now?
      " 12 44
    if [ $? -eq 0 ]; then
      clear
      echo "*************************************"
      echo "* PREPARING LND BACKUP DOWNLOAD"
      echo "*************************************"
      echo "please wait .."
      sleep 2
      /home/admin/config.scripts/lnd.rescue.sh backup
      echo
      echo "PRESS ENTER to continue once your done downloading."
      read key
    else
      clear
      echo "*************************************"
      echo "* JUST MAKING BACKUP TO SD CARD"
      echo "*************************************"
      echo "please wait .."
      sleep 2
      /home/admin/config.scripts/lnd.rescue.sh backup no-download
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

# Basic Options
OPTIONS=(HARDWARE "Run Hardwaretest" \
         SOFTWARE "Run Softwaretest (DebugReport)" \
         BACKUP "Backup your LND data (Rescue-File)" \
         RESET-CHAIN "Delete Blockchain & Re-Download" \
         RESET-LND "Delete LND & start new node/wallet" \
         RESET-HDD "Delete HDD Data but keep Blockchain" \
         RESET-ALL "Delete HDD completly to start fresh"
	)

CHOICE=$(whiptail --clear --title "Repair Options" --menu "" 12 62 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)

clear
case $CHOICE in
  HARDWARE)
    sudo /home/admin/05hardwareTest.sh
    /home/admin/00mainMenu.sh
    ;;
  SOFTWARE)
    sudo /home/admin/XXdebugLogs.sh
    echo "Press ENTER to return to main menu."
    read key
    /home/admin/00mainMenu.sh
    ;;
  BACKUP)
    sudo /home/admin/config.scripts/lnd.rescue.sh backup
    echo "Press ENTER to return to main menu."
    read key
    /home/admin/00mainMenu.sh
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
        _temp="/home/admin/download/dialog.$$"
        l1="Please enter the new name of your LND node:\n"
        l2="different name is better for a fresh identity\n"
        l3="one word, keep characters basic & not too long"
        dialog --backtitle "RaspiBlitz - Setup (${network}/${chain})" --inputbox "$l1$l2$l3" 13 52 2>$_temp
        result=$( cat $_temp | tr -dc '[:alnum:]-.' | tr -d ' ' )
        shred $_temp
        echo "processing ..."
        sleep 3
    done
    # prepare new name
    sudo sed -i "s/^alias=.*/alias=${result}/g" /home/admin/assets/lnd.${network}.conf
    sudo sed -i "s/^hostname=.*/hostname=${result}/g" /mnt/hdd/raspiblitz.conf

    sudo systemctl stop lnd
    sudo rm -r /mnt/hdd/lnd
    /home/admin/70initLND.sh

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
esac
