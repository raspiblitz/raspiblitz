#!/bin/bash

# get raspiblitz config
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# Basic Options
OPTIONS=(HARDWARE "Run Hardwaretest" \
         SOFTWARE "Run Softwaretest" \
         BLOCKCHAIN "Redownload Blockchain" \
         CLEANHDD "Delete Data - keep Blockchian"
	)

CHOICE=$(whiptail --clear --title "Repair Options" --menu "" 15 50 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)

clear
case $CHOICE in
  HARDWARE)
    echo "HARDWARE"
    read key
    exit 1;
    ;;
  SOFTWARE)
    echo "SOFTWARE"
    read key
    exit 1;
    ;;
  BLOCKCHAIN)
    echo "BLOCKCHAIN"
    read key
    exit 1;
    ;;
  CLEANHDD)
    echo "CLEANHDD"
    read key
    exit 1;
    ;;
esac
