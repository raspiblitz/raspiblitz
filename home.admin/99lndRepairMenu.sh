#!/bin/bash

# get raspiblitz config
echo "# get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

source <(/home/admin/config.scripts/network.aliases.sh getvars lnd $1)

askLNDbackupCopy()
{
  whiptail --title "LND Data Backup" --yes-button "Backup" --no-button "Skip" --yesno "
Before deleting your data, do you want
to make a backup of all your LND Data
and download the file(s) to your laptop?

Download LND Data Backup now?
  " 12 44
  if [ $? -eq 0 ]; then
    clear
    echo "***********************************"
    echo "* PREPARING THE LND BACKUP DOWNLOAD"
    echo "***********************************"
    echo "please wait .."
    /home/admin/config.scripts/lnd.compact.sh interactive
    /home/admin/config.scripts/lnd.backup.sh lnd-export-gui
    echo
    echo "PRESS ENTER to continue once you're done downloading."
    read key
  else
    clear
    echo "*****************************************"
    echo "* JUST MAKING A BACKUP TO THE SD CARD"
    echo "*****************************************"
    echo "please wait .."
    sleep 2
    /home/admin/config.scripts/lnd.backup.sh lnd-export
    sleep 3
  fi
}

getpasswordC() # from dialogPasswords.sh
{
  sudo /home/admin/config.scripts/blitz.setpassword.sh x "PASSWORD C - Lightning Wallet Password" $_temp
  passwordC=$(sudo cat $_temp)
  sudo rm $_temp
  dialog --backtitle "RaspiBlitz - Setup" --msgbox "\nThanks - Password C accepted.\n\nAlways use this password to \nunlock your Lightning Wallet." 10 34
}

lndHealthCheck() 
{
  # check that lnd started
  lndRunning=0
  loopcount=0
  while [ ${lndRunning} -eq 0 ]
  do
    lndRunning=$(systemctl status lnd.service | grep -c running)
    if [ ${lndRunning} -eq 0 ]; then
      date +%s
      echo "LND not ready yet ... waiting another 60 seconds."
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
}

syncAndCheckLND() 
{
  # sync macaroons & TLS to other users
  echo "*** Copy LND Macaroons to user admin ***"
  /home/admin/_cache.sh set message "LND Credentials"

  # check if macaroon exists now - if not fail
  macaroonExists=$(sudo -u bitcoin ls -la /home/bitcoin/.lnd/data/chain/${network}/${chain}net/admin.macaroon 2>/dev/null | grep -c admin.macaroon)
  if [ ${macaroonExists} -eq 0 ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-no-macaroons" "lnd did not create macaroons" "/home/bitcoin/.lnd/data/chain/${network}/${chain}net/admin.macaroon --> missing" ${logFile}
      exit 14
  fi

  # now sync macaroons & TLS to other users
  /home/admin/config.scripts/lnd.credentials.sh sync

  # make a final lnd check
  source <(/home/admin/config.scripts/lnd.check.sh basic-setup)
  if [ "${err}" != "" ]; then
    /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-check-error" "lnd.check.sh basic-setup with error" "/home/admin/config.scripts/lnd.check.sh basic-setup --> ${err}" ${logFile}
    exit 15
  fi
}

# BASIC MENU INFO
WIDTH=64
BACKTITLE="RaspiBlitz"
TITLE="LND repair options for $CHAIN"
MENU=""
OPTIONS=()

OPTIONS+=(COMPACT "Compact the LND channel.db")
OPTIONS+=(BACKUP-LND "Backup your LND data (Rescue-File)")
OPTIONS+=(RESET-LND "Delete LND & start new node/wallet")
OPTIONS+=(LNDRESCUE "Restore from a rescue file")
OPTIONS+=(SEED+SCB "Restore from a seed and channel.backup")
OPTIONS+=(ONLYSEED "Restore from a seed (onchain funds only)")

CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
HEIGHT=$((CHOICE_HEIGHT+6))
CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --ok-label "Select" \
                --cancel-label "Main menu" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

case $CHOICE in

  COMPACT)
    /home/admin/config.scripts/lnd.compact.sh interactive
    echo "# Starting lnd.service ..."
    sudo systemctl start lnd
    echo
    echo "Press ENTER to return to main menu."
    read key
    ;;
  BACKUP-LND)
    /home/admin/config.scripts/lnd.compact.sh interactive
    sudo /home/admin/config.scripts/lnd.backup.sh lnd-export-gui
    echo
    echo "Press ENTER when your backup download is done to shutdown."
    read key
    /home/admin/config.scripts/blitz.shutdown.sh
    ;;
  RESET-LND)
    askLNDbackupCopy
    # ask for a new name so that network analysis has harder time to connect new node id with old
    result=""
    while [ ${#result} -eq 0 ]
    do
        trap 'rm -f "$_temp"' EXIT
        _temp=$(mktemp -p /dev/shm/)
        l1="Please enter the name of your new LND node:\n"
        l2="different name is better for a fresh identity\n"
        l3="one word, use up to 32 basic characters"
        dialog --backtitle "RaspiBlitz - Setup (${network}/${chain})" --inputbox "$l1$l2$l3" 13 52 2>$_temp
        result=$( cat $_temp | tr -dc '[:alnum:]-.' | tr -d ' ' )
        echo "processing ..."
        sleep 3
    done

    # make sure host is named like in the raspiblitz config
    echo "Setting the Name/Alias/Hostname .."
    sudo /home/admin/config.scripts/lnd.setname.sh mainnet "${result}"
    /home/admin/config.scripts/blitz.conf.sh set hostname "${result}"

    echo "stopping lnd ..."
    sudo systemctl stop lnd
    if [ "${tlnd}" == "on" ];then
      sudo systemctl stop tlnd
    fi
    if [ "${slnd}" == "on" ];then
      sudo systemctl stop slnd
    fi
    echo "Delete wallet"
    sudo rm -r /mnt/hdd/lnd
    # create wallet
    /home/admin/config.scripts/lnd.install.sh on mainnet initwallet
    # display and delete the seed for mainnet
    sudo /home/admin/config.scripts/lnd.install.sh display-seed mainnet delete
    if [ "${tlnd}" == "on" ];then
      /home/admin/config.scripts/lnd.install.sh on testnet initwallet
    fi
    if [ "${slnd}" == "on" ];then
      /home/admin/config.scripts/lnd.install.sh on signet initwallet
    fi

    syncAndCheckLND

    echo "Press ENTER to return to main menu."
    read key    
    # go back to main menu (and show)
    /home/admin/00raspiblitz.sh
    exit 0
    ;;
  
  LNDRESCUE)
    askLNDbackupCopy
    echo "The next step will overwrite the old LND wallets on all chains"
    echo "Press ENTER to continue or CTRL+C to abort"
    read key
    echo "Stopping lnd ..."
    sudo systemctl stop lnd
    if [ "${tlnd}" == "on" ];then
      sudo systemctl stop tlnd
    fi
    if [ "${slnd}" == "on" ];then
      sudo systemctl stop slnd
    fi
    echo "Delete wallet"
    sudo rm -r /mnt/hdd/lnd

    ## from dialogLightningWallet.sh 
    # import file
    # run upload dialog and get result
    _temp="/var/cache/raspiblitz/temp/.temp.tmp"
    /home/admin/config.scripts/lnd.backup.sh lnd-import-gui production $_temp
    source $_temp 2>/dev/null
    sudo rm $_temp 2>/dev/null

    syncAndCheckLND
    
    echo "Press ENTER to return to main menu."
    read key
    # go back to main menu (and show)
    /home/admin/00raspiblitz.sh
    exit 0
    ;;

  SEED+SCB)
    askLNDbackupCopy

    ## from dialogLightningWallet.sh     
    # start seed input and get results
    _temp="/var/cache/raspiblitz/.temp.tmp"
    /home/admin/config.scripts/lnd.backup.sh seed-import-gui $_temp
    source $_temp 2>/dev/null
    sudo rm $_temp 2>/dev/null

    # if user cancelled the seed input
    if [ "${seedWords}" == "" ]; then
        # signal cancel to the calling script by exit code (4 = exit on seedwords)
        exit 4
    fi

    # import SCB and get results
    _temp="/var/cache/raspiblitz/.temp.tmp"
    /home/admin/config.scripts/lnd.backup.sh scb-import-gui setup $_temp
    source $_temp 2>/dev/null
    sudo rm $_temp 2>/dev/null
    
    # if user canceled the upload
    if [ "${staticchannelbackup}" == "" ]; then
        # signal cancel to the calling script by exit code (5 = exit on scb)
        exit 5
    fi
    
    getpasswordC

    # from _provison.setup.sh
    # create wallet
    # import static channel backup if was uploaded
    source <(/home/admin/config.scripts/lnd.backup.sh scb-import ${staticchannelbackup})
    if [ "${error}" != "" ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-scb-import" "lnd.backup.sh scb-import returned error" "/home/admin/config.scripts/lnd.backup.sh scb-import ${staticchannelbackup} --> ${error}" ${logFile}
      exit 10
    fi

    echo "The next step will overwrite the old LND wallets on all chains"
    echo "Press ENTER to continue or CTRL+C to abort"
    read key
    echo "Stopping lnd ..."
    sudo systemctl stop lnd
    if [ "${tlnd}" == "on" ];then
      sudo systemctl stop tlnd
    fi
    if [ "${slnd}" == "on" ];then
      sudo systemctl stop slnd
    fi
    echo "Delete wallet"
    sudo rm -r /mnt/hdd/lnd

    /home/admin/config.scripts/lnd.install.sh on $CHAIN
    sudo systemctl start ${netprefix}lnd
    lndHealthCheck

    # WALLET --> SEED + SCB 
    if [ "${seedWords}" != "" ] && [ "${staticchannelbackup}" != "" ]; then
      echo "WALLET --> SEED + SCB "
      /home/admin/_cache.sh set message "LND Wallet (SEED & SCB)"
      if ! pip list | grep grpc; then sudo -H python3 -m pip install grpcio==1.38.1; fi
      source <(/home/admin/config.scripts/lnd.initwallet.py scb mainnet ${passwordC} "${seedWords}" "${staticchannelbackup}" ${seedPassword})
      if [ "${err}" != "" ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-wallet-seed+scb" "lnd.initwallet.py scb returned error" "/home/admin/config.scripts/lnd.initwallet.py scb mainnet ... --> ${err} + ${errMore}" ${logFile}
      exit 11
      fi
    fi

    syncAndCheckLND
    
    echo "Press ENTER to return to main menu."
    read key
    # go back to main menu (and show)
    /home/admin/00raspiblitz.sh
    exit 0
    ;;

  ONLYSEED)
    askLNDbackupCopy

    ## from dialogLightningWallet.sh 
    # let people know about the difference between SEED & SEED+SCB
    whiptail --title "IMPORTANT INFO" --yes-button "JUST SEED" --no-button "Go Back" --yesno "
Using JUST SEED WORDS will only recover your on-chain funds.
To also try to recover the open channel funds you need the
channel.backup file (since RaspiBlitz v1.2 / LND 0.6-beta)
or having a complete LND rescue-backup from your old node.
    " 11 65
    
    # start seed input and get results
    _temp="/var/cache/raspiblitz/.temp.tmp"
    /home/admin/config.scripts/lnd.backup.sh seed-import-gui $_temp
    source $_temp 2>/dev/null
    sudo rm $_temp 2>/dev/null

    # if user canceled the seed input
    if [ "${seedWords}" == "" ]; then
      # signal cancel to the calling script by exit code (4 = exit on seedwords)
      exit 4
    fi

    getpasswordC

    echo "The next step will overwrite the old LND wallets on all chains"
    echo "Press ENTER to continue or CTRL+C to abort"
    read key
    echo "Stopping lnd ..."
    sudo systemctl stop lnd
    if [ "${tlnd}" == "on" ];then
      sudo systemctl stop tlnd
    fi
    if [ "${slnd}" == "on" ];then
      sudo systemctl stop slnd
    fi
    echo "Reset wallet"
    sudo rm -r /mnt/hdd/lnd

    /home/admin/config.scripts/lnd.install.sh on $CHAIN
    sudo systemctl start ${netprefix}lnd
    lndHealthCheck

    # from _provison.setup.sh
    # create wallet
    # WALLET --> SEED
    if [ "${seedWords}" != "" ]; then
      echo "WALLET --> SEED"
      /home/admin/_cache.sh set message "LND Wallet (SEED)"
      if ! pip list | grep grpc; then sudo -H python3 -m pip install grpcio==1.38.1; fi  
      source <(/home/admin/config.scripts/lnd.initwallet.py seed mainnet ${passwordC} "${seedWords}" ${seedPassword})
      if [ "${err}" != "" ]; then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-wallet-seed" "lnd.initwallet.py seed returned error" "/home/admin/config.scripts/lnd.initwallet.py seed mainnet ... --> ${err} + ${errMore}" ${logFile}
      exit 12
      fi
    fi

    syncAndCheckLND
    
    echo "Press ENTER to return to main menu."
    read key
    # go back to main menu (and show)
    /home/admin/00raspiblitz.sh
    exit 0
    ;;

esac

exit 0