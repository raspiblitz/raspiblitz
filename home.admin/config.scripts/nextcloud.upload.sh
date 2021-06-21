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

case "${1}" in
  on)
    sudo touch /home/admin/.tmp
    sudo chmod 777 /home/admin/.tmp

    SERVER="${2}"
    if [ -z "${SERVER}" ]; then
      whiptail --title "Static Channel Backup on Nextcloud" --inputbox "Enter your Nextcloud server URL\nExample: https://cloud.johnsmith.com" 11 70 2>/home/admin/.tmp
      SERVER=$(cat /home/admin/.tmp)
    fi

    USER="${3}"
    if [ -z "${USER}" ]; then
      whiptail --title "Static Channel Backup on Nextcloud" --inputbox "Enter your Nextcloud username" 11 70 2>/home/admin/.tmp
      USER=$(cat /home/admin/.tmp)
    fi

    PASSWORD="${4}"
    if [ -z "${PASSWORD}" ]; then
      whiptail --title "Static Channel Backup on Nextcloud" --inputbox "Enter your Nextcloud password" 11 70 2>/home/admin/.tmp
      PASSWORD=$(cat /home/admin/.tmp)
    fi

    shred -u /home/admin/.tmp

    if [ "${SERVER}" ] && [ "${USER}" ] && [ "${PASSWORD}" ]; then
      sudo sed -i '/nextcloudBackupServer=.*/d' /mnt/hdd/raspiblitz.conf
      echo "nextcloudBackupServer=${SERVER}" >> /mnt/hdd/raspiblitz.conf

      sudo sed -i '/nextcloudBackupUser=.*/d' /mnt/hdd/raspiblitz.conf
      echo "nextcloudBackupUser=${USER}" >> /mnt/hdd/raspiblitz.conf

      sudo sed -i '/nextcloudBackupPassword=.*/d' /mnt/hdd/raspiblitz.conf
      echo "nextcloudBackupPassword=${PASSWORD}" >> /mnt/hdd/raspiblitz.conf
    else
      echo "Please provide nextcloud server, username and password"
    fi
  ;;
  off)
    sudo sed -i '/nextcloudBackupServer=.*/d' /mnt/hdd/raspiblitz.conf
    sudo sed -i '/nextcloudBackupUser=.*/d' /mnt/hdd/raspiblitz.conf
    sudo sed -i '/nextcloudBackupPassword=.*/d' /mnt/hdd/raspiblitz.conf
  ;;
  upload)
    if [ -z "${nextcloudBackupServer}" ] || [ -z "${nextcloudBackupUser}" ] || [ -z "${nextcloudBackupPassword}" ]; then
      echo "err='nextcloud credentials are missing'"
      exit 1
    fi

    FILEPATH="${2}"
    if [ -z "${FILEPATH}" ]; then
      echo "err='filepath is missing'"
      exit 1
    fi

    REMOTE_DIR_URL="$nextcloudBackupServer/remote.php/dav/files/$nextcloudBackupUser/raspiblitz/"

    # checking if remote directory exists
    RESPONSE=$(curl "${REMOTE_DIR_URL}" \
      --user "${nextcloudBackupUser}:${nextcloudBackupPassword}" \
      --request PROPFIND \
      --silent)

    # if remote directory doesn't exist, we need to create it
    if [[ "${RESPONSE}" = *DAV\\Exception\\NotFound* ]]; then
      curl "${REMOTE_DIR_URL}" \
        --user "${nextcloudBackupUser}:${nextcloudBackupPassword}" \
        --request MKCOL \
        --silent
    fi

    if curl "${REMOTE_DIR_URL}" \
      --user "${nextcloudBackupUser}:${nextcloudBackupPassword}" \
      --upload-file "${FILEPATH}" \
      --silent;
    then
      echo "# Great success!"
      echo "upload=1"
    else
      echo "err='File upload failed'"
      echo "upload=0"
      exit 1
    fi
  ;;
  *)
    echo "err='Unknown action'"
    exit 1
  ;;
esac