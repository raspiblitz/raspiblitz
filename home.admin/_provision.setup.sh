#!/bin/bash

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
sudo sed -i "s/^message=.*/message='Provision Setup'/g" ${infoFile}

###################################
# Preserve SSH keys
# just copy dont link anymore
# see: https://github.com/rootzoll/raspiblitz/issues/1798
sed -i "s/^message=.*/message='SSH Keys'/g" ${infoFile}

# link ssh directory from SD card to HDD
/home/admin/config.scripts/blitz.ssh.sh backup

###################################
# Prepare Blockchain Service
sed -i "s/^message=.*/message='Blockchain Setup'/g" ${infoFile}

if [ "${network}" == "" ]; then
  sed -i "s/^state=.*/state=error/g" ${infoFile}
  sed -i "s/^message=.*/message='config: missing network'/g" ${infoFile}
  echo "FAIL see ${logFile}"
  echo "FAIL: missing network in (${setupFile})!" >> ${logFile}
  exit 20
fi

if [ "${chain}" == "" ]; then
  sed -i "s/^state=.*/state=error/g" ${infoFile}
  sed -i "s/^message=.*/message='config: missing chain'/g" ${infoFile}
  echo "FAIL see ${logFile}"
  echo "FAIL: missing chain in (${setupFile})!" >> ${logFile}
  exit 2
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

# set password B as RPC password
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
    sed -i "s/^state=.*/state=error/g" ${infoFile}
    sed -i "s/^message=.*/message='setup: failed ${network}'/g" ${infoFile}
    echo "FAIL: setup: failed ${network}" >> ${logFile}
    exit 4
  fi
done
echo "OK ${network} startup successful " >> ${logFile}


###################################
# Prepare Lightning
echo "Prepare Lightning (${lightning})" >> ${logFile}

if [ "${lightning}" != "lnd" ]; then 

  ###################################
  # Remove LND from systemd
  echo "Remove LND" >> ${logFile}
  sudo sed -i "s/^message=.*/message='Deactivate Lightning'/g" ${infoFile}
  sudo systemctl disable lnd
  sudo rm /etc/systemd/system/lnd.service 2>/dev/null
  sudo systemctl daemon-reload
fi

if [ "${lightning}" == "lnd" ]; then 

  ###################################
  # LND
  echo "############## Setup LND" >> ${logFile}
  sudo sed -i "s/^message=.*/message='LND Setup'/g" ${infoFile}

  if [ "${passwordC}" == "" ]; then
    sed -i "s/^state=.*/state=error/g" ${infoFile}
    sed -i "s/^message=.*/message='config: missing passwordC'/g" ${infoFile}
    echo "FAIL see ${logFile}"
    echo "FAIL: missing passwordC in (${setupFile})!" >> ${logFile}
    exit 5
  fi

  # if user uploaded an LND rescue file
  if [ "${lndrescue}" != "" ]; then
    echo "Restore LND data from uploaded rescue file ${lndrescue} ..." >> ${logFile}
    source <(sudo /home/admin/config.scripts/lnd.backup.sh lnd-import ${lndrescue})
    if [ "${error}" != "" ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: lnd import backup failed'/g" ${infoFile}
      echo "FAIL see ${logFile}"
      echo "FAIL: setup: lnd import backup failed" >> ${logFile}
      echo "${error}" >> ${logFile}
      exit 6
    fi
  else
    # preparing new LND config
    echo "Creating new LND config ..." >> ${logFile}
    sudo -u bitcoin mkdir /mnt/hdd/lnd 2> /dev/null
    sudo cp /home/admin/assets/lnd.${network}.conf /mnt/hdd/lnd/lnd.conf
    sudo chown bitcoin:bitcoin /mnt/hdd/lnd/lnd.conf
    sudo /home/admin/config.scripts/lnd.install.sh on mainnet
    sudo /home/admin/config.scripts/lnd.setname.sh mainnet ${hostname}
  fi

  # make sure all directories are linked
  sudo /home/admin/config.scripts/blitz.datadrive.sh link

  # check if now a config exists
  configLinkedCorrectly=$(sudo ls sudo ls /home/bitcoin/.lnd/lnd.conf | grep -c "lnd.conf")
  if [ "${configLinkedCorrectly}" != "1" ]; then
    sed -i "s/^state=.*/state=error/g" ${infoFile}
    sed -i "s/^message=.*/message='setup: lnd conf link broken'/g" ${infoFile}
    echo "FAIL see ${logFile}"
    echo "FAIL: setup: lnd conf link broken" >> ${logFile}
    exit 7
  fi

  # Init LND service & start
  echo "*** Init LND Service & Start ***" >> ${logFile}
  sudo sed -i "s/^message=.*/message='LND Testrun'/g" ${infoFile}

  # just in case
  sudo systemctl stop lnd 2>/dev/null
  sudo systemctl disable lnd 2>/dev/null

  # make sure lnd gets started after blockchain service
  sed -i "5s/.*/Wants=${network}d.service/" /home/admin/assets/lnd.service >> ${logFile}
  sed -i "6s/.*/After=${network}d.service/" /home/admin/assets/lnd.service >> ${logFile}
  sudo cp /home/admin/assets/lnd.service /etc/systemd/system/lnd.service >> ${logFile}

  # start lnd up
  echo "Starting LND Service ..." >> ${logFile}
  sudo systemctl enable lnd >> ${logFile}
  sudo systemctl start lnd >> ${logFile}

  # check that lnd started
  lndRunning=0
  loopcount=0
  while [ ${lndRunning} -eq 0 ]
  do
    lndRunning=$(sudo systemctl status lnd.service | grep -c running)
    if [ ${lndRunning} -eq 0 ]; then
      date +%s >> ${logFile}
      echo "LND not ready yet ... waiting another 60 seconds." >> ${logFile}
      sleep 10
    fi
    loopcount=$(($loopcount +1))
    if [ ${loopcount} -gt 100 ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: failed lnd start'/g" ${infoFile}
      echo "FAIL see ${logFile}"
      echo "FAIL: setup: failed lnd start" >> ${logFile}
      exit 8
    fi
  done
  echo "OK - LND is running" ${logFile}
  sleep 10

  # Check LND health/fails (to be extended)
  tlsExists=$(sudo ls /mnt/hdd/lnd/tls.cert 2>/dev/null | grep -c "tls.cert")
  if [ ${tlsExists} -eq 0 ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: missing lnd tls'/g" ${infoFile}
      echo "FAIL see ${logFile}"
      echo "FAIL: setup: missing lnd tls" >> ${logFile}
      exit 9
  fi

  # import static channel backup if was uploaded
  if [ "${staticchannelbackup}" != "" ]; then
    echo "Preparing static channel backup file ${staticchannelbackup} ..." >> ${logFile}
    source <(sudo /home/admin/config.scripts/lnd.backup.sh scb-import ${staticchannelbackup})
    if [ "${error}" != "" ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: lnd import SCB failed'/g" ${infoFile}
      echo "FAIL see ${logFile}"
      echo "FAIL: setup: lnd import SCB failed" >> ${logFile}
      echo "${error}" >> ${logFile}
      exit 10
    fi
  fi

  # WALLET --> SEED + SCB 
  if [ "${seedWords}" != "" ] && [ "${staticchannelbackup}" != "" ]; then

    echo "WALLET --> SEED + SCB " >> ${logFile}
    sudo sed -i "s/^message=.*/message='LND Wallet (SEED & SCB)'/g" ${infoFile}
    if ! pip list | grep grpc; then sudo -H python3 -m pip install grpcio==1.38.1; fi  
    sudo /home/admin/config.scripts/lnd.initwallet.py scb mainnet ${passwordC} "${seedWords}" "${staticchannelbackup}" ${seedPassword}
    if [ "${err}" != "" ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: lnd wallet SCB failed'/g" ${infoFile}
      echo "FAIL see ${logFile}"
      echo "FAIL: setup: lnd wallet SCB failed" >> ${logFile}
      echo "${err}" >> ${logFile}
      echo "${errMore}" >> ${logFile}
      exit 11
    fi

  # WALLET --> SEED
  elif [ "${seedWords}" != "" ]; then
    
    echo "WALLET --> SEED" >> ${logFile}
    sudo sed -i "s/^message=.*/message='LND Wallet (SEED)'/g" ${infoFile}
    if ! pip list | grep grpc; then sudo -H python3 -m pip install grpcio==1.38.1; fi  
    sudo /home/admin/config.scripts/lnd.initwallet.py seed mainnet ${passwordC} "${seedWords}" ${seedPassword}
    if [ "${err}" != "" ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: lnd wallet SEED failed'/g" ${infoFile}
      echo "FAIL see ${logFile}"
      echo "FAIL: setup: lnd wallet SEED failed" >> ${logFile}
      echo "${err}" >> ${logFile}
      echo "${errMore}" >> ${logFile}
      exit 12
    fi

  # WALLET --> NEW
  else

    echo "WALLET --> NEW" >> ${logFile}
    sudo sed -i "s/^message=.*/message='LND Wallet (NEW)'/g" ${infoFile}
    if ! pip list | grep grpc; then sudo -H python3 -m pip install grpcio==1.38.1; fi  
    source <(sudo /home/admin/config.scripts/lnd.initwallet.py new mainnet ${passwordC})
    if [ "${err}" != "" ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: lnd wallet SEED failed'/g" ${infoFile}
      echo "FAIL see ${logFile}"
      echo "FAIL: setup: lnd wallet SEED failed" >> ${logFile}
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
  sudo sed -i "s/^message=.*/message='LND Credentials'/g" ${infoFile}    

  # check if macaroon exists now - if not fail
  macaroonExists=$(sudo -u bitcoin ls -la /home/bitcoin/.lnd/data/chain/${network}/${chain}net/admin.macaroon 2>/dev/null | grep -c admin.macaroon)
  if [ ${macaroonExists} -eq 0 ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: lnd no macaroons'/g" ${infoFile}
      echo "FAIL: setup: lnd no macaroons" >> ${logFile}
      exit 14
  fi

  # now sync macaroons & TLS zo other users
  sudo /home/admin/config.scripts/lnd.credentials.sh sync >> ${logFile}

  # make a final lnd check
  source <(/home/admin/config.scripts/lnd.check.sh basic-setup)
  if [ "${err}" != "" ]; then
    sed -i "s/^state=.*/state=error/g" ${infoFile}
    sed -i "s/^message=.*/message='setup: lnd wallet SEED failed'/g" ${infoFile}
    echo "FAIL: setup: lnd wallet SEED failed" >> ${logFile}
    echo "${err}" >> ${logFile}
    exit 15
  fi

fi

if [ "${lightning}" == "cl" ]; then 

  ###################################
  # c-lightning
  echo "############## c-lightning" >> ${logFile}

  sudo sed -i "s/^message=.*/message='C-Lightning Install'/g" ${infoFile}
  sudo /home/admin/config.scripts/cl.install.sh on mainnet >> ${logFile}
  sudo sed -i "s/^message=.*/message='C-Lightning Setup'/g" ${infoFile}

  # OLD WALLET FROM CLIGHTNING RESCUE
  if [ "${clrescue}" != "" ]; then

    echo "Restore CL data from uploaded rescue file ${clrescue} ..." >> ${logFile}
    source <(sudo /home/admin/config.scripts/cl.backup.sh cl-import ${clrescue})
    if [ "${error}" != "" ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: cl import backup failed'/g" ${infoFile}
      echo "FAIL see ${logFile}"
      echo "FAIL: setup: cl import backup failed" >> ${logFile}
      echo "${error}" >> ${logFile}
      exit 16
    fi

  # OLD WALLET FROM SEEDWORDS
  elif [ "${seedWords}" != "" ]; then

    echo "Restore CL wallet from seedWords ..." >> ${logFile}
    source <(sudo /home/admin/config.scripts/cl.hsmtool.sh seed-force mainnet "${seedWords}" "${seedPassword}")

    # check if wallet really got created 
    walletExistsNow=$(sudo ls /home/bitcoin/.lightning/bitcoin/hsm_secret 2>/dev/null | grep -c "hsm_secret")
    if [ $walletExistsNow -eq 0 ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: seed maybe wrong'/g" ${infoFile}
      echo "FAIL: setup: no cl wallet created - seed maybe wrong" >> ${logFile}
      exit 17
    fi

  # NEW WALLET
  else

    echo "Generate new CL wallet ..." >> ${logFile}

    # generate new wallet
    source <(sudo /home/admin/config.scripts/cl.hsmtool.sh new-force mainnet)

    # check if got new seedwords
    if [ "${seedwords}" == "" ] || [ "${seedwords6x4}" == "" ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: no cl seedwords'/g" ${infoFile}
      echo "FAIL: setup: no cl seedwords" >> ${logFile}
      exit 18
    fi

    # check if wallet really got created 
    walletExistsNow=$(sudo ls /home/bitcoin/.lightning/bitcoin/hsm_secret 2>/dev/null | grep -c "hsm_secret")
    if [ $walletExistsNow -eq 0 ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: no cl wallet created'/g" ${infoFile}
      echo "FAIL: setup: no cl wallet created" >> ${logFile}
      exit 19
    fi

    # write created seedwords into SETUPFILE to be displayed to user on final setup later
    echo "seedwordsNEW='${seedwords}'" >> ${setupFile}
    echo "seedwords6x4NEW='${seedwords6x4}'" >> ${setupFile}

  fi

fi

sudo sed -i "s/^message=.*/message='Provision Setup Finish'/g" ${infoFile}
echo "END Setup"  >> ${logFile}
exit 0