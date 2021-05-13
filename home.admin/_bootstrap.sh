#!/bin/bash

# This script runs on every start called by boostrap.service
# It makes sure that the system is configured like the
# default values or as in the config.

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

# Init boostrap log file
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
setupPhase='boot'
fsexpanded=0
# see https://github.com/rootzoll/raspiblitz/issues/1265#issuecomment-813369284
displayClass="lcd"
displayType=""
fundRecovery=0

################################
# INIT raspiblitz.info
################################

# try to load old values if available (overwrites defaults)
source ${infoFile} 2>/dev/null

# try to load config values if available (config overwrites info)
source ${configFile} 2>/dev/null

# get first basic network info
source <(/home/admin/config.scripts/internet.sh status)

# resetting info file
echo "Resetting the InfoFile: ${infoFile}"
echo "state=starting" > $infoFile
echo "message=" >> $infoFile
echo "baseimage=${baseimage}" >> $infoFile
echo "cpu=${cpu}" >> $infoFile
echo "network=${network}" >> $infoFile
echo "chain=${chain}" >> $infoFile
echo "localip='${localip}'" >> $infoFile
echo "online='${online}'" >> $infoFile
echo "fsexpanded=${fsexpanded}" >> $infoFile
echo "displayClass=${displayClass}" >> $infoFile
echo "displayType=${displayType}" >> $infoFile
echo "setupStep=${setupStep}" >> $infoFile
echo "setupPhase=${setupPhase}" >> $infoFile
echo "fundRecovery=${fundRecovery}" >> $infoFile
if [ "${setupStep}" != "100" ]; then
  echo "hostname=${hostname}" >> $infoFile
fi
sudo chmod 777 ${infoFile}

######################################
# SECTION FOR POSSIBLE REBOOT ACTIONS
systemInitReboot=0

################################
# FORCED SWITCH TO HDMI
# if a file called 'hdmi' gets
# placed onto the boot part of
# the sd card - switch to hdmi
################################

forceHDMIoutput=$(sudo ls /boot/hdmi* 2>/dev/null | grep -c hdmi)
if [ ${forceHDMIoutput} -eq 1 ]; then
  # delete that file (to prevent loop)
  sudo rm /boot/hdmi*
  # switch to HDMI what will trigger reboot
  echo "HDMI switch found ... activating HDMI display output & reboot" >> $logFile
  sudo /home/admin/config.scripts/blitz.display.sh set-display hdmi >> $logFile
  systemInitReboot=1
else
  echo "No HDMI switch found. " >> $logFile
fi

################################
# SSH SERVER CERTS RESET
# if a file called 'ssh.reset' gets
# placed onto the boot part of
# the sd card - delete old ssh data
################################

sshReset=$(sudo ls /boot/ssh.reset* 2>/dev/null | grep -c reset)
if [ ${sshReset} -eq 1 ]; then
  # delete that file (to prevent loop)
  sudo rm /boot/ssh.reset* >> $logFile
  # delete ssh certs
  echo "SSHRESET switch found ... stopping SSH and deleting old certs" >> $logFile
  sudo systemctl stop sshd >> $logFile
  sudo rm /mnt/hdd/ssh/ssh_host* >> $logFile
  sudo ssh-keygen -A >> $logFile
  systemInitReboot=1
else
  echo "No SSHRESET switch found. " >> $logFile
fi

################################
# FS EXPAND
# if a file called 'ssh.reset' gets
# placed onto the boot part of
# the sd card - delete old ssh data
################################
source <(sudo /home/admin/config.scripts/blitz.bootdrive.sh status)
if [ "${needsExpansion}" == "1" ] && [ "${fsexpanded}" == "0" ]; then
  echo "FSEXPAND needed ... starting process" >> $logFile
  sudo /home/admin/config.scripts/blitz.bootdrive.sh status >> $logFile
  sudo /home/admin/config.scripts/blitz.bootdrive.sh fsexpand >> $logFile
  systemInitReboot=1
elif [ "${tooSmall}" == "1" ]; then
  echo "!!! FAIL !!!!!!!!!!!!!!!!!!!!" >> $logFile
  echo "SDCARD TOO SMALL 16G minimum" >> $logFile
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >> $logFile
  sed -i "s/^state=.*/state=sdtoosmall/g" ${infoFile}
  echo "System stopped. Please cut power." >> $logFile
  sleep 6000
  sudo shutdown -r now
  slepp 100
  exit 1
else
  echo "No FS EXPAND needed. needsExpansion(${needsExpansion}) fsexpanded(${fsexpanded})" >> $logFile
fi

################################
# UASP FIX - first try
# if HDD is connected on start
################################
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh uasp-fix)
if [ "${neededReboot}" == "1" ]; then
  echo "UASP FIX applied (1st-try) ... reboot needed." >> $logFile
  systemInitReboot=1
else
  echo "No UASP FIX needed (1st-try)." >> $logFile
fi

######################################
# CHECK IF REBOOT IS NEEDED
# from actions above

if [ "${systemInitReboot}" == "1" ]; then
  sudo cp ${logFile} ${logFile}.systeminit
  sudo sed -i "s/^state=.*/state=reboot/g" ${infoFile}
  sudo shutdown -r now
  sleep 100
  exit 0
fi

################################
# BOOT LOGO
################################

# display 3 secs logo - try to kickstart LCD
# see https://github.com/rootzoll/raspiblitz/issues/195#issuecomment-469918692
# see https://github.com/rootzoll/raspiblitz/issues/647
# see https://github.com/rootzoll/raspiblitz/pull/1580
randnum=$(shuf -i 0-7 -n 1)
/home/admin/config.scripts/blitz.display.sh image /home/admin/raspiblitz/pictures/startlogo${randnum}.png
sleep 5
/home/admin/config.scripts/blitz.display.sh hide

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
# CLEANING BOOT SYSTEM
################################

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
  if [ -d "/var/log/nginx" ]; then
    nginxLog=1
    echo "/var/log/nginx is present"
  fi
  sudo rm -r /var/log/*
  if [ $nginxLog == 1 ]; then
    sudo mkdir /var/log/nginx
    echo "Recreated /var/log/nginx"
  fi
  sleep 3
  echo "WARN !! Logs in /var/log in were bigger then 1GB and got emergency delete to prevent fillup."
  echo "If you see this in the logs please report to the GitHub issues, so LOG config needs to hbe optimized."
else
  echo "OK - logs are at ${logsMegaByte} MB - within safety limit"
fi
echo ""

###############################
# WAIT FOR ALL SERVICES

# get the state of data drive
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)

################################
# WAIT LOOP: HDD CONNECTED
################################

echo "Waiting for HDD/SSD ..." >> $logFile
until [ ${isMounted} -eq 1 ] || [ ${#hddCandidate} -gt 0 ]
do

  # recheck HDD/SSD
  source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
  echo "isMounted: $isMounted"
  echo "hddCandidate: $hddCandidate"

  # in case of HDD analyse ERROR
  if [ "${hddError}" != "" ]; then
    echo "FAIL - error on HDD analysis: ${hddError}" >> $logFile
    sed -i "s/^state=.*/state=errorHDD/g" ${infoFile}
    sed -i "s/^message=.*/message='${hddError}'/g" ${infoFile}
  elif [ "${isMounted}" == "0" ] && [ "${hddCandidate}" == "" ]; then
    sed -i "s/^state=.*/state=noHDD/g" ${infoFile}
    sed -i "s/^message=.*/message='1TB'/g" ${infoFile}
  fi

  # get latest network info & update raspiblitz.info (in case network changes)
  source <(/home/admin/config.scripts/internet.sh status)
  sed -i "s/^localip=.*/localip='${localip}'/g" ${infoFile}

  # wait for next check
  sleep 2

done
echo "HDD/SSD connected: ${$hddCandidate}" >> $logFile

# write info for LCD
sed -i "s/^state=.*/state=system-init/g" ${infoFile}
sed -i "s/^message=.*/message='please wait'/g" ${infoFile}

####################################
# WIFI RESTORE from HDD works with
# mem copy from datadrive inspection
####################################

# check if there is a WIFI configuration to backup or restore
/home/admin/config.scripts/internet.wifi.sh backup-restore >> $logFile

################################
# UASP FIX - second try
# when HDD gets connected later
################################
sed -i "s/^message=.*/message='checking HDD'/g" ${infoFile}
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh uasp-fix)
if [ "${neededReboot}" == "1" ]; then
  echo "UASP FIX applied (2nd-try) ... reboot needed." >> $logFile
  sudo cp ${logFile} ${logFile}.uasp
  sudo sed -i "s/^state=.*/state=reboot/g" ${infoFile}
  sudo shutdown -r now
  sleep 100
  exit 0
else
  echo "No UASP FIX needed (2nd-try)." >> $logFile
fi

###################################
# WAIT LOOP: LOCALNET / INTERNET
# after HDD > can contain WIFI conf
###################################

gotLocalIP=0
until [ ${gotLocalIP} -eq 1 ]
do

  # get latest network info & update raspiblitz.info
  source <(/home/admin/config.scripts/internet.sh status)
  sed -i "s/^localip=.*/localip='${localip}'/g" ${infoFile}

  # check state of network
  if [ ${dhcp} -eq 0 ]; then
    # display user waiting for DHCP
    sed -i "s/^state=.*/state=noDHCP/g" ${infoFile}
    sed -i "s/^message=.*/message='Waiting for DHCP'/g" ${infoFile}
  elif [ ${#localip} -eq 0 ]; then
    if [ ${configWifiExists} -eq 0 ]; then
      # display user to connect LAN
      sed -i "s/^state=.*/state=noIP-LAN/g" ${infoFile}
      sed -i "s/^message=.*/message='Connect the LAN/WAN'/g" ${infoFile}
    else
      # display user that wifi settings are not working
      sed -i "s/^state=.*/state=noIP-WIFI/g" ${infoFile}
      sed -i "s/^message=.*/message='WIFI Settings not working'/g" ${infoFile}
    fi
  elif [ ${online} -eq 0 ]; then
    # display user that wifi settings are not working
    sed -i "s/^state=.*/state=noInternet/g" ${infoFile}
    sed -i "s/^message=.*/message='No connection to Internet'/g" ${infoFile}
  else
    gotLocalIP=1
  fi
  sleep 1
done

# write info for LCD
sed -i "s/^state=.*/state=inspect-hdd/g" ${infoFile}
sed -i "s/^message=.*/message='please wait'/g" ${infoFile}

# get fresh info about data drive to continue
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)

# check if the HDD is auto-mounted ( auto-mounted = setup-done)
echo "HDD already part of system: $isMounted" >> $logFile
if [ ${isMounted} -eq 0 ]; then

  echo "HDD is there but not AutoMounted yet - Waiting for user Setup/Update" >> $logFile

  # determine correct info message
  infoMessage="Please Login for Setup"
  setupPhase="setup"
  if [ "${hddRaspiData}" == "1" ]; then
    infoMessage="Please Login for Update"
    setupPhase="update"
  elif [ "${hddGotMigrationData}" != "" ]; then
    infoMessage="Please Login for Migration"
    setupPhase="migration"
  elif [ "${hddBlocksBitcoin}" == "1" ] || [ "${hddBlocksLitecoin}" == "1" ]; then
    infoMessage="Login for presynced Setup"
    setupPhase="presync"
  fi

  # signal "WAIT LOOP: SETUP" to LCD, SSH & WEBAPI
  echo "Displaying Info Message: ${infoMessage}" >> $logFile
  sed -i "s/^state=.*/state=waitsetup/g" ${infoFile}
  sed -i "s/^message=.*/message='${infoMessage}'/g" ${infoFile}
  sed -i "s/^setupPhase=.*/setupPhase='${setupPhase}'/g" ${infoFile}

  #############################################
  # WAIT LOOP: USER SETUP/UPDATE/MIGRATION
  # until SSH or WEBUI setup data is available
  #############################################

  gotUserSetupInfo=0
  until [ ${gotUserSetupInfo} -eq 1 ]
  do

    # TODO: DETECT WHEN USER SETUP IS DONE
    echo "TODO: DETECT WHEN USER SETUP IS DONE hddError(${hddError}) hddCandidate(${hddCandidate})" >> $logFile

    # get latest network info & update raspiblitz.info (in case network changes)
    source <(/home/admin/config.scripts/internet.sh status)
    sed -i "s/^localip=.*/localip='${localip}'/g" ${infoFile}

    # get fresh info about data drive (in case the hdd gets disconnected)
    source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
    if [ "${hddCandidate}" == "" ]; then
      echo "!!! WARNING !!! Lost HDD connection .. triggering reboot, to restart system-init." >> $logFile
      sed -i "s/^state=.*/state=errorHDD/g" ${infoFile}
      sed -i "s/^message=.*/message='lost HDD - rebooting'/g" ${infoFile}
      sudo cp ${logFile} ${logFile}.error
      sleep 6
      sudo shutdown -r now
      sleep 100
      exit 0
    fi

    # give the loop a little bed time
    sleep 4

done

############################### TODO: RE-ARRANGE THE PARTS BELOW
echo "TODO: RE-ARRANGE THE PARTS BELOW" >> $logFile
exit 0


  # temp mount the HDD
  echo "Temp mounting data drive ($hddCandidate)" >> $logFile
  if [ "${hddFormat}" != "btrfs" ]; then
    source <(sudo /home/admin/config.scripts/blitz.datadrive.sh tempmount ${hddPartitionCandidate})
  else
    source <(sudo /home/admin/config.scripts/blitz.datadrive.sh tempmount ${hddCandidate})
  fi
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
    sudo touch /home/admin/recover.flag
    echo "state=recovered" >> /home/admin/recover.flag
    echo "shutdown in 1min" >> $logFile
    # save log file for inspection before reboot
    echo "REBOOT FOR SSH CERTS RESET ..." >> $logFile
    sudo cp ${logFile} ${logFile}.recover
    sync
    sudo shutdown -r -F -t 60
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

sed -i "s/^setupPhase=.*/setupPhase='starting'/g" ${infoFile}

# if a WIFI config exists backup to HDD
configWifiExists=$(sudo cat /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null| grep -c "network=")
if [ ${configWifiExists} -eq 1 ]; then
  echo "Making Backup Copy of WIFI config to HDD" >> $logFile
  sudo cp /etc/wpa_supplicant/wpa_supplicant.conf /mnt/hdd/app-data/wpa_supplicant.conf
fi

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

  # if not running TOR before starting LND internet connection with a valid public IP is needed
  waitForPublicIP=1
  if [ "${runBehindTor}" = "on" ] || [ "${runBehindTor}" = "1" ]; then
    echo "# no need to wait for internet - public Tor address already known" >> $logFile
    waitForPublicIP=0
  fi
  while [ ${waitForPublicIP} -eq 1 ]
    do
      source <(/home/admin/config.scripts/internet.sh status)
      if [ ${online} -eq 0 ]; then
        echo "# (loop) waiting for internet ... " >> $logFile
        sed -i "s/^state=.*/state=nointernet/g" ${infoFile}
        sed -i "s/^message=.*/message='Waiting for Internet'/g" ${infoFile}
        sleep 3
      else
        echo "# OK internet detected ... continue" >> $logFile
        waitForPublicIP=0
      fi
    done
  
  # update public IP on boot - set to domain is available
  /home/admin/config.scripts/internet.sh update-publicip ${lndAddress} 

fi

######################################################################
# MAKE SURE LND RPC/REST ports are standard & open to all connections 
######################################################################
sudo sed -i "s/^rpclisten=.*/rpclisten=0.0.0.0:10009/g" /mnt/hdd/lnd/lnd.conf
sudo sed -i "s/^restlisten=.*/restlisten=0.0.0.0:8080/g" /mnt/hdd/lnd/lnd.conf

#################################
# FIX BLOCKCHAINDATA OWNER (just in case)
# https://github.com/rootzoll/raspiblitz/issues/239#issuecomment-450887567
#################################
sudo chown bitcoin:bitcoin -R /mnt/hdd/bitcoin 2>/dev/null

#################################
# FIX BLOCKING FILES (just in case)
# https://github.com/rootzoll/raspiblitz/issues/1901#issue-774279088
# https://github.com/rootzoll/raspiblitz/issues/1836#issue-755342375
sudo rm -f /mnt/hdd/bitcoin/bitcoind.pid 2>/dev/null
sudo rm -f /mnt/hdd/bitcoin/.lock 2>/dev/null

#################################
# MAKE SURE USERS HAVE LATEST LND CREDENTIALS
#################################
source ${configFile}
if [ ${#network} -gt 0 ] && [ ${#chain} -gt 0 ]; then

  echo "running LND users credentials update" >> $logFile
  sudo /home/admin/config.scripts/lnd.credentials.sh sync >> $logFile

else 
  echo "skipping LND credientials sync" >> $logFile
fi

################################
# MOUNT BACKUP DRIVE
# if "localBackupDeviceUUID" is set in
# raspiblitz.conf mount it on boot
################################
source ${configFile}
echo "Checking if additional backup device is configured .. (${localBackupDeviceUUID})" >> $logFile
if [ "${localBackupDeviceUUID}" != "" ] && [ "${localBackupDeviceUUID}" != "off" ]; then
  echo "Yes - Mounting BackupDrive: ${localBackupDeviceUUID}" >> $logFile
  sudo /home/admin/config.scripts/blitz.backupdevice.sh mount >> $logFile
else
  echo "No additional backup device was configured." >> $logFile
fi

################################
# DETECT FRESHLY RECOVERED SD
################################

recoveredInfoExists=$(ls /home/admin/recover.flag | grep -c '.flag')
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
  source /mnt/hdd/bitcoin/bitcoin.conf >/dev/null 2>&1
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
# DELETE LOG & LOCK FILES
################################
# LND and Blockchain Errors will be still in systemd journals

# /mnt/hdd/bitcoin/debug.log
sudo rm /mnt/hdd/${network}/debug.log 2>/dev/null
# /mnt/hdd/lnd/logs/bitcoin/mainnet/lnd.log
sudo rm /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log 2>/dev/null
# https://github.com/rootzoll/raspiblitz/issues/1700
sudo rm /mnt/storage/app-storage/electrs/db/mainnet/LOCK 2>/dev/null

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

###############################
# RAID data check (BRTFS)
###############################
# see https://github.com/rootzoll/raspiblitz/issues/360#issuecomment-467698260

if [ ${isRaid} -eq 1 ]; then
  echo "TRIGGERING BTRFS RAID DATA CHECK ..."
  echo "Check status with: sudo btrfs scrub status /mnt/hdd/"
  sudo btrfs scrub start /mnt/hdd/
fi

######################################
# PREPARE SUBSCRIPTIONS DATA DIRECTORY
######################################

if [ -d "/mnt/hdd/app-data/subscrptions" ]; then
  echo "OK: subscription data directory exists"
else
  echo "CREATE: subscription data directory"
  sudo mkdir /mnt/hdd/app-data/subscriptions
  sudo chown admin:admin /mnt/hdd/app-data/subscriptions
fi

# mark that node is ready now
sed -i "s/^state=.*/state=ready/g" ${infoFile}
sed -i "s/^message=.*/message='Node Running'/g" ${infoFile}

# make sure that bitcoin service is active
sudo systemctl enable ${network}d

sed -i "s/^setupPhase=.*/setupPhase='done'/g" ${infoFile}

echo "DONE BOOTSTRAP" >> $logFile
exit 0
