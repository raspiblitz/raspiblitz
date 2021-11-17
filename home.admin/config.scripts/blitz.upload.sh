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

if [ "${action}" == "check-upload" ]; then

  # 2nd PARAMETER is type of upload (optional)
  type=$2
  echo "type='${type}'"

  # check if there to less or to many files in upload directory
  countFiles=$(ls ${defaultUploadPath} | wc -l 2>/dev/null)
  if [ ${countFiles} -lt 1 ]; then
    sudo rm ${defaultUploadPath}/* 2>/dev/null
    echo "error='not-found'"
    exit 1
  fi
  if [ ${countFiles} -gt 1 ]; then
    sudo rm ${defaultUploadPath}/* 2>/dev/null
    echo "error='multiple'"
    exit 1
  fi

  # get the file uploaded (full path)
  filename=$(sudo ls ${defaultUploadPath}/*.*)
  echo "# filename(${filename})"

  # check of size >0
  byteSize=$(ls -l ${filename} | awk '{print $5}')
  echo "# byteSize(${byteSize})"
  if [ "${byteSize}" == "" ] || [ "${byteSize}" == "0" ]; then
      sudo rm ${defaultUploadPath}/* 2>/dev/null
      echo "error='invalid'"
      echo "errorDetail='invalid byte size: ${byteSize}'"
      exit 1
  fi

  # SCB check if file looks valid
  if [ "${type}" == "scb" ]; then

    # general filename check
    typeCount=$(sudo ls ${defaultUploadPath}/*.backup 2>/dev/null | grep -c '.backup')
    if [ "${typeCount}" != "1" ]; then
      sudo rm ${defaultUploadPath}/* 2>/dev/null
      echo "error='invalid'"
      echo "errorDetail='not *.backup'"
      exit 1
    fi
  fi

  # LND-RESCUE check if file looks valid
  if [ "${type}" == "lnd-rescue" ]; then

    # general filename check
    typeCount=$(sudo ls ${defaultUploadPath}/lnd-rescue-*.tar.gz 2>/dev/null | grep -c 'lnd-rescue')
    if [ "${typeCount}" != "1" ]; then
      sudo rm ${defaultUploadPath}/* 2>/dev/null
      echo "error='invalid'"
      echo "errorDetail='not lnd-rescue-*.tar.gz'"
      exit 1
    fi

    # checksum test
    md5checksum=$(md5sum ${filename} | head -n1 | cut -d " " -f1)
    echo "# filename(${md5checksum})"
    isCorrect=$(echo ${filename} | grep -c ${md5checksum})
    if [ "${isCorrect}" != "1" ]; then
      sudo rm ${defaultUploadPath}/* 2>/dev/null
      echo "error='invalid'"
      echo "errorDetail='incorrect checksum'"
      exit 1
    fi
  fi

  # MIGRATION check if file looks valid
  if [ "${type}" == "migration" ]; then

    # general filename check
    typeCount=$(sudo ls ${defaultUploadPath}/raspiblitz-*.tar.gz 2>/dev/null | grep -c 'raspiblitz')
    if [ "${typeCount}" != "1" ]; then
      sudo rm ${defaultUploadPath}/* 2>/dev/null
      echo "error='invalid'"
      echo "errorDetail='not raspiblitz-*.tar.gz'"
      exit 1
    fi

    # checksum test
    md5checksum=$(md5sum ${filename} | head -n1 | cut -d " " -f1)
    echo "# filename(${md5checksum})"
    isCorrect=$(echo ${filename} | grep -c ${md5checksum})
    if [ "${isCorrect}" != "1" ]; then
      sudo rm ${defaultUploadPath}/* 2>/dev/null
      echo "error='invalid'"
      echo "errorDetail='incorrect checksum'"
      exit 1
    fi
  fi

  # ok looks good - return filename & more info
  echo "filename=${filename}"
  echo "bytesize=${byteSize}"
  exit 0
fi

echo "error='unkown parameter'"
exit 1