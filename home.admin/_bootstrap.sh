#!/bin/bash

# This script runs on every start called by boostrap.service
# It makes sure that the system is configured like the
# default values or as in the config.
# For more details see background_raspiblitzSettings.md

################################
# BASIC SETTINGS
################################

# load codeVersion
source /home/admin/_version.info

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

# set default values for raspiblitz.info
network=""
chain=""
setupStep=0
fsexpanded=0
lcd2hdmi="off"

# try to load old values if available (overwrites defaults)
source ${infoFile} 2>/dev/null

# resetting info file
echo "Resetting the InfoFile: ${infoFile}"
echo "state=starting" > $infoFile
echo "message=" >> $infoFile
echo "network=${network}" >> $infoFile
echo "chain=${chain}" >> $infoFile
echo "fsexpanded=${fsexpanded}" >> $infoFile
echo "lcd2hdmi=${lcd2hdmi}" >> $infoFile
echo "setupStep=${setupStep}" >> $infoFile
if [ "${setupStep}" != "100" ]; then
  echo "hostname=${hostname}" >> $infoFile
fi
sudo chmod 777 ${infoFile}

# resetting start count files
echo "SYSTEMD RESTART LOG: blockchain (bitcoind/litecoind)" > /home/admin/systemd.blockchain.log
echo "SYSTEMD RESTART LOG: lightning (LND)" > /home/admin/systemd.lightning.log
sudo chmod 777 /home/admin/systemd.blockchain.log
sudo chmod 777 /home/admin/systemd.lightning.log

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

###############################
# RAID data check (BRTFS)
###############################
# see https://github.com/rootzoll/raspiblitz/issues/360#issuecomment-467698260

source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
if [ ${isRaid} -eq 1 ]; then
  echo "TRIGGERING BTRFS RAID DATA CHECK ..."
  echo "Check status with: sudo btrfs scrub status /mnt/hdd/"
  sudo btrfs scrub start /mnt/hdd/
fi

################################
# BOOT LOGO
################################

# display 3 secs logo - try to kickstart LCD
# see https://github.com/rootzoll/raspiblitz/issues/195#issuecomment-469918692
# see https://github.com/rootzoll/raspiblitz/issues/647
randnum=$(shuf -i 0-7 -n 1)
sudo fbi -a -T 1 -d /dev/fb1 --noverbose /home/admin/raspiblitz/pictures/startlogo${randnum}.png
sleep 5
sudo killall -3 fbi

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
# FORCED SWITCH TO HDMI
# if a file called 'hdmi' gets
# placed onto the boot part of
# the sd card - switch to hdmi
################################

forceHDMIoutput=$(sudo ls /boot/hdmi 2>/dev/null | grep -c hdmi)
if [ ${forceHDMIoutput} -eq 1 ]; then
  # delete that file (to prevent loop)
  sudo rm /boot/hdmi
  # switch to HDMI what will trigger reboot
  sudo /home/admin/config.scripts/blitz.lcd.sh hdmi on
  exit 0
fi

################################
# WAIT FOR LOCAL NETWORK
################################

# wait until raspberry pi gets a local IP
gotLocalIP=0
until [ ${gotLocalIP} -eq 1 ]
do
  localip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0' | grep 'eth0\|wlan0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  if [ ${#localip} -eq 0 ]; then
    # display user to connect LAN
    sed -i "s/^state=.*/state=noIP/g" ${infoFile}
    sed -i "s/^message=.*/message='Connect the LAN/WAN'/g" ${infoFile}
  elif [ "${localip:0:4}" = "169." ]; then
    # display user waiting for DHCP
    sed -i "s/^state=.*/state=noDCHP/g" ${infoFile}
    sed -i "s/^message=.*/message='Waiting for DHCP'/g" ${infoFile}
  else
    gotLocalIP=1
  fi
  sleep 1
done

################################
# HDD CHECK & PRE-INIT
################################
 
# wait loop until HDD is connected
until [ ${isMounted} -eq 1 ] || [ ${#hddCandidate} -gt 0 ]
do
  source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
  if [ ${isMounted} -eq 0 ] && [ ${#hddCandidate} -eq 0 ]; then
    sed -i "s/^state=.*/state=noHDD/g" ${infoFile}
    sed -i "s/^message=.*/message='Connect the Hard Drive'/g" ${infoFile}
  fi
  sleep 2
done

# write info for LCD
sed -i "s/^state=.*/state=booting/g" ${infoFile}
sed -i "s/^message=.*/message='please wait'/g" ${infoFile}

# get fresh info about data drive to continue
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)

# check if the HDD is auto-mounted ( auto-mounted = setup-done)
if [ ${isMounted} -eq 0 ]; then

  echo "HDD is there but not AutoMounted yet - checking Setup" >> $logFile

  # when format is not EXT4 or BTRFS - stop bootstrap and await user setup
  if [ "${hddFormat}" != "ext4" ] && [ "${hddFormat}" != "btrfs" ]; then
    echo "HDD is NOT formatted in ${hddFormat} .. awaiting user setup." >> $logFile
    sed -i "s/^state=.*/state=waitsetup/g" ${infoFile}
    sed -i "s/^message=.*/message='HDD needs SetUp (1)'/g" ${infoFile}
    exit 0
  fi

  # when error on analysing HDD - stop bootstrap and await user setup
  if [ ${#hddError} -gt 0 ]; then
    echo "FAIL - error on HDD analysis: ${hddError}" >> $logFile
    sed -i "s/^state=.*/state=waitsetup/g" ${infoFile}
    sed -i "s/^message=.*/message='${hddError}'/g" ${infoFile}
    exit 0
  fi

  # temp mount the HDD
  echo "Temp mounting data drive" >> $logFile
  source <(sudo /home/admin/config.scripts/blitz.datadrive.sh tempmount ${hddCandidate})
  if [ ${#error} -gt 0 ]; then
    echo "Failed to tempmount the HDD .. awaiting user setup." >> $logFile
    sed -i "s/^state=.*/state=waitsetup/g" ${infoFile}
    sed -i "s/^message=.*/message='${error}'/g" ${infoFile}
    exit 0
  fi

  # make sure all links between directories/drives are correct
  echo "Refreshing links between directories/drives .." >> $logFile
  sudo /home/admin/config.scripts/blitz.datadrive.sh link

  # check if HDD contains already a configuration
  configExists=$(ls ${configFile} | grep -c '.conf')
  echo "HDD contains already a configuration: ${configExists}" >> $logFile
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
      sudo mv ${configFile} /mnt/hdd/raspiblitz.invalid.conf 2>/dev/null
    fi
  fi
  
  # UPDATE MIGRATION & CONFIG PROVISIONING 
  if [ ${configExists} -eq 1 ]; then
    echo "Found valid configuration" >> $logFile
    sed -i "s/^state=.*/state=recovering/g" ${infoFile}
    sed -i "s/^message=.*/message='Starting Recover'/g" ${infoFile}
    sed -i "s/^chain=.*/chain=${chain}/g" ${infoFile}
    sed -i "s/^network=.*/network=${network}/g" ${infoFile}
    echo "Calling Data Migration .." >> $logFile
    sudo /home/admin/_bootstrap.migration.sh
    echo "Calling Provisioning .." >> $logFile
    sudo /home/admin/_bootstrap.provision.sh
    sed -i "s/^state=.*/state=reboot/g" ${infoFile}
    sed -i "s/^message=.*/message='Done Recover'/g" ${infoFile}
    echo "rebooting" >> $logFile
    # set flag that system is freshly recovered and needs setup dialogs
    echo "state=recovered" >> /home/admin/raspiblitz.recover.info
    # save log file for inspection before reboot
    cp $logFile /home/admin/raspiblitz.recover.log
    echo "shutdown in 1min" >> $logFile
    sync
    sudo shutdown -r -F +1
    exit 0
  else 
    echo "OK - No config file found: ${configFile}" >> $logFile
  fi

  # if it got until here: HDD is empty ext4
  echo "Waiting for SetUp." >> $logFile
  sed -i "s/^state=.*/state=waitsetup/g" ${infoFile}
  sed -i "s/^message=.*/message='HDD needs SetUp (2)'/g" ${infoFile}
  # unmount HDD to be ready for auto-mount during setup
  sudo umount -l /mnt/hdd
  exit 0

fi # END - no automount - after this HDD is mounted

# config should exist now
configExists=$(ls ${configFile} | grep -c '.conf')
if [ ${configExists} -eq 0 ]; then
  sed -i "s/^state=.*/state=waitsetup/g" ${infoFile}
  sed -i "s/^message=.*/message='no config'/g" ${infoFile}
  exit 0
fi

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
        localip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0' | grep 'eth0\|wlan0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
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

#################################
# MAKE SURE ADMIN USER HAS LATEST LND DATA
#################################
source ${configFile}
if [ ${#network} -gt 0 ] && [ ${#chain} -gt 0 ]; then

  echo "making sure LND blockchain RPC password is set correct in lnd.conf" >> $logFile
  source <(sudo cat /mnt/hdd/${network}/${network}.conf 2>/dev/null | grep "rpcpass" | sed 's/^[a-z]*\./lnd/g')
  if [ ${#rpcpassword} -gt 0 ]; then
    sudo sed -i "s/^${network}d.rpcpass=.*/${network}d.rpcpass=${rpcpassword}/g" /mnt/hdd/lnd/lnd.conf 2>/dev/null
  else
    echo "WARN: could not get value 'rpcuser' from blockchain conf" >> $logFile
  fi

  echo "updating/cleaning admin user LND data" >> $logFile
  sudo rm -R /home/admin/.lnd 2>/dev/null
  sudo mkdir -p /home/admin/.lnd/data/chain/${network}/${chain}net 2>/dev/null
  sudo cp /mnt/hdd/lnd/lnd.conf /home/admin/.lnd/lnd.conf 2>> $logFile
  sudo cp /mnt/hdd/lnd/tls.cert /home/admin/.lnd/tls.cert 2>> $logFile
  sudo sh -c "cat /mnt/hdd/lnd/data/chain/${network}/${chain}net/admin.macaroon > /home/admin/.lnd/data/chain/${network}/${chain}net/admin.macaroon" 2>> $logFile
  sudo chown admin:admin -R /home/admin/.lnd 2>> $logFile

  echo "updating/cleaning pi user LND data (just read & invoice)" >> $logFile
  sudo rm -R /home/pi/.lnd 2>/dev/null
  sudo mkdir -p /home/pi/.lnd/data/chain/${network}/${chain}net/ 2>> $logFile
  sudo cp /mnt/hdd/lnd/tls.cert /home/pi/.lnd/tls.cert 2>> $logFile
  sudo sh -c "cat /mnt/hdd/lnd/data/chain/${network}/${chain}net/readonly.macaroon > /home/pi/.lnd/data/chain/${network}/${chain}net/readonly.macaroon" 2>> $logFile
  sudo sh -c "cat /mnt/hdd/lnd/data/chain/${network}/${chain}net/invoice.macaroon > /home/pi/.lnd/data/chain/${network}/${chain}net/invoice.macaroon" 2>> $logFile
  sudo chown pi:pi -R /home/pi/.lnd 2>> $logFile

  if [ "${LNBits}" = "on" ]; then
    echo "updating macaroons for LNBits fresh on start" >> $logFile
    sudo -u admin /home/admin/config.scripts/bonus.lnbits.sh write-macaroons >> $logFile
    sudo chown admin:admin -R /mnt/hdd/app-data/LNBits
  fi

else 
  echo "skipping admin user LND data update" >> $logFile
fi

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
# DELETE LOG FILES
################################
# LND and Blockchain Errors will be still in systemd journals

# /mnt/hdd/bitcoin/debug.log
sudo rm /mnt/hdd/${network}/debug.log 2>/dev/null
# /mnt/hdd/lnd/logs/bitcoin/mainnet/lnd.log
sudo rm /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log 2>/dev/null

#####################################
# CLEAN HDD TEMP
#####################################

echo "CLEANING TEMP DRIVE/FOLDER" >> $logFile
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh clean temp)
if [ ${#error} -gt 0 ]; then
  echo "FAIL: ${error}" >> $logFile
else
  echo "OK: Temp cleaned" >> $logFile
fi

################################
# IDENTIFY BASEIMAGE
################################

baseImage="?"
isDietPi=$(uname -n | grep -c 'DietPi')
isRaspbian=$(cat /etc/os-release 2>/dev/null | grep -c 'Raspbian')
isArmbian=$(cat /etc/os-release 2>/dev/null | grep -c 'Debian')
isUbuntu=$(cat /etc/os-release 2>/dev/null | grep -c 'Ubuntu')
if [ ${isRaspbian} -gt 0 ]; then
  baseImage="raspbian"
fi
if [ ${isArmbian} -gt 0 ]; then
  baseImage="armbian"
fi 
if [ ${isUbuntu} -gt 0 ]; then
baseImage="ubuntu"
fi
if [ ${isDietPi} -gt 0 ]; then
  baseImage="dietpi"
fi
echo "baseimage=${baseImage}" >> $infoFile

################################
# STRESSTEST RASPBERRY PI
################################

if [ "${baseImage}" = "raspbian" ] ; then
  # generate stresstest report on every startup (in case hardware has changed)
  sed -i "s/^state=.*/state=stresstest/g" ${infoFile}
  sed -i "s/^message=.*/message='Testing Hardware 60s'/g" ${infoFile}
  sudo /home/admin/config.scripts/blitz.stresstest.sh /home/admin/stresstest.report
  source /home/admin/stresstest.report
  if [ "${powerWARN}" = "0" ]; then
    # https://github.com/rootzoll/raspiblitz/issues/576
    echo "" > /var/log/syslog
  fi
fi

# mark that node is ready now
sed -i "s/^state=.*/state=ready/g" ${infoFile}
sed -i "s/^message=.*/message='Node Running'/g" ${infoFile}

echo "DONE BOOTSTRAP" >> $logFile
exit 0
