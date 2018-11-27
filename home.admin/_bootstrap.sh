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
sudo chmod 745 ${infoFile}

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
hddIsAutoMounted=$(ls -la /mnt/hdd 2>/dev/null)
if [ ${#hddIsAutoMounted} -eq 0 ]; then

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
  hddExt4=$(df -T /dev/${hddDeviceName} | grep -c "ext4")
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
  mountOK=$(df | grep -c /mnt/hdd)
  if [ ${mountOK} -eq 0 ]; then
    echo "FAIL - not able to temp-mount HDD" >> $logFile
    echo "state=waitsetup" > $infoFile
    echo "message='HDD failed Mounting'" >> $infoFile
    echo "device=${hddDeviceName}" >> $infoFile
    exit 1
  else 
     echo "OK - HDD available under /mnt/hdd" >> $logFile
  fi

  # check if HDD contains already a configuration
  echo "Check if HDD contains already a configuration .." >> $logFile
  configExists=$(ls ${configFile} 2>/dev/null | grep -c '.conf')
  if [ ${configExists} -eq 1 ]; then
    // TODO: Migration and Recover
    echo "Found existing configuration - TODO migration and recover!" >> $logFile
    echo "state=recovering" > $infoFile
    echo "message='TODO: migration and recover'" >> $infoFile
    echo "device=${hddDeviceName}" >> $infoFile
    exit 1
  else 
    echo "OK - No config file found: ${configFile}" >> $logFile
  fi

  # check if HDD cointains existing LND data (old RaspiBlitz Version)
  echo "Check if HDD contains existing LND data .." >> $logFile
  lndDataExists=$(ls /mnt/hdd/lnd/lnd.conf 2>/dev/null | grep -c '.conf')
  if [ ${lndDataExists} -eq 1 ]; then
    echo "Found existing LND data - old RaspiBlitz?" >> $logFile
    echo "state=olddata" > $infoFile
    echo "message='No Auto-Update possible'" >> $infoFile
    echo "device=${hddDeviceName}" >> $infoFile
    exit 1
  else 
    echo "OK - No LND data found" >> $logFile
  fi

  # check if HDD contains pre-loaded blockchain data (just bitcoin for now)
  echo "Check if HDD contains pre-loaded blockchain data .." >> $logFile
  blockchainDataExists=$(ls /mnt/hdd/bitcoin 2>/dev/null)
  if [ ${#blockchainDataExist} -gt 0 ]; then
    // TODO: Pre-Sync Blockchain
    echo "Found pre-loaded blockchain - TODO start pre-sync!" >> $logFile
    echo "state=presync" > $infoFile
    echo "message='TODO: start pre-sync'" >> $infoFile
    echo "device=${hddDeviceName}" >> $infoFile
    exit 1
  else
    echo "OK - No blockchain data found" >> $logFile
  fi

  # if it got until here: HDD is empty ext4
  echo "Waiting for SetUp." >> $logFile
  echo "state=waitsetup" > $infoFile
  echo "message='HDD needs SetUp (2)'" >> $infoFile
  echo "device=${hddDeviceName}" >> $infoFile
  exit 1

fi

################################
# CONFIGFILE BASICS
################################

# check if there is a config file
configExists=$(ls ${configFile} 2>/dev/null | grep -c '.conf')
if [ ${configExists} -eq 0 ]; then

  # create new config
  echo "creating config file: ${configFile}" >> $logFile
  echo "# RASPIBLITZ CONFIG FILE" > $configFile
  echo "raspiBlitzVersion='${version}'" >> $configFile
  sudo chmod 777 ${configFile}
  # the rest will be set under DEFAULT VALUES

else

  # load & check config version
  source $configFile
  echo "codeVersion(${codeVersion})" >> $logFile
  echo "configVersion(${raspiBlitzVersion})" >> $logFile
  if [ "${raspiBlitzVersion}" != "${codeVersion}" ]; then
      echo "detected version change ... starting migration script" >> $logFile
      /home/admin/_migrateVersion.sh
  fi

fi

##################################
# DEFAULT VALUES
# check which are not set and add
##################################

# COIN NETWORK
# network=bitcoin|litecoin
if [ ${#network} -eq 0 ]; then
  oldNetworkConfigExists=$(sudo ls /home/admin/.network | grep -c '.network')
  if [ ${oldNetworkConfigExists} -eq 1 ]; then
    network=`sudo cat /home/admin/.network`
    echo "importing old network value: ${network}" >> $logFile
    echo "network=${network}" >> $configFile
  else
    echo "network=" >> $configFile
  fi
fi

# RUNNING CHAIN
# chain=test|main
if [ ${#chain} -eq 0 ]; then
  networkConfigExists=$(sudo ls /mnt/hdd/${network}/${network}.conf 2>/dev/null | grep -c '.conf')
  if [ ${networkConfigExists} -eq 1 ]; then
    source /mnt/hdd/${network}/${network}.conf
    if [ ${testnet} -eq 1 ]; then
        echo "detecting mainchain" >> $logF
    ile
        echo "chain=main" >> $configFile
    else
        echo "detecting testnet" >> $logF
    ile
        echo "chain=test" >> $configFile
    fi
  else
    echo "chain=" >> $configFile
  fi
fi

# HOSTNAME
# hostname=ONEWORDSTRING
if [ ${#setupStep} -eq 0 ]; then
  oldValueExists=$(sudo ls /home/admin/.hostname | grep -c '.hostname')
  if [ ${oldValueExists} -eq 1 ]; then
    oldValue=`sudo cat /home/admin/.hostname`
    echo "importing old hostname: ${oldValue}" >> $logFile
    echo "hostname=${oldValue}" >> $configFile
  else
    echo "hostname=" >> $configFile
  fi
fi

# SETUP STEP
# setupStep=0-100
if [ ${#setupStep} -eq 0 ]; then
  oldValueExists=$(sudo ls /home/admin/.setup | grep -c '.setup')
  if [ ${oldValueExists} -eq 1 ]; then
    oldValue=`sudo cat /home/admin/.setup`
    echo "importing old setup value: ${oldValue}" >> $logFile
    echo "setupStep=${oldValue}" >> $configFile
  else
    echo "setupStep=0" >> $configFile
  fi
fi

# AUTOPILOT
# autoPilot=off|on
if [ ${#autoPilot} -eq 0 ]; then
  echo "autoPilot=off" >> $configFile
fi

# AUTO NAT DISCOVERY
# autoNatDiscovery=off|on
if [ ${#autoNatDiscovery} -eq 0 ]; then
  echo "autoNatDiscovery=off" >> $configFile
fi

##################################
# CHECK CONFIG CONSISTENCY
##################################

# after all default values written to config - reload config
source $configFile
echo "" >> $logFile

echo "DONE BOOTSTRAP" >> $logFile
echo "state=ready" > $infoFile