#!/bin/bash

# check if run by root user
if [ "$EUID" -ne 0 ]; then
  echo "error='run as root'"
  exit 1
fi

# LOGFILE - store debug logs of bootstrap
logFile="/home/admin/raspiblitz.provision-update.log"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# SETUPFILE - - setup data of RaspiBlitz
setupFile="/var/cache/raspiblitz/temp/raspiblitz.setup"
source ${setupFile}

# log header
echo "" > ${logFile}
sudo chmod 640 ${logFile}
chown root:sudo ${logFile}
echo "###################################" >> ${logFile}
echo "# _provision.update.sh" >> ${logFile}
echo "###################################" >> ${logFile}
/home/admin/_cache.sh set message "Running Data Update"

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

# load old or init raspiblitz config
source ${configFile}

# if hostname missing - set default
if [ ${#hostname} -eq 0 ]; then
  /home/admin/config.scripts/blitz.conf.sh set hostname "raspiblitz"
  source ${configFile}
fi

# re-check if config files contains hostname value
if [ ${#hostname} -eq 0 ]; then
  /home/admin/config.scripts/blitz.error.sh _provision.update.sh "missing-hostname" "${setupFile} or ${configFile} contains no hostname" "" ${logFile}
  exit 1
fi

# check if config files contain lightning (lnd is default) introduced in v1.7.1
entryExists=$(cat ${configFile} | grep -c "^lightning=")
if [ "${entryExists}" != "1" ]; then
  lightning="lnd"
  echo "lightning=${lightning}" >> ${configFile}
fi
# make sure lnd / cl is set if lightning is on
if [ "${lightning}" == "lnd" ] && [ "${lnd}" != "on" ]; then
  /home/admin/config.scripts/blitz.conf.sh set lnd on
fi
if [ "${lightning}" == "cl" ] && [ "${cl}" != "on" ]; then
  /home/admin/config.scripts/blitz.conf.sh set cl on
fi

# load codeVersion
source /home/admin/_version.info

# check if code version was loaded
if [ ${#codeVersion} -eq 0 ]; then
  /home/admin/config.scripts/blitz.error.sh _provision.update.sh "missing-version" "missing /home/admin/_version.info" "" ${logFile}
  exit 1
fi

echo "prechecks OK"  >> ${logFile}

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

# delete old Tor v1 addresses from config -  see: https://github.com/rootzoll/raspiblitz/issues/3659
sed -i -E "/^addnode=[a-z0-9]{8,18}\.onion/d" /mnt/hdd/${network}/${network}.conf 2>/dev/null

echo "Version Code: ${codeVersion}" >> ${logFile}
echo "Version Data: ${raspiBlitzVersion}" >> ${logFile}

if [ "${raspiBlitzVersion}" != "${codeVersion}" ]; then
  echo "detected version change ... starting migration script" >> ${logFile}
  # nothing specific here yet
  echo "OK Done - Updating version in config"
  /home/admin/config.scripts/blitz.conf.sh set raspiBlitzVersion "${codeVersion}"
else
  echo "OK - version of config data is up to date" >> ${logFile}
fi

# start network service
echo ""
echo "*** Start ${network} (UPDATE) ***" >> ${logFile}
/home/admin/_cache.sh set message "Blockchain Testrun"
echo "- This can take a while .." >> ${logFile}
chown -R bitcoin:bitcoin /mnt/hdd/${network} >>${logFile} 2>&1
systemctl daemon-reload >> ${logFile}
systemctl enable ${network}d.service >> ${logFile}
systemctl start ${network}d.service >> ${logFile}

# INSTALL LND on Update/Recovery
if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then

  # prepare lnd service
  cp /home/admin/assets/lnd.service /etc/systemd/system/lnd.service >> ${logFile} 2>&1

  # if old lnd.conf exists ...
  configExists=$(sudo ls /mnt/hdd/lnd/lnd.conf | grep -c '.conf')
  if [ ${configExists} -eq 1 ]; then

    # make sure correct file permisions are set
    chown bitcoin:bitcoin /mnt/hdd/lnd/lnd.conf
    chmod 664 /mnt/hdd/lnd/lnd.conf

    # make sure additional values are added to [Application Options] since v1.7
    echo "- lnd.conf --> checking additional [Application Options] since v1.7" >> ${logFile}
    applicationOptionsLineNumber=$(grep -n "\[Application Options\]" /mnt/hdd/lnd/lnd.conf | cut -d ":" -f1)
    if [ "${applicationOptionsLineNumber}" != "" ]; then
      applicationOptionsLineNumber="$(($applicationOptionsLineNumber+1))"

      # Avoid historical graph data sync
      # ignore-historical-gossip-filters=1
      configParamExists=$(grep -c "^ignore-historical-gossip-filters=" /mnt/hdd/lnd/lnd.conf)
      if [ "${configParamExists}" == "0" ]; then
        echo " - ADDING 'ignore-historical-gossip-filters'" >> ${logFile}
        sed -i "${applicationOptionsLineNumber}iignore-historical-gossip-filters=1" /mnt/hdd/lnd/lnd.conf
      else
        echo " - OK 'ignore-historical-gossip-filters' exists (${configParamExists})" >> ${logFile}
      fi

      # Avoid slow startup time
      # sync-freelist=1
      configParamExists=$(grep -c "^sync-freelist=" /mnt/hdd/lnd/lnd.conf)
      if [ "${configParamExists}" == "0" ]; then
        echo " - ADDING 'sync-freelist'" >> ${logFile}
        sed -i "${applicationOptionsLineNumber}isync-freelist=1" /mnt/hdd/lnd/lnd.conf
      else
        echo " - OK 'sync-freelist' exists (${configParamExists})" >> ${logFile}
      fi

      # Avoid high startup overhead
      # stagger-initial-reconnect=1
      configParamExists=$(grep -c "^stagger-initial-reconnect=" /mnt/hdd/lnd/lnd.conf)
      if [ "${configParamExists}" == "0" ]; then
        echo " - ADDING 'stagger-initial-reconnect'" >> ${logFile}
        sed -i "${applicationOptionsLineNumber}istagger-initial-reconnect=1" /mnt/hdd/lnd/lnd.conf
      else
        echo " - OK 'stagger-initial-reconnect' exists (${configParamExists})" >> ${logFile}
      fi

      # Delete and recreate RPC TLS certificate when details change or cert expires
      # tlsautorefresh=1
      configParamExists=$(grep -c "^tlsautorefresh=" /mnt/hdd/lnd/lnd.conf)
      if [ "${configParamExists}" == "0" ]; then
        echo " - ADDING 'tlsautorefresh'" >> ${logFile}
        sed -i "${applicationOptionsLineNumber}itlsautorefresh=1" /mnt/hdd/lnd/lnd.conf
      else
        echo " - OK 'tlsautorefresh' exists (${configParamExists})" >> ${logFile}
      fi

      # Do not include IPs in the RPC TLS certificate
      # tlsdisableautofill=1
      configParamExists=$(grep -c "^tlsdisableautofill=" /mnt/hdd/lnd/lnd.conf)
      if [ "${configParamExists}" == "0" ]; then
        echo " - ADDING 'tlsdisableautofill'" >> ${logFile}
        sed -i "${applicationOptionsLineNumber}itlsdisableautofill=1" /mnt/hdd/lnd/lnd.conf
      else
        echo " - OK 'tlsdisableautofill' exists (${configParamExists})" >> ${logFile}
      fi

    else
      echo " - WARN: section '[Application Options]' not found in lnd.conf" >> ${logFile}
    fi
  else
    echo "WARN: /mnt/hdd/lnd/lnd.conf not found" >> ${logFile}
  fi

  # start LND service
  echo "Starting LND Service ..." >> ${logFile}
  systemctl enable lnd >> ${logFile}
  systemctl start lnd >> ${logFile}

fi

if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ]; then

  echo "Install Core Lightning on update" >> ${logFile}
  /home/admin/_cache.sh set message "Core Lightning install"
  /home/admin/config.scripts/cl.install.sh on mainnet >> ${logFile}
  /home/admin/_cache.sh set message "Core Lightning Setup"

fi

echo "END Migration/Init"  >> ${logFile}

exit 0

