#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# use to prepare & check scp or web file upload to RaspiBlitz"
 echo "# blitz.upload.sh prepare-upload"
 echo "# blitz.upload.sh check-upload ?[scb|lnd-rescue|migration]"
 exit 0
fi

# get local ip
source <(/home/admin/config.scripts/internet.sh status local)

# set upload path
if [ -d "/mnt/hdd/temp" ]; then
  # HDD with temp directory is connected - the use it
  defaultUploadPath="/mnt/hdd/temp/upload"
  defaultUploadUser="bitcoin"
else
  # fallback if no HDD is connected
  defaultUploadPath="/home/bitcoin/temp/upload"
  defaultUploadUser="bitcoin"
fi


# 1st PRAMETER action
action="$1"

if [ "${action}" == "prepare-upload" ]; then

  # make sure that temp directory exists, is clear and can be written by ${defaultUploadUser}
  sudo mkdir -p ${defaultUploadPath} 2>/dev/null
  sudo rm ${defaultUploadPath}/* 2>/dev/null
  sudo chown -R ${defaultUploadUser}:${defaultUploadUser} ${defaultUploadPath} 2>/dev/null

  echo "localip='${localip}'"
  echo "defaultUploadPath='${defaultUploadPath}'"
  echo "defaultUploadUser='${defaultUploadUser}'"
  exit 0
fi

if [ "${action}" ="" "check-upload" ]; then

  # 2nd PARAMETER is type of upload (optional)
  type=$2
  echo "type='${type}'"

  # testcut

  # ok looks good - return filename & more info
  echo "filename=${filename}"
  echo "bytesize=${byteSize}"
  exit 0
fi

echo "error='unkown parameter'"
exit 1