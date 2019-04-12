#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

# CHECK #########

echo "*** Check Basic Config ***"
if [ ${#network} -eq 0 ]; then
  echo "FAIL - missing: network"
  exit 1
fi
if [ ${#chain} -eq 0 ]; then
  echo "FAIL - missing: chain"
  exit 1
fi

# CHECK #########

echo "*** Check ${network} Running ***"
bitcoinRunning=$(systemctl status ${network}d.service 2>/dev/null | grep -c running)
if [ ${bitcoinRunning} -eq 0 ]; then
  bitcoinRunning=$(sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo  | grep -c verificationprogress)
fi
if [ ${bitcoinRunning} -eq 0 ]; then 
  whiptail --title "70initLND - WARNING" --yes-button "Retry" --no-button "EXIT+Logs" --yesno "Service ${network}d is not running." 8 50
  if [ $? -eq 0 ]; then
    /home/admin/70initLND.sh
  else
    /home/admin/XXdebugLogs.sh
  fi
  exit 1
fi

# CHECK #########

echo "*** Check ${network} Responding ***"
chainIsReady=0
loopCount=0
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

# CHECK #########

echo "*** Check LND Config ***"
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

###### Check LND starting

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

###### Check LND health/fails (to be extended)
fail=""
tlsExists=$(sudo ls /mnt/hdd/lnd/tls.cert 2>/dev/null | grep -c "tls.cert")
if [ ${tlsExists} -eq 0 ]; then
  fail="LND was starting, but missing /mnt/hdd/lnd/tls.cert"
fi
if [ ${#fail} -gt 0 ]; then
  whiptail --title "70initLND - WARNING" --yes-button "Retry" --no-button "EXIT+Logs" --yesno "${fail}" 8 50
  if [ $? -eq 0 ]; then
    /home/admin/70initLND.sh
  else
    /home/admin/XXdebugLogs.sh
  fi
  exit 1
fi

###### Instructions on Creating/Restoring LND Wallet
walletExists=$(sudo ls /mnt/hdd/lnd/data/chain/${network}/${chain}net/wallet.db 2>/dev/null | grep wallet.db -c)
echo "walletExists(${walletExists})"
sleep 2
if [ ${walletExists} -eq 0 ]; then

  # UI: Ask if user wants NEW wallet or RECOVER a wallet
  OPTIONS=(NEW "Setup a brand new Lightning Node (DEFAULT)" \
           OLD "I had a old Node I want to recover/restore")
  CHOICE=$(dialog --backtitle "RaspiBlitz - LND Setup" --clear --title "LND Data & Wallet" --menu "How to setup your node?:" 11 60 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)
  echo "choice($CHOICE)"

  if [ "${CHOICE}" == "NEW" ]; then

    

    source lnd/bin/activate
    python /home/admin/config.scripts/lnd.initwallet.py new 12345678

  else

    # TODO: IMPLEMENT
    # - Recover with Seed Word List 
    #   --> (ask if seed word list was password D protected)
    # - Recover with Seed Word List & Channel Backup Snapshot File 
    #   --> (ask if seed word list was password D protected)
    # - Restore LND backup made with Rescue-Script (tar.gz-file)
    #   --> run retsore script

    # FALLBACK TO lncli create FOR NOW
    dialog --title "OK" --msgbox "\nI will start 'lncli create' for you ..." 7 44
    sudo -u bitcoin /usr/local/bin/lncli --chain=${network} create
    /home/admin/70.initLND.sh
    exit 1

  fi

