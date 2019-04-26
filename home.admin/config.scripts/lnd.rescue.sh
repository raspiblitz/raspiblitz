#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small rescue script to to backup or restore"
 echo "lnd.rescue.sh [backup|restore] [?no-download]"
 exit 1
fi

localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

mode="$1"
if [ ${mode} = "backup" ]; then

  ################################
  # BACKUP
  ################################

  echo "*** LND.RESCUE --> BACKUP"

  # stop LND
  echo "Stopping lnd..."
  sudo systemctl stop lnd
  sleep 5
  echo "OK"
  echo 

  # zip it
  sudo tar -zcvf /home/admin/lnd-rescue.tar.gz /mnt/hdd/lnd
  sudo chown admin:admin /home/admin/lnd-rescue.tar.gz

  # delete old backups
  rm /home/admin/lnd-rescue-*.tar.gz 2>/dev/null

  # name with md5 checksum
  md5checksum=$(md5sum /home/admin/lnd-rescue.tar.gz | head -n1 | cut -d " " -f1)
  mv /home/admin/lnd-rescue.tar.gz /home/admin/lnd-rescue-${md5checksum}.tar.gz

  # stop here in case of 'no-download' option
  if [ "${2}" == "no-download" ]; then
    echo "No download of LND data requested."
    exit 0
  fi

  # offer SCP for download
  clear
  echo
  echo "****************************"
  echo "* DOWNLOAD THE BACKUP FILE *"
  echo "****************************"
  echo 
  echo "RUN THE FOLLOWING COMMAND ON YOUR LAPTOP IN NEW TERMINAL:"
  echo "scp -r admin@${localip}:/home/admin/lnd-rescue-*.tar.gz ./"
  echo ""
  echo "Use password A to authenticate file transfere."
  echo
  echo "BEWARE: Your Lightning node is now stopped. So its safe to backup the data and restore it"
  echo "later on - for example on a fresh RaspiBlitz. But once this Lightning node gets started"
  echo "again by 'sudo systemctl start lnd' or a reboot its not adviced to restore the backup file"
  echo "anymore because it cointains outdated channel data and can lead to loss of channel funds."

elif [ ${mode} = "restore" ]; then

  ################################
  # RESTORE
  ################################

  echo "*** LND.RESCUE --> RESTORE"
  echo ""

    # delete old backups
  rm /home/admin/lnd-rescue-*.tar.gz

  filename=""
  while [ ${#filename} -eq 0 ]
    do
      countZips=$(sudo ls /home/admin/lnd-rescue-*.tar.gz 2>/dev/null | grep -c 'lnd-rescue')
      if [ ${countZips} -lt 1 ]; then
        echo "**************************"
        echo "* UPLOAD THE BACKUP FILE *"
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
        echo "Use password A to authenticate file transfere."
        echo "PRESS ENTER when upload is done. Enter x & ENTER to cancel."
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

        md5checksum=$(md5sum ${filename} | head -n1 | cut -d " " -f1)
        isCorrect=$(echo ${filename} | grep -c ${md5checksum})
        if [ ${isCorrect} -eq 1 ]; then
          echo "OK -> checksum looks good: ${md5checksum}"
        else
          echo "!!! FAIL -> Checksum not correct."
          echo "Maybe transfere failed? Continue on your own risk!"
          echo "Recommend to abort and upload again!"
        fi

        echo
        echo "WARNING: This will delete/overwrite the LND state/funds of this RaspiBlitz."
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

  # start LND
  echo "Starting lnd..."
  sudo systemctl start lnd
  echo "OK"
  echo

  echo "DONE - please check if LND starts up correctly with restored state and funds."
  echo "Keep in mind that some channels maybe forced closed in the meanwhile."
  echo 

else
  echo "unknown parameter '${mode}' - exit"
fi