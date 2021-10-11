#!/bin/bash

# DEPRECATED: https://github.com/rootzoll/raspiblitz/issues/2264#issuecomment-872655605
# script will stay on v1.7.1 ... but should be removed after that

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# script to upload a file to DropBox (without third party libs)"
 echo "# dropbox.upload.sh on [AUTHTOKEN]"
 echo "# dropbox.upload.sh off"
 echo "# dropbox.upload.sh upload [AUTHTOKEN] [FILEPATH]"
 echo "# dropbox.upload.sh check [AUTHTOKEN]"
 echo "# for Dropbox Setup with Authtoken, see:"
 echo "# https://gist.github.com/vindard/e0cd3d41bb403a823f3b5002488e3f90"
 echo "err='just informational output'"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# get first parameter
MODE="$1"
if [ "${MODE}" == "on" ]; then
  
  # second parameter: dropbox auth token
  authtoken="$2"

  # get auth token from user if not given as second parameter
  if [ ${#authtoken} -eq 0 ]; then
    sudo touch /home/admin/.tmp
    sudo chmod 777 /home/admin/.tmp
    whiptail --title " Static Channel Backup on Dropbox " --inputbox "
Follow the steps described at the following link
to get the DropBox-Authtoken from your account:
https://github.com/rootzoll/raspiblitz/#a-dropbox-backup-target" 11 70 2>/home/admin/.tmp
    authtoken=$(cat /home/admin/.tmp)
    shred -u /home/admin/.tmp
  fi

  # set in config - that activates the dropbox back in background process
  if [ ${#authtoken} -gt 0 ]; then
    if [ ${#dropboxBackupTarget} -eq 0 ]; then
      echo "dropboxBackupTarget='${authtoken}'" >> /mnt/hdd/raspiblitz.conf
    fi
    sudo sed -i "s/^dropboxBackupTarget=.*/dropboxBackupTarget='${authtoken}'/g" /mnt/hdd/raspiblitz.conf
  fi

elif [ "${MODE}" == "off" ]; then

  # to turn backup off - delete the parameter from the config file
  sudo sed -i '/dropboxBackupTarget=.*/d' /mnt/hdd/raspiblitz.conf

elif [ "${MODE}" == "check" ]; then

  # get needed second parameter
  DROPBOX_APITOKEN="$2"
  if [ ${#DROPBOX_APITOKEN} -eq 0 ]; then
    echo "err='missing Parameter AUTHTOKEN'"
    exit 1
  fi

  # run API check
  curl -s -X POST https://api.dropboxapi.com/2/users/get_current_account \
    --header "Authorization: Bearer "$DROPBOX_APITOKEN | grep rror
  if [[ ! $? -eq 0 ]] ; then
    echo "# Dropbox API Token worked"
    echo "check=1"
  else
    echo "# Invalid Dropbox API Token!"
    echo "check=0"
  fi

elif [ "${MODE}" == "upload" ]; then

  # get needed second parameter
  DROPBOX_APITOKEN="$2"
  if [ ${#DROPBOX_APITOKEN} -eq 0 ]; then
    echo "err='missing Parameter AUTHTOKEN'"
    exit 1
  fi

  # get needed third parameter
  SOURCEFILE="$3"
  if [ ${#SOURCEFILE} -eq 0 ]; then
    echo "err='missing Parameter SOURCEFILE'"
    exit 1
  fi

  source /mnt/hdd/raspiblitz.conf
  if [ ${#hostname} -eq 0 ]; then
    hostname="raspiblitz"
  fi

  DEVICE=$(echo "${hostname}" | awk '{print tolower($0)}' | sed -e 's/ /-/g')
  BACKUPFOLDER=lndbackup-$DEVICE
  FILENAME=$(basename "${SOURCEFILE}")

  sudo curl -s -X POST https://content.dropboxapi.com/2/files/upload \
    --header "Authorization: Bearer "${DROPBOX_APITOKEN}"" \
    --header "Dropbox-API-Arg: {\"path\": \"/"$BACKUPFOLDER"/"$FILENAME"\",\"mode\": \"overwrite\",\"autorename\": true,\"mute\": false,\"strict_conflict\": false}" \
    --header "Content-Type: application/octet-stream" \
    --data-binary @$SOURCEFILE > /home/admin/.dropbox.tmp
  safeResponse=$(sed 's/[^a-zA-Z0-9 ]//g' /home/admin/.dropbox.tmp)
  sudo shred -u /home/admin/.dropbox.tmp

  success=$(echo "${safeResponse}" | grep -c 'servermodified')
  sizeZero=$(echo "${safeResponse}" | grep -c 'size 0')
  if [ ${sizeZero} -gt 0 ]; then
    echo "# Upload happened but is size zero"
    echo "upload=0"
    echo "err='size zero'"
    echo "errMore='${safeResponse}'"
  elif [ ${success} -gt 0 ] ; then
    echo "# Successfully uploaded!"
    echo "upload=1"
  else
    echo "# Unknown Error"
    echo "upload=0"
    echo "err='unknown'"
    echo "errMore='${safeResponse}'"
  fi

else
  echo "err='unknown mode'"
  exit 1
fi









