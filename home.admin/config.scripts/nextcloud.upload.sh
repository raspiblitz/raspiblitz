#!/bin/bash

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# script to upload a file to Nextcloud"
  echo "# nextcloud.upload.sh on [SERVER] [USER] [PASSWORD]"
  echo "# nextcloud.upload.sh off"
  echo "# nextcloud.upload.sh upload [FILEPATH]"
  echo "err='just informational output'"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

MODE=$1

if test $MODE = "on"; then
  sudo touch /home/admin/.tmp
  sudo chmod 777 /home/admin/.tmp

  SERVER=$2
  if [ -z $SERVER ]; then
    whiptail --title "Static Channel Backup on Nextcloud" --inputbox "Enter your Nextcloud server URL\nExample: https://cloud.johnsmith.com" 11 70 2>/home/admin/.tmp
    SERVER=$(cat /home/admin/.tmp)
  fi

  USER=$3
  if [ -z $USER ]; then
    whiptail --title "Static Channel Backup on Nextcloud" --inputbox "Enter your Nextcloud username" 11 70 2>/home/admin/.tmp
    USER=$(cat /home/admin/.tmp)
  fi

  PASSWORD=$4
  if [ -z $PASSWORD ]; then
    whiptail --title "Static Channel Backup on Nextcloud" --inputbox "Enter your Nextcloud password" 11 70 2>/home/admin/.tmp
    PASSWORD=$(cat /home/admin/.tmp)
  fi

  shred -u /home/admin/.tmp

  if [ $SERVER ] && [ $USER ] && [ $PASSWORD ]; then
    if [ -z $nextcloudBackupServer ]; then
      echo "nextcloudBackupServer=$SERVER" >> /mnt/hdd/raspiblitz.conf
    fi
    sudo sed -i "s/^nextcloudBackupServer=.*/nextcloudBackupServer=$SERVER/g" /mnt/hdd/raspiblitz.conf

    if [ -z $nextcloudBackupUser ]; then
      echo "nextcloudBackupUser=$USER" >> /mnt/hdd/raspiblitz.conf
    fi
    sudo sed -i "s/^nextcloudBackupUser=.*/nextcloudBackupUser=$USER/g" /mnt/hdd/raspiblitz.conf

    if [ -z $nextcloudBackupPassword ]; then
      echo "nextcloudBackupPassword=$PASSWORD" >> /mnt/hdd/raspiblitz.conf
    fi
    sudo sed -i "s/^nextcloudBackupPassword=.*/nextcloudBackupPassword=$PASSWORD/g" /mnt/hdd/raspiblitz.conf
  else
    echo "Please provide nextcloud server, username and password"
  fi

elif test $MODE = "off"; then

  sudo sed -i '/nextcloudBackupServer=.*/d' /mnt/hdd/raspiblitz.conf
  sudo sed -i '/nextcloudBackupUser=.*/d' /mnt/hdd/raspiblitz.conf
  sudo sed -i '/nextcloudBackupPassword=.*/d' /mnt/hdd/raspiblitz.conf

elif test $MODE = "upload"; then

  if [ -z $nextcloudBackupServer ] || [ -z $nextcloudBackupUser ] || [ -z $nextcloudBackupPassword ]; then
    echo "err='nextcloud credentials are missing'"
    exit 1
  fi

  FILEPATH=$2
  if [ -z $FILEPATH ]; then
    echo "err='filepath is missing'"
    exit 1
  fi

  sudo curl "$nextcloudBackupServer/remote.php/dav/files/$nextcloudBackupUser/" \
    --user "$nextcloudBackupUser:$nextcloudBackupPassword" \
    --upload-file $FILEPATH

  if test $? = 0; then
    echo "# Great success!"
    echo "upload=1"
  else
    echo "err='file upload failed'"
    exit 1
  fi

else

  echo "err='unkown mode'"
  exit 1

fi
