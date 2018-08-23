#!/bin/sh
echo ""

# load network
network=`cat .network`

# get chain
chain=$(${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo | jq -r '.chain')

# verify that bitcoin is running
echo "*** Checking ${network} ***"
bitcoinRunning=$(sudo -u bitcoin ${network}-cli getblockchaininfo | grep -c blocks)
if [ ${bitcoinRunning} -eq 0 ]; then
  # HDD is not available yet
  echo "FAIL - ${network}d is not running"
  echo "recheck with orignal tutorial -->"
  echo "https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_30_bitcoin.md"
fi
echo "OK - ${network}d is running"
echo ""

###### Wait for Blochain Sync --> LET DO THIS LATER ON LND SCAN
#echo "*** Syncing Blockchain ***"
#ready=0
#while [ ${ready} -eq 0 ]
#  do
#    progress="$(sudo -u bitcoin ${network}-cli getblockchaininfo | jq -r '.verificationprogress')"
#    verySmallProgress=$(echo $progress | grep -c 'e-');
#    if [ ${verySmallProgress} -eq 1 ]; then
#     progress="0.00";
#    fi
#    ready=$(echo $progress'>0.99' | bc -l)
#    sync_percentage=$(printf "%.2f%%" "$(echo $progress | awk '{print 100 * $1}')")
#    #echo "progress($progress) verySmallProgress($verySmallProgress) ready($ready) sync_percentage($sync_percentage)"
#    if [ ${#ready} -eq 0 ]; then
#      echo "waiting for init ... can take a while"
#      ready=0
#    elif [ "$sync_percentage" = "0.00%" ]; then  
#      echo "waiting for network ... can take a while"
#      ready=0
#    elif [ ${ready} -eq 0 ]; then
#      echo "${sync_percentage}"
#    else
#      echo "finishing sync ... can take a while"
#    fi
#    sleep 3
#  done
#echo "OK - Blockchain is synced"
#echo ""

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
lndRunning=$(systemctl status lnd.service | grep -c running)
if [ ${lndRunning} -eq 0 ]; then
  sed -i "5s/.*/Wants=${network}d.service/" ./assets/lnd.service
  sed -i "6s/.*/After=${network}d.service/" ./assets/lnd.service
  sudo cp /home/admin/assets/lnd.service /etc/systemd/system/lnd.service
  sudo chmod +x /etc/systemd/system/lnd.service
  sudo systemctl enable lnd
  sudo systemctl start lnd
  echo "Starting LND ... give 120 seconds to init."
  sleep 120
fi

###### Check LND is running
lndRunning=0
while [ ${lndRunning} -eq 0 ]
do
  lndRunning=$(systemctl status lnd.service | grep -c running)
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

  # delete old macaroons if exist
  sudo rm /mnt/hdd/lnd/*.macaroon 2>/dev/null
  sudo rm /home/admin/.lnd/*.macaroon 2>/dev/null

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
  echo "lncli create"
  
  # execute command and monitor error
  _error="./.error.out"
  sudo -u bitcoin /usr/local/bin/lncli create 2>$_error
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
  # set SetupState to 75 (mid thru this process)
  echo "65" > /home/admin/.setup
fi

echo "--> lets wait 60 seconds for LND to get ready"
sleep 60

###### Copy LND macaroons to admin
echo ""
echo "*** Copy LND Macaroons to user admin ***"
macaroonExists=$(sudo -u bitcoin ls -la /home/bitcoin/.lnd/admin.macaroon | grep -c admin.macaroon)
if [ ${macaroonExists} -eq 0 ]; then
  ./AAunlockLND.sh
  sleep 3
fi
macaroonExists=$(sudo -u bitcoin ls -la /home/bitcoin/.lnd/admin.macaroon | grep -c admin.macaroon)
if [ ${macaroonExists} -eq 0 ]; then
  sudo -u bitcoin ls -la /home/bitcoin/.lnd/admin.macaroon
  echo ""
  echo "FAIL - LND Macaroons not created"
  echo "Please check the following LND issue:"
  echo "https://github.com/lightningnetwork/lnd/issues/890"
  echo "You may want try again with starting ./70initLND.sh"
  exit 1
fi
sudo mkdir /home/admin/.lnd 2>/dev/null
macaroonExists=$(sudo ls -la /home/admin/.lnd/ | grep -c admin.macaroon)
if [ ${macaroonExists} -eq 0 ]; then
  sudo mkdir /home/admin/.lnd
  sudo cp /home/bitcoin/.lnd/tls.cert /home/admin/.lnd
  sudo cp /home/bitcoin/.lnd/admin.macaroon /home/admin/.lnd
  sudo chown -R admin:admin /home/admin/.lnd/
  echo "OK - LND Macaroons created"
else
  echo "OK - Macaroons are already copied"
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

### Show Lighthning Sync
echo ""
echo "*** Check LND Sync ***"
item=0
lndSyncing=$(sudo -u bitcoin /usr/local/bin/lncli getinfo 2>/dev/null | jq -r '.synced_to_chain' | grep -c true)
if [ ${lndSyncing} -eq 0 ]; then
  echo "OK - wait for LND to be synced"
  while :
    do
      
      # show sync status
      ./80scanLND.sh
      sleep 3
      
      # break loop when synced
      lndSyncing=$(sudo -u bitcoin /usr/local/bin/lncli getinfo 2>/dev/null | jq -r '.synced_to_chain' | grep -c true)
      if [ ${lndSyncing} -eq 1 ]; then
        break
      fi

      # break loop when wallet is locked
      locked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep -c unlock)
      if [ ${locked} -eq 1 ]; then
        break
      fi

    done
  clear
else
  echo "OK - LND is in sync"
fi

# set SetupState (scan is done - so its 80%)
echo "80" > /home/admin/.setup

###### finishSetup
./90finishSetup.sh
