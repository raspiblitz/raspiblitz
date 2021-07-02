#!/bin/bash

# LOGFILE - store debug logs of bootstrap
logFile="/home/admin/raspiblitz.log"

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
echo "" >> ${logFile}
echo "###################################" >> ${logFile}
echo "# _provision.setup.sh" >> ${logFile}
echo "###################################" >> ${logFile}
sudo sed -i "s/^message=.*/message='Provision Setup'/g" ${infoFile}

###################################
# Preserve SSH keys
# just copy dont link anymore
# see: https://github.com/rootzoll/raspiblitz/issues/1798
sudo sed -i "s/^message=.*/message='SSH Keys'/g" ${infoFile}

# link ssh directory from SD card to HDD
echo "# --> SSH key settings" >> ${logFile}
echo "# copying SSH pub keys to HDD" >> ${logFile}
sudo cp -r /etc/ssh /mnt/hdd/ssh >> ${logFile}
echo "# OK" >> ${logFile}

###################################
# Prepare Blockchain Service
sudo sed -i "s/^message=.*/message='Blockchain Setup'/g" ${infoFile}

if [ "${network}" == "" ]; then
  sed -i "s/^state=.*/state=error/g" ${infoFile}
  sed -i "s/^message=.*/message='config: missing network'/g" ${infoFile}
  echo "FAIL see ${logFile}"
  echo "FAIL: missing network in (${setupFile})!" >> ${logFile}
  exit 1
fi

if [ "${chain}" == "" ]; then
  sed -i "s/^state=.*/state=error/g" ${infoFile}
  sed -i "s/^message=.*/message='config: missing chain'/g" ${infoFile}
  echo "FAIL see ${logFile}"
  echo "FAIL: missing chain in (${setupFile})!" >> ${logFile}
  exit 1
fi

# make sure choosen blockchain service is installed
if [ "${network}" != "bitcoin" ]; then
  # TODO also ... check if /home/admin/selfsync.flag is needed on other chains
  sed -i "s/^state=.*/state=error/g" ${infoFile}
  sed -i "s/^message=.*/message='TODO: install ${network}'/g" ${infoFile}
  echo "FAIL see ${logFile}"
  echo "TODO: make sure ${network} is installed!" >> ${logFile}
  exit 1
fi

# copy configs files and directories
echo ""
echo "*** Prepare ${network} ***" >> ${logFile}
sudo -u bitcoin mkdir /mnt/hdd/${network} 2>/dev/null
sudo -u bitcoin mkdir /mnt/hdd/${network}/blocks 2>/dev/null
sudo -u bitcoin mkdir /mnt/hdd/${network}/chainstate 2>/dev/null
sudo cp /home/admin/assets/${network}.conf /mnt/hdd/${network}/${network}.conf
sudo mkdir /home/admin/.${network} 2>/dev/null
sudo cp /home/admin/assets/${network}.conf /home/admin/.${network}/${network}.conf

# set password B as RPC password
echo "SETTING PASSWORD B" >> ${logFile}
sudo /home/admin/config.scripts/blitz.setpassword.sh b "${passwordB}" >> ${logFile}

# optimize RAM for blockchain validation (bitcoin only)
if [ "${network}" == "bitcoin" ] && [ "${hddBlocksBitcoin}" == "0" ]; then
  echo "*** Optimizing RAM for Sync ***" >> ${logFile}
  kbSizeRAM=$(cat /proc/meminfo | grep "MemTotal" | sed 's/[^0-9]*//g')
  echo "dont forget to reduce dbcache once IBD is done" > "/mnt/hdd/${network}/blocks/selfsync.flag"
  # RP4 4GB
  if [ ${kbSizeRAM} -gt 3500000 ]; then
    echo "Detected RAM >=4GB --> optimizing ${network}.conf" >> ${logFile}
    sudo sed -i "s/^dbcache=.*/dbcache=3072/g" /mnt/hdd/${network}/${network}.conf
  # RP4 2GB
  elif [ ${kbSizeRAM} -gt 1500000 ]; then
    echo "Detected RAM >=2GB --> optimizing ${network}.conf" >> ${logFile}
    sudo sed -i "s/^dbcache=.*/dbcache=1536/g" /mnt/hdd/${network}/${network}.conf
  #RP3/4 1GB
  else
    echo "Detected RAM <=1GB --> optimizing ${network}.conf" >> ${logFile}
    sudo sed -i "s/^dbcache=.*/dbcache=512/g" /mnt/hdd/${network}/${network}.conf
  fi
fi

# start network service
echo ""
echo "*** Start ${network} ***" >> ${logFile}
sudo sed -i "s/^message=.*/message='Blockchain Testrun'/g" ${infoFile}
echo "- This can take a while .." >> ${logFile}
sudo cp /home/admin/assets/${network}d.service /etc/systemd/system/${network}d.service
#sudo chmod +x /etc/systemd/system/${network}d.service
sudo systemctl daemon-reload >> ${logFile}
sudo systemctl enable ${network}d.service >> ${logFile}
sudo systemctl start ${network}d.service >> ${logFile}

# check if bitcoin has started
bitcoinRunning=0
loopcount=0
while [ ${bitcoinRunning} -eq 0 ]
do
  >&2 echo "# (${loopcount}/200) checking if ${network}d is running ... " >> ${logFile}
  bitcoinRunning=$(sudo -u bitcoin ${network}-cli getblockchaininfo 2>/dev/null | grep "initialblockdownload" -c)
  sleep 2
  sync
  loopcount=$(($loopcount +1))
  if [ ${loopcount} -gt 200 ]; then
    sed -i "s/^state=.*/state=error/g" ${infoFile}
    sed -i "s/^message=.*/message='setup: failed ${network}'/g" ${infoFile}
    echo "FAIL: setup: failed ${network}" >> ${logFile}
    exit 1
  fi
done
echo "OK ${network} startup successfull " >> ${logFile}


###################################
# Prepare Lightning
echo "Prepare Lightning (${lightning})" >> ${logFile}

if [ "${lightning}" == "lnd" ]; then 

  ###################################
  # LND
  sudo sed -i "s/^message=.*/message='LND Setup'/g" ${infoFile}

  if [ "${passwordC}" == "" ]; then
    sed -i "s/^state=.*/state=error/g" ${infoFile}
    sed -i "s/^message=.*/message='config: missing passwordC'/g" ${infoFile}
    echo "FAIL see ${logFile}"
    echo "FAIL: missing passwordC in (${setupFile})!" >> ${logFile}
    exit 1
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
      exit 1
    fi
  else
    # preparing new LND config
    echo "Creating new LND config ..." >> ${logFile}
    sudo -u bitcoin mkdir /mnt/hdd/lnd 2> /dev/null
    sudo cp /home/admin/assets/lnd.${network}.conf /mnt/hdd/lnd/lnd.conf
    sudo chown bitcoin:bitcoin /mnt/hdd/lnd/lnd.conf
    sudo /home/admin/config.scripts/lnd.setname.sh ${hostname}
  fi

  # check if now a config exists
  configLinkedCorrectly=$(sudo ls sudo ls /home/bitcoin/.lnd/lnd.conf | grep -c "lnd.conf")
  if [ "${configLinkedCorrectly}" != "1" ]; then
    sed -i "s/^state=.*/state=error/g" ${infoFile}
    sed -i "s/^message=.*/message='setup: lnd conf link broken'/g" ${infoFile}
    echo "FAIL see ${logFile}"
    echo "FAIL: setup: lnd conf link broken" >> ${logFile}
    exit 1
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

  # make sure LND starts with Tor by default
  sudo /home/admin/config.scripts/internet.tor.sh lndconf-on >> ${logFile}

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
      exit 1
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
      exit 1
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
      exit 1
    fi
  fi

  # WALLET --> SEED + SCB 
  if [ "${seedWords}" != "" ] && [ "${staticchannelbackup}" != "" ]; then

    echo "WALLET --> SEED + SCB " >> ${logFile}
    sudo sed -i "s/^message=.*/message='LND Wallet (SEED & SCB)'/g" ${infoFile}    
    sudo /home/admin/config.scripts/lnd.initwallet.py scb ${passwordC} "${seedWords}" "${staticchannelbackup}" ${seedPassword}
    if [ "${err}" != "" ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: lnd wallet SCB failed'/g" ${infoFile}
      echo "FAIL see ${logFile}"
      echo "FAIL: setup: lnd wallet SCB failed" >> ${logFile}
      echo "${err}" >> ${logFile}
      echo "${errMore}" >> ${logFile}
      exit 1
    fi

  # WALLET --> SEED
  elif [ "${seedWords}" != "" ]; then
    
    echo "WALLET --> SEED" >> ${logFile}
    sudo sed -i "s/^message=.*/message='LND Wallet (SEED)'/g" ${infoFile}    
    sudo /home/admin/config.scripts/lnd.initwallet.py seed ${passwordC} "${seedWords}" ${seedPassword}
    if [ "${err}" != "" ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: lnd wallet SEED failed'/g" ${infoFile}
      echo "FAIL see ${logFile}"
      echo "FAIL: setup: lnd wallet SEED failed" >> ${logFile}
      echo "${err}" >> ${logFile}
      echo "${errMore}" >> ${logFile}
      exit 1
    fi

  # WALLET --> NEW
  else

    echo "WALLET --> NEW" >> ${logFile}
    sudo sed -i "s/^message=.*/message='LND Wallet (NEW)'/g" ${infoFile}    
    source <(sudo /home/admin/config.scripts/lnd.initwallet.py new ${passwordC})
    if [ "${err}" != "" ]; then
      sed -i "s/^state=.*/state=error/g" ${infoFile}
      sed -i "s/^message=.*/message='setup: lnd wallet SEED failed'/g" ${infoFile}
      echo "FAIL see ${logFile}"
      echo "FAIL: setup: lnd wallet SEED failed" >> ${logFile}
      echo "${err}" >> ${logFile}
      echo "${errMore}" >> ${logFile}
      exit 1
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
      exit 1
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
    exit 1
  fi

fi

if [ "${lightning}" == "cln" ]; then 

  ###################################
  # c-lightning
  sudo sed -i "s/^message=.*/message='c-lightning Setup'/g" ${infoFile}

  # TODO: implement
  sed -i "s/^state=.*/state=error/g" ${infoFile}
  sed -i "s/^message=.*/message='TODO: install c-lightning'/g" ${infoFile}
  echo "FAIL see ${logFile}"
  echo "TODO: install c-lightning!" >> ${logFile}
  exit 1

  # these vars are available from the setup process for cln loaded from setupfile
  # seedWords --> if entered on old seed
  # clnrescue --> if user uploaded a rescue file
  # setPasswordC --> for any new wallet encryption

fi

sudo sed -i "s/^message=.*/message='Provision Setup Finish'/g" ${infoFile}
echo "END Setup"  >> ${logFile}
exit 0

