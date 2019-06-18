#!/bin/bash

# get raspiblitz config
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# Basic Options
OPTIONS=(HARDWARE "Run Hardwaretest" \
         SOFTWARE "Run Softwaretest (DebugReport)" \
         BLOCKCHAIN "Delete Blockchain & Re-Download" \
         CLEANHDD "Delete Data - keep Blockchain"
	)

CHOICE=$(whiptail --clear --title "Repair Options" --menu "" 12 60 5 "${OPTIONS[@]}" 2>&1 >/dev/tty)

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
  BLOCKCHAIN)
    /home/admin/XXcleanHDD.sh -blockchain
    exit 1;
    ;;
  CLEANHDD)
  
    whiptail --title "LND Data Backup" --yes-button "Download Backup" --no-button "Skip" --yesno "
Before deleting your data on HDD, do you
want to make a backup of all your LND Data
and download that file to your laptop.

Do you want to download LND Data Backup now?
      " 12 58
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
      echo "* JUST MAKING BACKUP TO OLD SD CARD"
      echo "*************************************"
      echo "please wait .."
      sleep 2
      /home/admin/config.scripts/lnd.rescue.sh backup no-download
    fi

    /home/admin/XXcleanHDD.sh
    exit 1;
    ;;
esac
