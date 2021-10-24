#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# Turns the RaspiBlitz into HDD CopyStation Mode"
 echo "# lightning is deactivated during CopyStationMode"
 echo "# reboot RaspiBlitz to set back to normal mode"
 exit 1
fi

####### CONFIG #############

# where to find the BITCOIN data directory (no trailing /)
pathBitcoinBlockchain="/mnt/hdd/bitcoin"

# where to find the RaspiBlitz HDD template directory (no trailing /)
pathTemplateHDD="/mnt/hdd/app-storage/templateHDD"

####### SCRIPT #############

# check sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (with sudo)"
  exit 1
fi

# get HDD info
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)

# check if HDD is mounted
if [ ${isMounted} -eq 0 ]; then
  echo "error='HDD is not mounted'"
  exit 1
fi

# check if HDD is big enough
if [ ${hddGigaBytes} -lt 800 ]; then
  echo "# To run copy station (+/- 1TB needed)"
  echo "error='HDD is too small'"
  exit 1
fi

# check that path information is valid
if [ -d "$pathBitcoinBlockchain" ]; then
  echo "# OK found $pathBitcoinBlockchain"
else
  echo "# FAIL path of 'pathBitcoinBlockchain' does not exists: ${pathBitcoinBlockchain}"
  echo "error='pathBitcoinBlockchain not found'"
  exit 1
fi

# make sure that its running in screen
# call with '-foreground' to prevent running in screen
if [ "$1" != "-foreground" ]; then 
  screenPID=$(screen -ls | grep "copystation" | cut -d "." -f1 | xargs)
  if [ ${#screenPID} -eq 0 ]; then
    # start copystation in screen 
    echo "# starting copystation screen session"
    screen -S copystation -dm /home/admin/XXcopyStation.sh -foreground
    screen -d -r
    exit 0
  else
    echo "# changing into running copystation screen session"
    screen -d -r
    exit 0
  fi
fi

clear
echo "# ******************************"
echo "# RASPIBLITZ COPYSTATION SCRIPT"
echo "# ******************************"
echo
echo "Make sure that no target HDD/SSDs are not connected yet .."
echo
sudo sed -i "s/^state=.*/state=copystation/g" /home/admin/raspiblitz.info 2>/dev/null
sleep 10

echo "*** CHECKING CONFIG"

# check that path information is valid
if [ -d "$pathTemplateHDD" ]; then
  echo "# OK found $pathTemplateHDD"
else
  echo "# Creating: ${pathTemplateHDD}"
  mkdir ${pathTemplateHDD}
  chmod 777 ${pathTemplateHDD}
fi

# make sure that lnd is stopped (if running)
systemctl stop lnd 2>/dev/null
systemctl stop background 2>/dev/null

# finding system drives (the drives that should not be synced to)
echo "# OK - the following drives detected as the system drive: $datadisk"
echo

# BASIC IDEA:
# 1. get fresh data from bitcoind --> template data
# 2. detect HDDs
# 3. sync HDDs with template data
# repeat

echo 
echo "*** RUNNING ***"
lastBlockchainUpdateTimestamp=1
firstLoop=1

while :
do

  hddsInfoString=""
  
  ################################################
  # 1. get fresh data from bitcoind for template data (skip on first loop)

  # only execute every 30min
  nowTimestamp=$(date +%s)
  secondsDiff=$(echo "${nowTimestamp}-${lastBlockchainUpdateTimestamp}" | bc)
  echo "# seconds since last update from bitcoind: ${secondsDiff}"
  echo

  if [ ${secondsDiff} -gt 3000 ]; then
  
    echo "******************************"
    echo "Bitcoin Blockchain Update"
    echo "******************************"

    # stop blockchains
    echo "# Stopping Blockchain ..."
    systemctl stop bitcoind 2>/dev/null
    sleep 10

    # sync bitcoin
    echo "# Syncing Bitcoin to template folder ..."

    sed -i "s/^message=.*/message='Updating Template: Bitcoin'/g" /home/admin/raspiblitz.info 2>/dev/null

    # make sure the bitcoin directory in template folder exists
    if [ ! -d "$pathTemplateHDD/bitcoin" ]; then
      echo "# creating the bitcoin subfolder in the template folder"
      mkdir ${pathTemplateHDD}/bitcoin
      chmod 777 ${pathTemplateHDD}/bitcoin
    fi

    # do the sync to the template folder for BITCOIN
    rsync -a --info=progress2 --delete ${pathBitcoinBlockchain}/chainstate ${pathBitcoinBlockchain}/blocks ${pathTemplateHDD}/bitcoin

    # restart bitcoind (to let further setup while syncing HDDs)
    echo "# Restarting Blockchain ..."
    systemctl start bitcoind 2>/dev/null

    # update timer
    lastBlockchainUpdateTimestamp=$(date +%s)
  fi

  ################################################
  # 2. detect connected HDDs and loop thru them

  echo
  echo "**************************************"
  echo "SYNCING TEMPLATE -> CONNECTED HDD/SSDs"
  echo "**************************************"
  echo "NOTE: Only use to prepare fresh HDDs"

  sleep 4
  echo "" > ./.syncinfo.tmp
  lsblk -o NAME | grep "^[s|v]d" | while read -r detectedDrive ; do
    isSystemDrive=$(echo "${datadisk}" | grep -c "${detectedDrive}")
    if [ ${isSystemDrive} -eq 0 ]; then

      # remember that disks were found
      hddsInfoString="found-disks"

      # check if drives 1st partition is named BLOCKCHAIN & in EXT4 format
      isNamedBlockchain=$(lsblk -o NAME,FSTYPE,LABEL | grep "${detectedDrive}" | grep -c "BLOCKCHAIN")
      isFormatExt4=$(lsblk -o NAME,FSTYPE,LABEL | grep "${detectedDrive}" | grep -c "ext4")
      
      # init a fresh device
      if [ ${isNamedBlockchain} -eq 0 ] || [ ${isFormatExt4} -eq 0 ]; then

        echo
        echo "**************************************************************"
        echo "*** NEW EMPTY HDD FOUND ---> ${detectedDrive}"
        echo "isNamedBlockchain: ${isNamedBlockchain}"
        echo "isFormatExt4:" ${isFormatExt4}

        # check if size is OK
        size=$(lsblk -o NAME,SIZE -b | grep "^${detectedDrive}" | awk '$1=$1' | cut -d " " -f 2)
        echo "size: ${size}"
        if [ ${size} -lt 900000000000 ]; then
            echo "!! THE HDD/SSD IS TOO SMALL <900GB - use at least 1TB"
            sed -i "s/^message=.*/message='HDD smaller than 1TB: ${detectedDrive}'/g" /home/admin/raspiblitz.info 2>/dev/null
            echo
            sleep 10
        else

          choice=0
          sed -i "s/^message=.*/message='Formatting new HDD: ${detectedDrive}'/g" /home/admin/raspiblitz.info 2>/dev/null

          # format the HDD
          echo "Starting Formatting of device ${detectedDrive} ..."
          /home/admin/config.scripts/blitz.datadrive.sh format ext4 ${detectedDrive}
          sleep 4

        fi

      fi # end init new HDD

      ################################################
      # 3. sync HDD with template data (skip on first loop)

      partition=$(lsblk -o NAME,FSTYPE,LABEL | grep "${detectedDrive}" | grep "BLOCKCHAIN" | cut -d ' ' -f 1 | tr -cd "[:alnum:]")
      if [ "${firstLoop}" != "1" ] && [ ${#partition} -gt 0 ]; then

        # temp mount device
        echo "mounting: ${partition}"
        mkdir /mnt/hdd2 2>/dev/null
        mount -t ext4 /dev/${partition} /mnt/hdd2

        # rsync device
        mountOK=$(lsblk -o NAME,MOUNTPOINT | grep "${detectedDrive}" | grep -c "/mnt/hdd2")
        if [ ${mountOK} -eq 1 ]; then
          sed -i "s/^message=.*/message='${hddsInfoString} ${partition}>SYNC'/g" /home/admin/raspiblitz.info 2>/dev/null
          rsync -a --info=progress2 --delete ${pathTemplateHDD}/* /mnt/hdd2
          chmod -R 777 /mnt/hdd2
          rm -r /mnt/hdd2/lost+found 2>/dev/null
          hddsInfoString="${hddsInfoString} ${partition}>OK"
        else
          echo "# FAIL: was not able to mount --> ${partition}"
        fi
        
        # unmount device
        umount -l /mnt/hdd2
        
      fi

    fi
  done

  clear
  if [ "${hddsInfoString}" == "" ]; then

    echo "**** NO TARGET HDD/SSDs CONNECTED ****"
    echo
    echo "Best way to start a new batch:"
    echo "- Disconnect powered USB-Hub (best unplug USB cable at USB-Hub)"
    echo "- Connect all HDD/SSDs to the disconnected USB-Hub"
    echo "- Connect powered USB-Hub to Blitz (plug USB cable in)"
    echo "- During formatting remember names of physical HDD/SSDs"
    echo "- As soon as you see an OK for that HDD/SSD name you can remove it"
    sed -i "s/^message=.*/message='No target HDD/SSDs connected - connect USB Hub'/g" /home/admin/raspiblitz.info 2>/dev/null
    firstLoop=1

  else

    echo "**** SYNC LOOP DONE ****"
    echo "HDDs ready synced: ${hddsInfoString}"
    echo "*************************"
    echo
    echo "Its safe to disconnect/remove HDDs now."
    echo "To stop copystation script: CTRL+c and then 'restart'"
    sed -i "s/^message=.*/message='Ready HDDs: ${hddsInfoString}'/g" /home/admin/raspiblitz.info 2>/dev/null
    firstLoop=0

  fi 
  
  if [ "${hddsInfoString}" == "found-disks" ]; then
    # after script found discs and did formatting ... go into full loop
    firstLoop=0
  else
    echo
    echo "Next round starts in 25 seconds ..."
    echo "To stop copystation script: CTRL+c and then 'restart'"
    echo "You can close SSH terminal and script will run in background can can be re-entered."
    sleep 25
  fi

  clear
  echo "starting new sync loop"
  sleep 5
  
done
