#!/bin/bash

source /mnt/hdd/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# small rescue script to to backup or restore LND data"
 echo "# -> backup all LND data in a tar.gz file for download:"
 echo "# lnd.rescue.sh backup [?no-download]"
 echo "# -> upload a LND data tar.gz file to replace LND data:"
 echo "# lnd.rescue.sh restore"
 echo "# -> download the LND channel.backup file from SD card:"
 echo "# lnd.rescue.sh scb-down"
 echo "# -> upload the LND channel.backup to recover wallet:"
 echo "# lnd.rescue.sh scb-up"
 exit 1
fi

localip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0|veth' | grep 'eth0\|wlan0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

mode="$1"
if [ ${mode} = "backup" ]; then

  ################################
  # BACKUP
  ################################

  echo "# *** LND.RESCUE --> BACKUP"

  # stop LND
  echo "# Stopping lnd..."
  sudo systemctl stop lnd
  sleep 5
  echo "# OK"
  echo 

  # zip it
  sudo tar -zcvf /home/admin/lnd-rescue.tar.gz /mnt/hdd/lnd 1>&2
  sudo chown admin:admin /home/admin/lnd-rescue.tar.gz 1>&2

  # delete old backups
  rm /home/admin/lnd-rescue-*.tar.gz 2>/dev/null 1>/dev/null

  # name with md5 checksum
  md5checksum=$(md5sum /home/admin/lnd-rescue.tar.gz | head -n1 | cut -d " " -f1)
  mv /home/admin/lnd-rescue.tar.gz /home/admin/lnd-rescue-${md5checksum}.tar.gz 1>&2
  echo "file='lnd-rescue-${md5checksum}.tar.gz'"
  echo "path='/home/admin/'"

  byteSize=$(ls -l /home/admin/lnd-rescue-${md5checksum}.tar.gz | awk '{print $5}')
  echo "size=${byteSize}"

  if [ ${byteSize} -lt 100 ]; then
    echo "error='backup is empty'"
    echo
    echo "# *****************************"
    echo "# * BACKUP ERROR              *"
    echo "# *****************************"
    echo "# The byte size of the created rescue-file is too small (${byteSize}) - might be empty!"
    echo "# If you plan any update or recovery please stop and report this error to dev team. Thx."
    exit 0
  fi

  # stop here in case of 'no-download' option
  if [ "${2}" == "no-download" ]; then
    echo "# No download of LND data requested."
    exit 0
  fi

  # offer SCP for download
  clear
  echo
  echo "****************************"
  echo "* DOWNLOAD THE RESCUE FILE *"
  echo "****************************"
  echo 
  echo "ON YOUR LAPTOP - RUN IN NEW TERMINAL:"
  echo "scp -r 'admin@${localip}:/home/admin/lnd-rescue-*.tar.gz' ./"
  echo ""
  echo "Use password A to authenticate file transfer."
  echo "Check for correct file size after transfer: ${byteSize} byte"
  echo
  echo "BEWARE: Your Lightning node is now stopped. It's safe to backup the data and"
  echo "restore it on a fresh RaspiBlitz. But once this Lightning node gets started"
  echo "again or rebooted its not adviced to restore the backup file anymore because"
  echo "it cointains then outdated channel data & can lead to loss of channel funds."

elif [ ${mode} = "restore" ]; then

  ################################
  # RESTORE
  ################################

  echo "# LND.RESCUE --> RESTORE"
  echo ""

  # delete old backups
  rm /home/admin/lnd-rescue-*.tar.gz

  filename=""
  while [ ${#filename} -eq 0 ]
    do
      countZips=$(sudo ls /home/admin/lnd-rescue-*.tar.gz 2>/dev/null | grep -c 'lnd-rescue')
      if [ ${countZips} -lt 1 ]; then
        echo "**************************"
        echo "* UPLOAD THE RESCUE FILE *"
        echo "**************************"
        echo "If you have a lnd-rescue backup file on your laptop you can now"
        echo "upload it and restore the your latest LND state."
        echo
        echo "CAUTION: Dont restore old LND states - risk of loosing funds!"
        echo
        echo "To make upload open a new terminal on your laptop,"
        echo "change into the directory where your lnd-rescue file is and"
        echo "COPY, PASTE AND EXECUTE THE FOLLOWING COMMAND:"
        echo "scp -r ./lnd-rescue-*.tar.gz admin@${localip}:/home/admin/"
        echo ""
        echo "Use password A to authenticate file transfer."
        echo "PRESS ENTER when upload is done."
      fi
      if [ ${countZips} -gt 1 ]; then
        echo "!! WARNING !!"
        echo "There are multiple lnd-rescue files in directory /home/admin."
        echo "Make sure you upload only one tar.gz-file and start again."
        echo 
        echo "PRESS ENTER to continue."
        read key
        exit 1
      fi
      if [ ${countZips} -eq 1 ]; then
        
        clear
        echo
        echo "**************************"
        echo "* RESTORING BACKUP FILE  *"
        echo "**************************"
        echo

        filename=$(sudo ls /home/admin/lnd-rescue-*.tar.gz)
        echo "OK -> found file to restore: ${filename}"

        # checksum test
        md5checksum=$(md5sum ${filename} | head -n1 | cut -d " " -f1)
        isCorrect=$(echo ${filename} | grep -c ${md5checksum})
        if [ ${isCorrect} -eq 1 ]; then
          echo "OK -> checksum looks good: ${md5checksum}"
        else
          echo "!!! FAIL -> Checksum not correct."
          echo "Maybe transfer failed? Continue at your own risk!"
          echo "It is recommended to abort and upload again!"
        fi

        # overrride test
        oldWalletExists=$(sudo ls /mnt/hdd/lnd/data/chain/${network}/${chain}net/wallet.db 2>/dev/null | grep -c "wallet.db")
        if [ ${oldWalletExists} -gt 0 ]; then
          echo
          echo "WARNING: This will delete/overwrite the LND state/funds of this RaspiBlitz."
        fi
        echo
        echo "PRESS ENTER to start restore. Enter x & ENTER to cancel."
      fi
      read key
      if [ "${key}" == "x" ]; then
        exit 1
      fi
    done

  # stop LND
  echo "Stopping lnd..."
  sudo systemctl stop lnd
  sleep 5
  echo "OK"
  echo 

  # clean DIR
  echo "Cleaning LND data ..."
  sudo rm -r /mnt/hdd/lnd/*
  echo "OK"
  echo 

  # unpack zip
  echo "Restoring LND data from ${filename} ..."
  sudo tar -xf ${filename} -C /
  sudo chown -R bitcoin:bitcoin /mnt/hdd/lnd
  echo "OK"
  echo

  # check if LND needs update
  # (if RaspiBlitz has an optional LND version update, then install it
  # the newer LND version can always handle older data)
  echo "Checking LND version ..."
  source <(sudo -u admin /home/admin/config.scripts/lnd.update.sh info)
  if [ ${lndUpdateInstalled} -eq 0 ]; then
    echo "Installing available LND update ... (newer version can handle more wallet formats)"
    sudo -u admin /home/admin/config.scripts/lnd.update.sh verified
  else
    echo "OK"
  fi
  echo

  # start LND
  echo "Starting lnd..."
  sudo systemctl start lnd
  echo "OK"
  echo

  echo "DONE - please check if LND starts up correctly with restored state and funds."
  echo "Keep in mind that some channels maybe forced closed in the meanwhile."
  echo 

elif [ ${mode} = "scb-down" ]; then

  echo
  echo "****************************"
  echo "* DOWNLOAD THE BACKUP FILE *"
  echo "****************************"
  echo 
  echo "RUN THE FOLLOWING COMMAND ON YOUR LAPTOP IN NEW TERMINAL:"
  echo "scp -r admin@${localip}:/home/admin/.lnd/data/chain/${network}/${chain}net/channel.backup ./"
  echo ""
  echo "Use password A to authenticate file transfer."
  echo
  echo "NOTE: Use this file when setting up a fresh RaspiBlitz by choosing" 
  echo "option OLD WALLET and then SCB+SEED -> Seed & channel.backup file" 
  echo "Will just recover on-chain & channel-funds, but closing all channels" 

elif [ ${mode} = "scb-up" ]; then

  gotFile=-1
  while [ ${gotFile} -lt 1 ]
  do

    # show info
    clear
    sleep 1
    echo "**********************************"
    echo "* UPLOAD THE channel.backup FILE *"
    echo "**********************************"
    echo
    if [ ${gotFile} -eq -1 ]; then
      echo "If you have the channel.backup file on your laptop or on"
      echo "another server you can now upload it to the RaspiBlitz."
    elif [ ${gotFile} -eq 0 ]; then
      echo "NO channel.backup FOUND IN /home/admin"
      echo "Please try upload again."
    fi
    echo
    echo "To make upload open a new terminal and change,"
    echo "into the directory where your lnd-rescue file is and"
    echo "COPY, PASTE AND EXECUTE THE FOLLOWING COMMAND:"
    echo "scp ./channel.backup admin@${localip}:/home/admin/"
    echo ""
    echo "Use password A to authenticate file transfer."
    echo "PRESS ENTER when upload is done. Enter x & ENTER to cancel."

    # wait user interaction
    echo "Please upload file. Press ENTER to try again or (x & ENTER) to cancel."
    read key
    if [ "${key}" == "x" ]; then
      # EXIT with CODE 1 --> USER CANCEL
      echo "# CANCEL upload"
      exit 1
    fi

    # test upload
    gotFile=$(ls /home/admin/channel.backup | grep -c 'channel.backup')

  done

  # EXIT with CODE 1 --> FILE UPLOADED
  echo
  echo "# OK channel.backup uploaded"
  sleep 2
  exit 0

else
  echo "unknown parameter '${mode}' - exit"
fi
