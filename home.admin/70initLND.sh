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
  CHOICE=$(dialog --backtitle "RaspiBlitz" --clear --title "LND Setup" --menu "LND Data & Wallet" 11 60 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)
  echo "choice($CHOICE)"

  if [ "${CHOICE}" == "NEW" ]; then

    # let user enter password c
    sudo shred /home/admin/.pass.tmp 2>/dev/null
    sudo ./config.scripts/blitz.setpassword.sh x "Set your Password C for the LND Wallet Unlock" /home/admin/.pass.tmp
    passwordC=`sudo cat /home/admin/.pass.tmp`
    sudo shred /home/admin/.pass.tmp 2>/dev/null

    # make sure passwordC is set
    if [ ${#passwordC} -eq 0 ]; then
      /home/admin/70initLND.sh
      exit 1
    fi

    # generate wallet with seed and set passwordC
    echo "Generating new Wallet ...."
    source /home/admin/python-env-lnd/bin/activate
    python /home/admin/config.scripts/lnd.initwallet.py new ${passwordC} > /home/admin/.seed.tmp
    source /home/admin/.seed.tmp
    sudo shred /home/admin/.pass.tmp 2>/dev/null

    # in case of error - retry
    if [ ${#err} -gt 0 ]; then
      whiptail --title "lnd.initwallet.py - ERROR" --msgbox "${err}" 8 50
      /home/admin/70initLND.sh
      exit 1
    else
      if [ ${#seedwords} -eq 0 ]; then
        echo "FAIL!! -> MISSING seedwords data - but also no err data ?!?"
        echo "CHECK output data above - PRESS ENTER to restart 70initLND.sh" 
        read key
        /home/admin/70initLND.sh
        exit 1
      fi
    fi

    if [ ${#seedwords6x4} -eq 0 ]; then
      seedwords6x4="${seedwords}"
    fi

    ack=0
    while [ ${ack} -eq 0 ]
    do
      whiptail --title "IMPORTANT SEED WORDS - PLEASE WRITE DOWN" --msgbox "LND Wallet got created. Store these numbered words in a safe location:\n\n${seedwords6x4}" 12 76
      whiptail --title "Please Confirm" --yes-button "Show Again" --no-button "CONTINUE" --yesno "  Are you sure that you wrote down the word list?" 8 55
      if [ $? -eq 1 ]; then
        ack=1
      fi
    done

    sudo sed -i "s/^setupStep=.*/setupStep=65/g" /home/admin/raspiblitz.info

  else

    OPTIONS=(LNDRESCUE "LND tar.gz-Backupfile (BEST)" \
             SEED_SCB "Seed & channel.backup file (OK)" \
             ONLYSEED "Only Seed Word List (FALLBACK)")
    CHOICE=$(dialog --backtitle "RaspiBlitz" --clear --title "RECOVER LND DATA & WALLET" --menu "Data you have to recover from?" 11 60 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)
    echo "choice($CHOICE)"

    if [ "${CHOICE}" == "SEED_SCB" ]; then

      # dialog to enter
      dialog --backtitle "RaspiBlitz - LND Recover" --inputbox "Please enter/paste the SEED WORD LIST:\n(just the words, seperated by commas, in correct order as numbered)" 9 78 2>/home/admin/.seed.tmp
      wordstring=$( cat /home/admin/.seed.tmp | tr -dc '[:alnum:]-.' | tr -d ' ' )
      shred /home/admin/.seed.tmp
      echo "processing ... ${wordstring}"

      # remove spaces
      #wordstring=$(echo "${wordstring}" | sed 's/[^a-zA-Z0-9 ]//g')

      # string to array
      #IFS=',' read -r -a seedArray <<< "$wordstring"
        
      # check array
      #if [ ${#seedArray[@]} -eq 24 ]; then
      #  echo "OK - 24 words"
      #  exit 1
      #else
      #  echo "wrong number of words"
      #  wordstring=""
      #  exit 1
      #fi

    fi

    if [ "${CHOICE}" == "ONLYSEED" ]; then
      echo "TODO: ONLYSEED"
      exit 1

    elif [ "${CHOICE}" == "SEED_SCB" ]; then
      echo "TODO: SEED+SCB"
      exit 1

    elif [ "${CHOICE}" == "LNDRESCUE" ]; then
      sudo /home/admin/config.scripts/lnd.rescue.sh restore
      echo ""
      echo "PRESS ENTER to continue."
      read key
      /home/admin/70initLND.sh
      exit 1

    else
      echo "CANCEL"
      /home/admin/70initLND.sh
      exit 1
    fi

    # TODO: IMPLEMENT
    # - Recover with Seed Word List 
    #   --> (ask if seed word list was password D protected)
    # - Recover with Seed Word List & channel.backup file 
    #   --> (ask if seed word list was password D protected)
    # - Restore LND backup made with Rescue-Script (tar.gz-file)
    #   --> run retsore script

    # FALLBACK TO lncli create FOR NOW
    #dialog --title "OK" --msgbox "\nI will start 'lncli create' for you ..." 7 44
    #sudo -u bitcoin /usr/local/bin/lncli --chain=${network} create
    #/home/admin/70initLND.sh
    
  fi

else
  echo "OK - LND wallet already exists."
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