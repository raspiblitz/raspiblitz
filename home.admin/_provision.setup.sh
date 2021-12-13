#!/bin/bash

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='run as root'"
  exit 1
fi

# this provision file is just executed on fresh setups
# not on recoveries or updates

# LOGFILE - store debug logs of bootstrap
logFile="/home/admin/raspiblitz.provision-setup.log"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"
source ${infoFile}

# SETUPFILE - setup data of RaspiBlitz
setupFile="/var/cache/raspiblitz/temp/raspiblitz.setup"
source ${setupFile}

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"
source ${configFile}

# log header
echo "" > ${logFile}
echo "###################################" >> ${logFile}
echo "# _provision.setup.sh" >> ${logFile}
echo "###################################" >> ${logFile}

###################################
# Preserve SSH keys
# just copy dont link anymore
# see: https://github.com/rootzoll/raspiblitz/issues/1798
/home/admin/_cache.sh set message "SSH Keys"

# link ssh directory from SD card to HDD
/home/admin/config.scripts/blitz.ssh.sh backup

###################################
# Prepare Blockchain Service
/home/admin/_cache.sh set message "Blockchain Setup"
source <(/home/admin/_cache.sh get network chain hddBlocksBitcoin)

if [ "${network}" == "" ]; then
  /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "missing-network" "" "" ${logFile}
  exit 2
fi

if [ "${chain}" == "" ]; then
  /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "missing-chain" "" "" ${logFile}
  exit 3
fi

# copy configs files and directories
echo ""
echo "*** Prepare ${network} ***" >> ${logFile}
mkdir /mnt/hdd/${network} >>${logFile} 2>&1
chown -R bitcoin:bitcoin /mnt/hdd/${network} >>${logFile} 2>&1
sudo -u bitcoin mkdir /mnt/hdd/${network}/blocks >>${logFile} 2>&1
sudo -u bitcoin mkdir /mnt/hdd/${network}/chainstate >>${logFile} 2>&1
cp /home/admin/assets/${network}.conf /mnt/hdd/${network}/${network}.conf
chown bitcoin:bitcoin /mnt/hdd/${network}/${network}.conf >>${logFile} 2>&1
mkdir /home/admin/.${network} >>${logFile} 2>&1
cp /home/admin/assets/${network}.conf /home/admin/.${network}/${network}.conf
chown -R admin:admin /home/admin/.${network} >>${logFile} 2>&1

# make sure all directories are linked
/home/admin/config.scripts/blitz.datadrive.sh link >> ${logFile}

# test bitcoin config
confExists=$(sudo ls /mnt/hdd/${network}/${network}.conf | grep -c "${network}.conf")
echo "File Exists: /mnt/hdd/${network}/${network}.conf --> ${confExists}" >> ${logFile}

# set password B as RPC password (from setup file)
echo "# setting PASSWORD B" >> ${logFile}
/home/admin/config.scripts/blitz.setpassword.sh b "${passwordB}" >> ${logFile}

# optimize RAM for blockchain validation (bitcoin only)
if [ "${network}" == "bitcoin" ] && [ "${hddBlocksBitcoin}" == "0" ]; then
  echo "*** Optimizing RAM for Sync ***" >> ${logFile}
  kbSizeRAM=$(cat /proc/meminfo | grep "MemTotal" | sed 's/[^0-9]*//g')
  echo "kbSizeRAM(${kbSizeRAM})" >> ${logFile}
  echo "dont forget to reduce dbcache once IBD is done" > "/mnt/hdd/${network}/blocks/selfsync.flag"
  # RP4 4GB
  if [ ${kbSizeRAM} -gt 3500000 ]; then
    echo "Detected RAM >=4GB --> optimizing ${network}.conf" >> ${logFile}
    sed -i "s/^dbcache=.*/dbcache=2560/g" /mnt/hdd/${network}/${network}.conf
  # RP4 2GB
  elif [ ${kbSizeRAM} -gt 1500000 ]; then
    echo "Detected RAM >=2GB --> optimizing ${network}.conf" >> ${logFile}
    sed -i "s/^dbcache=.*/dbcache=1536/g" /mnt/hdd/${network}/${network}.conf
  #RP3/4 1GB
  else
    echo "Detected RAM <=1GB --> optimizing ${network}.conf" >> ${logFile}
    sed -i "s/^dbcache=.*/dbcache=512/g" /mnt/hdd/${network}/${network}.conf
  fi
fi

# start network service
echo ""
echo "*** Start ${network} (SETUP) ***" >> ${logFile}
sed -i "s/^message=.*/message='Blockchain Testrun'/g" ${infoFile}
echo "- This can take a while .." >> ${logFile}
cp /home/admin/assets/${network}d.service /etc/systemd/system/${network}d.service
systemctl enable ${network}d.service
systemctl start ${network}d.service

# check if bitcoin has started
bitcoinRunning=0
loopcount=0
while [ ${bitcoinRunning} -eq 0 ]
do
  >&2 echo "# (${loopcount}/50) checking if ${network}d is running ... " >> ${logFile}
  bitcoinRunning=$(sudo -u bitcoin ${network}-cli getblockchaininfo 2>/dev/null | grep "initialblockdownload" -c)
  sleep 8
  sync
  loopcount=$(($loopcount +1))
  if [ ${loopcount} -gt 50 ]; then
    /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "btc-testrun-fail" "${network}d not running" "sudo -u bitcoin ${network}-cli getblockchaininfo | grep "initialblockdownload" -c --> ${bitcoinRunning}" ${logFile}
    exit 4
  fi
done
echo "OK ${network} startup successful " >> ${logFile}


###################################
# Prepare Lightning
source <(/home/admin/_cache.sh get lightning hostname)
echo "Prepare Lightning (${lightning})" >> ${logFile}

if [ "${hostname}" == "" ]; then
  /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "missing-hostname" "" "" ${logFile}
  exit 41
fi

if [ "${lightning}" != "lnd" ]; then 

  ###################################
  # Remove LND from systemd
  echo "Remove LND" >> ${logFile}
  /home/admin/_cache.sh set message "Deactivate Lightning"
  sudo systemctl disable lnd
  sudo rm /etc/systemd/system/lnd.service 2>/dev/null
  sudo systemctl daemon-reload
fi

if [ "${lightning}" == "lnd" ]; then 

  ###################################
  # LND
  echo "############## Setup LND" >> ${logFile}
  /home/admin/_cache.sh set message "LND Setup"

  # password C (raspiblitz.setup)
  if [ "${passwordC}" == "" ]; then
    /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "missing-passwordc" "config: missing passwordC" "" ${logFile}
    exit 5
  fi

  # if user uploaded an LND rescue file (raspiblitz.setup)
  if [ "${lndrescue}" != "" ]; then
    echo "Restore LND data from uploaded rescue file ${lndrescue} ..." >> ${logFile}
    source <(sudo /home/admin/config.scripts/lnd.backup.sh lnd-import ${lndrescue})
    if [ "${error}" != "" ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lndrescue-import" "setup: lnd import backup failed" "${error}" ${logFile}
      exit 6
    fi
  else
    # preparing new LND config (raspiblitz.setup)
    echo "Creating new LND config ..." >> ${logFile}
    sudo -u bitcoin mkdir /mnt/hdd/lnd 2> /dev/null
    sudo cp /home/admin/assets/lnd.bitcoin.conf /mnt/hdd/lnd/lnd.conf
    sudo chown bitcoin:bitcoin /mnt/hdd/lnd/lnd.conf
    sudo /home/admin/config.scripts/lnd.install.sh on mainnet
    sudo /home/admin/config.scripts/lnd.setname.sh mainnet ${hostname}
  fi

  # make sure all directories are linked
  sudo /home/admin/config.scripts/blitz.datadrive.sh link

  # check if now a config exists
  configLinkedCorrectly=$(sudo ls sudo ls /home/bitcoin/.lnd/lnd.conf | grep -c "lnd.conf")
  if [ "${configLinkedCorrectly}" != "1" ]; then
    /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-link-broken" "link /home/bitcoin/.lnd/lnd.conf broken" "" ${logFile}
    exit 7
  fi

  # Init LND service & start
  echo "*** Init LND Service & Start ***" >> ${logFile}
  /home/admin/_cache.sh set message "LND Testrun"

  # just in case
  sudo systemctl stop lnd 2>/dev/null
  sudo systemctl disable lnd 2>/dev/null

  # copy lnd service
  sudo cp /home/admin/assets/lnd.service /etc/systemd/system/lnd.service >> ${logFile}

  # start lnd up
  echo "Starting LND Service ..." >> ${logFile}
  sudo systemctl enable lnd >> ${logFile}
  sudo systemctl start lnd >> ${logFile}
  echo "Starting LND Service ... executed" >> ${logFile}

  # check that lnd started
  lndRunning=0
  loopcount=0
  while [ ${lndRunning} -eq 0 ]
  do
    lndRunning=$(systemctl status lnd.service | grep -c running)
    if [ ${lndRunning} -eq 0 ]; then
      date +%s >> ${logFile}
      echo "LND not ready yet ... waiting another 60 seconds." >> ${logFile}
      sleep 10
    fi
    loopcount=$(($loopcount +1))
    if [ ${loopcount} -gt 100 ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-start-fail" "lnd service not getting to running status" "sudo systemctl status lnd.service | grep -c running --> ${lndRunning}" ${logFile}
      exit 8
    fi
  done
  echo "OK - LND is running" ${logFile}
  sleep 10

  # Check LND health/fails (to be extended)
  tlsExists=$(ls /mnt/hdd/lnd/tls.cert 2>/dev/null | grep -c "tls.cert")
  if [ ${tlsExists} -eq 0 ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-no-tls" "lnd not created TLS cert" "no /mnt/hdd/lnd/tls.cert" ${logFile}
      exit 9
  fi

  # import static channel backup if was uploaded
  if [ "${staticchannelbackup}" != "" ]; then
    echo "Preparing static channel backup file ${staticchannelbackup} ..." >> ${logFile}
    source <(/home/admin/config.scripts/lnd.backup.sh scb-import ${staticchannelbackup})
    if [ "${error}" != "" ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-scb-import" "lnd.backup.sh scb-import returned error" "/home/admin/config.scripts/lnd.backup.sh scb-import ${staticchannelbackup} --> ${error}" ${logFile}
      exit 10
    fi
  fi

  # WALLET --> SEED + SCB 
  if [ "${seedWords}" != "" ] && [ "${staticchannelbackup}" != "" ]; then

    echo "WALLET --> SEED + SCB " >> ${logFile}
    /home/admin/_cache.sh set message "LND Wallet (SEED & SCB)"
    if ! pip list | grep grpc; then sudo -H python3 -m pip install grpcio==1.38.1; fi
    source <(/home/admin/config.scripts/lnd.initwallet.py scb mainnet ${passwordC} "${seedWords}" "${staticchannelbackup}" ${seedPassword})
    if [ "${err}" != "" ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-wallet-seed+scb" "lnd.initwallet.py scb returned error" "/home/admin/config.scripts/lnd.initwallet.py scb mainnet ... --> ${err} + ${errMore}" ${logFile}
      exit 11
    fi

  # WALLET --> SEED
  elif [ "${seedWords}" != "" ]; then
    
    echo "WALLET --> SEED" >> ${logFile} 
    /home/admin/_cache.sh set message "LND Wallet (SEED)"
    if ! pip list | grep grpc; then sudo -H python3 -m pip install grpcio==1.38.1; fi  
    source <(/home/admin/config.scripts/lnd.initwallet.py seed mainnet ${passwordC} "${seedWords}" ${seedPassword})
    if [ "${err}" != "" ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-wallet-seed" "lnd.initwallet.py seed returned error" "/home/admin/config.scripts/lnd.initwallet.py seed mainnet ... --> ${err} + ${errMore}" ${logFile}
      exit 12
    fi

  # WALLET --> NEW
  else

    echo "WALLET --> NEW" >> ${logFile}
    /home/admin/_cache.sh set message "LND Wallet (NEW)"
    if ! pip list | grep grpc; then sudo -H python3 -m pip install grpcio==1.38.1; fi 
    source <(/home/admin/config.scripts/lnd.initwallet.py new mainnet ${passwordC})
    if [ "${err}" != "" ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-wallet-new" "lnd.initwallet.py new returned error" "/home/admin/config.scripts/lnd.initwallet.py new mainnet ... --> ${err} + ${errMore}" ${logFile}
      /home/admin/_cache.sh set state "error"
      /home/admin/_cache.sh set message "setup: lnd wallet NEW failed"
      echo "FAIL see ${logFile}"
      echo "FAIL: setup: lnd wallet SEED failed (2)" >> ${logFile}
      echo "${err}" >> ${logFile}
      echo "${errMore}" >> ${logFile}
      exit 13
    fi

    # write created seedwords into SETUPFILE to be displayed to user on final setup later
    echo "seedwordsNEW='${seedwords}'" >> ${setupFile}
    echo "seedwords6x4NEW='${seedwords6x4}'" >> ${setupFile}

  fi

  # sync macaroons & TLS to other users
  echo "*** Copy LND Macaroons to user admin ***" >> ${logFile}
  /home/admin/_cache.sh set message "LND Credentials"

  # check if macaroon exists now - if not fail
  macaroonExists=$(sudo -u bitcoin ls -la /home/bitcoin/.lnd/data/chain/${network}/${chain}net/admin.macaroon 2>/dev/null | grep -c admin.macaroon)
  if [ ${macaroonExists} -eq 0 ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-no-macaroons" "lnd did not create macaroons" "/home/bitcoin/.lnd/data/chain/${network}/${chain}net/admin.macaroon --> missing" ${logFile}
      exit 14
  fi

  # now sync macaroons & TLS zo other users
  sudo /home/admin/config.scripts/lnd.credentials.sh sync >> ${logFile}

  # make a final lnd check
  source <(/home/admin/config.scripts/lnd.check.sh basic-setup)
  if [ "${err}" != "" ]; then
    /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-check-error" "lnd.check.sh basic-setup with error" "/home/admin/config.scripts/lnd.check.sh basic-setup --> ${err}" ${logFile}
    exit 15
  fi

  # stop lnd for the rest of the provision process
  echo "stopping lnd for the rest provision again (will start on next boot)" >> ${logFile}
  systemctl stop lnd >> ${logFile}

fi

if [ "${lightning}" == "cl" ]; then 

  ###################################
  # c-lightning
  echo "############## c-lightning" >> ${logFile}

  /home/admin/_cache.sh set message "C-Lightning Install"
  sudo /home/admin/config.scripts/cl.install.sh on mainnet >> ${logFile}
  /home/admin/_cache.sh set message "C-Lightning Setup"

  # OLD WALLET FROM CLIGHTNING RESCUE
  if [ "${clrescue}" != "" ]; then

    echo "Restore CL data from uploaded rescue file ${clrescue} ..." >> ${logFile}
    source <(/home/admin/config.scripts/cl.backup.sh cl-import ${clrescue})
    if [ "${error}" != "" ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "cl-import-backup" "cl.backup.sh cl-import with error" "/home/admin/config.scripts/cl.backup.sh cl-import ${clrescue} --> ${error}" ${logFile}
      exit 16
    fi

  # OLD WALLET FROM SEEDWORDS
  elif [ "${seedWords}" != "" ]; then

    echo "Restore CL wallet from seedWords ..." >> ${logFile}
    source <(/home/admin/config.scripts/cl.hsmtool.sh seed-force mainnet "${seedWords}" "${seedPassword}")

    # check if wallet really got created 
    walletExistsNow=$(ls /home/bitcoin/.lightning/bitcoin/hsm_secret 2>/dev/null | grep -c "hsm_secret")
    if [ $walletExistsNow -eq 0 ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "cl-wallet-seed" "cl.hsmtool.sh seed-force not created wallet" "ls /home/bitcoin/.lightning/bitcoin/hsm_secret --> 0" ${logFile}
      exit 17
    fi

  # NEW WALLET
  else

    echo "Generate new CL wallet ..." >> ${logFile}

    # generate new wallet
    source <(/home/admin/config.scripts/cl.hsmtool.sh new-force mainnet)

    # check if got new seedwords
    if [ "${seedwords}" == "" ] || [ "${seedwords6x4}" == "" ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "cl-wallet-new-noseeds" "cl.hsmtool.sh new-force did not returned seedwords" "/home/admin/config.scripts/cl.hsmtool.sh new-force mainnet --> seedwords=''" ${logFile}
      exit 18
    fi

    # check if wallet really got created 
    walletExistsNow=$(sudo ls /home/bitcoin/.lightning/bitcoin/hsm_secret 2>/dev/null | grep -c "hsm_secret")
    if [ $walletExistsNow -eq 0 ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "cl-wallet-new-nowallet" "cl.hsmtool.sh new-force did not created wallet" "/home/bitcoin/.lightning/bitcoin/hsm_secret --> missing" ${logFile}
      exit 19
    fi

    # write created seedwords into SETUPFILE to be displayed to user on final setup later
    echo "seedwordsNEW='${seedwords}'" >> ${setupFile}
    echo "seedwords6x4NEW='${seedwords6x4}'" >> ${setupFile}

  fi

  # stop c-lightning for the rest of the provision process
  echo "stopping lightningd for the rest provision again (will start on next boot)" >> ${logFile}
  systemctl stop lightningd >> ${logFile}

fi

# stop bitcoind for the rest of the provision process
echo "stopping bitcoind for the rest provision again (will start on next boot)" >> ${logFile}
systemctl stop bitcoind >> ${logFile}

/home/admin/_cache.sh set message "Provision Setup Finish"
echo "END Setup"  >> ${logFile}
exit 0