#!/bin/bash

# TODO: check if services/apps are running and stop all ... or let thet to outside?
# TODO: check if old data ... or let this to outside?

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# managing the RaspiBlitz data - import, export, backup."
 echo "# blitz.rescue.sh [status|export|import]"
 echo "ERROR='missing parameters'"
 exit 1
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "ERROR='missing sudo'"
  exit 1
fi

# check if data drive is mounted - other wise cannot operate
isMounted=$(sudo df | grep -c /mnt/hdd)
if [ ${isMounted} -eq 0 ]; then
  echo "# FAIL check why /mnt/hdd is not available/mounted"
  echo "error='datadrive not found'"
  exit 1
fi

###################
# STATUS
###################

# gathering system info
isBTRFS=$(lsblk -o FSTYPE,MOUNTPOINT | grep /mnt/hdd | awk '$1=$1' | cut -d " " -f 1 | grep -c btrfs)

# set place where zipped TAR file gets stored
defaultZipPath="/mnt/hdd/temp"

# SCP download and upload links
localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
scpDownload="scp -r 'bitcoin@${localip}:${defaultZipPath}/raspiblitz-*.tar.gz' ./"
scpUpload="scp -r './raspiblitz-*.tar.gz' bitcoin@${localip}:${defaultZipPath}"

# output status data & exit
if [ "$1" = "status" ]; then
  echo "# RASPIBLITZ Data Import & Export"
  echo "isBTRFS=${isBTRFS}"  
  echo "scpDownload='${scpDownload}'" 
  echo "scpUpload='${scpUpload}'" 
  exit 1
fi

#########################
# EXPORT RaspiBlitz Data
#########################

if [ "$1" = "export" ]; then

  echo "# RASPIBLITZ DATA --> EXPORT"

  # collect files to exclude in export in temp file
  echo "*.tar.gz" > ~/.exclude.temp
  echo "/mnt/hdd/bitcoin" >> ~/.exclude.temp 
  echo "/mnt/hdd/litecoin" >> ~/.exclude.temp 
  echo "/mnt/hdd/swapfile" >> ~/.exclude.temp 
  echo "/mnt/hdd/temp" >> ~/.exclude.temp
  echo "/mnt/hdd/lost+found" >> ~/.exclude.temp 
  echo "/mnt/hdd/snapshots" >> ~/.exclude.temp 
  echo "/mnt/hdd/torrent" >> ~/.exclude.temp 
  echo "/mnt/hdd/app-storage" >> ~/.exclude.temp

  # copy bitcoin data files to backup dir (if bitcoin active)
  if [ -f "/mnt/hdd/bitcoin/bitcoin.conf" ]; then
    sudo mkdir -p /mnt/hdd/backup_bitcoin
    sudo cp /mnt/hdd/bitcoin/bitcoin.conf /mnt/hdd/backup_bitcoin/bitcoin.conf
    sudo cp /mnt/hdd/bitcoin/wallet.dat /mnt/hdd/backup_bitcoin/wallet.dat 2>/dev/null
  fi

  # copy litecoin data files to backup dir (if litecoin active)
  if [ -f "/mnt/hdd/litecoin/litecoin.conf" ]; then
    sudo mkdir -p /mnt/hdd/backup_litecoin
    sudo cp /mnt/hdd/bitcoin/litecoin.conf /mnt/hdd/backup_litecoin/litecoin.conf
    sudo cp /mnt/hdd/bitcoin/wallet.dat /mnt/hdd/backup_litecoin/wallet.dat 2>/dev/null
  fi

  # clean old backups from temp
  rm /hdd/temp/raspiblitz-*.tar.gz 2>/dev/null

  # get date stamp
  datestamp=$(date "+%y-%m-%d-%H-%M")
  echo "# datestamp=${datestamp}"

  # get name of RaspiBlitz from config (optional if exists)
  blitzname="-"
  source /mnt/hdd/raspiblitz.conf 2>/dev/null
  if [ ${#hostname} -gt 0 ]; then
    blitzname=$(echo "${hostname}" | sed 's/[^0-9a-z]*//g')
    blitzname=$(echo "-${blitzname}-")
  fi
  echo "# blitzname=${blitzname}"

  # zip it
  echo "# Building the Export File (this can take some time) .."
  sudo tar -zcvf ${defaultZipPath}/raspiblitz-export-temp.tar.gz -X ~/.exclude.temp /mnt/hdd 1>~/.include.temp

  # get md5 checksum
  echo "# Building checksum (can take also a while) ..." 
  md5checksum=$(md5sum ${defaultZipPath}/raspiblitz-export-temp.tar.gz | head -n1 | cut -d " " -f1)
  echo "# md5checksum=${md5checksum}"
  
  # final renaming 
  name="raspiblitz${blitzname}${datestamp}-${md5checksum}.tar.gz"
  echo "exportpath='${defaultZipPath}'"
  echo "filename='${name}'"
  sudo ${defaultZipPath}/raspiblitz-export-temp.tar.gz
  mv ${defaultZipPath}/raspiblitz-export-temp.tar.gz ${defaultZipPath}/${name}
  sudo chown bitcoin:bitcoin ${defaultZipPath}/${name}

  # delete temp files
  rm ~/.exclude.temp
  rm ~/.include.temp
  
  echo "scpDownload='${scpDownload}'"
  echo "# OK - Export done"
  exit 0
fi

#########################
# IMPORT RaspiBlitz Data
#########################

if [ "$1" = "import" ]; then

  # check second parameter for path and/or filename of import
  importFile="${defaultZipPath}/raspiblitz-*.tar.gz"
  if [ ${#2} -gt 0 ]; then
    # check if and/or filename of import
    containsPath=$(echo $2 | grep -c '/')
    if [ ${containsPath} -gt 0 ]; then
      startsOnPath=$(echo $2 | grep -c '^/')
      if [ ${startsOnPath} -eq 0 ]; then
        echo "# needs to be an absolut path: ${2}"
        echo "error='invalid path'"
        exit 1
      else
        if [ -d "$2" ]; then
          echo "# using path from parameter to search for import"  
          endsOnPath=$(echo $2 | grep -c '/$')
          if [ ${endsOnPath} -eq 1 ]; then
            importFile="${2}raspiblitz-*.tar.gz"  
          else
            importFile="${2}/raspiblitz-*.tar.gz"  
          fi
        else
          echo "# using path+file from parameter for import"
          importFile=$2
        fi
      fi
    else
      # is just filename - to use with default path
      echo "# using file from parameter for import"
      importFile="${defaultZipPath}/${2}"     
    fi 
  fi
  
  # checking if file exists and unique
  echo "# checking for file with: ${importFile}"
  countZips=$(sudo ls ${importFile} 2>/dev/null | grep -c '.tar.gz')
  if [ ${countZips} -eq 0 ]; then
    echo "# can just find file when ends on .tar.gz and exists"
    echo "scpUpload='${scpUpload}'" 
    echo "error='file not found'"
    exit 1
  elif [ ${countZips} -eq 1 ]; then
    importFile=$(sudo ls ${importFile})
  else
    echo "# Multiple files found. Not sure which to use."
    echo "# Please use absolut-path+file as second parameter."
    echo "error='file not unique'"
    exit 1
  fi
  echo "importFile='${importFile}'"

  echo "# Validating Checksum (can take some time) .."
  md5checksum=$(md5sum ${importFile} | head -n1 | cut -d " " -f1)
  isCorrect=$(echo ${importFile} | grep -c ${md5checksum})
  if [ ${isCorrect} -eq 1 ]; then
    echo "# OK -> checksum looks good: ${md5checksum}"
  else
    echo "# FAIL -> Checksum not correct: ${md5checksum}"
    echo "# Maybe transfere/upload failed?"
    echo "error='bad checksum'"
    exit 1
  fi

  echo "# Importing (overwrite) (can take some time) .."
  sudo tar -xf ${importFile} -C /

  # copy bitcoin/litecoin data backups back to orgplaces (if part of backup)
  if [ -d "/mnt/hdd/backup_bitcoin" ]; then
    echo "# Copying back bitcoin backup data .."
    sudo cp /mnt/hdd/backup_bitcoin/bitcoin.conf /mnt/hdd/bitcoin/bitcoin.conf
    sudo cp /mnt/hdd/backup_bitcoin/wallet.dat /mnt/hdd/bitcoin/wallet.dat  2>/dev/null
  fi
  if [ -d "/mnt/hdd/backup_litecoin" ]; then
    echo "# Copying back litecoin backup data .."
    sudo cp /mnt/hdd/backup_litecoin/litecoin.conf /mnt/hdd/litecoin/litecoin.conf
    sudo cp /mnt/hdd/backup_litecoin/wallet.dat /mnt/hdd/litecoin/wallet.dat  2>/dev/null
  fi

  echo "# OK done - you may now want to:"
  echo "# make sure that HDD is not registered in /etc/fstab & reboot"
  echo "# to kickstart recovering system based in imported data"

  exit 0
fi

echo "error='unkown command'"
exit 1