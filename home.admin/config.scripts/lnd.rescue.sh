#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small rescue script to to backup or restore"
 echo "lnd.rescue.sh [backup|restore]"
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

  # name with md5 checksum
  md5checksum=$(md5sum /home/admin/lnd-rescue.tar.gz | head -n1 | cut -d " " -f1)
  mv /home/admin/lnd-rescue.tar.gz /home/admin/lnd-rescue-${md5checksum}.tar.gz

  # offer SCP for download
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

  filename=""
  while [ ${#filename} -eq 0 ]
    do
      countZips=$(sudo ls /home/admin/lnd-rescue-*.tar.gz 2>/dev/null | grep -c 'lnd-rescue')
      if [ ${countZips} -lt 1 ]; then
        echo "**************************"
        echo "* UPLOAD THE BACKUP FILE *"
        echo "**************************"
        echo 
        echo "If you have a lnd-rescue backup file on your laptop you can now"
        echo "upload it and restore the your old LND state."
        echo
        echo "To make upload open a new terminal on your laptop,"
        echo "change into the directory where your lnd-rescue file is and"
        echo "COPY, PASTE AND EXECUTE THE FOLLOWING COMMAND:"
        echo "scp -r ./lnd-rescue-*.tar.gz admin@${localip}:/home/admin/"
        echo ""
        echo "Use password A to authenticate file transfere."
        echo
        echo "PRESS ENTER when upload is done. Use CTRL-C to abort."
      fi
      if [ ${countZips} -gt 1 ]; then
        echo "!! WARNING !!"
        echo "There are multiple lnd-rescue files in directory /home/admin."
        echo "Make sure there is only one file to work with and start again."
        echo 
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
        echo "PRESS ENTER to start restore. Use CTRL-C to abort."
      fi
      read key
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
  echo "Keep in mind that some channels got forced closed by channel partners in the meanwhile."
  echo 

else
  echo "unknown parameter '${mode}' - exit"
fi