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
  echo
  echo "# *** Copy Blockchain Source Modus ***"

  echo "# get IP of RaspiBlitz to copy to ..."
  targetIP=$(whiptail --inputbox "\nPlease enter the LOCAL IP of the\nRaspiBlitz to copy Blockchain to:" 10 38 "" --title " Target IP " --backtitle "RaspiBlitz - Copy Blockchain" 3>&1 1>&2 2>&3)
  targetIP=$(echo "${targetIP[0]}")
  localIP=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0|veth' | grep 'eth0\|wlan0\|enp0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  if [ ${#targetIP} -eq 0 ]; then
    return
  fi
  if [ "${localIP}" == "${targetIP}" ]; then
    whiptail --msgbox "Dont type in the local IP of this RaspiBlitz,\nthe LOCAL IP of the other RaspiBlitz is needed." 8 54 "" --title " Testing Target IP " --backtitle "RaspiBlitz - Copy Blockchain"
    return
  fi
  canPingIP=$(ping ${targetIP} -c 1 | grep -c "1 received")
  if [ ${canPingIP} -eq 0 ]; then
    whiptail --msgbox "Was not able to contact/ping: ${targetIP}\n\n- check if IP of target RaspiBlitz is correct.\n- check to be on the same local network.\n- try again ..." 11 58 "" --title " Testing Target IP " --backtitle "RaspiBlitz - Copy Blockchain"
    return
  fi
  
  echo "# get Password of RaspiBlitz to copy to ..."
  targetPassword=$(whiptail --passwordbox "\nPlease enter the PASSWORD A of the\nRaspiBlitz to copy Blockchain to:" 10 38 "" --title "Target Password" --backtitle "RaspiBlitz - Copy Blockchain" 3>&1 1>&2 2>&3)
  if [ ${#targetPassword} -eq 0 ]; then
    return
  fi

  sudo rm /root/.ssh/known_hosts 2>/dev/null
  canLogin=$(sudo sshpass -p "${targetPassword}" ssh -t -o StrictHostKeyChecking=no bitcoin@${targetIP} "echo 'working'" 2>/dev/null | grep -c 'working')
  if [ ${canLogin} -eq 0 ]; then
    whiptail --msgbox "Password was not working for IP: ${targetIP}\n\n- check thats the correct IP for correct RaspiBlitz\n- check that you used PASSWORD A and had no typo\n- If you tried too often, wait 1h try again" 11 58 "" --title " Testing Target Password " --backtitle "RaspiBlitz - Copy Blockchain"
    return
  fi

  echo "# stopping services ..."
  sudo systemctl stop background
  sudo systemctl stop lnd
  sudo systemctl stop ${network}d
  sudo systemctl disable ${network}d
  sleep 5
  sudo systemctl stop bitcoind 2>/dev/null
  
  clear
  echo
  echo "# Starting copy over LAN (around 4-6 hours) ..."
  sed -i "s/^state=.*/state=copysource/g" /home/admin/raspiblitz.info
  cd /mnt/hdd/${network}

  # transfere beginning flag
  date +%s > /home/admin/copy_begin.time
  sudo sshpass -p "${targetPassword}" rsync -avhW -e 'ssh -o StrictHostKeyChecking=no -p 22' /home/admin/copy_begin.time bitcoin@${targetIP}:/mnt/hdd/bitcoin
  sudo rm -f /home/admin/copy_begin.time

  # repeat the syncing of directories until
  # a) there are no files left to transfere (be robust against failing connections, etc)
  # b) the user hits a key to break loop after report


  while :
    do

      # transfere blockchain data
      rm -f ./transferred.rsync
      sudo sshpass -p "${targetPassword}" rsync -avhW -e 'ssh -o StrictHostKeyChecking=no -p 22' --info=progress2 --log-file=./transferred.rsync ./chainstate ./blocks bitcoin@${targetIP}:/mnt/hdd/bitcoin

      # check result
      # the idea is even after successfull transfer the loop will run a second time
      # but on the second time there will be no files transfered (log lines are below 4)
      # thats the signal that its done
      linesInLogFile=$(wc -l ./transferred.rsync | cut -d " " -f 1) 
      if [ ${linesInLogFile} -lt 4 ]; then
        echo ""
        echo "OK all files transfered. DONE"
        sleep 2
        break
      fi

      # wait 20 seconds for user exiting loop
      echo ""
      echo -en "OK on sync loop done ... will test in another if all was transferred."
      echo -en "PRESS X TO MANUALLY FINISH SYNCING"
      read -n 1 -t 6 keyPressed
      if [ "${keyPressed}" = "x" ]; then
        echo ""
        echo "Ending Sync ..."
        sleep 2
        break
      fi

    done
  
  # transfere end flag
  sed -i "s/^state=.*/state=/g" /home/admin/raspiblitz.info
  date +%s > /home/admin/copy_end.time
  sudo sshpass -p "${targetPassword}" rsync -avhW -e 'ssh -o StrictHostKeyChecking=no -p 22' /home/admin/copy_end.time bitcoin@${targetIP}:/mnt/hdd/bitcoin
  sudo rm -f /home/admin/copy_end.time

  echo "# start services again ..."
  sudo systemctl enable ${network}d
  sudo systemctl start ${network}d
  sudo systemctl start lnd
  sudo systemctl start background

  echo "# show final message"
  whiptail --msgbox "OK - Copy Process Finished.\n\nNow check on the target RaspiBlitz if it was sucessful." 10 40 "" --title " DONE " --backtitle "RaspiBlitz - Copy Blockchain"

}

# when called with parameter "sourcemode"
if [ "$1" == "sourcemode" ]; then
  copyHost
  raspiblitz
  exit 0
fi

# Basic Options
OPTIONS=(HARDWARE "Run Hardwaretest" \
         SOFTWARE "Run Softwaretest (DebugReport)" \
         BACKUP-LND "Backup your LND data (Rescue-File)" \
         MIGRATION "Migrate Blitz Data to new Hardware" \
         COPY-SOURCE "Copy Blockchain Source Modus" \
         RESET-CHAIN "Delete Blockchain & Re-Download" \
         RESET-LND "Delete LND & start new node/wallet" \
         RESET-HDD "Delete HDD Data but keep Blockchain" \
         RESET-ALL "Delete HDD completly to start fresh" \
         DELETE-ELEC "Delete Electrum Index" \
         DELETE-INDEX "Delete Bitcoin Transaction-Index"
	)

CHOICE=$(whiptail --clear --title "Repair Options" --menu "" 18 62 11 "${OPTIONS[@]}" 2>&1 >/dev/tty)

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
        _temp=$(mktemp -p /dev/shm/)
        l1="Please enter the new name of your LND node:\n"
        l2="different name is better for a fresh identity\n"
        l3="one word, keep characters basic & not too long"
        dialog --backtitle "RaspiBlitz - Setup (${network}/${chain})" --inputbox "$l1$l2$l3" 13 52 2>$_temp
        result=$( cat $_temp | tr -dc '[:alnum:]-.' | tr -d ' ' )
        shred -u $_temp
        echo "processing ..."
        sleep 3
    done

    # make sure host is named like in the raspiblitz config
    echo "Setting the Name/Alias/Hostname .."
    sudo /home/admin/config.scripts/lnd.setname.sh ${result}
    sudo sed -i "s/^hostname=.*/hostname=${result}/g" /mnt/hdd/raspiblitz.conf

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
  DELETE-ELEC)
    /home/admin/config.scripts/bonus.electrs.sh off deleteindex
    exit 1;
    ;;
  DELETE-INDEX)
    /home/admin/config.scripts/network.txindex.sh delete
    exit 1;
    ;;
  COPY-SOURCE)
    copyHost
    /home/admin/config.scripts/lnd.unlock.sh
    ;;
esac
