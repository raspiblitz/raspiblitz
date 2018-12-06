#!/bin/bash

# This script runs on every start calles by boostrap.service
# It makes sure that the system is configured like the
# default values or as in the config.
# For more details see background_raspiblitzSettings.md

# load codeVersion
source /home/admin/_version.info

################################
# FILES TO WORK WITH
################################

# CONFIGFILE - configuration of RaspiBlitz
# used by fresh SD image to recover configuration
# and delivers basic config info for scripts 
configFile="/mnt/hdd/raspiblitz.conf"

# LOGFILE - store debug logs of bootstrap
# resets on every start
logFile="/home/admin/raspiblitz.log"

# INFOFILE - state data from bootstrap
# used by display and later setup steps
infoFile="/home/admin/raspiblitz.info"

echo "Writing logs to: ${logFile}"
echo "" > $logFile
echo "***********************************************" >> $logFile
echo "Running RaspiBlitz Bootstrap ${codeVersion}" >> $logFile
date >> $logFile
echo "***********************************************" >> $logFile

echo "Resetting the InfoFile: ${infoFile}"
echo "state=starting" > $infoFile
sudo chmod 777 ${infoFile}

################################
# AFTER BOOT SCRIPT
# when a process needs to 
# execute stuff after a reboot
# it should in file
# /home/admin/setup.sh
################################

# check for after boot script
afterSetupScriptExists=$(ls /home/admin/setup.sh 2>/dev/null | grep -c setup.sh)
if [ ${afterSetupScriptExists} -eq 1 ]; then
  echo "*** SETUP SCRIPT DETECTED ***"
  # echo out script to journal logs
  sudo cat /home/admin/setup.sh
  # execute the after boot script
  sudo /home/admin/setup.sh
  # delete the after boot script
  sudo rm /home/admin/setup.sh
  # reboot again
  echo "DONE wait 6 secs ... one more reboot needed ... "
  sudo shutdown -r now
  sleep 100
fi


################################
# PUBLIC IP
# for LND on startup
################################
printf "PUBLICIP=$(curl -vv ipinfo.io/ip 2> /run/publicip.log)\n" > /run/publicip;
chmod 774 /run/publicip


################################
# HDD CHECK & PRE-INIT
################################
 
# waiting for HDD to connect
hddExists=$(lsblk | grep -c sda1)
while [ ${hddExists} -eq 0 ]
  do
    # display will ask user to connect a HDD
    echo "state=nohdd" > $infoFile
    echo "message='Connect the Hard Drive'" >> $infoFile
    sleep 5
    # retry to find HDD
    hddExists=$(lsblk | grep -c sda1)
  done

# check if the HDD is auto-mounted
hddIsAutoMounted=$(lsblk | grep -c '/mnt/hdd')
if [ ${hddIsAutoMounted} -eq 0 ]; then

  echo "HDD is there but not AutoMounted yet." >> $logFile
  echo "Analysing the situation ..." >> $logFile

  # detect for correct device name (the biggest partition)
  hddDeviceName="sda1"
  hddSecondPartitionExists=$(lsblk | grep -c sda2)
  if [ ${hddSecondPartitionExists} -eq 1 ]; then
    echo "HDD has a second partition - choosing the bigger one ..." >> $logFile
    # get both with size
    size1=$(lsblk -o NAME,SIZE -b | grep "sda1" | awk '{ print substr( $0, 12, length($0)-2 ) }' | xargs)
    echo "sda1(${size1})" >> $logFile
    size2=$(lsblk -o NAME,SIZE -b | grep "sda2" | awk '{ print substr( $0, 12, length($0)-2 ) }' | xargs)
    echo "sda2(${size2})" >> $logFile
    # chosse to run with the bigger one
    if [ ${size2} -gt ${size1} ]; then
      echo "sda2 is BIGGER - run with this one" >> $logFile
      hddDeviceName="sda2"
    else
      echo "sda1 is BIGGER - run with this one" >> $logFile
      hddDeviceName="sda1"
    fi
  fi

  # check if HDD is formatted EXT4
  hddExt4=$(lsblk -o NAME,FSTYPE -b /dev/${hddDeviceName} | grep -c "ext4")
  if [ ${hddExt4} -eq 0 ]; then
    echo "HDD is NOT formatted in ext4." >> $logFile
    # stop the bootstrap here ...
    # display will ask user to run setup
    echo "state=waitsetup" > $infoFile
    echo "message='HDD needs SetUp (1)'" >> $infoFile
    echo "device=${hddDeviceName}" >> $infoFile
    exit 1
  fi

  # temp-mount the HDD
  echo "temp-mounting the HDD .." >> $logFile
  sudo mkdir /mnt/hdd
  sudo mount -t ext4 /dev/${hddDeviceName} /mnt/hdd
  mountOK=$(lsblk | grep -c '/mnt/hdd')
  if [ ${mountOK} -eq 0 ]; then
    echo "FAIL - not able to temp-mount HDD" >> $logFile
    echo "state=waitsetup" > $infoFile
    echo "message='HDD failed Mounting'" >> $infoFile
    echo "device=${hddDeviceName}" >> $infoFile
    # no need to unmount the HDD, it failed mounting
    exit 1
  else 
     echo "OK - HDD available under /mnt/hdd" >> $logFile
  fi

  # check if HDD contains already a configuration
  echo "Check if HDD contains already a configuration .." >> $logFile
  configExists=$(ls ${configFile} | grep -c '.conf')
  if [ ${configExists} -eq 1 ]; then
    // TODO: Migration and Recover
    echo "Found existing configuration - TODO migration and recover!" >> $logFile
    echo "state=recovering" > $infoFile
    echo "message='TODO: migration and recover'" >> $infoFile
    echo "device=${hddDeviceName}" >> $infoFile
    # unmountig the HDD at the end of the process
    sudo umount -l /mnt/hdd
    exit 1
  else 
    echo "OK - No config file found: ${configFile}" >> $logFile
  fi

  # check if HDD cointains existing LND data (old RaspiBlitz Version)
  echo "Check if HDD contains existing LND data .." >> $logFile
  lndDataExists=$(ls /mnt/hdd/lnd/lnd.conf | grep -c '.conf')
  if [ ${lndDataExists} -eq 1 ]; then
    echo "Found existing LND data - old RaspiBlitz?" >> $logFile
    echo "state=olddata" > $infoFile
    echo "message='No Auto-Update possible'" >> $infoFile
    echo "device=${hddDeviceName}" >> $infoFile
    # keep HDD mounted if user wants to copy data
    exit 1
  else 
    echo "OK - No LND data found" >> $logFile
  fi

  # check if HDD contains pre-loaded blockchain data (just bitcoin for now)
  echo "Check if HDD contains pre-loaded blockchain data .." >> $logFile
  blockchainDataExists=$(ls /mnt/hdd/bitcoin/blocks/blk00000.dat 2>/dev/null | grep -c '.dat')
  if [ ${blockchainDataExists} -eq 1 ]; then

    # update info file
    echo "state=presync" > $infoFile
    echo "message='starting pre-sync'" >> $infoFile
    echo "device=${hddDeviceName}" >> $infoFile

    # activating presync
    # so that on a hackathon you can just connect a RaspiBlitz
    # to the network and have it up-to-date for setting up
    echo "Found pre-loaded blockchain" >> $logFile

    # check if pre-sync was already activated on last power-on
    #presyncActive=$(systemctl status bitcoind | grep -c 'could not be found')
    echo "starting pre-sync in background" >> $logFile
    # starting in background, because this scripts is part of systemd
    # so to change systemd needs to happen after delay in seperate process
    /home/admin/_bootstrap.presync.sh &
    echo "done" >> $logFile

    # after admin login, presync will be stoped and HDD unmounted
    exit 1
  
  else
    ls /mnt/hdd/bitcoin/blocks/blk00000.dat >> $logFile
    echo "OK - No blockchain data found" >> $logFile
  fi

  # if it got until here: HDD is empty ext4
  echo "Waiting for SetUp." >> $logFile
  echo "state=waitsetup" > $infoFile
  echo "message='HDD needs SetUp (2)'" >> $infoFile
  echo "device=${hddDeviceName}" >> $infoFile
  # unmount HDD to be ready for auto-mount during setup
  sudo umount -l /mnt/hdd
  exit 1

fi

################################
# INFOFILE BASICS
################################

# init network and chain values if needed with defaults
valueExists=$(sudo cat /home/admin/raspiblitz.info 2>/dev/null | grep -c "network=")
if [ ${valueExists} -eq 0 ]; then
  echo "network=bitcoin" >> /home/admin/raspiblitz.info
fi
valueExists=$(sudo cat /home/admin/raspiblitz.info 2>/dev/null | grep -c "chain=")
if [ ${valueExists} -eq 0 ]; then
  echo "chain=main" >> /home/admin/raspiblitz.info
fi

# EXIT on BOOTSTRAP HERE AT THE MOMENT
echo "DONE BOOTSTRAP (before any configs etc)" >> $logFile
echo "state=ready" > $infoFile
exit 0