#!/bin/bash

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# managing the RaspiBlitz data - import, export, backup."
 echo "# blitz.migration.sh [status|export|import|export-gui|import-gui]"
 echo "error='missing parameters'"
 exit 1
fi

# file to print debug info on longer processes to
logFile="/home/admin/raspiblitz.log"

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='missing sudo'"
  exit 1
fi

###################
# STATUS
###################

# check if data drive is mounted - other wise cannot operate
isMounted=0
if [ -L /mnt/hdd/app-data ]; then
  isMounted=1
fi

# set place where zipped TAR file gets stored
defaultDownloadPath="/mnt/hdd/temp/migration"
defaultUploadPath="/mnt/upload/temp"

# get local ip
source <(/home/admin/config.scripts/internet.sh status local)

# SCP download and upload links
downloadUnix="scp -r 'bitcoin@${localip}:${defaultDownloadPath}/raspiblitz-*.tar.gz' ./"
downloadWin="scp -r bitcoin@${localip}:${defaultDownloadPath}/raspiblitz-*.tar.gz ."
uploadUnix="scp -r ./raspiblitz-*.tar.gz admin@${localip}:${defaultUploadPath}"
uploadWin="scp -r ./raspiblitz-*.tar.gz admin@${localip}:${defaultUploadPath}"

# check for a filename in the upload path
firstMigrationFile=$(ls -1 ${defaultUploadPath}/raspiblitz-*.tar.gz 2>/dev/null | head -n 1)
if [ -n "$firstMigrationFile" ]; then
  echo "# Found migration file: ${firstMigrationFile}"
  migrationFilename=$(basename "$firstMigrationFile")
else
  echo "# No migration files found"
  migrationFilename=""
fi

# output status data & exit
if [ "$1" = "status" ]; then
  echo "# RASPIBLITZ Data Import & Export"
  echo "localip=\"${localip}\""
  echo "defaultDownloadPath=\"${defaultDownloadPath}\""
  echo "defaultUploadPath=\"${defaultUploadPath}\""
  echo "downloadUnix=\"${downloadUnix}\""
  echo "uploadUnix=\"${uploadUnix}\""
  echo "downloadWin=\"${downloadWin}\""
  echo "uploadWin=\"${uploadWin}\""
  echo "migrationFile=\"${migrationFilename}\""
  exit 1
fi

#########################
# EXPORT RaspiBlitz Data
#########################

if [ "$1" = "export" ]; then

  echo "# RASPIBLITZ DATA --> EXPORT"

  # clean all temp to make max space
  rm -fr /mnt/hdd/temp/* 2>/dev/null

  # collect files to exclude in export in temp file
  echo "*.tar.gz" > ~/.exclude.temp
  echo "/mnt/hdd/bitcoin" >> ~/.exclude.temp 
  echo "/mnt/hdd/temp" >> ~/.exclude.temp
  echo "/mnt/hdd/lost+found" >> ~/.exclude.temp
  echo "/mnt/hdd/app-storage" >> ~/.exclude.temp
  echo "/mnt/hdd/snapshots" >> ~/.exclude.temp  # keep for legacy reasons (until v2)
  echo "/mnt/hdd/torrent" >> ~/.exclude.temp # keep for legacy reasons (until v2)
  echo "/mnt/hdd/litecoin" >> ~/.exclude.temp # keep for legacy reasons (until v2)
  echo "/mnt/hdd/swapfile" >> ~/.exclude.temp # keep for legacy reasons (until v2)

  # get date stamp
  datestamp=$(date "+%y-%m-%d-%H-%M")
  echo "# datestamp=${datestamp}"

  # get name of RaspiBlitz from config (optional if exists)
  blitzname="-"
  source /mnt/hdd/app-data/raspiblitz.conf 2>/dev/null
  if [ ${#hostname} -gt 0 ]; then
    blitzname="-${hostname}-"
  fi
  echo "# blitzname=${blitzname}"

  # zip it
  echo "# Building the Export File (this can take some time) .."
  sudo mkdir -p ${defaultDownloadPath}
  sudo tar -zcvf ${defaultDownloadPath}/raspiblitz-export-temp.tar.gz -X ~/.exclude.temp /mnt/hdd 1>~/.include.temp 2>/dev/null

  # get md5 checksum
  echo "# Building checksum (can take a while) ..." 
  md5checksum=$(md5sum ${defaultDownloadPath}/raspiblitz-export-temp.tar.gz | head -n1 | cut -d " " -f1)
  echo "md5checksum=${md5checksum}"
  
  # get byte size
  bytesize=$(wc -c ${defaultDownloadPath}/raspiblitz-export-temp.tar.gz | cut -d " " -f 1)
  echo "bytesize=${bytesize}"

  # final renaming 
  name="raspiblitz${blitzname}${datestamp}-${md5checksum}.tar.gz"
  echo "exportpath='${defaultDownloadPath}'"
  echo "filename='${name}'"
  sudo mv ${defaultDownloadPath}/raspiblitz-export-temp.tar.gz ${defaultDownloadPath}/${name}
  sudo chown bitcoin:bitcoin ${defaultDownloadPath}/${name}

  # delete temp files
  rm ~/.exclude.temp
  rm ~/.include.temp

  echo "name=\"${defaultDownloadPath}/${name}\""
  echo "# OK - Export done"
  exit 0
fi

if [ "$1" = "export-gui" ]; then

  # cleaning old migration files from blitz
  sudo rm ${defaultDownloadPath}/*.tar.gz 2>/dev/null
  source /mnt/hdd/app-data/raspiblitz.conf

  # make sure bitcoin & lighning is stopped
  sudo systemctl stop bitcoind 2>/dev/null
  sudo systemctl stop tbitcoind 2>/dev/null
  sudo systemctl stop sbitcoind 2>/dev/null
  sudo systemctl stop lnd 2>/dev/null
  sudo systemctl stop tlnd 2>/dev/null
  sudo systemctl stop slnd 2>/dev/null
  sudo systemctl stop lightningd  2>/dev/null
  sudo systemctl stop tlightningd 2>/dev/null
  sudo systemctl stop slightningd 2>/dev/null

  # create new migration file
  clear
  echo "--> creating blitz migration file ... (please wait)"
  source <(sudo /home/admin/config.scripts/blitz.migration.sh export)
  if [ ${#filename} -eq 0 ]; then
    echo "# Error: $"
    echo "# FAIL: was not able to create migration file"
    exit 0
  fi

  # show info for migration
  clear
  echo
  echo "*******************************"
  echo "* DOWNLOAD THE MIGRATION FILE *"
  echo "*******************************"
  echo 
  echo "On your Linux or MacOS Laptop - RUN IN NEW TERMINAL:"
  echo "${downloadUnix}"
  echo "On Windows use command:"
  echo "${downloadWin}"
  echo ""
  echo "Use password A to authenticate file transfer."
  echo 
  echo "To check if you downloaded the file correctly:"
  echo "md5-checksum --> ${md5checksum}"
  echo "byte-size --> ${bytesize}"
  echo 
  echo "Your Lightning node is now stopped. After download press ENTER to shutdown your raspiblitz."
  echo "To complete the data migration follow then instructions on the github FAQ."
  echo
  read key
  echo "Shutting down ...."
  sleep 4
  sudo /home/admin/config.scripts/blitz.shutdown.sh
  exit 0
fi

if [ "$1" = "import-gui" ]; then

  source <(/home/admin/_cache.sh get ui_migration_upload ui_migration_uploadUnix ui_migration_uploadWin)
  clear
  echo
  echo "*******************************"
  echo "* UPLOAD THE MIGRATION FILE *"
  echo "*******************************"
  echo 
  echo "On your Linux or MacOS Laptop - OPEN NEW TERMINAL."
  echo "Go into the folder where you have stored your raspiblitz-*.tar.gz file and run:"
  echo "${ui_migration_uploadUnix}"
  echo "Or on Windows use command:"
  echo "${ui_migration_uploadWin}"
  echo
  echo "Use password 'raspiblitz' to authenticate file transfer."
  echo
  echo "After upload command press ENTER to process."
  echo
  read key
  echo "Processing ...."
  exit 0
fi

#########################
# IMPORT RaspiBlitz Data
#########################

if [ "$1" = "import" ]; then

  # INFO: the migration import is only called during setup phase - assume a prepared but clean HDD

  # 2nd PARAMETER: file to import (expect that the file was valid checked from calling script)
  importFile=$2
  if [ "${importFile}" == "" ]; then
    echo "error='filename missing'"
    exit 1
  fi
  fileExists=$(sudo ls ${importFile} 2>/dev/null | grep -c "${importFile}")
  if [ "${fileExists}" != "1" ]; then
    echo "error='filename not found'"
    exit 1
  fi
  echo "importFile='${importFile}'"

  echo "# Importiere Dateien (kann einige Zeit dauern)..." >> ${logFile}
  # Temporäres Verzeichnis erstellen
  sudo mkdir -p /mnt/hdd/temp/migration_extract

  # Datei zuerst in temporäres Verzeichnis entpacken
  sudo tar -xf ${importFile} -C /mnt/hdd/temp/migration_extract >> ${logFile}
  if [ "$?" != "0" ]; then
    echo "error='migration tar failed'"
    exit 1
  fi
  sudo rm ${importFile}

  # Mit rsync übertragen und dabei symbolische Links erhalten
  sudo rsync -avK --keep-dirlinks /mnt/hdd/temp/migration_extract/mnt/hdd/ /mnt/hdd/ 2>>${logFile}
  if [ "$?" != "0" ]; then
    echo "error='migration rsync failed'"
    exit 1
  fi
  sudo rm -rf /mnt/hdd/temp/migration_extract

  # copy bitcoin data backups back to original places (if part of backup before v1.12)
  if [ -d "/mnt/hdd/backup_bitcoin" ]; then
    echo "# Copying back bitcoin backup data .."
    sudo mkdir -p /mnt/app-data/bitcoin
    sudo chown -R bitcoin:bitcoin /mnt/hdd/app-data/bitcoin
    sudo cp /mnt/hdd/backup_bitcoin/bitcoin.conf /mnt/hdd/app-data/bitcoin/bitcoin.conf
    sudo cp /mnt/hdd/backup_bitcoin/wallet.dat /mnt/hdd/app-data/bitcoin/wallet.dat  2>/dev/null
    rm -rf /mnt/hdd/backup_bitcoin
  fi

  # make sure all imported data is linked correctly (also moves old data layouts)
  sudo /home/admin/config.scripts/blitz.data.sh link

  #4073 if migration is imported on VM - make sure to set displayClass to headless
  source /home/admin/raspiblitz.info
  if [ "${vm}" == "1" ]; then
    /home/admin/config.scripts/blitz.conf.sh set displayClass "headless"
  fi

  # correcting all user rights on data will be done by provisioning process
  echo "# OK import done - provisioning process needed"
  exit 0
fi

echo "error='unkown command'"
exit 1
