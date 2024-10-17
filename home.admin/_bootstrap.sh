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
configFile="/mnt/hdd/raspiblitz.conf"

# LOGFILE - store debug logs of bootstrap
# resets on every start
logFile="/home/admin/raspiblitz.log"

# INFOFILE - state data from bootstrap
# used by display and later setup steps
infoFile="/home/admin/raspiblitz.info"

# SETUPFILE
# this key/value file contains the state during the setup process
setupFile="/var/cache/raspiblitz/temp/raspiblitz.setup"

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
raspi_bootdir=""
if [ -d /boot/firmware ]; then
  raspi_bootdir="/boot/firmware"
elif [ -d /boot ]; then
  raspi_bootdir="/boot"
fi
echo "# raspi_bootdir(${raspi_bootdir})" >> $logFile

######################################
# STOP file flag - for manual provision

# when a file 'stop' is on the sd card bootfs partition root - stop for manual provision
flagExists=$(ls ${raspi_bootdir}/stop 2>/dev/null | grep -c 'stop')
if [ "${flagExists}" == "1" ]; then
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
if [ "${vm}" == "1"  ] && [ ${flagExists} -gt 0 ]; then
  localip=$(hostname -I | awk '{print $1}')
  /home/admin/_cache.sh set state "stop"
  /home/admin/_cache.sh set message "VM stopped for manual provision"
  systemctl stop background.service
  systemctl stop background.scan.service
  # log info
  echo "INFO: 'bootstrap stopped - remove the audio device from the VM" >> ${logFile}
  exit 0
fi

#########################
# INIT RaspiBlitz Cache
#########################

# make sure that redis service is enabled (disabled on fresh sd card image)
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

echo "## INIT RaspiBlitz Cache ... wait background.scan.service to finish first scan loop" >> $logFile
systemscan_runtime=""
while [ "${systemscan_runtime}" == "" ]
do
  sleep 1
  source <(/home/admin/_cache.sh get systemscan_runtime)
  echo "- waiting for background.scan.service --> systemscan_runtime(${systemscan_runtime})" >> $logFile
done

# make sure latest info file is imported
/home/admin/_cache.sh import $infoFile

# setting basic status info
/home/admin/_cache.sh set state "starting"
/home/admin/_cache.sh set message "bootstrap"

# try to load config values if available (config overwrites info)
source ${configFile} 2>/dev/null

# monitor LAN connection fast to display local IP changes
/home/admin/_cache.sh focus internet_localip 0

######################################
# CHECK SD CARD STATE

# wifi config by file on sd card
wifiFileExists=$(ls ${raspi_bootdir}/wifi 2>/dev/null | grep -c 'wifi')
wpaFileExists=$(ls ${raspi_bootdir}/wpa_supplicant.conf 2>/dev/null | grep -c 'wpa_supplicant.conf')
if [ "${wifiFileExists}" == "1" ] || [ "${wpaFileExists}" == "1" ]; then

  # set info
  echo "Setting Wifi by file on sd card ..." >> ${logFile}
  /home/admin/_cache.sh set message "setting wifi"

  # File: wifi
  # get first line as string from wifi file (NAME OF WIFI)
  # get second line as string from wifi file (PASSWORD OF WIFI)
  if [ "${wifiFileExists}" == "1" ]; then
    echo "Getting data from file: ${raspi_bootdir}/wifi" >> ${logFile}
    ssid=$(sed -n '1p' ${raspi_bootdir}/wifi | tr -d '[:space:]')
    password=$(sed -n '2p' ${raspi_bootdir}/wifi | tr -d '[:space:]')
  fi

  # File: wpa_supplicant.conf (legacy way to set wifi)
  # see: https://github.com/raspibolt/raspibolt/blob/a21788c0518618d17093e3f447f68a53e4efa6e7/raspibolt/raspibolt_20_pi.md#prepare-wifi
  if [ "${wpaFileExists}" == "1" ]; then  
    echo "Getting data from file: ${raspi_bootdir}/wpa_supplicant.conf" >> ${logFile}
    ssid=$(grep ssid "${raspi_bootdir}/wpa_supplicant.conf" | awk -F'=' '{print $2}' | tr -d '"')
    password=$(grep psk "${raspi_bootdir}/wpa_supplicant.conf" | awk -F'=' '{print $2}' | tr -d '"')
  fi

  # set wifi
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

  # remove file
  echo "Setting Wifi worked - removing file" >> ${logFile}
  rm ${raspi_bootdir}/wifi 2>/dev/null
  rm ${raspi_bootdir}/wpa_supplicant.conf 2>/dev/null
else
  echo "No Wifi config by file on sd card." >> ${logFile}
fi

# when the provision did not ran thru without error (ask user for fresh sd card)
provisionFlagExists=$(ls /home/admin/provision.flag | grep -c 'provision.flag')
if [ "${provisionFlagExists}" == "1" ]; then
  systemctl stop ${network}d 2>/dev/null
  /home/admin/_cache.sh set state "inconsistentsystem"
  /home/admin/_cache.sh set message "provision did not ran thru"
  echo "FAIL: 'provision did not ran thru' - need fresh sd card!" >> ${logFile}
  exit 1
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

# get the state of data drive
source <(/home/admin/config.scripts/blitz.datadrive.sh status)

################################
# WAIT LOOP: HDD CONNECTED
################################

echo "Waiting for HDD/SSD ..." >> $logFile
until [ ${isMounted} -eq 1 ] || [ ${#hddCandidate} -gt 0 ]
do

  # recheck HDD/SSD
  source <(/home/admin/config.scripts/blitz.datadrive.sh status)
  echo "isMounted: $isMounted" >> $logFile
  echo "hddCandidate: $hddCandidate" >> $logFile

  # in case of HDD analyse ERROR
  if [ "${hddError}" != "" ]; then
    echo "FAIL - error on HDD analysis: ${hddError}" >> $logFile
    /home/admin/_cache.sh set state "errorHDD"
    /home/admin/_cache.sh set message "${hddError}"
  elif [ "${isMounted}" == "0" ] && [ "${hddCandidate}" == "" ]; then
    /home/admin/_cache.sh set state "noHDD"
    /home/admin/_cache.sh set message ">=1TB"
  fi

  # wait for next check
  sleep 2

done
echo "HDD/SSD connected: ${hddCandidate}" >> $logFile

# write info for LCD
/home/admin/_cache.sh set state "system-init"
/home/admin/_cache.sh set message "please wait"

######################################
# SECTION FOR POSSIBLE REBOOT ACTIONS
systemInitReboot=0

################################
# FORCED SWITCH TO HDMI
# if a file called 'hdmi' gets
# placed onto the bootfs part of
# the sd card - switch to hdmi
################################

forceHDMIoutput=$(ls ${raspi_bootdir}/hdmi* 2>/dev/null | grep -c hdmi)
if [ ${forceHDMIoutput} -eq 1 ]; then
  # delete that file (to prevent loop)
  rm ${raspi_bootdir}/hdmi*
  # switch to HDMI what will trigger reboot
  echo "HDMI switch found ... activating HDMI display output & reboot" >> $logFile
  /home/admin/config.scripts/blitz.display.sh set-display hdmi >> $logFile
  systemInitReboot=1
  /home/admin/_cache.sh set message "HDMI"
else
  echo "No HDMI switch found. " >> $logFile
fi

################################
# GPT integrity check
################################

check_and_fix_gpt() {
  local device=$1
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
}

# List all block devices
devices=$(lsblk -dno NAME | grep -E '^sd|^nvme|^vd|^mmcblk')

# Check and fix each device
for dev in $devices; do
  check_and_fix_gpt /dev/$dev
done

################################
# FS EXPAND
# extend sd card to maximum capacity
################################

source <(/home/admin/config.scripts/blitz.bootdrive.sh status)
if [ "${needsExpansion}" == "1" ] && [ "${fsexpanded}" == "0" ]; then
  echo "FSEXPAND needed ... starting process" >> $logFile
  /home/admin/config.scripts/blitz.bootdrive.sh status >> $logFile
  /home/admin/config.scripts/blitz.bootdrive.sh fsexpand >> $logFile
  systemInitReboot=1
  /home/admin/_cache.sh set message "FSEXPAND"
elif [ "${tooSmall}" == "1" ]; then
  echo "# FAIL #######" >> $logFile
  echo "SDCARD TOO SMALL 16GB minimum" >> $logFile
  echo "##############" >> $logFile
  /home/admin/_cache.sh set state "sdtoosmall"
  echo "System stopped. Please cut power." >> $logFile
  sleep 6000
  shutdown -r now
  slepp 100
  exit 1
else
  echo "No FS EXPAND needed. needsExpansion(${needsExpansion}) fsexpanded(${fsexpanded})" >> $logFile
fi

# now that HDD/SSD is connected ... if relevant data from a previous RaspiBlitz was available
# /var/cache/raspiblitz/hdd-inspect exists with copy of config data to init system with
# NOTE: /var/cache/raspiblitz/hdd-inspect will not exist when HDD/SSD is already regulary mounted

####################################
# WIFI RESTORE from HDD works with
# mem copy from datadrive inspection
####################################

# check if there is a WIFI configuration to backup or restore
if [ -d "/var/cache/raspiblitz/hdd-inspect/wifi" ]; then
  echo "WIFI RESTORE from /var/cache/raspiblitz/hdd-inspect/wpa_supplicant.conf" >> $logFile
  /home/admin/config.scripts/internet.wifi.sh backup-restore >> $logFile
else
  echo "No WIFI RESTORE because no /var/cache/raspiblitz/hdd-inspect/wpa_supplicant.conf" >> $logFile
fi

################################
# SSH SERVER CERTS RESTORE
# if backup is available on HDD/SSD
################################

if [ -d "/var/cache/raspiblitz/hdd-inspect/sshd" ]; then
  # INIT OLD SSH HOST KEYS on Update/Recovery to prevent "Unknown Host" on ssh client
  echo "SSH SERVER CERTS RESTORE activating old SSH host keys" >> $logFile
  /home/admin/config.scripts/blitz.ssh.sh restore /var/cache/raspiblitz/hdd-inspect/sshd/ssh >> $logFile
else
  echo "No SSH SERVER CERTS RESTORE because no /var/cache/raspiblitz/hdd-inspect" >> $logFile
fi

################################
# SSH SERVER CERTS RESET
# if a file called 'ssh.reset' gets
# placed onto the boot part of
# the sd card - delete old ssh data
################################

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
##################################
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
################################
/home/admin/_cache.sh set message "checking HDD"
source <(/home/admin/config.scripts/blitz.datadrive.sh uasp-fix)
if [ "${neededReboot}" == "1" ]; then
  echo "UASP FIX applied ... reboot needed." >> $logFile
  systemInitReboot=1
else
  echo "No UASP FIX needed" >> $logFile
fi

######################################
# CHECK IF REBOOT IS NEEDED
# from actions above

if [ "${systemInitReboot}" == "1" ]; then
  echo "Reboot" >> $logFile
  cp ${logFile} /home/admin/raspiblitz.systeminit.log
  /home/admin/_cache.sh set state "reboot"
  sleep 8
  shutdown -r now
  sleep 100
  exit 0
fi

###################################
# WAIT LOOP: LOCALNET / INTERNET
# after HDD > can contain WIFI conf
###################################
gotLocalIP=0
until [ ${gotLocalIP} -eq 1 ]
do

  echo "gotLocalIP(${gotLocalIP})" >> $logFile

  # get latest network info directly
  source <(/home/admin/config.scripts/internet.sh status online)

  # check state of network
  if [ ${dhcp} -eq 0 ]; then
    # display user waiting for DHCP
    /home/admin/_cache.sh set state "noDHCP"
    /home/admin/_cache.sh set message "Waiting for DHCP"
  elif [ ${#localip} -eq 0 ]; then
    if [ ${configWifiExists} -eq 0 ]; then
      # display user to connect LAN
      /home/admin/_cache.sh set state "noIP-LAN"
      /home/admin/_cache.sh set message "Connect the LAN/WAN"
    else
      # display user that wifi settings are not working
      /home/admin/_cache.sh set state "noIP-WIFI"
      /home/admin/_cache.sh set message "WIFI Settings not working"
    fi
  elif [ ${online} -eq 0 ]; then
    # display user that wifi settings are not working
    /home/admin/_cache.sh set state "noInternet"
    /home/admin/_cache.sh set message "No connection to Internet"
  else
    gotLocalIP=1
  fi
  sleep 1
done

################################
# RaspberryPi 5 - Firmware Update (needs internet)
# https://github.com/raspiblitz/raspiblitz/issues/4359
################################

echo "checking Firmware" >> $logFile
/home/admin/_cache.sh set message "checking Firmware"
if [ "${baseimage}" == "raspios_arm64" ]; then
  echo "getting data" >> $logFile
  isRaspberryPi5=$(cat /proc/device-tree/model 2>/dev/null | grep -c "Raspberry Pi 5")
  firmwareBuildNumber=$(rpi-eeprom-update | grep "CURRENT" | cut -d "(" -f2 | sed 's/[^0-9]*//g')
  echo "checking Firmware: isRaspberryPi5(${isRaspberryPi5}) firmwareBuildNumber(${firmwareBuildNumber})" >> $logFile
  if [ ${isRaspberryPi5} -gt 0 ] && [ ${firmwareBuildNumber} -lt 1708097321 ]; then # Fri 16 Feb 15:28:41 UTC 2024 (1708097321)
    echo "updating Firmware" >> $logFile
    echo "RaspberryPi 5 detected with old firmware (${firmwareBuildNumber}) ... do update." >> $logFile
    apt-get update -y
    apt-get upgrade -y
    apt-get install -y rpi-eeprom
    rpi-eeprom-update -a
    echo "Restarting ..." >> $logFile
    sleep 3
    reboot
  else
    echo "RaspberryPi Firmware not in th need of update." >> $logFile
  fi
else
  echo "Not a RaspberryPi .. no firmware update needed." >> $logFile
fi

# write info for LCD
/home/admin/_cache.sh set state "inspect-hdd"
/home/admin/_cache.sh set message "please wait"

# get fresh info about data drive to continue
source <(/home/admin/config.scripts/blitz.datadrive.sh status)

echo "isMounted: $isMounted" >> $logFile

# check if the HDD is auto-mounted ( auto-mounted = setup-done)
echo "HDD already part of system: $isMounted" >> $logFile

############################
############################
# WHEN SETUP IS NEEDED  
############################

if [ ${isMounted} -eq 0 ]; then

  # temp mount the HDD
  echo "Temp mounting (1) data drive" >> $logFile
  source <(/home/admin/config.scripts/blitz.datadrive.sh tempmount)
  echo "Temp mounting (1) result: ${isMounted}" >> $logFile

  # write data needed for setup process into raspiblitz.info
  /home/admin/_cache.sh set hddCandidate "${hddCandidate}"
  /home/admin/_cache.sh set hddGigaBytes "${hddGigaBytes}"
  /home/admin/_cache.sh set hddBlocksBitcoin "${hddBlocksBitcoin}"
  /home/admin/_cache.sh set hddBlocksLitecoin "${hddBlocksLitecoin}"
  /home/admin/_cache.sh set hddGotMigrationData "${hddGotMigrationData}"
  /home/admin/_cache.sh set hddVersionLND "${hddVersionLND}"
  echo ""
  echo "HDD is there but not AutoMounted yet - Waiting for user Setup/Update" >> $logFile

  # add some debug info to logfile
  echo "# df " >> ${logFile}
  df >> ${logFile}
  echo "# lsblk -o NAME,FSTYPE,LABEL " >> ${logFile}
  lsblk -o NAME,FSTYPE,LABEL >> ${logFile}
  echo "# /home/admin/config.scripts/blitz.datadrive.sh status"
  /home/admin/config.scripts/blitz.datadrive.sh status >> ${logFile}

  # determine correct setup phase
  infoMessage="Please start Setup"
  setupPhase="setup"
  
  if [ "${hddGotMigrationData}" != "" ]; then
    infoMessage="Please start Migration"
    setupPhase="migration"
    # check if lightning is outdated
    migrationMode="normal"
    if [ "${hddVersionLND}" != "" ]; then
      # get local lnd version & check compatibility
      source <(/home/admin/config.scripts/lnd.install.sh info "${hddVersionLND}")
      if [ "${compatible}" != "1" ]; then
        migrationMode="outdatedLightning"
      fi 
    fi
    /home/admin/_cache.sh set migrationMode "${migrationMode}"

  elif [ "${hddRaspiData}" == "1" ]; then

    # determine if this is a recovery or an update
    # TODO: improve version/update detection later
    isRecovery=$(echo "${hddRaspiVersion}" | grep -c "${codeVersion}")
    if [ "${isRecovery}" == "1" ]; then
      infoMessage="Please start Recovery"
      setupPhase="recovery"
    else
      infoMessage="Please start Update"
      setupPhase="update"
    fi

  fi

  # signal "WAIT LOOP: SETUP" to LCD, SSH & WEBAPI
  echo "Displaying Info Message: ${infoMessage}" >> $logFile
  /home/admin/_cache.sh set state "waitsetup"
  /home/admin/_cache.sh set message "${infoMessage}"
  /home/admin/_cache.sh set setupPhase "${setupPhase}"

  #############################################
  # WAIT LOOP: USER SETUP/UPDATE/MIGRATION
  # until SSH or WEBUI setup data is available
  #############################################

  echo "## WAIT LOOP: USER SETUP/UPDATE/MIGRATION" >> ${logFile}
  until [ "${state}" == "waitprovision" ]
  do

    # get fresh info about data drive (in case the hdd gets disconnected)
    source <(/home/admin/config.scripts/blitz.datadrive.sh status)
    if [ "${hddCandidate}" == "" ]; then
      /home/admin/config.scripts/blitz.error.sh _bootstrap.sh "lost-hdd" "Lost HDD connection .. triggering reboot." "happened during WAIT LOOP: USER SETUP/UPDATE/MIGRATION" ${logFile}
      sleep 8
      shutdown -r now
      sleep 100
      exit 0
    fi

    # detect if network get deconnected again (call directly instead of cache)
    # --> "removing network cable" can be used as signal to shutdown clean on test startup
    source <(/home/admin/config.scripts/internet.sh status local)
    if [ "${localip}" == "" ]; then
      sed -i "s/^state=.*/state=errorNetwork/g" ${infoFile}
      sleep 8
      shutdown now
      sleep 100
      exit 0
    fi

    # give the loop a little bed time
    sleep 4

    # check for updated state value from SSH-UI or WEB-UI for loop
    source <(/home/admin/_cache.sh get state)

  done

  #############################################
  # PROVISION PROCESS
  #############################################

  # refresh data from info file
  source <(/home/admin/_cache.sh get state setupPhase)
  echo "# PROVISION PROCESS with setupPhase(${setupPhase})" >> ${logFile}

  # mark system on sd card as in setup process
  echo "the provision process was started but did not finish yet" > /home/admin/provision.flag

  # get fresh data from setup file & data drive
  source <(/home/admin/config.scripts/blitz.datadrive.sh status)
  source ${setupFile}

  # special setup tasks (triggered by api/webui thru setupfile)

  # FORMAT DATA DRIVE
  if [ "${formatHDD}" == "1" ]; then
    echo "# special setup tasks: FORMAT DATA DRIVE" >> ${logFile}
      
    # check if there is a flag set on sd card boot section to format as btrfs (experimental)
    filesystem="ext4"
    flagBTRFS=$(ls ${raspi_bootdir}/btrfs* 2>/dev/null | grep -c btrfs)
    if [ "${flagBTRFS}" != "0" ]; then
      echo "Found BTRFS flag ---> formatting with experimental BTRFS filesystem" >> ${logFile}
      filesystem="btrfs"
    fi

    # run formatting
    error=""
    /home/admin/_cache.sh set state "formathdd"
    echo "Running Format: filesystem(${filesystem}) hddCandidate(${hddCandidate})" >> ${logFile}
    source <(/home/admin/config.scripts/blitz.datadrive.sh format ${filesystem} ${hddCandidate})
    if [ "${error}" != "" ]; then
      echo "FAIL ON FORMATTING THE DRIVE:" >> ${logFile}
      echo "${error}" >> ${logFile}
      echo "Please report as issue on the raspiblitz github." >> ${logFile}
      /home/admin/_cache.sh set state "errorHDD"
      /home/admin/_cache.sh set message "Fail Format (${filesystem})"
      exit 1
    fi
    /home/admin/_cache.sh set setupPhase "setup"
  fi

  # CLEAN DRIVE & KEEP BLOCKCHAIN
  if [ "${cleanHDD}" == "1" ]; then
    echo "# special setup tasks: CLEAN DRIVE & KEEP BLOCKCHAIN" >> ${logFile}

    # when blockchain comes from another node migrate data first
    if [ "${hddGotMigrationData}" != "" ]; then
        clear
        echo "Migrating Blockchain of ${hddGotMigrationData}'" >> ${logFile}
        source <(/home/admin/config.scripts/blitz.migration.sh migration-${hddGotMigrationData})
        if [ "${error}" != "0" ]; then
          echo "MIGRATION OF BLOCKHAIN FAILED: ${err}" >> ${logFile}
          echo "Format data disk on laptop & recover funds with fresh sd card using seed words + static channel backup." >> ${logFile}
          /home/admin/_cache.sh set state "errorHDD"
          /home/admin/_cache.sh set message "Fail Migrate Blockchain (${hddGotMigrationData})"
          exit 1
        fi
    fi

    # delete everything but blockchain
    echo "Deleting everything on HDD/SSD while keeping blockchain ..." >> ${logFile}
    /home/admin/config.scripts/blitz.datadrive.sh tempmount 1>/dev/null 2>/dev/null
    /home/admin/config.scripts/blitz.datadrive.sh clean all -keepblockchain >> ${logFile}
    if [ "${error}" != "" ]; then
       echo "CLEANING HDD FAILED:" >> ${logFile}
      echo "${error}" >> ${logFile}
      echo "Please report as issue on the raspiblitz github." >> ${logFile}
      /home/admin/_cache.sh set state "errorHDD"
      /home/admin/_cache.sh set message "Fail Cleaning HDD"
      exit 1
    fi
    /home/admin/config.scripts/blitz.datadrive.sh unmount >> ${logFile}
    /home/admin/_cache.sh set setupPhase "setup"

    sleep 2

  fi

  source <(/home/admin/_cache.sh get state setupPhase)
  if [ "${setupPhase}" == "setup" ]; then

    echo "# CREATING raspiblitz.conf from your setup choices" >> ${logFile}
    if [ "${network}" == "" ]; then
      network="bitcoin"
    fi
    if [ "${chain}" == "" ]; then
      chain="main"
    fi

    # source the raspiblitz version
    source /home/admin/_version.info

    # prepare & write basic config file
    # will first be created and in cache drive
    # and some lines below copied to hdd when mounted
    TEMPCONFIGFILE="/var/cache/raspiblitz/temp/raspiblitz.conf"
    rm $TEMPCONFIGFILE 2>/dev/null
    touch $TEMPCONFIGFILE
    chown admin:admin $TEMPCONFIGFILE
    chmod 777 $TEMPCONFIGFILE
    echo "# RASPIBLITZ CONFIG FILE" > $TEMPCONFIGFILE
    echo "raspiBlitzVersion='${codeVersion}'" >> $TEMPCONFIGFILE
    echo "lcdrotate='1'" >> $TEMPCONFIGFILE
    echo "lightning='${lightning}'" >> $TEMPCONFIGFILE
    echo "network='${network}'" >> $TEMPCONFIGFILE
    echo "chain='${chain}'" >> $TEMPCONFIGFILE
    echo "hostname='${hostname}'" >> $TEMPCONFIGFILE
    echo "runBehindTor='on'" >> $TEMPCONFIGFILE
  fi

  # make sure HDD is mounted (could be freshly formatted by user on last loop)
  source <(/home/admin/config.scripts/blitz.datadrive.sh status)
  echo "Temp mounting (2) data drive (hddFormat='${hddFormat}')" >> ${logFile}
  source <(/home/admin/config.scripts/blitz.datadrive.sh tempmount)
  echo "Temp mounting (2) result: ${isMounted}" >> ${logFile}

  # check that HDD was temp mounted
  if [ "${isMounted}" != "1" ]; then
    /home/admin/_cache.sh set state "errorHDD"
    /home/admin/_cache.sh set message "Was not able to mount HDD (2)"
    exit 1
  fi

  # make sure all links between directories/drives are correct
  echo "Refreshing links between directories/drives .." >> ${logFile}
  /home/admin/config.scripts/blitz.datadrive.sh link

  # copy over the raspiblitz.conf created from setup to HDD
  configExists=$(ls /mnt/hdd/raspiblitz.conf 2>/dev/null | grep -c "raspiblitz.conf")
  if [ "${configExists}" != "1" ]; then
    cp /var/cache/raspiblitz/temp/raspiblitz.conf ${configFile}
  fi

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

  # load fresh setup data
  echo "# Sourcing ${setupFile} " >> ${logFile}
  source ${setupFile}

  # if migrationFile was uploaded (value from raspiblitz.setup) - now import
  echo "# migrationFile(${migrationFile})" >> ${logFile}
  if [ "${migrationFile}" != "" ]; then

    echo "##### IMPORT MIGRATIONFILE: ${migrationFile}" >> ${logFile}

    # unpack
    /home/admin/_cache.sh set message "Unpacking Migration Data"
    error=""
    source <(/home/admin/config.scripts/blitz.migration.sh import "${migrationFile}")

    # check for errors
    if [ "${error}" != "" ]; then 
      /home/admin/config.scripts/blitz.error.sh _bootstrap.sh "migration-import-error" "blitz.migration.sh import exited with error" "/home/admin/config.scripts/blitz.migration.sh import ${migrationFile} --> ${error}" ${logFile}
      exit 1
    fi

    # make sure a raspiblitz.conf exists after migration
    confExists=$(ls /mnt/hdd/raspiblitz.conf 2>/dev/null | grep -c "raspiblitz.conf")
    if [ "${confExists}" != "1" ]; then
      /home/admin/config.scripts/blitz.error.sh _bootstrap.sh "migration-failed" "missing-config" "After runnign migration process - no raspiblitz.conf abvailable." ${logFile}
      exit 1
    fi

    # signal recovery provision phase
    setupPhase="recovery"
    /home/admin/_cache.sh set setupPhase "${setupPhase}"
  fi

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

  ###################################
  # Set Password A (in all cases)
  
  if [ "${passwordA}" == "" ]; then
    /home/admin/config.scripts/blitz.error.sh _bootstrap.sh "missing-passworda-2" "missing passwordA(2) in (${setupFile})" "" ${logFile}
    exit 1
  fi

  echo "# setting PASSWORD A" >> ${logFile}
  /home/admin/config.scripts/blitz.passwords.sh set a "${passwordA}" >> ${logFile}

  # Bitcoin Mainnet
  if [ "${mainnet}" == "on" ] || [ "${chain}" == "main" ]; then
    echo "Provisioning ${network} Mainnet - run config script" >> ${logFile}
    /home/admin/config.scripts/bitcoin.install.sh on mainnet >> ${logFile} 2>&1
  else
    echo "Provisioning ${network} Mainnet - not active" >> ${logFile}
  fi

  # Bitcoin Testnet
  if [ "${testnet}" == "on" ]; then
    echo "Provisioning ${network} Testnet - run config script" >> ${logFile}
    /home/admin/config.scripts/bitcoin.install.sh on testnet >> ${logFile} 2>&1
  else
    echo "Provisioning ${network} Testnet - not active" >> ${logFile}
  fi

  # Bitcoin Signet
  if [ "${signet}" == "on" ]; then
    echo "Provisioning ${network} Signet - run config script" >> ${logFile}
    /home/admin/config.scripts/bitcoin.install.sh on signet >> ${logFile} 2>&1
  else
    echo "Provisioning ${network} Signet - not active" >> ${logFile}
  fi

  # if setup - run provision setup first
  if [ "${setupPhase}" == "setup" ]; then
    echo "Calling _provision.setup.sh for basic setup tasks .." >> $logFile
    echo "Follow in a new terminal with: 'tail -f raspiblitz.provision-setup.log'" >> $logFile
    /home/admin/_cache.sh set message "Provision Setup"
    /home/admin/_provision.setup.sh
    errorState=$?
    cat /home/admin/raspiblitz.provision-setup.log
    if [ "$errorState" != "0" ]; then
      # only trigger an error message if the script hasnt itself triggered an error message already
      source <(/home/admin/_cache.sh get state)
      if [ "${state}" != "error" ]; then
        /home/admin/config.scripts/blitz.error.sh _bootstrap.sh "provision-setup-exit" "unknown or syntax error on (${errorState}) _provision.setup.sh" "" ${logFile}
      fi
      exit 1
    fi
  fi

  # if migration from other nodes - run the migration provision first
  if [ "${setupPhase}" == "migration" ]; then
    echo "Calling _provision.migration.sh for possible migrations .." >> $logFile
    /home/admin/_cache.sh set message "Provision migration"
    /home/admin/_provision.migration.sh
    errorState=$?
    cat /home/admin/raspiblitz.provision-migration.log
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
  if [ "${setupPhase}" == "update" ] || [ "${setupPhase}" == "recovery" ] || [ "${setupPhase}" == "migration" ]; then
    echo "Calling _provision.update.sh .." >> $logFile
    echo "Follow in a new terminal with: 'tail -f raspiblitz.provision-update.log'" >> $logFile
    /home/admin/_cache.sh set message "Provision Update/Recovery/Migration"
    /home/admin/_provision.update.sh
    errorState=$?
    cat /home/admin/raspiblitz.provision-update.log
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
  # /mnt/hdd/lnd/logs/bitcoin/mainnet/lnd.log
  rm /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log 2>/dev/null
  # https://github.com/rootzoll/raspiblitz/issues/1700
  rm /mnt/storage/app-storage/electrs/db/mainnet/LOCK 2>/dev/null

fi

##############################
##############################
# BOOSTRAP IN EVERY SITUATION
##############################
/home/admin/_cache.sh set setupPhase "starting"

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
if [ "${blitzapi}" == "" ] && [ ${blitzApiRunning} -eq 1 ]; then
  /home/admin/config.scripts/blitz.conf.sh set blitzapi "on"
fi

# make sure users have latest credentials (if lnd is on)
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
  echo "running LND users credentials update" >> $logFile
  /home/admin/config.scripts/lnd.credentials.sh sync "${chain:-main}net" >> $logFile
else
  echo "skipping LND credentials sync" >> $logFile
fi

################################
# MOUNT BACKUP DRIVE
# if "localBackupDeviceUUID" is set in
# raspiblitz.conf mount it on boot
################################
echo "Checking if additional backup device is configured .. (${localBackupDeviceUUID})" >> $logFile
if [ "${localBackupDeviceUUID}" != "" ] && [ "${localBackupDeviceUUID}" != "off" ]; then
  echo "Yes - Mounting BackupDrive: ${localBackupDeviceUUID}" >> $logFile
  /home/admin/config.scripts/blitz.backupdevice.sh mount >> $logFile
else
  echo "No additional backup device was configured." >> $logFile
fi

#####################################
# CLEAN HDD TEMP
#####################################
echo "CLEANING TEMP DRIVE/FOLDER" >> $logFile
source <(/home/admin/config.scripts/blitz.datadrive.sh clean temp)
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
  btrfs scrub start /mnt/hdd/
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
if [ "${btc_default_sync_initialblockdownload}" == "1" ]; then
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
