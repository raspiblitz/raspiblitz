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

# HDD BTRFS RAID REPAIR IF NEEDED
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
if [ ${isBTRFS} -eq 1 ] && [ ${isMounted} -eq 1 ]; then
  echo "CHECK BTRFS RAID"  >> ${logFile}
  if [ ${isRaid} -eq 1 ] && [ ${#raidUsbDev} -eq 0 ]; then
      echo "HDD was set to work in RAID, but RAID drive is not connected"  >> ${logFile}
      echo "Trying to set HDD back to single mode."  >> ${logFile}
      sudo /home/admin/config.scripts/blitz.datadrive.sh raid off >> ${logFile}
  else
      echo "OK"  >> ${logFile}
  fi
fi

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
  # https://github.com/rootzoll/raspiblitz/issues/950

  if ! grep -Eq "^rpcallowip=.*" /mnt/hdd/${network}/${network}.conf; then
    echo "fix issue #217 -> adding rpcallowip=127.0.0.1" >> ${logFile}
    echo "rpcallowip=127.0.0.1" >> /mnt/hdd/${network}/${network}.conf
  else
    echo "check issue #217 -> ok rpcallow exists" >> ${logFile}
  fi

  # check whether "main." needs to be added to rpcport and rpcbind
  if grep -Eq "^rpcport=.*" /mnt/hdd/${network}/${network}.conf; then
    echo "fix issue #950 -> change rpcport to main.rpcport" >> ${logFile}
    sudo sed -i -E 's/^(rpcport=.*)/main.\1/g' /mnt/hdd/${network}/${network}.conf
  else
    echo "check issue #950 -> ok ^rpcport does not exist" >> ${logFile}
  fi

  if grep -Eq "^rpcbind=.*" /mnt/hdd/${network}/${network}.conf; then
    echo "fix issue #950 -> change rpcbind to main.rpcbind" >> ${logFile}
    sudo sed -i -E 's/^(rpcbind=.*)/main.\1/g' /mnt/hdd/${network}/${network}.conf
  else
    echo "check issue #950 -> ok ^rpcbind does not exist" >> ${logFile}
  fi

  # check whether right settings are there ("main.")
  if ! grep -Eq "^main.rpcport=.*" /mnt/hdd/${network}/${network}.conf; then
    echo "fix issue #217 -> adding main.rpcport=8332" >> ${logFile}
    echo "main.rpcport=8332" >> /mnt/hdd/${network}/${network}.conf
  else
    echo "check issue #217 -> ok main.rpcport exists" >> ${logFile}
  fi

  if ! grep -Eq "^main.rpcbind=.*" /mnt/hdd/${network}/${network}.conf; then
    echo "fix issue #217 -> adding main.rpcbind=127.0.0.1:8332" >> ${logFile}
    echo "main.rpcbind=127.0.0.1:8332" >> /mnt/hdd/${network}/${network}.conf
  else
    echo "check issue #217 -> ok main.rpcbind exists" >> ${logFile}
  fi

  # same for testnet
  if ! grep -Eq "^test.rpcport=.*" /mnt/hdd/${network}/${network}.conf; then
    echo "fix issue #950 -> adding test.rpcport=18332" >> ${logFile}
    echo "test.rpcport=18332" >> /mnt/hdd/${network}/${network}.conf
  else
    echo "check issue #950 -> ok test.rpcport exists" >> ${logFile}
  fi

  if ! grep -Eq "^test.rpcbind=.*" /mnt/hdd/${network}/${network}.conf; then
    echo "fix issue #950 -> adding test.rpcbind=127.0.0.1:18332" >> ${logFile}
    echo "test.rpcbind=127.0.0.1:18332" >> /mnt/hdd/${network}/${network}.conf
  else
    echo "check issue #950 -> ok test.rpcbind exists" >> ${logFile}
  fi

else
  echo "WARN: /mnt/hdd/bitcoin/bitcoin.conf not found" >> ${logFile}
fi

# if old lnd.conf exists ...
configExists=$(sudo ls /mnt/hdd/lnd/lnd.conf | grep -c '.conf')
if [ ${configExists} -eq 1 ]; then

  # remove RPC user & pass from lnd.conf ... since v1.7
  # https://github.com/rootzoll/raspiblitz/issues/2160
  echo "- #2160 lnd.conf --> make sure contains no RPC user/pass for bitcoind" >> ${logFile}
  sudo sed -i '/^\[Bitcoind\]/d' /mnt/hdd/lnd/lnd.conf
  sudo sed -i '/^bitcoind.rpchost=/d' /mnt/hdd/lnd/lnd.conf
  sudo sed -i '/^bitcoind.rpcpass=/d' /mnt/hdd/lnd/lnd.conf
  sudo sed -i '/^bitcoind.rpcuser=/d' /mnt/hdd/lnd/lnd.conf
  sudo sed -i '/^bitcoind.zmqpubrawblock=/d' /mnt/hdd/lnd/lnd.conf
  sudo sed -i '/^bitcoind.zmqpubrawtx=/d' /mnt/hdd/lnd/lnd.conf
  
else
  echo "WARN: /mnt/hdd/lnd/lnd.conf not found" >> ${logFile}
fi

echo "Version Code: ${codeVersion}" >> ${logFile}
echo "Version Data: ${raspiBlitzVersion}" >> ${logFile}

if [ "${raspiBlitzVersion}" != "${codeVersion}" ]; then
  echo "detected version change ... starting migration script" >> ${logFile}
  # nothing specific here yet
  echo "OK Done - Updating version in config"
  sudo sed -i "s/^raspiBlitzVersion=.*/raspiBlitzVersion='${codeVersion}'/g" ${configFile}
else
  echo "OK - version of config data is up to date" >> ${logFile}
fi

echo "END Migration/Init"  >> ${logFile}

exit 0

