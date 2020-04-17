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
      echo "PRESS ENTER to continue once you are done downloading."
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

copyHost()
{
  clear
  sed -i "s/^state=.*/state=copysource/g" /home/admin/raspiblitz.info
  sudo systemctl stop lnd
  sudo systemctl stop ${network}d
  cd /mnt/hdd/${network}
  echo
  echo "*** Copy Blockchain Source Modus ***"
  echo "Your RaspiBlitz has now stopped LND and ${network}d ..."
  echo "1. Use command to change to source dir: cd /mnt/hdd/$network"
  echo "2. Then run the script given by the other RaspiBlitz in Terminal"
  echo "3. When you are done - Restart RaspiBlitz: sudo shutdown -r now"
  echo
  exit 99
}

# Basic Options
OPTIONS=(HARDWARE "Run Hardwaretest" \
         SOFTWARE "Run Softwaretest (DebugReport)" \
         BACKUP-LND "Backup your LND data (Rescue-File)" \
         MIGRATION "Migrate Blitz Data to new Hardware" \
         COPY-SOURCE "Copy Blockchain Source Modus" \
         RESET-CHAIN "Delete Blockchain & Re-Download" \
         RESET-LND "Delete LND & start new node/wallet" \
         RESET-HDD "Delete HDD Data but keep Blockchain" \
         RESET-ALL "Delete HDD completly to start fresh"
	)

CHOICE=$(whiptail --clear --title "Repair Options" --menu "" 15 62 8 "${OPTIONS[@]}" 2>&1 >/dev/tty)

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
  BACKUP-LND)
    sudo /home/admin/config.scripts/lnd.rescue.sh backup
    echo
    echo "Press ENTER when your backup download is done to shutdown."
    read key
    /home/admin/XXshutdown.sh
    ;;
  MIGRATION)
    sudo /home/admin/config.scripts/blitz.migration.sh "export-gui"
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

    # make sure host is named like in the raspiblitz config
    echo "Setting the Name/Alias/Hostname .."
    sudo /home/admin/config.scripts/lnd.setname.sh ${result}

    echo "stopping lnd ..."
    sudo systemctl stop lnd
    sudo rm -r /mnt/hdd/lnd
    /home/admin/70initLND.sh

    # go back to main menu (and show)
    /home/admin/00raspiblitz.sh
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
  COPY-SOURCE)
    copyHost
    ;;
esac
