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


# FUNCTIONS to be used later on in the script

# wait until raspberry pi gets a local IP
function wait_for_local_network() {
  gotLocalIP=0
  until [ ${gotLocalIP} -eq 1 ]
  do
    localip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0|veth' | egrep -i '(*[eth|ens|enp|eno|wlan|wlp][0-9]$)' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
    if [ ${#localip} -eq 0 ]; then
      configWifiExists=$(sudo cat /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null| grep -c "network=")
      if [ ${configWifiExists} -eq 0 ]; then
        # display user to connect LAN
        sed -i "s/^state=.*/state=noIP/g" ${infoFile}
        sed -i "s/^message=.*/message='Connect the LAN/WAN'/g" ${infoFile}
      else
        # display user that wifi settings are not working
        sed -i "s/^state=.*/state=noIP/g" ${infoFile}
        sed -i "s/^message=.*/message='WIFI Settings not working'/g" ${infoFile}
      fi
    elif [ "${localip:0:4}" = "169." ]; then
      # display user waiting for DHCP
      sed -i "s/^state=.*/state=noDCHP/g" ${infoFile}
      sed -i "s/^message=.*/message='Waiting for DHCP'/g" ${infoFile}
    else
      gotLocalIP=1
    fi
    sleep 1
  done
}

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
# see https://github.com/rootzoll/raspiblitz/issues/1265#issuecomment-813369284
displayClass="lcd"
displayType=""

# try to load old values if available (overwrites defaults)
source ${infoFile} 2>/dev/null

# try to load config values if available (config overwrites info)
source ${configFile} 2>/dev/null

# resetting info file
echo "Resetting the InfoFile: ${infoFile}"
echo "state=starting" > $infoFile
echo "message=" >> $infoFile
echo "baseimage=${baseimage}" >> $infoFile
echo "cpu=${cpu}" >> $infoFile
echo "network=${network}" >> $infoFile
echo "chain=${chain}" >> $infoFile
echo "fsexpanded=${fsexpanded}" >> $infoFile
echo "lcd2hdmi=${lcd2hdmi}" >> $infoFile
echo "displayClass=${displayClass}" >> $infoFile
echo "displayType=${displayType}" >> $infoFile
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
# see https://github.com/rootzoll/raspiblitz/pull/1580
randnum=$(shuf -i 0-7 -n 1)
lcdExists=$(sudo ls /dev/fb1 2>/dev/null | grep -c "/dev/fb1")
if [ ${lcdExists} -eq 1 ] ; then
   # LCD
   sudo fbi -a -T 1 -d /dev/fb1 --noverbose /home/admin/raspiblitz/pictures/startlogo${randnum}.png
else
   # HDMI
   sudo fbi -a -T 1 -d /dev/fb0 --noverbose /home/admin/raspiblitz/pictures/startlogo${randnum}.png
fi
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
  # LCD info
  sudo sed -i "s/^state=.*/state=recovering/g" ${infoFile}
  sudo sed -i "s/^message=.*/message='After Boot Setup (takes time)'/g" ${infoFile}
  # echo out script to journal logs
  sudo cat /home/admin/setup.sh
  # execute the after boot script
  echo "Logs in stored to: /home/admin/raspiblitz.recover.log"
  echo "\n***** RUNNING AFTER BOOT SCRIPT ******** " >> /home/admin/raspiblitz.recover.log
  sudo /home/admin/setup.sh >> /home/admin/raspiblitz.recover.log
  # delete the after boot script
  sudo rm /home/admin/setup.sh 
  # reboot again
  echo "DONE wait 10 secs ... one more reboot needed ... " >> /home/admin/raspiblitz.recover.log
  sudo shutdown -r now
  sleep 100
  exit 0
fi

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
  echo "Switching HDMI ON ... (reboot) " >> /home/admin/raspiblitz.recover.log
  sudo /home/admin/config.scripts/blitz.display.sh hdmi on
  exit 0
fi

################################
# UPDATE LCD DRIVERS IF NEEEDED
################################

if [ "${lcd2hdmi}" != "on" ]; then
  sudo /home/admin/config.scripts/blitz.display.sh check-repair >> $logFile
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
  sudo rm /boot/ssh.reset*
  # show info ssh reset
  sed -i "s/^state=.*/state=sshreset/g" ${infoFile}
  sed -i "s/^message=.*/message='resetting SSH & reboot'/g" ${infoFile}
  # delete ssh certs
  sudo systemctl stop sshd
  sudo rm /mnt/hdd/ssh/ssh_host*
  sudo ssh-keygen -A
  echo "SSH SERVER CERTS RESET ... (reboot) " >> /home/admin/raspiblitz.recover.log
  sudo /home/admin/XXshutdown.sh reboot
  exit 0
fi

################################
# HDD CHECK & PRE-INIT
################################
 
# Without LCD message needs to be printed
# wait loop until HDD is connected
echo ""
until [ ${isMounted} -eq 1 ] || [ ${#hddCandidate} -gt 0 ]
do
  source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
  echo "isMounted: $isMounted" >> $logFile
  echo "hddCandidate: $hddCandidate" >> $logFile
  message="Connect the Hard Drive"
  echo $message
  if [ ${isMounted} -eq 0 ] && [ ${#hddCandidate} -eq 0 ]; then
    sed -i "s/^state=.*/state=noHDD/g" ${infoFile}
    sed -i "s/^message=.*/message='$message'/g" ${infoFile}
  fi
  sleep 2
done

# write info for LCD
sed -i "s/^state=.*/state=booting/g" ${infoFile}
sed -i "s/^message=.*/message='please wait'/g" ${infoFile}

# get fresh info about data drive to continue
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
echo "isMounted: $isMounted" >> $logFile

# check if UASP is already deactivated (on RaspiOS)
# https://www.pragmaticlinux.com/2021/03/fix-for-getting-your-ssd-working-via-usb-3-on-your-raspberry-pi/
cmdlineExists=$(sudo ls /boot/cmdline.txt 2>/dev/null | grep -c "cmdline.txt")
if [ ${cmdlineExists} -eq 1 ] && [ ${#hddAdapterUSB} -gt 0 ] && [ ${hddAdapterUSAP} -eq 0 ]; then
  echo "Checking for UASP deactivation ..." >> $logFile
  usbQuirkActive=$(sudo cat /boot/cmdline.txt | grep -c "usb-storage.quirks=")
  # check if its maybe other device
  usbQuirkDone=$(sudo cat /boot/cmdline.txt | grep -c "usb-storage.quirks=${hddAdapterUSB}:u")
  if [ ${usbQuirkActive} -gt 0 ] && [ ${usbQuirkDone} -eq 0 ]; then
    # remove old usb-storage.quirks
    sudo sed -i "s/usb-storage.quirks=[^ ]* //g" /boot/cmdline.txt
  fi 
  if [ ${usbQuirkDone} -eq 0 ]; then
    # add new usb-storage.quirks
    sudo sed -i "1s/^/usb-storage.quirks=${hddAdapterUSB}:u /" /boot/cmdline.txt
    sudo cat /boot/cmdline.txt
    # go into reboot to activate new setting
    echo "DONE deactivating UASP for ${hddAdapterUSB} ... one more reboot needed ... "
    sudo shutdown -r now
    sleep 100
  fi
else 
  echo "Skipping UASP deactivation ... cmdlineExists(${cmdlineExists}) hddAdapterUSB(${hddAdapterUSB}) hddAdapterUSAP(${hddAdapterUSAP})" >> $logFile
fi

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

  # check if there is a WIFI configuration to backup or restore
  sudo /home/admin/config.scripts/internet.wifi.sh backup-restore

  # make sure at this point local network is connected
  wait_for_local_network

  # make sure before update/recovery that a internet connection is working
  wait_for_local_internet

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
    echo "shutdown in 1min" >> $logFile
    # save log file for inspection before reboot
    cp $logFile /home/admin/raspiblitz.recover.log
    sync
    echo "SSH SERVER CERTS RESET ... (reboot) " >> /home/admin/raspiblitz.recover.log
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

# make sure at this point local network is connected
wait_for_local_network

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
        sleep 4
      else
        echo "# OK internet detected ... continue" >> $logFile
        waitForPublicIP=0
      fi
    done
  
  # update public IP on boot - set to domain is available
  /home/admin/config.scripts/internet.sh update-publicip ${lndAddress} 

fi

#################################
# FIX BLOCKCHAINDATA OWNER (just in case)
# https://github.com/rootzoll/raspiblitz/issues/239#issuecomment-450887567
#################################
sudo chown bitcoin:bitcoin -R /mnt/hdd/bitcoin 2>/dev/null


#################################
# FIX BLOCKING FILES (just in case)
# https://github.com/rootzoll/raspiblitz/issues/1901#issue-774279088
# https://github.com/rootzoll/raspiblitz/issues/1836#issue-755342375
sudo rm -f /home/bitcoin/.bitcoin/bitcoind.pid 2>/dev/null
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

################################
# STRESSTEST RASPBERRY PI
################################

if [ "${baseimage}" = "raspbian" ] || [ "${baseimage}" = "raspios_arm64" ]; then
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

# make sure that bitcoin service is active
sudo systemctl enable ${network}d

echo "DONE BOOTSTRAP" >> $logFile
exit 0
