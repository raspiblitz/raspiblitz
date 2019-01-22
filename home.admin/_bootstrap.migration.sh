#!/bin/bash

# LOGFILE - store debug logs of bootstrap
logFile="/home/admin/raspiblitz.log"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# debug info
echo "STARTED Migration/Init --> see logs in ${logFile}"
echo "STARTED Migration/Init" >> ${logFile}
sudo sed -i "s/^message=.*/message='Running Data Migration'/g" ${infoFile}

# LOAD DATA & PRECHECK

# check if there is a config file
configExists=$(ls ${configFile} 2>/dev/null | grep -c '.conf')
if [ ${configExists} -eq 0 ]; then
  echo "FAIL see ${logFile}"
  echo "FAIL: no config file (${configFile}) found to init or upgrade!"  >> ${logFile}
  exit 1
fi

# load old or init raspiblitz config
source ${configFile}

# check if config files contains basic: hostname
if [ ${#hostname} -eq 0 ]; then
  echo "FAIL see ${logFile}"
  echo "FAIL: missing hostname in (${configFile})!" >> ${logFile}
  exit 1
fi

# load codeVersion
source /home/admin/_version.info

# check if code version was loaded
if [ ${#codeVersion} -eq 0 ]; then
  echo "FAIL see ${logFile}"
  echo "FAIL: no code version (/home/admin/_version.info) found!" >> ${logFile}
  exit 1
fi

echo "prechecks OK"  >> ${logFile}

# DEFAULT VALUES - MISSING data fields on init or upadte

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

# TOR
# runBehindTor=off|on
if [ ${#runBehindTor} -eq 0 ]; then
  echo "runBehindTor=off" >> $configFile
fi

# RideTheLightning RTL
# rtlWebinterface=off|on
if [ ${#rtlWebinterface} -eq 0 ]; then
  echo "rtlWebinterface=off" >> $configFile
fi

echo "default values OK"  >> ${logFile}

# MIGRATION - DATA CONVERSION when updating config
# this is the place if on a future version change
# a conversion of config data or app data is needed 

# if old bitcoin.conf exists ...
configExists=$(sudo ls /mnt/hdd/bitcoin/bitcoin.conf | grep -c '.conf')
if [ ${configExists} -eq 1 ]; then
  echo "Checking old bitcoin.conf ..." >> ${logFile}

  # make sure to fix bitcoind RPC port if not done in old version
  # https://github.com/rootzoll/raspiblitz/issues/217
  settingExists=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep -c 'rpcport=')
  if [ ${settingExists} -eq 0 ]; then
    echo "fix issue #217 -> adding rpcport=8332" >> ${logFile}
    echo "rpcport=8332" >> /mnt/hdd/bitcoin/bitcoin.conf
  else
    echo "check issue #217 -> ok rpcport exists" >> ${logFile}
  fi
  settingExists=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep -c 'rpcallowip=')
  if [ ${settingExists} -eq 0 ]; then
    echo "fix issue #217 -> adding rpcallowip=127.0.0.1" >> ${logFile}
    echo "rpcallowip=127.0.0.1" >> /mnt/hdd/bitcoin/bitcoin.conf
  else
    echo "check issue #217 -> ok rpcallowip exists" >> ${logFile}
  fi
  settingExists=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep -c 'rpcbind=')
  if [ ${settingExists} -eq 0 ]; then
    echo "fix issue #217 -> adding rpcbind=127.0.0.1:8332" >> ${logFile}
    echo "rpcbind=127.0.0.1:8332" >> /mnt/hdd/bitcoin/bitcoin.conf
  else
    echo "check issue #217 -> ok rpcbind exists" >> ${logFile}
  fi
fi

echo "Version Code: ${codeVersion}" >> ${logFile}
echo "Version Data: ${raspiBlitzVersion}" >> ${logFile}

if [ "${raspiBlitzVersion}" != "${codeVersion}" ]; then
  echo "detected version change ... starting migration script" >> ${logFile}
  echo "TODO: Update Migration check ... only needed after version 1.0" >> ${logFile}
else
  echo "OK - version of config data is up to date" >> ${logFile}
fi

echo "END Migration/Init"  >> ${logFile}

exit 0

