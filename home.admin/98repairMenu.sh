#!/bin/bash

# get raspiblitz config
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# Basic Options
OPTIONS=(HARDWARE "Run Hardwaretest" \
         SOFTWARE "Run Softwaretest (DebugReport)" \
         BLOCKCHAIN "Redownload Blockchain" \
         CLEANHDD "Delete Data - keep Blockchain"
	)

CHOICE=$(whiptail --clear --title "Repair Options" --menu "" 12 60 5 "${OPTIONS[@]}" 2>&1 >/dev/tty)

clear
case $CHOICE in
  HARDWARE)
    sudo ./05hardwareTest.sh
    ./00mainMenu.sh
    ;;
  SOFTWARE)
    sudo ./XXdebugLogs.sh
    echo "Press ENTER to return to main menu."
    read key
    ./00mainMenu.sh
    ;;
  BLOCKCHAIN)
    ./XXcleanHDD.sh --blockchain
    exit 1;
    ;;
  CLEANHDD)
    ./XXcleanHDD.sh
    exit 1;
    ;;
esac
