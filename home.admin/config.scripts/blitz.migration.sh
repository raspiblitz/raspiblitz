#!/bin/bash

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# managing the RaspiBlitz data - import, export, backup."
 echo "# blitz.migration.sh [export|import|export-gui|migration-umbrel|migration-mynode|migration-citadel]"
 echo "error='missing parameters'"
 exit 1
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='missing sudo'"
  exit 1
fi

###################
# STATUS
###################

# check if data drive is mounted - other wise cannot operate
isMounted=$(sudo df | grep -c /mnt/hdd)

# set place where zipped TAR file gets stored
defaultUploadPath="/mnt/hdd/temp/migration"

# get local ip
source <(/home/admin/config.scripts/internet.sh status local)

# SCP download and upload links
scpDownloadUnix="scp -r 'bitcoin@${localip}:${defaultUploadPath}/raspiblitz-*.tar.gz' ./"
scpDownloadWin="scp -r bitcoin@${localip}:${defaultUploadPath}/raspiblitz-*.tar.gz ."
scpUploadUnix="scp -r ./raspiblitz-*.tar.gz bitcoin@${localip}:${defaultUploadPath}"
scpUploadWin="scp -r ./raspiblitz-*.tar.gz bitcoin@${localip}:${defaultUploadPath}"

# output status data & exit
if [ "$1" = "status" ]; then
  echo "# RASPIBLITZ Data Import & Export"
  echo "localip=\"${localip}\""
  echo "defaultUploadPath=\"${defaultUploadPath}\""
  echo "scpDownloadUnix=\"${scpDownloadUnix}\""
  echo "scpUploadUnix=\"${scpUploadUnix}\""
  echo "scpDownloadWin=\"${scpDownloadWin}\""
  echo "scpUploadWin=\"${scpUploadWin}\""
  exit 1
fi

########################
# MIGRATION BASICS
########################

migrate_btc_conf () {
  # keep old conf als backup
  sudo mv /mnt/hdd/bitcoin/bitcoin.conf /mnt/hdd/bitcoin/bitcoin.conf.migration
  # start from fresh configuration template 
  sudo cp /home/admin/assets/bitcoin.conf /mnt/hdd/bitcoin/bitcoin.conf
}

migrate_lnd_conf () { 

  # 1st parameter can be an alias to set
  nodename=$1
  if [ ${#nodename} -eq 0 ]; then
    nodename="raspiblitz"
  fi

  # keep old conf as backup
  sudo mv /mnt/hdd/lnd/lnd.conf /mnt/hdd/lnd/lnd.conf.migration
  # start from fresh configuration template (user will set password B on recovery)
  sudo cp /home/admin/assets/lnd.bitcoin.conf /mnt/hdd/lnd/lnd.conf
  sudo sed -i "s/^alias=.*/alias=${nodename}/g" /mnt/hdd/lnd/lnd.conf

  # make sure correct file permisions are set
  sudo chown bitcoin:bitcoin /mnt/hdd/lnd/lnd.conf
  sudo chmod 664 /mnt/hdd/lnd/lnd.conf

}

migrate_raspiblitz_conf () {

  # 1st parameter can be an nodename to set
  nodename=$1
  if [ ${#nodename} -eq 0 ]; then
    nodename="raspiblitz"
  fi
  
  # write default raspiblitz config
  source /home/admin/_version.info
  echo "# RASPIBLITZ CONFIG FILE" > /home/admin/raspiblitz.conf
  sudo mv /home/admin/raspiblitz.conf /mnt/hdd/raspiblitz.conf
  sudo chown root:sudo /mnt/hdd/raspiblitz.conf
  sudo chmod 664 /mnt/hdd/raspiblitz.conf

  /home/admin/config.scripts/blitz.conf.sh set raspiBlitzVersion "${codeVersion}"
  /home/admin/config.scripts/blitz.conf.sh set network "bitcoin"
  /home/admin/config.scripts/blitz.conf.sh set chain "main"
  /home/admin/config.scripts/blitz.conf.sh set hostname "${nodename}"
  /home/admin/config.scripts/blitz.conf.sh set displayClass "lcd"
  /home/admin/config.scripts/blitz.conf.sh set lcdrotate "1"
  /home/admin/config.scripts/blitz.conf.sh set runBehindTor "on"

  # rename ext4 data drive
  sudo e2label /dev/sda1 BLOCKCHAIN
}

########################
# MIGRATION from Umbrel
########################

if [ "$1" = "migration-umbrel" ]; then

  # make sure data drive is mounted
  source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
  if [ "${isMounted}" != "1" ]; then
    source <(sudo /home/admin/config.scripts/blitz.datadrive.sh tempmount)
  fi
  if [ "${isMounted}" == "1" ]; then
    echo "# mounted /mnt/hdd (hddFormat='${hddFormat}')"
  else
    echo "err='failed temp mounting disk'"
    exit 1
  fi

  # checking basic data disk layout
  if [ -f /mnt/hdd/umbrel/bitcoin/bitcoin.conf ] && [ -f /mnt/hdd/umbrel/lnd/lnd.conf ]; then
    echo "# found bitcoin & lnd data <0.5.0"
  elif [ "${hddVersionBTC}" != "" ] || [ "${hddVersionLND}" != "" ] || [ "${hddVersionCLN}" != "" ]; then
    echo "# found umbrel data >=0.5.0"
  else
    echo "err='umbrel data layout changed'"
    exit 1
  fi

  echo "# starting to rearrange the data drive for raspiblitz .."

  # determine version
  version=$(sudo cat /mnt/hdd/umbrel/info.json | jq -r '.version')
  if [ "${version}" == "" ]; then
    echo "err='not able to get version'"
    exit 1
  fi
  versionMajor=$(echo "${version}" | cut -d "." -f1)
  versionMiner=$(echo "${version}" | cut -d "." -f2)
  versionPatch=$(echo "${version}" | cut -d "." -f3)
  if [ "${versionMajor}" == "" ] || [ "${versionMiner}" == "" ] || [ "${versionPatch}" == "" ]; then
    echo "err='not able processing version'"
    exit 1
  fi

  # since 0.3.9 umbrel uses a fixed/default password for lnd wallet (before it was the user set one)
  if [ ${versionMajor} -eq 0 ] && [ ${versionMiner} -lt 4 ] && [ ${versionPatch} -lt 9 ]; then
    echo "# umbrel before 0.3.9 --> password c is old user set password"
  else
    echo "# umbrel 0.3.9 or higher --> password c is fixed 'moneyprintergobrrr'"
    # set flag with standard password to be changed on final recovery setup
    sudo touch /mnt/hdd/passwordc.flag
    sudo chmod 777 /mnt/hdd/passwordc.flag
    echo "moneyprintergobrrr" >> /mnt/hdd/passwordc.flag
    sudo chown admin:admin /mnt/hdd/passwordc.flag
  fi

  # extract detailed data
  nameNode=$(sudo jq -r '.name' /mnt/hdd/umbrel/db/user.json)

  # call function for final migration
  migrate_raspiblitz_conf ${nameNode}

  # move bitcoin/blockchain & call function to migrate config
  sudo mv /mnt/hdd/bitcoin /mnt/hdd/backup_bitcoin 2>/dev/null
  sudo mv /mnt/hdd/umbrel/bitcoin /mnt/hdd/
  sudo rm /mnt/hdd/bitcoin/.walletlock 2>/dev/null
  sudo chown bitcoin:bitcoin -R /mnt/hdd/bitcoin
  migrate_btc_conf

  # CORE LIGHTNING since 0.5.0 umbrel has core lightning
  echo "### CORE LIGHTNING ###"
  if [ ${versionMajor} -eq 0 ] && [ ${versionMiner} -gt 4 ]; then
    clnExists=$(sudo ls /mnt/hdd/umbrel/app-data/lightning/data/lnd/lnd.conf | grep -c "lnd.conf")
    if [ "${clnExists}" == "1" ]; then 
      echo "# moving cln data >=0.5.0"
      sudo mv /mnt/hdd/app-data/.lightning /mnt/hdd/app-data/backup_lightning 2>/dev/null
      sudo mkdir /mnt/hdd/app-data/.lightning 2>/dev/null
      sudo mv /mnt/hdd/umbrel/app-data/core-lightning/data/lightningd/bitcoin /mnt/hdd/app-data/.lightning/
      sudo chown bitcoin:bitcoin -R /mnt/hdd/app-data/.lightning
      /home/admin/config.scripts/blitz.conf.sh set cl on
      /home/admin/config.scripts/blitz.conf.sh set lightning "cl"
    else
      echo "# no cln data found >=0.5.0"
    fi
  else
    echo "# no core lightning <0.5.0"
  fi

  # LND since 0.5.0 umbrel uses a different data structure
  echo "### LND ###"
  if [ ${versionMajor} -eq 0 ] && [ ${versionMiner} -gt 4 ]; then
    # new way - lnd might even not exist because its optional 
    lndExists=$(sudo ls /mnt/hdd/umbrel/app-data/lightning/data/lnd/lnd.conf | grep -c "lnd.conf")
    if [ "${lndExists}" == "1" ]; then
      echo "# moving lnd data >=0.5.0"
      sudo mv /mnt/hdd/lnd /mnt/hdd/backup_lnd 2>/dev/null
      sudo mv /mnt/hdd/umbrel/app-data/lightning/data/lnd /mnt/hdd/
      sudo chown bitcoin:bitcoin -R /mnt/hdd/lnd 
      migrate_lnd_conf ${nameNode}
      /home/admin/config.scripts/blitz.conf.sh set lnd on
      /home/admin/config.scripts/blitz.conf.sh set lightning "lnd"
    else
      echo "# no lnd data found >=0.5.0"
    fi
  else
    echo "# moving old lnd data <0.5.0"
    sudo mv /mnt/hdd/lnd /mnt/hdd/backup_lnd 2>/dev/null
    sudo mv /mnt/hdd/umbrel/lnd /mnt/hdd/
    sudo chown bitcoin:bitcoin -R /mnt/hdd/lnd
    migrate_lnd_conf ${nameNode}
    /home/admin/config.scripts/blitz.conf.sh set lnd on
    /home/admin/config.scripts/blitz.conf.sh set lightning "lnd"
  fi

  # backup & rename the rest of the data
  sudo mv /mnt/hdd/umbrel /mnt/hdd/backup_migration

  echo "# OK ... data disk converted to RaspiBlitz"
  exit 0
fi

########################
# MIGRATION from Citadel
########################

if [ "$1" = "migration-citadel" ]; then

  # make sure data drive is mounted
  source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
  if [ "${isMounted}" != "1" ]; then
    source <(sudo /home/admin/config.scripts/blitz.datadrive.sh tempmount)
  fi
  if [ "${isMounted}" == "1" ]; then
    echo "# mounted /mnt/hdd (hddFormat='${hddFormat}')"
  else
    echo "err='failed temp mounting disk'"
    exit 1
  fi

  # checking basic data disk layout
  if [ -f /mnt/hdd/citadel/bitcoin/bitcoin.conf ] && [ -f /mnt/hdd/citadel/lnd/lnd.conf ]; then
    echo "# found bitcoin & lnd data"
  else
    echo "err='citadel data layout changed'"
    exit 1
  fi

  echo "# starting to rearrange the data drive for raspiblitz .."

  # determine version
  version=$(sudo cat /mnt/hdd/citadel/info.json | jq -r '.version')
  if [ "${version}" == "" ]; then
    echo "err='not able to get version'"
    exit 1
  fi
  versionMajor=$(echo "${version}" | cut -d "." -f1)
  versionMiner=$(echo "${version}" | cut -d "." -f2)
  versionPatch=$(echo "${version}" | cut -d "." -f3)
  if [ "${versionMajor}" == "" ] || [ "${versionMiner}" == "" ] || [ "${versionPatch}" == "" ]; then
    echo "err='not able processing version'"
    exit 1
  fi

  # set flag with standard password to be changed on final recovery setup
  sudo touch /mnt/hdd/passwordc.flag
  sudo chmod 777 /mnt/hdd/passwordc.flag
  echo "moneyprintergobrrr" >> /mnt/hdd/passwordc.flag
  sudo chown admin:admin /mnt/hdd/passwordc.flag

  # extract detailed data
  nameNode=$(sudo jq -r '.name' /mnt/hdd/citadel/db/user.json)

  # move bitcoin/blockchain & call function to migrate config
  sudo mv /mnt/hdd/bitcoin /mnt/hdd/backup_bitcoin 2>/dev/null
  sudo mv /mnt/hdd/citadel/bitcoin /mnt/hdd/
  sudo rm /mnt/hdd/bitcoin/.walletlock 2>/dev/null
  sudo chown bitcoin:bitcoin -R /mnt/hdd/bitcoin
  migrate_btc_conf

  # move lnd & call function to migrate config
  sudo mv /mnt/hdd/lnd /mnt/hdd/backup_lnd 2>/dev/null
  sudo mv /mnt/hdd/citadel/lnd /mnt/hdd/
  sudo chown bitcoin:bitcoin -R /mnt/hdd/lnd
  migrate_lnd_conf ${nameNode}

  # backup & rename the rest of the data
  sudo mv /mnt/hdd/citadel /mnt/hdd/backup_migration

  # call function for final migration
  migrate_raspiblitz_conf ${nameNode}

  echo "# OK ... data disk converted to RaspiBlitz"
  exit 0
fi

########################
# MIGRATION from myNode
# see manual steps: https://btc21.de/bitcoin/raspiblitz-migration/
########################

if [ "$1" = "migration-mynode" ]; then

  # make sure data drive is mounted
  source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
  if [ "${isMounted}" != "1" ]; then
    source <(sudo /home/admin/config.scripts/blitz.datadrive.sh tempmount)
  fi
  if [ "${isMounted}" == "1" ]; then
    echo "# mounted /mnt/hdd (hddFormat='${hddFormat}')"
  else
    echo "err='failed temp mounting disk'"
    exit 1
  fi

  # checking basic data disk layout
  if [ -f /mnt/hdd/mynode/bitcoin/bitcoin.conf ] && [ -f /mnt/hdd/mynode/lnd/lnd.conf ]; then
    echo "# found bitcoin & lnd data"
  else
    echo "err='mynode data layout changed'"
    exit 1
  fi

  echo "# starting to rearrange the data drive for raspiblitz .."

  # move bitcoin/blockchain & call function to migrate config
  sudo mv /mnt/hdd/bitcoin /mnt/hdd/backup_bitcoin 2>/dev/null
  sudo mv /mnt/hdd/mynode/bitcoin /mnt/hdd/
  sudo chown bitcoin:bitcoin -R /mnt/hdd/bitcoin
  migrate_btc_conf

  # move lnd & call function to migrate config
  sudo mv /mnt/hdd/lnd /mnt/hdd/backup_lnd 2>/dev/null
  sudo mv /mnt/hdd/mynode/lnd /mnt/hdd/
  sudo chown bitcoin:bitcoin -R /mnt/hdd/lnd
  migrate_lnd_conf

  # copy lnd wallet password - so that user can set own on final setup
  sudo cp /mnt/hdd/mynode/settings/.lndpw /mnt/hdd/passwordc.flag

  # backup & rename the rest of the data
  sudo mv /mnt/hdd/mynode /mnt/hdd/backup_migration

  # call function for final migration
  migrate_raspiblitz_conf

  echo "# OK ... data disk converted to RaspiBlitz"
  exit 0
fi

#########################
# EXPORT RaspiBlitz Data
#########################

if [ "$1" = "export" ]; then

  echo "# RASPIBLITZ DATA --> EXPORT"

  # collect files to exclude in export in temp file
  echo "*.tar.gz" > ~/.exclude.temp
  echo "/mnt/hdd/bitcoin" >> ~/.exclude.temp 
  echo "/mnt/hdd/litecoin" >> ~/.exclude.temp # keep for legacy reasons
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

  # clean old backups from temp
  rm -f /hdd/temp/raspiblitz-*.tar.gz 2>/dev/null

  # get date stamp
  datestamp=$(date "+%y-%m-%d-%H-%M")
  echo "# datestamp=${datestamp}"

  # get name of RaspiBlitz from config (optional if exists)
  blitzname="-"
  source /mnt/hdd/raspiblitz.conf 2>/dev/null
  if [ ${#hostname} -gt 0 ]; then
    blitzname="-${hostname}-"
  fi
  echo "# blitzname=${blitzname}"

  # zip it
  echo "# Building the Export File (this can take some time) .."
  sudo mkdir -p ${defaultUploadPath}
  sudo tar -zcvf ${defaultUploadPath}/raspiblitz-export-temp.tar.gz -X ~/.exclude.temp /mnt/hdd 1>~/.include.temp 2>/dev/null

  # get md5 checksum
  echo "# Building checksum (can take a while) ..." 
  md5checksum=$(md5sum ${defaultUploadPath}/raspiblitz-export-temp.tar.gz | head -n1 | cut -d " " -f1)
  echo "md5checksum=${md5checksum}"
  
  # get byte size
  bytesize=$(wc -c ${defaultUploadPath}/raspiblitz-export-temp.tar.gz | cut -d " " -f 1)
  echo "bytesize=${bytesize}"

  # final renaming 
  name="raspiblitz${blitzname}${datestamp}-${md5checksum}.tar.gz"
  echo "exportpath='${defaultUploadPath}'"
  echo "filename='${name}'"
  sudo mv ${defaultUploadPath}/raspiblitz-export-temp.tar.gz ${defaultUploadPath}/${name}
  sudo chown bitcoin:bitcoin ${defaultUploadPath}/${name}

  # delete temp files
  rm ~/.exclude.temp
  rm ~/.include.temp
  
  echo "scpDownloadUnix=\"${scpDownloadUnix}\""
  echo "scpDownloadWin=\"${scpDownloadWin}\""  
  echo "# OK - Export done"
  exit 0
fi

if [ "$1" = "export-gui" ]; then

  # cleaning old migration files from blitz
  sudo rm ${defaultUploadPath}/*.tar.gz 2>/dev/null

  echo "--> stopping services ..."
  source /mnt/hdd/raspiblitz.conf
  # bitcoind
  sudo systemctl stop bitcoind
  if [ "${testnet}" == "on" ] || [ "${cl}" == "1" ]; then
    sudo systemctl stop tbitcoind
  fi
  if [ "${signet}" == "on" ] || [ "${tcl}" == "1" ]; then
    sudo systemctl stop sbitcoind
  fi
  # lnd
  if [ "${lnd}" == "on" ] || [ "${lnd}" == "1" ]; then
    sudo systemctl stop lnd
  fi
  if [ "${tlnd}" == "on" ] || [ "${tlnd}" == "1" ]; then
    sudo systemctl stop tlnd
  fi
  if [ "${slnd}" == "on" ] || [ "${slnd}" == "1" ]; then
    sudo systemctl stop slnd
  fi
  # lightningd
  if [ "${cl}" == "on" ] || [ "${cl}" == "1" ]; then
    sudo systemctl stop lightningd
  fi
  if [ "${tcl}" == "on" ] || [ "${tcl}" == "1" ]; then
    sudo systemctl stop tlightningd
  fi
  if [ "${scl}" == "on" ] || [ "${scl}" == "1" ]; then
    sudo systemctl stop slightningd
  fi

  # create new migration file
  clear
  echo "--> creating blitz migration file ... (please wait)"
  source <(sudo /home/admin/config.scripts/blitz.migration.sh export)
  if [ ${#filename} -eq 0 ]; then
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
  echo "${scpDownloadUnix}"
  echo "On Windows use command:"
  echo "${scpDownloadWin}"
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
  /home/admin/config.scripts/blitz.shutdown.sh
  exit 0
fi

#########################
# IMPORT RaspiBlitz Data
#########################

if [ "$1" = "import" ]; then

  # BACKGROUND:
  # the migration import is only called during setup phase - assume a prepared but clean HDD

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

  echo "# Importing (overwrite) (can take some time) .."
  sudo tar -xf ${importFile} -C /
  if [ "$?" != "0" ]; then
    echo "error='non zero exit state of unzipping migration file'"
    echo "# reboot system ... HDD will offer fresh formating"
    exit 1
  fi

  # copy bitcoin data backups back to original places (if part of backup)
  if [ -d "/mnt/hdd/backup_bitcoin" ]; then
    echo "# Copying back bitcoin backup data .."
    sudo mkdir /mnt/hdd/bitcoin 2>/dev/null
    sudo cp /mnt/hdd/backup_bitcoin/bitcoin.conf /mnt/hdd/bitcoin/bitcoin.conf
    sudo cp /mnt/hdd/backup_bitcoin/wallet.dat /mnt/hdd/bitcoin/wallet.dat  2>/dev/null
    sudo chown bitcoin:bitcoin -R /mnt/hdd/bitcoin
    sudo chown bitcoin:bitcoin -R /mnt/storage/bitcoin 2>/dev/null
  fi

  # check migration 
  raspiblitzConfExists=$(sudo ls /mnt/hdd/raspiblitz.conf | grep -c "raspiblitz.conf")
  if [ "${raspiblitzConfExists}" != "1" ]; then
    echo "error='no raspiblitz.conf after unzip migration file'"
    echo "# reboot system ... HDD will offer fresh formating"
    exit 1
  fi

  # correcting all user rights on data will be done by provisioning process
  echo "# OK import done - provisioning process needed"
  exit 0
fi

echo "error='unkown command'"
exit 1
