#!/bin/bash

# This script runs on every start called by boostrap.service
# see logs with --> tail -n 100 /home/admin/raspiblitz.log

# NOTE: this boostrap script runs as root user (bootstrap.service) - so no sudo needed

################################
# BASIC SETTINGS
################################

# load codeVersion
source /home/admin/_version.info

# CONFIGFILE - configuration of RaspiBlitz
# used by fresh SD image to recover configuration
# and delivers basic config info for scripts 
configFile="/mnt/hdd/app-data/raspiblitz.conf"

# LOGFILE - store debug logs of bootstrap
# resets on every start
logFile="/home/admin/raspiblitz.log"

# INFOFILE - state data from bootstrap
# used by display and later setup steps
infoFile="/home/admin/raspiblitz.info"

# SETUPFILE
# this key/value file contains the state during the setup process
setupFile="/var/cache/raspiblitz/temp/raspiblitz.setup"

 # make sure ram disk is mounted
/home/admin/_cache.sh ramdisk on 

# Backup last log file if available
cp ${logFile} /home/admin/raspiblitz.last.log 2>/dev/null

# Init boostrap log file
echo "Writing logs to: ${logFile}"
echo "" > $logFile
chmod 640 ${logFile}
chown root:sudo ${logFile}
echo "***********************************************" >> $logFile
echo "Running RaspiBlitz Bootstrap ${codeVersion}" >> $logFile
date >> $logFile
echo "***********************************************" >> $logFile

# list all running systemd services for future debug
systemctl list-units --type=service --state=running >> $logFile

# make sure ssh is configured and running
echo "# make sure SSH server is configured & running" >> $logFile
/home/admin/config.scripts/blitz.ssh.sh checkrepair >> $logFile

echo "## prepare raspiblitz temp" >> $logFile

# make sure /var/cache/raspiblitz/temp exists
mkdir -p /var/cache/raspiblitz/temp
chmod 777 /var/cache/raspiblitz/temp

################################
# INIT raspiblitz.info
################################
# raspiblitz.info contains the persisted system state
# that either given by build or has to survive a reboot
echo "## INIT raspiblitz.info" >> $logFile

# set default values for raspiblitz.info (that are not set by build_sdcard.sh)

setupPhase='boot'
setupStep=0
fsexpanded=0
blitzapi='off'

btc_mainnet_sync_initial_done=0
btc_testnet_sync_initial_done=0
btc_signet_sync_initial_done=0

ln_lnd_mainnet_sync_initial_done=0
ln_lnd_testnet_sync_initial_done=0
ln_lnd_signet_sync_initial_done=0

ln_cl_mainnet_sync_initial_done=0
ln_cl_testnet_sync_initial_done=0
ln_cl_signet_sync_initial_done=0

# detect VM
vm=0
if [ $(systemd-detect-virt) != "none" ]; then
  vm=1
fi

# load already persisted valued (overwriting defaults if exist)
source ${infoFile} 2>/dev/null

# write fresh raspiblitz.info file
echo "state=starting" > $infoFile
echo "message=starting" >> $infoFile
echo "setupPhase=${setupPhase}" >> $infoFile
echo "setupStep=${setupStep}" >> $infoFile
echo "baseimage=${baseimage}" >> $infoFile
echo "cpu=${cpu}" >> $infoFile
echo "vm=${vm}" >> $infoFile
echo "blitzapi=${blitzapi}" >> $infoFile
echo "displayClass=${displayClass}" >> $infoFile
echo "displayType=${displayType}" >> $infoFile
echo "fsexpanded=${fsexpanded}" >> $infoFile
echo "btc_mainnet_sync_initial_done=${btc_mainnet_sync_initial_done}" >> $infoFile
echo "btc_testnet_sync_initial_done=${btc_testnet_sync_initial_done}" >> $infoFile
echo "btc_signet_sync_initial_done=${btc_signet_sync_initial_done}" >> $infoFile
echo "ln_lnd_mainnet_sync_initial_done=${ln_lnd_mainnet_sync_initial_done}" >> $infoFile
echo "ln_lnd_testnet_sync_initial_done=${ln_lnd_testnet_sync_initial_done}" >> $infoFile
echo "ln_lnd_signet_sync_initial_done=${ln_lnd_signet_sync_initial_done}" >> $infoFile
echo "ln_cl_mainnet_sync_initial_done=${ln_cl_mainnet_sync_initial_done}" >> $infoFile
echo "ln_cl_testnet_sync_initial_done=${ln_cl_testnet_sync_initial_done}" >> $infoFile
echo "ln_cl_signet_sync_initial_done=${ln_cl_signet_sync_initial_done}" >> $infoFile

chmod 664 ${infoFile}

# write content of raspiblitz.info to logs
cat $infoFile >> $logFile

# determine correct raspberrypi boot drive path (that easy to access when sd card is insert into laptop)
raspi_bootdir="/boot/firmware"

######################################
# STOP flags - for manual provision

# when a file 'stop' is on the sd card bootfs partition root - stop for manual provision (raspberrypi)
flagExists=$(ls ${raspi_bootdir}/stop 2>/dev/null | grep -c 'stop')
# when a file 'stop' is in the /home/admin directory - stop for manual provision (laptop)
if [ "${flagExists}" = "0" ]; then
  flagExists=$(ls /home/admin/stop 2>/dev/null | grep -c 'stop')
fi
if [ "${flagExists}" = "1" ]; then
  localip=$(hostname -I | awk '{print $1}')
  /home/admin/_cache.sh set state "stop"
  /home/admin/_cache.sh set message "stopped for manual provision ${localip}"
  systemctl stop background.service
  systemctl stop background.scan.service
  # log info
  echo "INFO: 'bootstrap stopped - run command release after manual provison to remove stop flag" >> ${logFile}
  exit 0
fi

# VM stop signal for manual provision - when an audio device is detected on a VM
flagExists=$(lspci | grep -c "Audio")
if [ "${vm}" = "1"  ] && [ ${flagExists} -gt 0 ]; then
  localip=$(hostname -I | awk '{print $1}')
  /home/admin/_cache.sh set state "stop"
  /home/admin/_cache.sh set message "VM stopped for manual provision"
  systemctl stop background.service
  systemctl stop background.scan.service
  # log info
  echo "INFO: 'bootstrap stopped - remove the audio device from the VM" >> ${logFile}
  exit 0
fi

# when the provision did not ran thru without error (ask user for fresh sd card)
provisionFlagExists=$(ls /home/admin/provision.flag | grep -c 'provision.flag')
if [ "${provisionFlagExists}" = "1" ]; then
  systemctl stop ${network}d 2>/dev/null
  /home/admin/_cache.sh set state "inconsistentsystem"
  /home/admin/_cache.sh set message "provision did not ran thru"
  echo "FAIL: 'provision did not ran thru' - need fresh sd card!" >> ${logFile}
  rm /mnt/hdd/app-data/raspiblitz.setup
  exit 1
fi

#########################
# INIT RaspiBlitz Cache
#########################

# make sure that redis service is enabled (disabled on fresh install medium)
redisEnabled=$(systemctl is-enabled redis-server | grep -c "enabled")
echo "## redisEnabled(${redisEnabled})" >> $logFile
if [ ${redisEnabled} -eq 0 ]; then
  echo "# make sure redis is running" >> $logFile
  sleep 6
  systemctl status redis-server >> $logFile
  systemctl enable redis-server >> $logFile
  systemctl start redis-server >> $logFile
  systemctl status redis-server >> $logFile
fi

# make sure latest info file is imported
/home/admin/_cache.sh import $infoFile

# setting basic status info
/home/admin/_cache.sh set state "starting"
/home/admin/_cache.sh set message "bootstrap"

# try to load config values if available (config overwrites info)
source ${configFile} 2>/dev/null

# monitor LAN connection fast to display local IP changes
/home/admin/_cache.sh focus internet_localip 0

################################
# SET WIFI (by file)
################################

# File: wpa_supplicant.conf
# legacy way to set wifi of rasperrypi
wpaFileExists=$(ls ${raspi_bootdir}/wpa_supplicant.conf 2>/dev/null | grep -c 'wpa_supplicant.conf')
if [ "${wpaFileExists}" = "1" ]; then  
  echo "Getting data from file: ${raspi_bootdir}/wpa_supplicant.conf" >> ${logFile}
  ssid=$(grep ssid "${raspi_bootdir}/wpa_supplicant.conf" | awk -F'=' '{print $2}' | tr -d '"')
  password=$(grep psk "${raspi_bootdir}/wpa_supplicant.conf" | awk -F'=' '{print $2}' | tr -d '"')
fi

# File: wifi
# get first line as string from wifi file (NAME OF WIFI)
# get second line as string from wifi file (PASSWORD OF WIFI)
wifiFileExists=$(ls ${raspi_bootdir}/wifi 2>/dev/null | grep -c 'wifi')
if [ "${wifiFileExists}" = "1" ]; then
  echo "Getting data from file: ${raspi_bootdir}/wifi" >> ${logFile}
  ssid=$(sed -n '1p' ${raspi_bootdir}/wifi | tr -d '[:space:]')
  password=$(sed -n '2p' ${raspi_bootdir}/wifi | tr -d '[:space:]')
fi

# set wifi if data is available
if [ "${ssid}" != "" ] && [ "${password}" != "" ]; then
  echo "Setting Wifi ..." >> ${logFile}
  echo "ssid(${ssid}) password(${password})" >> ${logFile}
  /home/admin/_cache.sh set message "setting wifi"
  err=""
  echo "Setting Wifi SSID(${ssid}) Password(${password})" >> ${logFile}
  source <(/home/admin/config.scripts/internet.wifi.sh on ${ssid} ${password})
  if [ "${err}" != "" ]; then
    echo "Setting Wifi failed - edit or remove file ${raspi_bootdir}/wifi" >> ${logFile}
    echo "error(${err})" >> ${logFile}
    echo "Will shutdown in 1min ..." >> ${logFile}
    /home/admin/_cache.sh set state "errorWIFI"
    /home/admin/_cache.sh set message "${err}"
    sleep 60
    shutdown now
    exit 1
  fi
  rm ${raspi_bootdir}/wifi 2>/dev/null
  rm ${raspi_bootdir}/wpa_supplicant.conf 2>/dev/null
fi

################################
# CLEANING BOOT SYSTEM
################################

# Emergency cleaning logs when over 1GB (to prevent SD card filling up)
# see https://github.com/rootzoll/raspiblitz/issues/418#issuecomment-472180944
echo "*** Checking Log Size ***"
logsMegaByte=$(du -c -m /var/log | grep "total" | awk '{print $1;}')
if [ ${logsMegaByte} -gt 1000 ]; then
  echo "WARN # Logs /var/log in are bigger then 1GB" >> $logFile
  # dont delete directories - can make services crash
  rm /var/log/*
  service rsyslog restart
  /home/admin/_cache.sh set message "WARNING: /var/log/ >1GB"
  echo "WARN # Logs in /var/log in were bigger then 1GB and got emergency delete to prevent fillup." >> $logFile
  ls -la /var/log >> $logFile
  echo "If you see this in the logs please report to the GitHub issues, so LOG config needs to be optimized." >> $logFile
  sleep 10
else
  echo "OK - logs are at ${logsMegaByte} MB - within safety limit" >> $logFile
fi
echo ""

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

######################################
# WAIT FOR FIRST FULL BACKGROUND SCAN
echo "## RaspiBlitz Cache ... wait background.scan.service to finish first scan loop" >> $logFile
systemscan_runtime=""
while [ "${systemscan_runtime}" = "" ]
do
  sleep 1
  source <(/home/admin/_cache.sh get systemscan_runtime)
  echo "- waiting for background.scan.service --> systemscan_runtime(${systemscan_runtime})" >> $logFile
done

################################
# WAIT LOOP: HDD CONNECTED
# (old RaspiBlitz Setup)
################################

echo "Waiting for HDD/SSD ..." >> $logFile

scenario="" # run loop at least on time
until [ ${#scenario} -gt 0 ] && [[ ! "${scenario}" =~ ^error ]]; do

  # recheck HDD/SSD
  source <(/home/admin/config.scripts/blitz.data.sh status)
  echo "blitz.data.sh status - scenario: ${scenario}" >> $logFile

  # in case of HDD analyse ERROR
  if [ "${scenario}" = "error:no-storage" ]; then
    /home/admin/_cache.sh set state "noHDD"
    /home/admin/_cache.sh set message ">=1TB"
  elif [ "${scenario}" =~ ^error ]; then
    echo "FAIL - error on HDD analysis: ${scenario}" >> $logFile
    /home/admin/_cache.sh set state "errorHDD"
    /home/admin/_cache.sh set message "${scenario}"
  fi

  # wait for next check
  sleep 2
  
done

################################
# GPT integrity check
################################

# List all block devices
devices=$(lsblk -dno NAME | grep -E '^sd|^nvme|^vd|^mmcblk')
# Check and fix each device
for dev in $devices; do
  device="/dev/$dev"
  output=$(sudo gdisk -l $device 2>&1)
  if echo "$output" | grep -q "PMBR size mismatch"; then
    echo "GPT PMBR size mismatch detected on $device. Fixing..." >> $logFile
    sgdisk -e $device
    echo "Fixed GPT PMBR size mismatch on $device." >> $logFile
  elif echo "$output" | grep -q "The backup GPT table is not on the end of the device"; then
    echo "Backup GPT table is not at the end of $device. Fixing..." >> $logFile
    sgdisk -e $device
    echo "Fixed backup GPT table location on $device." >> $logFile
  else
    echo "No GPT issues detected on $device." >> $logFile
  fi
done

#####################################
# PRE-SETUP INIT (ALL SYSTEMS)
#####################################

if [ "${scenario}" != "ready" ] ; then

  # write info for LCD
   echo "## PRE-SETUP INIT (ALL SYSTEMS)" >> $logFile
  /home/admin/_cache.sh set state "system-init"
  /home/admin/_cache.sh set message "please wait"

  # now that HDD/SSD is connected ... if relevant data from a previous RaspiBlitz was available
  # /var/cache/raspiblitz/hdd-inspect exists with copy of config data to init system with
  echo "STORAGE connected .. run inspection" >> $logFile
  /home/admin/config.scripts/blitz.data.sh status -inspect >> $logFile

  #####################################
  # WIFI RESTORE
  # from former RaspiBlitz

  # check if there is a WIFI configuration to backup or restore
  if [ -d "/var/cache/raspiblitz/hdd-inspect/wifi" ]; then
    echo "WIFI RESTORE from /var/cache/raspiblitz/hdd-inspect/wpa_supplicant.conf" >> $logFile
    /home/admin/config.scripts/internet.wifi.sh backup-restore >> $logFile
  else
    echo "No WIFI RESTORE because no /var/cache/raspiblitz/hdd-inspect/wpa_supplicant.conf" >> $logFile
  fi

  ################################
  # SSH SERVER CERTS RESTORE
  # from former RaspiBlitz

  if [ -d "/var/cache/raspiblitz/hdd-inspect/sshd" ]; then
    # INIT OLD SSH HOST KEYS on Update/Recovery to prevent "Unknown Host" on ssh client
    echo "SSH SERVER CERTS RESTORE activating old SSH host keys" >> $logFile
    /home/admin/config.scripts/blitz.ssh.sh restore /var/cache/raspiblitz/hdd-inspect/sshd/ssh >> $logFile
  else
    echo "No SSH SERVER CERTS RESTORE because no /var/cache/raspiblitz/hdd-inspect" >> $logFile
  fi

fi

###################################
# WAIT LOOP: LOCALNET / INTERNET
# after HDD > can contain WIFI conf
###################################
while true; do

  # get latest network info directly
  source <(/home/admin/config.scripts/internet.sh status online)
  echo "internet.sh status localip(${localip}) online(${online})" >> $logFile

  # check state of network
  if [ "${dhcp}" = "0" ]; then
    # display user waiting for DHCP
    echo "Waiting for DHCP ..." >> $logFile
    /home/admin/_cache.sh set state "noDHCP"
    /home/admin/_cache.sh set message "Waiting for DHCP"
  elif [ "${localip}" = "" ]; then
    if [ "${configWifiExists}" = "0" ]; then
      # display user to connect LAN
      echo "Waiting for LAN/WAN ..." >> $logFile
      /home/admin/_cache.sh set state "noIP-LAN"
      /home/admin/_cache.sh set message "Connect the LAN/WAN"
    else
      # display user that wifi settings are not working
      echo "WIFI Settings not working ..." >> $logFile
      /home/admin/_cache.sh set state "noIP-WIFI"
      /home/admin/_cache.sh set message "WIFI Settings not working"
    fi
  elif [ "${online}" = "0" ]; then
    # display user that internet is missing (needed for firmware updates)
    echo "Waiting for internet ..." >> $logFile
    /home/admin/_cache.sh set state "noInternet"
    /home/admin/_cache.sh set message "No connection to Internet"
  else
    echo "OK got localIP & Internet .." >> $logFile
    break
  fi
  sleep 1
done

#####################################
# PRE-SETUP INIT(RASPBERRY PI)
#####################################

if [ "${scenario}" != "ready" ] && [ "${baseimage}" = "raspios_arm64" ]; then

  echo "## PRE-SETUP INIT(RASPBERRY PI)" >> $logFile

  # set flag for reboot (only needed on raspberry pi)
  systemInitReboot=0

  ################################
  # FS EXPAND
  # extend sd card to maximum capacity

  source <(/home/admin/config.scripts/blitz.bootdrive.sh status)
  if [ "${needsExpansion}" = "1" ] && [ "${fsexpanded}" = "0" ]; then
    echo "FSEXPAND needed ... starting process" >> $logFile
    /home/admin/config.scripts/blitz.bootdrive.sh status >> $logFile
    /home/admin/config.scripts/blitz.bootdrive.sh fsexpand >> $logFile
    systemInitReboot=1
    /home/admin/_cache.sh set message "FSEXPAND"
  elif [ "${tooSmall}" = "1" ]; then
    echo "# FAIL #######" >> $logFile
    echo "SDCARD TOO SMALL 16GB minimum" >> $logFile
    echo "##############" >> $logFile
    /home/admin/_cache.sh set state "sdtoosmall"
    echo "System stopped. Please cut power." >> $logFile
    sleep 6000
    shutdown now
    sleep 100
    exit 1
  else
    echo "No FS EXPAND needed. needsExpansion(${needsExpansion}) fsexpanded(${fsexpanded})" >> $logFile
  fi

  ################################
  # FORCED SWITCH TO HDMI
  # if a file called 'hdmi' gets
  # placed onto the bootfs part of
  # the sd card - switch to hdmi

  forceHDMIoutput=$(ls ${raspi_bootdir}/hdmi* 2>/dev/null | grep -c hdmi)
  if [ ${forceHDMIoutput} -eq 1 ]; then
    /home/admin/_cache.sh set message "HDMI"
    # delete that file (to prevent loop)
    rm ${raspi_bootdir}/hdmi*
    # switch to HDMI what will trigger reboot
    echo "HDMI switch found ... activating HDMI display output & flag reboot" >> $logFile
    /home/admin/config.scripts/blitz.display.sh set-display hdmi >> $logFile
    systemInitReboot=1
  else
    echo "No HDMI switch found. " >> $logFile
  fi

  ################################
  # SSH SERVER CERTS RESET
  # if a file called 'ssh.reset' gets
  # placed onto the boot part of
  # the sd card - delete old ssh data

  sshReset=$(ls ${raspi_bootdir}/ssh.reset* 2>/dev/null | grep -c reset)
  if [ ${sshReset} -eq 1 ]; then
    # delete that file (to prevent loop)
    rm ${raspi_bootdir}/ssh.reset* >> $logFile
    # delete ssh certs
    echo "SSHRESET switch found ... stopping SSH and deleting old certs" >> $logFile
    /home/admin/config.scripts/blitz.ssh.sh renew >> $logFile
    /home/admin/config.scripts/blitz.ssh.sh backup >> $logFile
    systemInitReboot=1
    /home/admin/_cache.sh set message "SSHRESET"
  else
    echo "No SSHRESET switch found. " >> $logFile
  fi

  ##################################
  # DISPLAY RESTORE (if needed)

  if [ -f "/var/cache/raspiblitz/hdd-inspect/raspiblitz.conf" ]; then

    echo "check that display class in raspiblitz.conf from HDD is different from as it is now in raspiblitz.info ..." >> $logFile
  
    # get display class value from raspiblitz.info
    source <(cat ${infoFile} | grep "^displayClass=")
    infoFileDisplayClass="${displayClass}"
    echo "infoFileDisplayClass(${infoFileDisplayClass})" >> $logFile

    # get display class value from raspiblitz.conf
    source <(cat /var/cache/raspiblitz/hdd-inspect/raspiblitz.conf | grep "^displayClass=")
    confFileDisplayClass="${displayClass}"
    echo "confFileDisplayClass(${confFileDisplayClass})" >> $logFile

    # check if values are different and need to change
    if [ "${confFileDisplayClass}" != "" ] && [ "${infoFileDisplayClass}" != "${displayClass}" ]; then
      echo "DISPLAY RESTORE - need to update displayClass from (${infoFileDisplayClass}) to (${confFileDisplayClass})'" >> ${logFile}
      /home/admin/config.scripts/blitz.display.sh set-display ${confFileDisplayClass} >> ${logFile}
      systemInitReboot=1
    else
      echo "No DISPLAY RESTORE because no need to change" >> $logFile
    fi

  else
    echo "No DISPLAY RESTORE because no /var/cache/raspiblitz/hdd-inspect/raspiblitz.conf" >> $logFile
  fi

  ################################
  # UASP FIX

  /home/admin/_cache.sh set message "checking HDD"
  source <(/home/admin/config.scripts/blitz.data.sh uasp-fix)
  if [ "${error}" != "" ]; then
    echo "UASP FIX failed: ${error}" >> $logFile
    /home/admin/_cache.sh set state "errorUASP"
    /home/admin/_cache.sh set message "${error}"
    exit 1
  fi
  if [ "${neededReboot}" = "1" ]; then
    echo "UASP FIX applied ... reboot needed." >> $logFile
    systemInitReboot=1
  else
    echo "No UASP FIX needed" >> $logFile
  fi

  ################################
  # RaspberryPi 5 - Firmware Update (needs internet)
  # https://github.com/raspiblitz/raspiblitz/issues/4359

  echo "checking Firmware" >> $logFile
  /home/admin/_cache.sh set message "checking Firmware"
  echo "getting data" >> $logFile
  raspberryPiVersion=$(tr -d '\0' 2>/dev/null < /sys/firmware/devicetree/base/model | sed -E 's/.*Raspberry Pi ([0-9]+).*/\1/')
  firmwareBuildNumber=$(rpi-eeprom-update 2>/dev/null | grep "CURRENT" | cut -d "(" -f2 | sed 's/[^0-9]*//g')
  echo "checking Firmware: isRaspberryPiVersion(${raspberryPiVersion}) firmwareBuildNumber(${firmwareBuildNumber})" >> $logFile
  if [ "${raspberryPiVersion}" != "" ] && [ ${raspberryPiVersion} -gt 4 ] && [ ${firmwareBuildNumber} -lt 1741626637 ]; then # Mon Mar 10 05:10:37 PM UTC 2025 (1741626637)
    echo "updating Firmware" >> $logFile
    echo "RaspberryPi 5 detected with old firmware (${firmwareBuildNumber}) ... do update." >> $logFile
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y rpi-eeprom
    rpi-eeprom-update -a
    systemInitReboot=1
  else
    echo "RaspberryPi Firmware no need for update." >> $logFile
  fi

  ######################################
  # CHECK IF REBOOT IS NEEDED
  # from actions above

  if [ "${systemInitReboot}" = "1" ]; then
    echo "Reboot" >> $logFile
    cp ${logFile} /home/admin/raspiblitz.systeminit.log
    /home/admin/_cache.sh set state "reboot"
    sleep 8
    shutdown -r now
    sleep 100
    exit 0
  else
    echo "No Reboot needed" >> $logFile
  fi

fi

############################
############################
# WHEN SETUP IS NEEDED  
############################

echo "Check if setup is needed --> scenario(${scenario})" >> $logFile
echo "Starting Bootstrap Setup Section: $( [ "${scenario}" != "ready" ] && echo "true" || echo "false" )" >> $logFile
if [ "${scenario}" != "ready" ] ; then

  echo "## WHEN SETUP IS NEEDED " >> $logFile
  echo "/home/admin/config.scripts/blitz.data.sh status -inspect (auto store to cache)" >> $logFile
  source <(/home/admin/config.scripts/blitz.data.sh status -inspect)

  # when there are no partitions on any drive - signal all drives are clean 
  /home/admin/_cache.sh set system_setup_cleanDrives "0"
  if [ "${storagePartitionsCount}" = "0" ] && [ "${dataPartitionsCount}" = "0" ]; then
    if [ "${systemMountedPath}" = "/" ] || [ "${systemPartitionsCount}" = "0" ]; then
      echo "INFO: no partitions on any drive - signal all drives are clean" >> $logFile
      /home/admin/_cache.sh set system_setup_cleanDrives "1"
    fi
  fi
  
  # add info if a flag shows that install medium was tried before
  if [ -f "/home/admin/systemcopy.flag" ]; then
    /home/admin/_cache.sh set "system_setup_secondtry" "1"
    rm /home/admin/systemcopy.flag
  else
    /home/admin/_cache.sh set "system_setup_secondtry" "0"
  fi

  # TODO: GET INFO FROM OTHER IMPLEMENTATIONS & COMPARE AGAINST LOCAL - not just LND
  # when migration check if for outdated btc, lnd, cln
  if [ "${scenario}" = "migration" ]; then 
    migrationMode="normal"
    if [ "${hddVersionLND}" != "" ]; then
      source <(/home/admin/config.scripts/lnd.install.sh info "${hddVersionLND}")
      if [ "${compatible}" != "1" ]; then
        migrationMode="outdatedLightning"
      fi 
    fi
    /home/admin/_cache.sh set migrationMode "${migrationMode}"
  fi

  # TODO: REPLACE THIS OLD VALUES IN SSH & WEBUI
  /home/admin/_cache.sh set hddCandidate "${hddCandidate}"
  /home/admin/_cache.sh set hddGigaBytes "${hddGigaBytes}"
  /home/admin/_cache.sh set hddBlocksBitcoin "${hddBlocksBitcoin}"
  /home/admin/_cache.sh set hddGotMigrationData "${hddGotMigrationData}"
  /home/admin/_cache.sh set hddVersionLND "${hddVersionLND}"

  # map scenario to setupPhase
  /home/admin/_cache.sh set "system_setup_askSystemCopy" "0"

  if [ "${scenario}" = "setup" ]; then
    setupPhase="setup"
    infoMessage="Please start Setup"
    /home/admin/_cache.sh set "system_setup_askSystemCopy" "${scenarioSystemCopy}"

  elif [ "${scenario}" = "biggerdevice" ]; then
    setupPhase="biggerdevice"
    infoMessage="Please start Setup"
    /home/admin/_cache.sh set "system_setup_askSystemCopy" "${scenarioSystemCopy}"

  elif [ "${scenario}" = "recover" ]; then
    setupPhase="recovery"
    infoMessage="Please start Recovery"
    /home/admin/_cache.sh set "system_setup_askSystemCopy" "${scenarioSystemCopy}"

  elif [ "${scenario}" = "migration" ]; then
    setupPhase="migration"
    infoMessage="Please start Migration"

  else
    setupPhase="error"
    infoMessage="Unkonwn Setup Phase"
  fi

  # check if raspiblitz.setup exists (from former system copy step)
   if [ -f "/var/cache/raspiblitz/hdd-inspect/raspiblitz.setup" ]; then

      # this is when booting from hdd after system copy
      echo "INFO: 'raspiblitz.setup' exists - skip user wait loop" >> ${logFile}
      cp -a /var/cache/raspiblitz/hdd-inspect/raspiblitz.setup ${setupFile}
      state="waitprovision"

  else
    echo "INFO: 'raspiblitz.setup' does not exist - wait for user config" >> ${logFile}
    state="waitsetup"
    /home/admin/_cache.sh set state "${state}"
    /home/admin/_cache.sh set message "${infoMessage}"
    /home/admin/_cache.sh set setupPhase "${setupPhase}"
  fi

  #############################################
  # WAIT LOOP: USER SETUP/UPDATE/MIGRATION
  # until SSH or WEBUI setup data is available
  #############################################

  echo "## WAIT LOOP: USER SETUP/UPDATE/MIGRATION" >> ${logFile}
  echo "state(${state})" >> ${logFile}
  until [ "${state}" = "waitprovision" ]
  do

    # give the loop a little bed time
    sleep 4

    # check for updated state value from SSH-UI or WEB-UI for loop
    source <(/home/admin/_cache.sh get state)

  done
  echo "## WAIT LOOP: DONE" >> ${logFile}

  echo "/home/admin/config.scripts/blitz.data.sh status -inspect (auto store to cache)"
  source <(/home/admin/config.scripts/blitz.data.sh status -inspect)

  # get the results from the SSH-UI or WEB-UI
  echo "LOADING 'raspiblitz.setup' ..." >> ${logFile}
  source ${setupFile}

  # overwrite recover by user choice
  if [ "${scenario}" = "recover" ] && [ "${menuchoice}" = "setup" ]; then
    echo "OVERWRITE BY USERCHOICE recover -> setup" >> ${logFile}
    scenario="setup"
    setupPhase="setup"
    /home/admin/_cache.sh set setupPhase "${setupPhase}"
  fi

  # when this is the boot of the new system (skip to provision)
  if [ "${systemCopy}" = "done" ]; then
    echo "INFO: 'systemCopy' is done - skip to provision / scenario(${scenario})" >> ${logFile}
    if [ "${scenario}" != "recover" ]; then
      echo "INFO: set scenario to setup" >> ${logFile}
      scenario="setup"
    fi
    setupCommand="skip"
    bootFromStorage=0

  # system recommended setup & system but user decided against - downgrade to simple setup
  elif [ "${scenario}" = "setup" ] && [ "${scenarioSystemCopy}" = "1" ] && [ "${systemCopy}" = "0" ] && [ "${deleteData}" = "all" ]; then
    echo "# downgrade to install medium setup" >> ${logFile}
    setupCommand="setup"
    bootFromStorage=0

  # system recommended setup & system but user decided against but keep blockhain - downgrade to simple setup 
  elif [ "${scenario}" = "setup" ] && [ "${scenarioSystemCopy}" = "1" ] && [ "${systemCopy}" = "0" ] && [ "${deleteData}" = "keepBlockchain" ]; then
    echo "# downgrade to install medium clean" >> ${logFile}
    setupCommand="clean"
    bootFromStorage=0

  # user agreed to system copy & delete all data
  elif [ "${scenario}" = "setup" ] && [ "${scenarioSystemCopy}" = "1" ] && [ "${systemCopy}" = "1" ] && [ "${deleteData}" = "all" ]; then
    echo "# user agreed to system copy & delete all data" >> ${logFile}
    setupCommand="setup"

  # user agreed to system copy & delete all data
  elif [ "${scenario}" = "setup" ] && [ "${scenarioSystemCopy}" = "1" ] && [ "${systemCopy}" = "1" ] && [ "${deleteData}" = "keepBlockchain" ]; then
    echo "# user agreed to system clean to keep blockchain" >> ${logFile}
    setupCommand="clean"

  # user agreed to run system from install medium and delete all data
  elif [ "${scenario}" = "setup" ] && [ "${deleteData}" = "all" ]; then
    echo "# user agreed to run system from install medium and delete all data" >> ${logFile}
    setupCommand="setup"
    bootFromStorage=0

  # user agreed to run system from install medium and keep blockchain
  elif [ "${scenario}" = "setup" ] && [ "${deleteData}" = "keepBlockchain" ]; then
    echo "# user agreed to run system from install medium and keep blockchain" >> ${logFile}
    setupCommand="clean"
    bootFromStorage=0

  # run recovery
  elif [ "${scenario}" = "recover" ]; then
    echo "# run recovery" >> ${logFile}
    setupCommand="recover"
  
  else
    echo "WARN: No matching scenario found" >> ${logFile}
  fi

  # even when the user decided not to run the system from storage/data drive
  # create a place holder partition for future system use
  # ONLY when a dedicated system device is available - dont create a system partition 
  createSystemPartion=1
  if [ ${#systemDevice} -gt 0 ]; then
    createSystemPartion=0
  fi

  echo "scenario(${scenario})" >> ${logFile}
  echo "scenarioSystemCopy(${scenarioSystemCopy})" >> ${logFile}    # recommended by system
  echo "systemCopy(${systemCopy})" >> ${logFile}                    # user choice
  echo "createSystemPartion(${createSystemPartion})" >> ${logFile}  # system partition
  echo "deleteData(${deleteData})" >> ${logFile}
  echo "setupCommand(${setupCommand})" >> ${logFile}
  echo "bootFromStorage(${bootFromStorage})" >> ${logFile}
  echo "storageDevice(${storageDevice})" >> ${logFile}
  echo "systemDevice(${systemDevice})" >> ${logFile}
  echo "dataDevice(${dataDevice})" >> ${logFile}

  ###############################################
  # SYSTEM COPY OF FRESH SYSTEM (SETUP & RECOVER)

  if [ "${setupCommand}" = "setup" ] || [ "${setupCommand}" = "recover" ] || [ "${setupCommand}" = "clean" ]; then

    echo "FORMAT/RECOVER DRIVES" >> ${logFile}
    /home/admin/_cache.sh set state "hdd-format"
    /home/admin/_cache.sh set message "formatting drives"

    # STORAGE
    echo "# storageDevice(${storageDevice}) storageMountedPath(${storageMountedPath})" >> ${logFile}
    if [ ${#storageDevice} -gt 0 ] && [ ${#storageMountedPath} -eq 0 ]; then
      error=""
      source <(/home/admin/config.scripts/blitz.data.sh ${setupCommand} STORAGE "${storageDevice}" "${combinedDataStorage}" "${createSystemPartion}")
      if [ "${error}" != "" ]; then
        echo "FAIL: '${setupCommand} STORAGE' failed error(${error})" >> ${logFile}
        /home/admin/_cache.sh set state "error"
        /home/admin/_cache.sh set message "${error}"
        exit 1
      fi
      echo "STORAGE: ${setupCommand} STORAGE done" >> ${logFile}
    fi

    # SYSTEM
    echo "# systemDevice(${systemDevice}) systemWarning(${systemWarning})" >> ${logFile}
    if [ ${#systemDevice} -gt 0 ] && [ "${bootFromStorage}" = "0" ] && [ ${#systemWarning} -eq 0 ]; then
      error=""
      source <(/home/admin/config.scripts/blitz.data.sh ${setupCommand} SYSTEM "${systemDevice}")
      if [ "${error}" != "" ]; then
        echo "FAIL: '${setupCommand} SYSTEM' failed error(${error})" >> ${logFile}
        /home/admin/_cache.sh set state "error"
        /home/admin/_cache.sh set message "${error}"
        exit 1
      fi
      echo "SYSTEM: ${setupCommand} SYSTEM done" >> ${logFile}
    else
      if [ "${systemMountedPath}" = "/" ]; then
        echo "SYSTEM: ${setupCommand} SYSTEM skipped - its active system" >> ${logFile}
      fi
    fi

    # DATA
    echo "# dataDevice(${dataDevice}) dataWarning(${dataWarning})" >> ${logFile}
    if [ ${#dataDevice} -gt 0 ] && [ ${#dataWarning} -eq 0 ]; then
      error=""
      source <(/home/admin/config.scripts/blitz.data.sh ${setupCommand} DATA "${dataDevice}")
      if [ "${error}" != "" ]; then
        echo "FAIL: '${setupCommand} DATA' failed error(${error})" >> ${logFile}
        /home/admin/_cache.sh set state "error"
        /home/admin/_cache.sh set message "${error}"
        exit 1
      fi
      echo "DATA: ${setupCommand} DATA done" >> ${logFile}
    fi

    # when system was installed on new boot drive
    echo "scenario(${scenario})" >> ${logFile}
    echo "systemCopy(${systemCopy})" >> ${logFile}

    #############################################
    # WAIT LOOP: 2nd SETUP UI WAIT LOOP
    # (after HDD/SSD is setup)
    ############################################

    # at the moment only needed for upload file migration
    echo "uploadMigration(${uploadMigration}) storagePartition(${storagePartition})" >> ${logFile}  
    if [ "${uploadMigration}" = "1" ]; then
      # trigger the 2nd setup loop
      state="waitsetup-extended"
      source <(/home/admin/config.scripts/blitz.migration.sh status)
      /home/admin/_cache.sh set "ui_migration_upload" "1"
      /home/admin/_cache.sh set "ui_migration_uploadUnix" "${uploadUnix}"
      /home/admin/_cache.sh set "ui_migration_uploadWin" "${uploadWin}"
      if [ "${storagePartition}" = "" ]; then
        echo "FAIL: storagePartition is empty" >> ${logFile}
        /home/admin/_cache.sh set state "error"
        /home/admin/_cache.sh set message "storagePartition empty"
        exit 1
      fi
      # prepare upload storage
      mkdir -p /mnt/upload 2>/dev/null
      mount /dev/${storagePartition} /mnt/upload
      mkdir -p /mnt/upload/temp 2>/dev/null
      chown -R admin:admin /mnt/upload
      chmod -R 777 /mnt/upload
      rm -rf /mnt/upload/temp/*
    else
      # skip the 2nd setup loop
      state="waitprovision"
    fi
    /home/admin/_cache.sh set state "${state}"

    echo "## 2nd WAIT LOOP: AFTER HDD/SETUP" >> ${logFile}
    echo "state(${state})" >> ${logFile}
    until [ "${state}" = "waitprovision" ]
    do

      # give the loop a little bed time
      sleep 4

      # check for updated state value from SSH-UI or WEB-UI for loop
      source <(/home/admin/_cache.sh get state)

    done
    echo "## 2nd WAIT LOOP: DONE" >> ${logFile}

    # detect possible uploaded migration file 
    source <(/home/admin/config.scripts/blitz.migration.sh status)
    if [ "${migrationFile}" != "" ]; then
      # wirite migration file to setup file
      echo "adding to ${setupFile} migrationFile(${migrationFile})" >> ${logFile}
      echo "migrationFile=${migrationFile}" >> ${setupFile}
    else
      if [ "${uploadMigration}" = "1" ]; then
        echo "FAIL: no migration file found" >> ${logFile}
        /home/admin/_cache.sh set state "error"
        /home/admin/_cache.sh set message "no migration file found"
        exit 1
      else
        echo "OK - no migration file found" >> ${logFile}
      fi
    fi
    umount /mnt/upload 2>/dev/null

    # pre-quick change of login passwort for admin
    # do proper passwordA setting later when HDD is mounted
    source ${setupFile}
    if [ "${passwordA}" != "" ]; then
      echo "## SETTING PASSWORD FOR ADMIN" >> ${logFile}
      echo "admin:${passwordA}" | chpasswd
    fi
    
    #############################################
    # SYSTEM COPY
    ############################################

    if [ "${systemCopy}" = "1" ]; then

      if [ "${systemDevice}" = "" ]; then
        echo "systemDevice() - using storageDevice for system" >> ${logFile}
        systemDevice="${storageDevice}"
        bootFromStorage=1
      fi

      echo "SYSTEM COPY OF FRESH SYSTEM" >> ${logFile}
      echo "bootFromStorage(${bootFromStorage})" >> ${logFile}
      echo "storageDevice(${storageDevice})" >> ${logFile}
      echo "systemDevice(${systemDevice})" >> ${logFile}
      echo "dataDevice(${dataDevice})" >> ${logFile}

      /home/admin/_cache.sh set state "systemcopy"
      /home/admin/_cache.sh set message "copying system"

      echo "bootFromStorage(${bootFromStorage})" >> ${logFile}
      if [ "${bootFromStorage}" = "1" ]; then
        /home/admin/config.scripts/blitz.data.sh copy-system "${storageDevice}" storage
        if [ $? -ne 0 ]; then
          echo "FAIL: copy-system (storage) failed" >> ${logFile}
          /home/admin/_cache.sh set state "error"
          /home/admin/_cache.sh set message "copy-system failed"
          exit 1
        fi
      else
        /home/admin/config.scripts/blitz.data.sh copy-system "${systemDevice}" system
        if [ $? -ne 0 ]; then
          echo "FAIL: copy-system (system) failed" >> ${logFile}
          /home/admin/_cache.sh set state "error"
          /home/admin/_cache.sh set message "copy-system failed"
          exit 1
        fi
      fi

      # mark systemCopy as done in raspiblitz.setup
      if ! sed -i "s/^systemCopy=.*/systemCopy=done/" "${setupFile}"; then
        echo "error='failed to update systemCopy in setupFile'" >> ${logFile}
        exit 1
      fi

      # put setupFile to new system (so after reboot it does not need to ask user again)
      source <(/home/admin/config.scripts/blitz.data.sh status)
      mkdir -p /mnt/disk_data 2>/dev/null
      mount /dev/${dataPartition} /mnt/disk_data
      echo "copy setupFile(${setupFile}) to /mnt/disk_data/app-data/raspiblitz.setup" >> ${logFile}
      mkdir -p /mnt/disk_data/app-data 2>/dev/null
      cp ${setupFile} /mnt/disk_data/app-data/raspiblitz.setup
      if [ $? -ne 0 ]; then
        echo "FAIL: copy setupFile to new system failed" >> ${logFile}
        /home/admin/_cache.sh set state "error"
        /home/admin/_cache.sh set message "copy setupFile to new system failed"
        exit 1
      fi
      umount /mnt/disk_data

      # put flag file into old system 
      touch /home/admin/systemcopy.flag

      # disable old system boot
      echo "# disable old system boot" >> ${logFile}
      /home/admin/config.scripts/blitz.data.sh kill-boot ${installDevice} >> ${logFile}
      if [ $? -eq 1 ]; then
        echo "FAIL: blitz.data.sh kill-boot \"${installDevice}\" failed" >> ${logFile}
        /home/admin/_cache.sh set state "error"
        /home/admin/_cache.sh set message "blitz.data.sh kill-boot failed"
        exit 1
      fi

      # reboot so that new system can start
      echo "GOING INTO REBOOT" >> ${logFile}
      /home/admin/_cache.sh set state "system-change"
      /home/admin/_cache.sh set message "changing boot device"
      # sync filesystem buffers
      sync
      # force write of memory-cached filesystem data
      sync; echo 3 > /proc/sys/vm/drop_caches
      # wait for sync to complete
      sleep 2
      shutdown -r now
      exit 0
    else
      # continue with setup
      echo "NO systemCopy" >> ${logFile}
    fi

  else
    echo "Skipping System Copy" >> ${logFile}
  fi

  #############################################
  # MIGRATION from old RaspiBlitz
  ############################################

  if [ "${hddMigration}" = "1" ]; then
    echo "## MIGRATION from old RaspiBlitz via old HDD" >> ${logFile}
    /home/admin/_cache.sh set state "hdd-migration"
    /home/admin/_cache.sh set message "${hddMigrateDeviceFrom} ${hddMigrateDeviceTo}"
    /home/admin/config.scripts/blitz.data.sh migration hdd run "${hddMigrateDeviceFrom}" >> ${logFile}
    if [ $? -ne 0 ]; then
      echo "FAIL: blitz.data.sh migration hdd run failed" >> ${logFile}
      /home/admin/_cache.sh set state "error"
      /home/admin/_cache.sh set message "blitz.migration.sh migrate failed"
      exit 1
    fi
    scenario="recovery"
    setupPhase="recovery"
    /home/admin/_cache.sh set setupPhase "${setupPhase}"
  fi

  #############################################
  # PROVISION PROCESS
  #############################################

  # set flag that provision process was started on this system 
  echo "the provision process was started but did not finish yet" > /home/admin/provision.flag

  # perma mount drives/partitions
  /home/admin/config.scripts/blitz.data.sh mount >> ${logFile}
  if [ $? -eq 1 ]; then
    echo "FAIL: blitz.data.sh mount failed" >> ${logFile}
    /home/admin/_cache.sh set state "error"
    /home/admin/_cache.sh set message "blitz.data.sh mount failed"
    exit 1
  fi

  # link directories together in /mnt/hdd (pre-provision)
  /home/admin/config.scripts/blitz.data.sh link >> ${logFile}
  if [ $? -eq 1 ]; then
    echo "FAIL: blitz.data.sh link failed" >> ${logFile}
    /home/admin/_cache.sh set state "error"
    /home/admin/_cache.sh set message "blitz.data.sh link failed"
    exit 1
  fi

  #############################################
  # MIGRATION from uploaded migration file
  ############################################

  # if migrationFile was uploaded (value from raspiblitz.setup) - now import
  source ${setupFile}
  echo "# migrationFile(/mnt/disk_storage/temp/${migrationFile})" >> ${logFile}
  if [ "${migrationFile}" != "" ]; then

    echo "##### IMPORT MIGRATIONFILE: ${migrationFile}" >> ${logFile}

    # unpack
    /home/admin/_cache.sh set message "Unpacking Migration Data"
    error=""
    source <(/home/admin/config.scripts/blitz.migration.sh import "/mnt/disk_storage/temp/${migrationFile}")

    # check for errors
    if [ "${error}" != "" ]; then 
      /home/admin/config.scripts/blitz.error.sh _bootstrap.sh "migration-import-error" "blitz.migration.sh import exited with error" "/home/admin/config.scripts/blitz.migration.sh import ${migrationFile} --> ${error}" ${logFile}
      exit 1
    fi

    # make sure a raspiblitz.conf exists after migration
    confExists=$(ls /mnt/hdd/app-data/raspiblitz.conf 2>/dev/null | grep -c "raspiblitz.conf")
    if [ "${confExists}" != "1" ]; then
      /home/admin/config.scripts/blitz.error.sh _bootstrap.sh "migration-failed" "missing-config" "After runnign migration process - no raspiblitz.conf abvailable." ${logFile}
      exit 1
    fi

    # make sure upload mount is deleted
    rm -rf /mnt/upload 2>/dev/null

    # signal recovery provision phase
    scenario="recovery"
    setupPhase="recovery"
    /home/admin/_cache.sh set setupPhase "${setupPhase}"
  fi

  if [ "${scenario}" = "setup" ]; then
    rm -f ${configFile}
    echo "# CREATING raspiblitz.conf from setup file" >> ${logFile}
    source /home/admin/_version.info
    source ${setupFile}
    touch ${configFile} >> ${logFile}
    echo "# RASPIBLITZ CONFIG FILE" > ${configFile}
    echo "raspiBlitzVersion='${codeVersion}'" >> ${configFile}
    echo "lcdrotate='1'" >> ${configFile}
    echo "lightning='${lightning}'" >> ${configFile}
    echo "network='bitcoin'" >> ${configFile}
    echo "chain='main'" >> ${configFile}
    echo "hostname='${hostname}'" >> ${configFile}
    echo "runBehindTor='on'" >> ${configFile}
    chown root:sudo ${configFile}
    chmod 664 ${configFile}
    echo "cat ${configFile}" >> ${logFile}
    cat ${configFile} >> ${logFile}
  fi

  # load fresh setup data
  echo "# Sourcing ${setupFile} " >> ${logFile}
  source ${setupFile}
  
  # enable tor service
  /home/admin/config.scripts/tor.install.sh enable >> ${logFile}

  # kick-off provision process
  /home/admin/_cache.sh set state "provision"
  /home/admin/_cache.sh set message "Starting Provision"

  # add some debug info to logfile
  echo "# df " >> ${logFile}
  df >> ${logFile}
  echo "# lsblk -o NAME,FSTYPE,LABEL " >> ${logFile}
  lsblk -o NAME,FSTYPE,LABEL >> ${logFile}

  # load fresh config data
  echo "# Sourcing ${configFile} " >> ${logFile}
  cat ${configFile} >> ${logFile}
  source ${configFile}

  # load fresh setup data
  echo "# Sourcing ${setupFile} " >> ${logFile}
  source ${setupFile}

  # make sure basic info is in raspiblitz.info
  /home/admin/_cache.sh set network "${network}"
  /home/admin/_cache.sh set chain "${chain}"
  /home/admin/_cache.sh set lightning "${lightning}"

  # Bitcoin Mainnet
  if [ "${mainnet}" = "on" ] || [ "${chain}" = "main" ]; then
    echo "Provisioning ${network} Mainnet - run config script" >> ${logFile}
    /home/admin/config.scripts/bitcoin.install.sh on mainnet >> ${logFile} 2>&1
  else
    echo "Provisioning ${network} Mainnet - not active" >> ${logFile}
  fi

  # Bitcoin Testnet
  if [ "${testnet}" = "on" ]; then
    echo "Provisioning ${network} Testnet - run config script" >> ${logFile}
    /home/admin/config.scripts/bitcoin.install.sh on testnet >> ${logFile} 2>&1
  else
    echo "Provisioning ${network} Testnet - not active" >> ${logFile}
  fi

  # Bitcoin Signet
  if [ "${signet}" = "on" ]; then
    echo "Provisioning ${network} Signet - run config script" >> ${logFile}
    /home/admin/config.scripts/bitcoin.install.sh on signet >> ${logFile} 2>&1
  else
    echo "Provisioning ${network} Signet - not active" >> ${logFile}
  fi

  # if setup - run provision setup first
  if [ "${setupPhase}" = "setup" ]; then
    echo "Calling _provision.setup.sh for basic setup tasks .." >> $logFile
    /home/admin/_cache.sh set message "Provision Setup"
    /home/admin/_provision.setup.sh
    errorState=$?
    if [ "$errorState" != "0" ]; then
      # only trigger an error message if the script hasnt itself triggered an error message already
      source <(/home/admin/_cache.sh get state)
      if [ "${state}" != "error" ]; then
        /home/admin/config.scripts/blitz.error.sh _bootstrap.sh "provision-setup-exit" "unknown or syntax error on (${errorState}) _provision.setup.sh" "" ${logFile}
      fi
      exit 1
    fi
  fi

  echo "# CHOOSE PROVISION: setupPhase(${setupPhase})" >> ${logFile}

  # if migration from other nodes - run the migration provision first
  if [ "${setupPhase}" = "migration" ]; then
    echo "Calling _provision.migration.sh for possible migrations .." >> $logFile
    /home/admin/_cache.sh set message "Provision migration"
    /home/admin/_provision.migration.sh
    errorState=$?
    if [ "$errorState" != "0" ]; then
      # only trigger an error message if the script hasnt itself triggered an error message already
      source <(/home/admin/_cache.sh get state)
      if [ "${state}" != "error" ]; then
        /home/admin/config.scripts/blitz.error.sh _bootstrap.sh "provision-migration-exit" "unknown or syntax error on (${errorState}) _provision.migration.sh" "" ${logFile}
      fi
      exit 1
    fi
  fi

  # if update/recovery/migration-followup
  if [ "${setupPhase}" = "update" ] || [ "${setupPhase}" = "recovery" ] || [ "${setupPhase}" = "migration" ]; then
    echo "Calling _provision.update.sh .." >> $logFile
    /home/admin/_cache.sh set message "Provision Update/Recovery/Migration"
    /home/admin/_provision.update.sh
    errorState=$?
    if [ "$errorState" != "0" ]; then
      # only trigger an error message if the script hasnt itself triggered an error message already
      source <(/home/admin/_cache.sh get state)
      if [ "${state}" != "error" ]; then
        /home/admin/config.scripts/blitz.error.sh _bootstrap.sh "provision-update-exit" "unknown or syntax error on (${errorState}) _provision.update.sh" "" ${logFile}
      fi
      exit 1
    fi
  fi
  
  # finalize provisioning
  echo "Calling _bootstrap.provision.sh for general system provisioning (${setupPhase}) .." >> $logFile
  /home/admin/_cache.sh set message "Provision Basics"
  /home/admin/_provision_.sh
  errorState=$?
  if [ "$errorState" != "0" ]; then
    # only trigger an error message if the script hasnt itself triggered an error message already
    source <(/home/admin/_cache.sh get state)
    if [ "${state}" != "error" ]; then
      /home/admin/config.scripts/blitz.error.sh _bootstrap.sh "provision-exit" "unknown or syntax error on (${errorState}) _provision_.sh" "" ${logFile}
    fi
    exit 1
  fi

  # everyone can read the config but it can only be
  # edited/written by root ot admin user (part of group sudo)
  chown root:sudo ${configFile}
  chmod 664 ${configFile}

  # delete provision in progress flag
  rm /home/admin/provision.flag
  rm /mnt/hdd/app-data/raspiblitz.setup 2>/dev/null

  # final relink of directories
  /home/admin/config.scripts/blitz.data.sh link >> ${logFile}
  if [ $? -eq 1 ]; then
    echo "FAIL: blitz.data.sh link failed (2)" >> ${logFile}
    /home/admin/_cache.sh set state "error"
    /home/admin/_cache.sh set message "blitz.data.sh link failed (2)"
    exit 1
  fi

  ###################################
  # Set Password A (in all cases)
  if [ "${passwordA}" = "" ]; then
    /home/admin/config.scripts/blitz.error.sh _bootstrap.sh "missing-passworda-2" "missing passwordA(2) in (${setupFile})" "" ${logFile}
    exit 1
  fi
  echo "# setting PASSWORD A" >> ${logFile}
  /home/admin/config.scripts/blitz.passwords.sh set a "${passwordA}" >> ${logFile}

  # mark provision process done
  /home/admin/_cache.sh set message "Provision Done"

  # wait until syncProgress is available (neeed for final dialogs)
  /home/admin/_cache.sh set state "waitsync"
  btc_default_ready="0"
  while [ "${btc_default_ready}" != "1" ]
  do
    source <(/home/admin/_cache.sh get btc_default_ready)
    echo "# waitsync loop ... btc_default_ready(${btc_default_ready})" >> $logFile
    sleep 2
  done

  # one time add info on blockchain sync to chache
  source <(/home/admin/_cache.sh get chain)
  source <(/home/admin/config.scripts/bitcoin.monitor.sh ${chain}net info)
  /home/admin/_cache.sh set btc_default_blocks_data_kb "${btc_blocks_data_kb}"

  ###################################################
  # HANDOVER TO FINAL SETUP CONTROLLER
  ###################################################

  echo "# HANDOVER TO FINAL SETUP CONTROLLER ..." >> $logFile
  /home/admin/_cache.sh set state "waitfinal"
  /home/admin/_cache.sh set message "Setup Done"

  # system has to wait before reboot to present like seed words and other info/options to user
  echo "BOOTSTRAP EXIT ... waiting for final setup controller to initiate final reboot." >> $logFile
  exit 1

else

  ############################
  ############################
  # NORMAL START BOOTSTRAP (not executed after setup)
  # Blockchain & Lightning not running
  ############################

  echo "# NORMAL START BOOTSTRAP" >> $logFile
  source <(/home/admin/config.scripts/blitz.data.sh status)

  #################################
  # FIX BLOCKCHAINDATA OWNER (just in case)
  # https://github.com/rootzoll/raspiblitz/issues/239#issuecomment-450887567
  #################################
  chown bitcoin:bitcoin -R /mnt/hdd/bitcoin 2>/dev/null

  #################################
  # FIX BLOCKING FILES (just in case)
  # https://github.com/rootzoll/raspiblitz/issues/1901#issue-774279088
  # https://github.com/rootzoll/raspiblitz/issues/1836#issue-755342375
  rm -f /mnt/hdd/bitcoin/bitcoind.pid 2>/dev/null
  rm -f /mnt/hdd/bitcoin/.lock 2>/dev/null

  ################################
  # DELETE LOG & LOCK FILES
  ################################
  # LND and Blockchain Errors will be still in systemd journals

  # limit debug.log to 10MB on start - see #3872
  if [ $(grep -c "shrinkdebugfile=" < /mnt/hdd/bitcoin/bitcoin.conf) -eq 0 ];then
    echo "shrinkdebugfile=1" | tee -a /mnt/hdd/bitcoin/bitcoin.conf
  fi
  # /mnt/hdd/app-data/lnd/logs/bitcoin/mainnet/lnd.log
  rm /mnt/hdd/app-data/lnd/logs/${network}/${chain}net/lnd.log 2>/dev/null
  # https://github.com/rootzoll/raspiblitz/issues/1700
  rm /mnt/storage/app-storage/electrs/db/mainnet/LOCK 2>/dev/null

  ####################################
  # EXPANDING PARTITIONS (for Proxmox)
  ####################################
  if [ ${#storagePartition} -gt 0 ] && [ ${#storageUnusedSpacePercent} -gt 0 ] && [ ${storageUnusedSpacePercent} != "0" ]; then
    echo "# EXPANDING STORAGE PARTITION" >> $logFile
    /home/admin/config.scripts/blitz.data.sh expand ${storagePartition} >> ${logFile}
  fi
  if [ ${#dataPartition} -gt 0 ] && [ "${combinedDataStorage}" = "0" ] && [ ${#dataUnusedSpacePercent} -gt 0 ] && [ ${dataUnusedSpacePercent} != "0" ]; then
    echo "# EXPANDING DATA PARTITION" >> $logFile
    /home/admin/config.scripts/blitz.data.sh expand ${dataPartition} >> ${logFile}
  fi

fi

##############################
##############################
# BOOSTRAP IN EVERY SITUATION
##############################
echo "# BOOSTRAP IN EVERY SITUATION" >> $logFile
/home/admin/_cache.sh set setupPhase "starting"

# make sure all is linked correctly
echo "blitz.data.sh link" >> $logFile
/home/admin/config.scripts/blitz.data.sh link >> ${logFile}

# load data from config file fresh
echo "load configfile data" >> $logFile
source ${configFile}

# if a WIFI config exists backup to HDD
source <(/home/admin/config.scripts/internet.sh status)
if [ ${configWifiExists} -eq 1 ]; then
  echo "Making Backup Copy of WIFI config to HDD" >> $logFile
  cp /etc/wpa_supplicant/wpa_supplicant.conf /mnt/hdd/app-data/wpa_supplicant.conf
fi

# always copy the latest display setting (maybe just in raspiblitz.info) to raspiblitz.conf
if [ "${displayClass}" != "" ]; then
  /home/admin/config.scripts/blitz.conf.sh set displayClass ${displayClass}
fi
if [ "${displayType}" != "" ]; then
  /home/admin/config.scripts/blitz.conf.sh set displayType ${displayType}
fi

# correct blitzapi config value
blitzApiRunning=$(ls /etc/systemd/system/blitzapi.service 2>/dev/null | grep -c "blitzapi.service")
if [ "${blitzapi}" = "" ] && [ ${blitzApiRunning} -eq 1 ]; then
  /home/admin/config.scripts/blitz.conf.sh set blitzapi "on"
fi

# make sure users have latest credentials (if lnd is on)
if [ "${lightning}" = "lnd" ] || [ "${lnd}" = "on" ]; then
  echo "running LND users credentials update" >> $logFile
  /home/admin/config.scripts/lnd.credentials.sh sync "${chain:-main}net" >> $logFile
else
  echo "skipping LND credentials sync" >> $logFile
fi

#####################################
# CLEAN HDD TEMP
#####################################
echo "CLEANING TEMP DRIVE/FOLDER" >> $logFile
if [ -d "/mnt/hdd/temp" ]; then
  echo "# Cleaning /mnt/hdd/temp" >> $logFile
  rm -rf /mnt/hdd/temp/*
else
  echo "# No /mnt/hdd/temp folder found" >> $logFile
fi

####################
# FORCE UASP FLAG
####################
# if uasp.force flag was set on sd card - now move into raspiblitz.conf
if [ -f "${raspi_bootdir}/uasp.force" ]; then
  /home/admin/config.scripts/blitz.conf.sh set forceUasp "on"
  rm ${raspi_bootdir}/uasp.force* >> $logFile
  echo "DONE forceUasp=on recorded in raspiblitz.conf" >> $logFile
fi

######################################
# PREPARE SUBSCRIPTIONS DATA DIRECTORY
######################################

if [ -d "/mnt/hdd/app-data/subscriptions" ]; then
  echo "OK: subscription data directory exists"
  chown admin:admin /mnt/hdd/app-data/subscriptions
else
  echo "CREATE: subscription data directory"
  mkdir /mnt/hdd/app-data/subscriptions
  chown admin:admin /mnt/hdd/app-data/subscriptions
fi

# make sure that bitcoin service is active
systemctl enable ${network}d

# make sure setup/provision is marked as done
/home/admin/_cache.sh set setupPhase "done"
/home/admin/_cache.sh set state "ready"
/home/admin/_cache.sh set message "Node Running"

# relax systemscan on certain values
/home/admin/_cache.sh focus internet_localip -1

# if node is stil in inital blockchain download
source <(/home/admin/_cache.sh get btc_default_sync_initialblockdownload)
if [ "${btc_default_sync_initialblockdownload}" = "1" ]; then
  echo "Node is still in IBD .. refresh btc_default_sync_progress faster" >> $logFile
  /home/admin/_cache.sh focus btc_default_sync_progress 0
fi

# backup wifi settings
/home/admin/config.scripts/internet.wifi.sh backup-restore

# notify about (re)start if activated
source <(/home/admin/_cache.sh get hostname)
/home/admin/config.scripts/blitz.notify.sh send "RaspiBlitz '${hostname}' (re)started" >> $logFile

echo "DONE BOOTSTRAP" >> $logFile
exit 0
