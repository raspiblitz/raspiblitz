#!/bin/bash

# TODO: check if services/apps are running and stop all ... or let thet to outside?

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# managing the RaspiBlitz data - import, export, backup."
 echo "# blitz.migration.sh [status|export|import|export-gui|import-gui]"
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

# gathering system info
isBTRFS=$(lsblk -o FSTYPE,MOUNTPOINT | grep /mnt/hdd | awk '$1=$1' | cut -d " " -f 1 | grep -c btrfs)

# set place where zipped TAR file gets stored
defaultZipPath="/mnt/hdd/temp"

# SCP download and upload links
localip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0|veth' | grep 'inet'| tail -n1 | awk '{print $2}' | cut -f1 -d'/')
scpDownload="scp -r 'bitcoin@${localip}:${defaultZipPath}/raspiblitz-*.tar.gz' ./"
scpUpload="scp -r './raspiblitz-*.tar.gz bitcoin@${localip}:${defaultZipPath}'"

# output status data & exit
if [ "$1" = "status" ]; then
  echo "# RASPIBLITZ Data Import & Export"
  echo "isBTRFS=${isBTRFS}"
  echo "scpDownload=\"${scpDownload}\""
  echo "scpUpload=\"${scpUpload}\""
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
  rm -f /hdd/temp/raspiblitz-*.tar.gz 2>/dev/null

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
  sudo tar -zcvf ${defaultZipPath}/raspiblitz-export-temp.tar.gz -X ~/.exclude.temp /mnt/hdd 1>~/.include.temp 2>/dev/null

  # get md5 checksum
  echo "# Building checksum (can take also a while) ..." 
  md5checksum=$(md5sum ${defaultZipPath}/raspiblitz-export-temp.tar.gz | head -n1 | cut -d " " -f1)
  echo "# md5checksum=${md5checksum}"
  
  # final renaming 
  name="raspiblitz${blitzname}${datestamp}-${md5checksum}.tar.gz"
  echo "exportpath='${defaultZipPath}'"
  echo "filename='${name}'"
  sudo mv ${defaultZipPath}/raspiblitz-export-temp.tar.gz ${defaultZipPath}/${name}
  sudo chown bitcoin:bitcoin ${defaultZipPath}/${name}

  # delete temp files
  rm ~/.exclude.temp
  rm ~/.include.temp
  
  echo "scpDownload=\"${scpDownload}\""
  echo "# OK - Export done"
  exit 0
fi

if [ "$1" = "export-gui" ]; then

  # cleaning old migration files from blitz
  sudo rm ${defaultZipPath}/*.tar.gz

  # stopping lnd / bitcoin
  echo "--> stopping services ..."
  sudo systemctl stop lnd
  sudo systemctl stop bitcoind

  # create new migration file
  clear
  echo "--> creating blitz migration file ... (please wait)"
  source <(sudo /home/admin/config.scripts/blitz.migration.sh "export")
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
  echo "ON YOUR LAPTOP - RUN IN NEW TERMINAL:"
  echo "${scpDownload}"
  echo ""
  echo "Use password A to authenticate file transfer."
  echo
  echo "Your Lightning node is now stopped. After download press ENTER to shutdown your raspiblitz."
  echo "To complete the data migration follow then instructions on the github FAQ."
  echo
  read key
  echo "Shutting down ...."
  sleep 4
  /home/admin/XXshutdown.sh
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
    echo "scpUpload=\"${scpUpload}\"" 
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
    echo "# Maybe transfer/upload failed?"
    echo "error='bad checksum'"
    exit 1
  fi

  echo "# Importing (overwrite) (can take some time) .."
  sudo tar -xf ${importFile} -C /

  # copy bitcoin/litecoin data backups back to orgplaces (if part of backup)
  if [ -d "/mnt/hdd/backup_bitcoin" ]; then
    echo "# Copying back bitcoin backup data .."
    sudo mkdir /mnt/hdd/bitcoin
    sudo cp /mnt/hdd/backup_bitcoin/bitcoin.conf /mnt/hdd/bitcoin/bitcoin.conf
    sudo cp /mnt/hdd/backup_bitcoin/wallet.dat /mnt/hdd/bitcoin/wallet.dat  2>/dev/null
    sudo chown bitcoin:bitcoin -R /mnt/hdd/bitcoin
  fi
  if [ -d "/mnt/hdd/backup_litecoin" ]; then
    echo "# Copying back litecoin backup data .."
    sudo mkdir /mnt/hdd/litecoin
    sudo cp /mnt/hdd/backup_litecoin/litecoin.conf /mnt/hdd/litecoin/litecoin.conf
    sudo cp /mnt/hdd/backup_litecoin/wallet.dat /mnt/hdd/litecoin/wallet.dat  2>/dev/null
    sudo chown bitcoin:bitcoin -R /mnt/hdd/litecoin
  fi

  echo "# OK done - you may now want to:"
  echo "# make sure that HDD is not registered in /etc/fstab & reboot"
  echo "# to kickstart recovering system based in imported data"

  exit 0
fi

if [ "$1" = "import-gui" ]; then

  # get info about HDD
  source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)

  # make sure HDD/SSD is not mounted
  # because importing migration just works during early setup
  if [ ${isMounted} -eq 1 ]; then
    echo "FAIL --> cannot import migration data when HDD/SSD is mounted"
    exit 1
  fi

  # make sure a HDD/SSD is connected
  if [ ${#hddCandidate} -eq 0 ]; then
    echo "FAIL --> there is no HDD/SSD connected to migrate data to"
    exit 1
  fi

  # check if HDD/SSD is big enough
  if [ ${hddGigaBytes} -lt 120 ]; then
    echo "FAIL --> connected HDD/SSD is too small"
    exit 1
  fi



  # ask format for new HDD/SSD
  OPTIONS=()
  # check if HDD/SSD contains Bitcoin Blockchain
  if [ "${hddBlocksBitcoin}" == "1" ]; then 
    OPTIONS+=(KEEP "Dont format & use Blockchain")
  fi
  OPTIONS+=(EXT4 "Ext4 & 1 Partition (default)")
  OPTIONS+=(BTRFS "BTRFS & 3 Partitions (experimental)")

  useBlockchain=0
  CHOICE=$(whiptail --clear --title "Formatting ${hddCandidate}" --menu "" 10 52 3 "${OPTIONS[@]}" 2>&1 >/dev/tty)
  clear
  case $CHOICE in
    EXT4)
      echo "EXT4 FORMAT -->"
      source <(sudo /home/admin/config.scripts/blitz.datadrive.sh format ext4 ${hddCandidate})
      if [ ${#error} -gt 0 ]; then
        echo "FAIL --> ${error}"
        exit 1
      fi
      ;;
    BTRFS)
      echo "BTRFS FORMAT"
      source <(sudo /home/admin/config.scripts/blitz.datadrive.sh format btrfs ${hddCandidate})
      if [ ${#error} -gt 0 ]; then
        echo "FAIL --> ${error}"
        exit 1
      fi
      ;;
    KEEP)
      echo "Keep HDD & Blockchain"
      useBlockchain=1
      ;;
    *)
      echo "CANCEL"
      exit 0
      ;;
  esac

  # now temp mount the HDD/SSD
  source <(sudo /home/admin/config.scripts/blitz.datadrive.sh tempmount ${hddPartitionCandidate})
  if [ ${#error} -gt 0 ]; then
    echo "FAIL: Was not able to temp mount the HDD/SSD --> ${error}"
    exit 1
  fi

  # make sure that temp directory exists and can be written by admin
  sudo mkdir -p ${defaultZipPath}
  sudo chmod 777 -R ${defaultZipPath}

  clear
  echo
  echo "*****************************"
  echo "* UPLOAD THE MIGRATION FILE *"
  echo "*****************************"
  echo "If you have a migration file on your laptop you can now"
  echo "upload it and restore on the new HDD/SSD."
  echo
  echo "ON YOUR LAPTOP open a new terminal and change into"
  echo "the directory where your migration file is and"
  echo "COPY, PASTE AND EXECUTE THE FOLLOWING COMMAND:"
  echo "scp -r ./raspiblitz-*.tar.gz admin@${localip}:${defaultZipPath}"
  echo ""
  echo "Use password 'raspiblitz' to authenticate file transfer."
  echo "PRESS ENTER when upload is done."
  read key

  countZips=$(sudo ls ${defaultZipPath}/raspiblitz-*.tar.gz 2>/dev/null | grep -c 'raspiblitz-')

  # in case no upload found
  if [ ${countZips} -eq 0 ]; then
    echo
    echo "FAIL: Was not able to detect uploaded file in ${defaultZipPath}"
    exit 0
  fi

  # in case of multiple files
  if [ ${countZips} -gt 1 ]; then
    echo
    echo "FAIL: Multiple possible files detected in ${defaultZipPath}"
    exit 0
  fi

  # restore upload
  echo
  echo "OK: Upload found in ${defaultZipPath} - restoring data ... (please wait)"
  source <(sudo /home/admin/config.scripts/blitz.migration.sh "import")
  if [ ${#error} -gt 0 ]; then
    echo
    echo "FAIL: Was not able to restore data --> ${error}"
    exit 1
  fi
  
  # check & load config
  source /mnt/hdd/raspiblitz.conf
  if [ ${#network} -eq 0 ]; then
    echo
    echo "FAIL: No raspiblitz.conf found afer migration restore"
    exit 1
  fi

  echo
  echo "OK: Migration data was imported"

  # Copy from other computer is only option for Bitcoin
  if [ "${network}" == "bitcoin" ] && [ ${useBlockchain} -eq 0 ]; then
    OPTIONS=(SYNC "Re-Sync & Validate Blockchain" \
             COPY "Copy over LAN from other Computer"
	  )
    CHOICE=$(whiptail --clear --title "How to get Blockchain?" --menu "" 9 52 2 "${OPTIONS[@]}" 2>&1 >/dev/tty)
    clear
    case $CHOICE in
      COPY)
        echo "Copy Blockchain Data -->"
        /home/admin/50copyHDD.sh stop-after-script
        ;;
    esac
  fi

  # if there is no blockchain yet - fallback to syncing
  if [ $(sudo ls /mnt/hdd/bitcoin/ 2>/dev/null | grep -c blocks) -eq 0 ]; then
    echo "Setting Blockchain Data to resync ..."
    sudo -u bitcoin mkdir /mnt/hdd/${network}/blocks 2>/dev/null
    sudo -u bitcoin mkdir /mnt/hdd/${network}/chainstate 2>/dev/null
    sudo -u bitcoin touch /mnt/hdd/${network}/blocks/.selfsync
  fi

  echo "--> Now rebooting and kicking your node in to recovery/update mode ..."
  sudo shutdown -r now
  exit 0
fi

echo "error='unkown command'"
exit 1
