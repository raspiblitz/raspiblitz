#!/bin/bash
echo ""

## get basic info
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

# verify that bitcoin is running
echo "*** Checking ${network} ***"
bitcoinRunning=$(systemctl status ${network}d.service 2>/dev/null | grep -c running)
if [ ${bitcoinRunning} -eq 0 ]; then
  #doublecheck
  bitcoinRunning=$(sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo  | grep -c verificationprogress)
fi
if [ ${bitcoinRunning} -eq 0 ]; then
  # HDD is not available yet
  echo "FAIL - ${network}d is not running"
  echo "recheck with orignal tutorial -->"
  echo "https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_30_bitcoin.md"
fi
echo "OK - ${network}d is running"
echo ""

# verify that chainnetwork is ready
chainIsReady=0
loopCount=0
echo "*** Wait until ${network}d is ready ..."
while [ ${chainIsReady} -eq 0 ]
  do
    loopCount=$(($loopCount +1))
    result=$(sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo 2>error.out)
    error=`cat error.out`
    rm error.out
    if [ ${#error} -gt 0 ]; then
      if [ ${loopCount} -gt 33 ]; then
        echo "*** TAKES LONGER THEN EXCEPTED ***"
        date +%s
        echo "result(${result})"
        echo "error(${error})"
        testnetAdd=""
        if [ "${chain}"  = "test" ]; then
         testnetAdd="testnet3/"
        fi
        sudo tail -n 5 /mnt/hdd/${network}/${testnetAdd}debug.log
        echo "If you see an error -28 relax, just give it some time."
        echo "Waiting 1 minute and then trying again ..."
        sleep 60
      else
        echo "(${loopCount}/33) still waiting .."
        sleep 10
      fi
    else
      echo "OK - chainnetwork is working"
      echo ""
      chainIsReady=1
      break
    fi
  done

###### LND Config
echo "*** LND Config ***"
configExists=$( sudo ls /mnt/hdd/lnd/ | grep -c lnd.conf )
if [ ${configExists} -eq 0 ]; then
  sudo cp /home/admin/assets/lnd.${network}.conf /mnt/hdd/lnd/lnd.conf
  sudo chown bitcoin:bitcoin /mnt/hdd/lnd/lnd.conf
  if [ -d /home/bitcoin/.lnd ]; then
    echo "OK - LND config written"
  else
    echo "FAIL - Was not able to setup LND"
    exit 1
  fi
else
  echo "OK - exists"
fi
echo ""

###### Start LND
echo "*** Starting LND ***"
lndRunning=$(sudo systemctl status lnd.service 2>/dev/null | grep -c running)
if [ ${lndRunning} -eq 0 ]; then
  sed -i "5s/.*/Wants=${network}d.service/" ./assets/lnd.service
  sed -i "6s/.*/After=${network}d.service/" ./assets/lnd.service
  sudo cp /home/admin/assets/lnd.service /etc/systemd/system/lnd.service
  sudo chmod +x /etc/systemd/system/lnd.service
  sudo systemctl enable lnd
  sudo systemctl start lnd
  echo ""
  dialog --pause "  Starting LND - please wait .." 8 58 120
fi

###### Check LND is running
lndRunning=0
while [ ${lndRunning} -eq 0 ]
do
  lndRunning=$(sudo systemctl status lnd.service | grep -c running)
  if [ ${lndRunning} -eq 0 ]; then
    date +%s
    echo "LND not ready yet ... waiting another 60 seconds."
    echo "If this takes too long (more then 10min total) --> CTRL+c and report Problem"
    sleep 60
  fi
done
echo "OK - LND is running"
echo ""

###### Instructions on Creating LND Wallet
walletExists=$(sudo ls /mnt/hdd/lnd/data/chain/${network}/${chain}net/wallet.db 2>/dev/null | grep wallet.db -c)
echo "walletExists(${walletExists})"
sleep 2
if [ ${walletExists} -eq 0 ]; then

  # setup state signals, that no wallet has been created yet
  dialog --backtitle "RaspiBlitz - LND Lightning Wallet (${network}/${chain})" --msgbox "
${network} and Lighthing Services are installed.
You now need to setup your Lightning Wallet:

We will now call the command: lncli create
lncli = Lightning Network Command Line Interface
Learn more: https://api.lightning.community
Press OK and follow the 'Helping Instructions'.
" 14 52
  clear
  echo "****************************************************************************"
  echo "Helping Instructions --> for creating a new LND Wallet"
  echo "****************************************************************************"
  echo "A) For 'Wallet Password' use your PASSWORD C --> !! minimum 8 characters !!"
  echo "B) Answere 'n' because you dont have a 'cipher seed mnemonic' (24 words) yet" 
  echo "C) For 'passphrase' to encrypt your 'cipher seed' use PASSWORD D (optional)"
  echo "****************************************************************************"
  echo ""
  echo "lncli --chain=${network} create"
  
  # execute command and monitor error
  _error="./.error.out"
  sudo -u bitcoin /usr/local/bin/lncli --chain=${network} create 2>$_error
  error=`cat ${_error}`

  if [ ${#error} -gt 0 ]; then
    echo ""
    echo "!!! FAIL !!! SOMETHING WENT WRONG:"
    echo "${error}"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo ""
    echo "Press ENTER to retry ... or CTRL-c to EXIT"
    read key
    echo "Starting RETRY ..."
    ./70initLND.sh
    exit 1
  fi

  echo ""
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "!!! Make sure to write down the 24 words (cipher seed mnemonic) !!!"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "If you are ready. Press ENTER."
  read key

  sudo sed -i "s/^setupStep=.*/setupStep=65/g" /home/admin/raspiblitz.info
fi

dialog --pause "  Waiting for LND - please wait .." 8 58 60

###### Copy LND macaroons to admin
echo ""
echo "*** Copy LND Macaroons to user admin ***"
macaroonExists=$(sudo -u bitcoin ls -la /home/bitcoin/.lnd/data/chain/${network}/${chain}net/admin.macaroon 2>/dev/null | grep -c admin.macaroon)
if [ ${macaroonExists} -eq 0 ]; then
  ./AAunlockLND.sh
  sleep 3
fi
macaroonExists=$(sudo -u bitcoin ls -la /home/bitcoin/.lnd/data/chain/${network}/${chain}net/admin.macaroon 2>/dev/null | grep -c admin.macaroon)
if [ ${macaroonExists} -eq 0 ]; then
  sudo -u bitcoin ls -la /home/bitcoin/.lnd/data/chain/${network}/${chain}net/admin.macaroon
  echo ""
  echo "FAIL - LND Macaroons not created"
  echo "Please check the following LND issue:"
  echo "https://github.com/lightningnetwork/lnd/issues/890"
  echo "You may want try again with starting ./70initLND.sh"
  exit 1
fi
macaroonExists=$(sudo ls -la /home/admin/.lnd/data/chain/${network}/${chain}net/ | grep -c admin.macaroon)
if [ ${macaroonExists} -eq 0 ]; then
  sudo mkdir /home/admin/.lnd
  sudo mkdir /home/admin/.lnd/data
  sudo mkdir /home/admin/.lnd/data/chain
  sudo mkdir /home/admin/.lnd/data/chain/${network}
  sudo mkdir /home/admin/.lnd/data/chain/${network}/${chain}net
  sudo cp /home/bitcoin/.lnd/tls.cert /home/admin/.lnd
  sudo cp /home/bitcoin/.lnd/lnd.conf /home/admin/.lnd
  sudo cp /home/bitcoin/.lnd/data/chain/${network}/${chain}net/admin.macaroon /home/admin/.lnd/data/chain/${network}/${chain}net
  sudo chown -R admin:admin /home/admin/.lnd/
  echo "OK - LND Macaroons created"
  echo ""
else
  echo "OK - Macaroons are already copied"
  echo ""
fi

###### Unlock Wallet (if needed)
echo "*** Check Wallet Lock ***"
locked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep -c unlock)
if [ ${locked} -gt 0 ]; then
  echo "OK - Wallet is locked ... starting unlocking dialog"
  ./AAunlockLND.sh
else
  echo "OK - Wallet is already unlocked"
fi

# set SetupState (scan is done - so its 80%)
sudo sed -i "s/^setupStep=.*/setupStep=80/g" /home/admin/raspiblitz.info

###### finishSetup
sudo ./90finishSetup.sh
sudo ./95finalSetup.sh
