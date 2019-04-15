#!/bin/bash

# This script runs on every start called by boostrap.service
# It makes sure that the system is configured like the
# default values or as in the config.
# For more details see background_raspiblitzSettings.md

# use to detect multiple starts of service
#uid=$(date +%s)
#echo "started" > /home/admin/${uid}.boot

# load codeVersion
source /home/admin/_version.info

################################
# FILES TO WORK WITH
################################

# CONFIGFILE - configuration of RaspiBlitz
# used by fresh SD image to recover configuration
# and delivers basic config info for scripts 
# make raspiblitz.conf if not there
sudo touch /mnt/hdd/raspiblitz.conf
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

# display 3 secs logo - try to kickstart LCD
# see https://github.com/rootzoll/raspiblitz/issues/195#issuecomment-469918692
sudo fbi -a -T 1 -d /dev/fb1 --noverbose /home/admin/raspiblitz/pictures/logoraspiblitz.png
sleep 5
sudo killall -3 fbi

# set default values for raspiblitz.info
network=""
chain=""
setupStep=0

# try to load old values if available (overwrites defaults)
source ${infoFile} 2>/dev/null

# resetting info file
echo "Resetting the InfoFile: ${infoFile}"
echo "state=starting" > $infoFile
echo "message=" >> $infoFile
echo "network=${network}" >> $infoFile
echo "chain=${chain}" >> $infoFile
echo "setupStep=${setupStep}" >> $infoFile
if [ "${setupStep}" != "100" ]; then
  echo "hostname=${hostname}" >> $infoFile
fi
sudo chmod 777 ${infoFile}

# Emergency cleaning logs when over 1GB (to prevent SD card filling up)
# see https://github.com/rootzoll/raspiblitz/issues/418#issuecomment-472180944
echo "*** Checking Log Size ***"
logsMegaByte=$(sudo du -c -m /var/log | grep "total" | awk '{print $1;}')
if [ ${logsMegaByte} -gt 1000 ]; then
  echo "WARN !! Logs /var/log in are bigger then 1GB"
  echo "ACTION --> DELETED ALL LOGS"
  sudo rm -r /var/log/*
  sleep 3
  echo "WARN !! Logs in /var/log in were bigger then 1GB and got emergency delete to prevent fillup."
  echo "If you see this in the logs please report to the GitHub issues, so LOG config needs to hbe optimized."
else
  echo "OK - logs are at ${logsMegaByte} MB - within safety limit"
fi
echo ""

################################
# GENERATE UNIQUE SSH PUB KEYS
# on first boot up
################################

numberOfPubKeys=$(sudo ls /etc/ssh/ | grep -c 'ssh_host_')
if [ ${numberOfPubKeys} -eq 0 ]; then
  echo "*** Generating new SSH PubKeys" >> $logFile
  sudo dpkg-reconfigure openssh-server
  echo "OK" >> $logFile
fi

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
# HDD CHECK & PRE-INIT
################################
 
# waiting for HDD to connect
hddExists=$(lsblk | grep -c sda1)
while [ ${hddExists} -eq 0 ]
  do
    # display will ask user to connect a HDD
    sed -i "s/^state=.*/state=nohdd/g" ${infoFile}
    sed -i "s/^message=.*/message='Connect the Hard Drive'/g" ${infoFile}
    sleep 5
    # retry to find HDD
    hddExists=$(lsblk | grep -c sda1)
  done

# check if the HDD is auto-mounted ( auto-mounted = setup-done)
hddIsAutoMounted=$(sudo cat /etc/fstab | grep -c '/mnt/hdd')
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
    sed -i "s/^state=.*/state=waitsetup/g" ${infoFile}
    sed -i "s/^message=.*/message='HDD needs SetUp (1)'/g" ${infoFile}
    exit 0
  fi

  # temp-mount the HDD
  echo "temp-mounting the HDD .." >> $logFile
  sudo mkdir /mnt/hdd
  sudo mount -t ext4 /dev/${hddDeviceName} /mnt/hdd
  mountOK=$(lsblk | grep -c '/mnt/hdd')
  if [ ${mountOK} -eq 0 ]; then
    echo "FAIL - not able to temp-mount HDD" >> $logFile
    sed -i "s/^state=.*/state=waitsetup/g" ${infoFile}
    sed -i "s/^message=.*/message='HDD failed Mounting'/g" ${infoFile}
    # no need to unmount the HDD, it failed mounting
    exit 0
  else 
     echo "OK - HDD available under /mnt/hdd" >> $logFile
  fi

  # UPDATE MIGRATION & CONFIG PROVISIONING 
  # check if HDD contains already a configuration
  echo "Check if HDD contains already a configuration .." >> $logFile
  configExists=$(ls ${configFile} | grep -c '.conf')
  if [ ${configExists} -eq 1 ]; then
    echo "Found existing configuration" >> $logFile
    source ${configFile}
    # check if config files contains basic: version
    if [ ${#raspiBlitzVersion} -eq 0 ]; then
      echo "Invalid Config: missing raspiBlitzVersion in (${configFile})!" >> ${logFile}
      configExists=0
    fi
    # check if config files contains basic: network
    if [ ${#network} -eq 0 ]; then
      echo "Invalid Config: missing network in (${configFile})!" >> ${logFile}
      configExists=0
    fi
    # check if config files contains basic: chain
    if [ ${#chain} -eq 0 ]; then
      echo "Invalid Config: missing chain in (${configFile})!" >> ${logFile}
      configExists=0
    fi
    if [ ${configExists} -eq 0 ]; then
      echo "Moving invalid config to raspiblitz.invalid.conf" >> ${logFile}
      sudo mv ${configFile} /mnt/hdd/raspiblitz.invalid.conf
    fi
  fi
  # if config is still valid ...
  if [ ${configExists} -eq 1 ]; then
    echo "Found valid configuration" >> $logFile
    sed -i "s/^state=.*/state=recovering/g" ${infoFile}
    sed -i "s/^message=.*/message='Starting Recover'/g" ${infoFile}
    echo "Calling Data Migration .." >> $logFile
    sudo /home/admin/_bootstrap.migration.sh
    echo "Calling Provisioning .." >> $logFile
    sudo /home/admin/_bootstrap.provision.sh
    sed -i "s/^state=.*/state=recovered/g" ${infoFile}
    sed -i "s/^message=.*/message='Done Recover'/g" ${infoFile}
    echo "rebooting" >> $logFile
    # set flag that system is freshly recovered and needs setup dialogs
    echo "state=recovered" >> /home/admin/raspiblitz.recover.info
    # save log file for inspection before reboot
    cp $logFile /home/admin/raspiblitz.recover.log
    sudo shutdown -r now
    exit 0
  else 
    echo "OK - No config file found: ${configFile}" >> $logFile
  fi

  # check if HDD contains existing LND data (old RaspiBlitz Version)
  echo "Check if HDD contains existing LND data .." >> $logFile
  lndDataExists=$(ls /mnt/hdd/lnd/lnd.conf | grep -c '.conf')
  if [ ${lndDataExists} -eq 1 ]; then
    echo "Found existing LND data - old RaspiBlitz?" >> $logFile
    sed -i "s/^state=.*/state=olddata/g" ${infoFile}
    sed -i "s/^message=.*/message='No Auto-Update possible'/g" ${infoFile}
    # keep HDD mounted if user wants to copy data
    exit 0
  else 
    echo "OK - No LND data found" >> $logFile
  fi

  # check if HDD contains pre-loaded blockchain data
  echo "Check if HDD contains pre-loaded blockchain data .." >> $logFile
  litecoinDataExists=$(ls /mnt/hdd/litecoin/blocks/blk00000.dat 2>/dev/null | grep -c '.dat')
  bitcoinDataExists=$(ls /mnt/hdd/bitcoin/blocks/blk00000.dat 2>/dev/null | grep -c '.dat')

  # check if node can go into presync (only for bitcoin)
  if [ ${bitcoinDataExists} -eq 1 ]; then

    # update info file
    sed -i "s/^state=.*/state=presync/g" ${infoFile}
    sed -i "s/^message=.*/message='starting presync'/g" ${infoFile}

    # activating presync
    # so that on a hackathon you can just connect a RaspiBlitz
    # to the network and have it up-to-date for setting up
    echo "Found pre-loaded blockchain" >> $logFile

    # check if pre-sync was already activated on last power-on
    #presyncActive=$(systemctl status bitcoind | grep -c 'could not be found')
    echo "starting pre-sync in background" >> $logFile
    # make sure that debug file is clean, so just pre-sync gets analysed on stop
    sudo rm /mnt/hdd/bitcoin/debug.log
    # starting in background, because this scripts is part of systemd
    # so to change systemd needs to happen after delay in seperate process
    sudo chown -R bitcoin:bitcoin /mnt/hdd/bitcoin 2>> $logFile
    sudo -u bitcoin /usr/local/bin/bitcoind -daemon -conf=/home/admin/assets/bitcoin.conf -pid=/mnt/hdd/bitcoin/bitcoind.pid 2>> $logFile
    echo "OK Started bitcoind for presync" >> $logFile
    sudo sed -i "s/^message=.*/message='running presync'/g" ${infoFile}
    # after admin login, presync will be stopped and HDD unmounted
    exit 0
  
  else
    echo "OK - No bitcoin blockchain data found" >> $logFile
  fi

  # if it got until here: HDD is empty ext4
  echo "Waiting for SetUp." >> $logFile
  sed -i "s/^state=.*/state=waitsetup/g" ${infoFile}
  sed -i "s/^message=.*/message='HDD needs SetUp (2)'/g" ${infoFile}
  # unmount HDD to be ready for auto-mount during setup
  sudo umount -l /mnt/hdd
  exit 0

fi # END - no automount

#####################################
# UPDATE HDD CONFIG FILE (if exists)
# needs to be done before starting LND
# so that environment info is fresh
#####################################

echo "Check if HDD contains configuration .." >> $logFile
configExists=$(ls ${configFile} | grep -c '.conf')
if [ ${configExists} -eq 1 ]; then

  # make sure lndAddress & lndPort exist
  valueExists=$(cat ${configFile} | grep -c 'lndPort=')
  if [ ${valueExists} -eq 0 ]; then
    lndPort=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep "^listen=*" | cut -f2 -d':')
    if [ ${#lndPort} -eq 0 ]; then
      lndPort="9735"
    fi
    echo "lndPort='${lndPort}'" >> ${configFile}
  fi
  valueExists=$(cat ${configFile} | grep -c 'lndAddress=')
  if [ ${valueExists} -eq 0 ]; then
      echo "lndAddress=''" >> ${configFile}
  fi

  # load values
  echo "load and update publicIP" >> $logFile
  source ${configFile}
  freshPublicIP=""
  
  # determine the publicIP/domain that LND should announce
  if [ ${#lndAddress} -gt 3 ]; then

    # use domain as PUBLICIP 
    freshPublicIP="${lndAddress}"

  else

    # update public IP on boot
    # wait otherwise looking for publicIP fails
    sleep 5
    freshPublicIP=$(curl -s http://v4.ipv6-test.com/api/myip.php)

    # sanity check on IP data
    # see https://github.com/rootzoll/raspiblitz/issues/371#issuecomment-472416349
    echo "-> sanity check of IP data:"
    if [[ $freshPublicIP =~ ^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$ ]]; then
      echo "OK IPv6"
    elif [[ $freshPublicIP =~ ^([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]]; then
      echo "OK IPv4"
    else
      echo "FAIL - not an IPv4 or IPv6 address"
      freshPublicIP=""
    fi

    if [ ${#freshPublicIP} -eq 0 ]; then
      # prevent having no publicIP set at all and LND getting stuck
      # https://github.com/rootzoll/raspiblitz/issues/312#issuecomment-462675101
      if [ ${#publicIP} -eq 0 ]; then
        localIP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
        echo "WARNING: No publicIP information at all - working with placeholder: ${localIP}" >> $logFile
        freshPublicIP="${localIP}"
      fi
    fi

  fi

  # set publicip value in raspiblitz.conf
  if [ ${#freshPublicIP} -eq 0 ]; then
    echo "WARNING: Was not able to determine external IP/domain on startup." >> $logFile
  else
    publicIPValueExists=$( sudo cat ${configFile} | grep -c 'publicIP=' )
    if [ ${publicIPValueExists} -gt 1 ]; then
      # remove one 
      echo "more then one publiIp entry - removing one" >> $logFile
      sed -i "s/^publicIP=.*//g" ${configFile}
      publicIPValueExists=$( sudo cat ${configFile} | grep -c 'publicIP=' )
    fi
    if [ ${publicIPValueExists} -eq 0 ]; then
      echo "create value (${freshPublicIP})" >> $logFile
      echo "publicIP='${freshPublicIP}'" >> $configFile
    else
      echo "update value (${freshPublicIP})" >> $logFile
      sed -i "s/^publicIP=.*/publicIP='${freshPublicIP}'/g" ${configFile}
    fi
  fi

fi

#################################
# FIX BLOCKCHAINDATA OWNER (just in case)
# https://github.com/rootzoll/raspiblitz/issues/239#issuecomment-450887567
#################################
sudo chown bitcoin:bitcoin -R /mnt/hdd/bitcoin 2>/dev/null

################################
# DETECT FRESHLY RECOVERED SD
################################

recoveredInfoExists=$(ls /home/admin/raspiblitz.recover.info | grep -c '.info')
if [ ${recoveredInfoExists} -eq 1 ]; then
  sed -i "s/^state=.*/state=recovered/g" ${infoFile}
  sed -i "s/^message=.*/message='login to finish'/g" ${infoFile}
  exit 0
fi

################################
# SD INFOFILE BASICS
################################

# state info
sed -i "s/^state=.*/state=ready/g" ${infoFile}
sed -i "s/^message=.*/message='waiting login'/g" ${infoFile}

# determine network and chain from system

# check for BITCOIN
loaded=$(sudo systemctl status bitcoind | grep -c 'loaded')
if [ ${loaded} -gt 0 ]; then
  sed -i "s/^network=.*/network=bitcoin/g" ${infoFile}
  source /mnt/hdd/bitcoin/bitcoin.conf
  if [ ${testnet} -gt 0 ]; then
    sed -i "s/^chain=.*/chain=test/g" ${infoFile}
  else
    sed -i "s/^chain=.*/chain=main/g" ${infoFile}
  fi
fi

# check for LITECOIN
loaded=$(sudo systemctl status litecoind | grep -c 'loaded')
if [ ${loaded} -gt 0 ]; then
  sed -i "s/^network=.*/network=litecoin/g" ${infoFile}
  sed -i "s/^chain=.*/chain=main/g" ${infoFile}
fi

################################
# STRESSTEST HARDWARE
################################

# generate stresstest report on every startup (in case hardware has changed)
sed -i "s/^state=.*/state=stresstest/g" ${infoFile}
sed -i "s/^message=.*/message='Testing Hardware 60s'/g" ${infoFile}
sudo /home/admin/config.scripts/blitz.stresstest.sh /home/admin/stresstest.report

echo "DONE BOOTSTRAP" >> $logFile
exit 0