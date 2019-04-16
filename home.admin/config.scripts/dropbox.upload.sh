#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# script to upload a file to DropBox (without third party libs)"
 echo "# dropbox.upload.sh upload [AUTHTOKEN] [FILEPATH]"
 echo "# dropbox.upload.sh check [AUTHTOKEN]"
 echo "# for Dropbox Setup with Authtoken, see:"
 echo "# https://gist.github.com/vindard/e0cd3d41bb403a823f3b5002488e3f90"
 echo "err='just informational output'"
 exit 1
fi

# get first parameter
MODE="$1"
if [ "${MODE}" == "check" ]; then

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
  sudo shred /home/admin/.dropbox.tmp
  sudo rm /home/admin/.dropbox.tmp 2>/dev/null

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
  echo "err='unkown mode'"
  exit 1
fi









