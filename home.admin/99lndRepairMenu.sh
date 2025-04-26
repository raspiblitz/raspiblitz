#!/bin/bash

# get raspiblitz config
echo "# get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/app-data/raspiblitz.conf

source <(/home/admin/config.scripts/network.aliases.sh getvars lnd $1)

sudo mkdir /var/cache/raspiblitz/temp 2>/dev/null

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
    echo "*************************************"
    echo "* JUST MAKING A BACKUP TO THE SD CARD"
    echo "*************************************"
    echo "please wait .."
    sleep 2
    /home/admin/config.scripts/lnd.backup.sh lnd-export
    sleep 3
  fi
}

getpasswordC() # from dialogPasswords.sh
{
  # temp file for password results
  _temp="/var/cache/raspiblitz/temp/.temp.tmp"
  sudo /home/admin/config.scripts/blitz.passwords.sh set x "PASSWORD C - Lightning Wallet Password" $_temp
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
    lndRunning=$(systemctl status ${netprefix}lnd.service | grep -c running)
    if [ ${lndRunning} -eq 0 ]; then
      date +%s
      echo "LND not ready yet ... waiting another 60 seconds."
      sleep 10
    fi
    loopcount=$(($loopcount +1))
    if [ ${loopcount} -gt 100 ]; then
      echo "lnd-start-fail" "lnd service not getting to running status" "sudo systemctl status ${netprefix}lnd.service | grep -c running --> ${lndRunning}"
      exit 8
    fi
  done
  echo "OK - LND is running"
  sleep 10

  # Check LND health/fails (to be extended)
  tlsExists=$(ls /mnt/hdd/app-data/lnd/tls.cert 2>/dev/null | grep -c "tls.cert")
  if [ ${tlsExists} -eq 0 ]; then
    echo "lnd-no-tls" "lnd not created TLS cert" "no /mnt/hdd/app-data/lnd/tls.cert"
    exit 9
  fi
}

syncAndCheckLND() # from _provision.setup.sh
{
  # make sure all directories are linked
  sudo /home/admin/config.scripts/blitz.data.sh link

  # check if now a config exists
  configLinkedCorrectly=$(ls /mnt/hdd/app-data/lnd/${netprefix}lnd.conf | grep -c "${netprefix}lnd.conf")
  if [ "${configLinkedCorrectly}" != "1" ]; then
    echo "lnd-link-broken" "link /mnt/hdd/app-data/lnd/${netprefix}lnd.conf broken" ""
    exit 7
  fi

  # Init LND service & start
  echo "*** Init LND Service & Start ***"
  /home/admin/_cache.sh set message "LND Testrun"

  # just in case
  sudo systemctl stop ${netprefix}lnd 2>/dev/null
  sudo systemctl disable ${netprefix}lnd 2>/dev/null

  # copy lnd service - note the same service is created with 'lnd.install.sh on mainnet'
  sudo cp /home/admin/assets/lnd.service /etc/systemd/system/lnd.service

  # start lnd up
  echo "Starting LND Service ..."
  sudo systemctl enable ${netprefix}lnd
  sudo systemctl start ${netprefix}lnd
  echo "Starting LND Service ... executed"  
  
  if [ $(sudo -u bitcoin ls /mnt/hdd/app-data/lnd/data/chain/bitcoin/${chain}net/wallet.db 2>/dev/null | grep -c wallet.db) -gt 0 ]; then
    echo "# OK, there is an LND wallet present"
  else
    echo "lnd-no-wallet" "there is no LND wallet present" "/mnt/hdd/app-data/lnd/data/chain/bitcoin/${chain}net/wallet.db --> missing"
    exit 13
  fi
  # sync macaroons & TLS to other users
  echo "*** Copy LND Macaroons to user admin ***"
  /home/admin/_cache.sh set message "LND Credentials"

  # check if macaroon exists now - if not fail
  attempt=0
  while [ $(sudo -u bitcoin ls -la /mnt/hdd/app-data/lnd/data/chain/${network}/${chain}net/admin.macaroon 2>/dev/null | grep -c admin.macaroon) -eq 0 ]; do
    echo "Waiting 2 mins for LND to create macaroons ... (${attempt}0s)"
    sleep 10
    attempt=$((attempt+1))
    if [ $attempt -eq 12 ];then
      /home/admin/config.scripts/blitz.error.sh _provision.setup.sh "lnd-no-macaroons" "lnd did not create macaroons" "/mnt/hdd/app-data/lnd/data/chain/${network}/${chain}net/admin.macaroon --> missing"
      exit 14
    fi
  done

  # now sync macaroons & TLS to other users
  sudo /home/admin/config.scripts/lnd.credentials.sh sync ${chain}net

 # make a final lnd check
 source <(/home/admin/config.scripts/lnd.check.sh basic-setup "${chain}net")
 if [ "${err}" != "" ]; then
   echo
   echo "lnd-check-error" "lnd.check.sh basic-setup ${chain}net with error" "/home/admin/config.scripts/lnd.check.sh basic-setup ${chain}net --> ${err}"
   echo
   # exit 15
 fi
}

function restoreFromSeed()
{
    askLNDbackupCopy

    ## from dialogLightningWallet.sh 
    # let people know about the difference between SEED & SEED+SCB
    whiptail --title "IMPORTANT INFO" --yes-button "ENTER SEED" --no-button "Go Back" --yesno "
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

    removeLNDwallet

    # creates fresh lnd.conf without an alias
    /home/admin/config.scripts/lnd.install.sh on $CHAIN
    sudo systemctl start ${netprefix}lnd
    lndHealthCheck

    # from _provison.setup.sh
    # create wallet
    # WALLET --> SEED
    if [ "${seedWords}" != "" ]; then
      echo "WALLET --> SEED"
      /home/admin/_cache.sh set message "LND Wallet (SEED)"
      source <(/home/admin/config.scripts/lnd.initwallet.py seed "${chain}net" "${passwordC}" "${seedWords}" "${seedPassword}")
      if [ "${err}" != "" ]; then
        echo "lnd-wallet-seed" "lnd.initwallet.py seed returned error" "/home/admin/config.scripts/lnd.initwallet.py seed ${chain}net ... --> ${err} + ${errMore}"
        exit 12
      fi
    fi

    syncAndCheckLND
}

function restoreSCB()
{
    # import SCB and get results
    _temp="/var/cache/raspiblitz/.temp.tmp"
    # 'production' to use passwordA
    /home/admin/config.scripts/lnd.backup.sh scb-import-gui production $_temp
    source $_temp 2>/dev/null
    sudo rm $_temp 2>/dev/null
    
    # if user canceled the upload
    if ! ls -la /home/admin/channel.backup; then
      echo "# signal cancel to the calling script by exit code (5 = exit on scb)"
      exit 5
    fi
    
    echo
    echo "The next step will attempt to trigger all online peers to force close the channels."
    echo "Restoring the channel.backup can be repeated until all the channels are force closed."
    echo
    echo "Make sure to enter the Raspiblitz menu to trigger the next step."
    echo "If menu does not open automatically - use command: raspiblitz"
    echo "Press ENTER to continue or CTRL+C to abort"
    read key

### --> DEACTIVATED BECAUSE when a file is placed at /home/admin/channel.backup
###     it will now automatically trigger a Static-Channel-Backup procedure after lnd recoverymode is done
#
#    # WALLET --> SEED + SCB 
#    if ls -la /home/admin/channel.backup; then
#
#      # LND was restarted so need to unlock
#      echo "WALLET --> UNLOCK WALLET - SCAN 0"
#      /home/admin/_cache.sh set message "LND Wallet Unlock - scan 0"
#      source <(/home/admin/config.scripts/lnd.initwallet.py unlock "${chain}net" "${passwordC}" 0)
#      if [ "${err}" != "" ]; then
#        echo "lnd-wallet-unlock" "lnd.initwallet.py unlock returned error" "/home/admin/config.scripts/lnd.initwallet.py unlock ${chain}net ... --> ${err} + ${errMore}"
#        if [ "${errMore}" = "wallet already unlocked, WalletUnlocker service is no longer available" ]; then
#          echo "The wallet is already unlocked, continue."
#        else
#          exit 11
#        fi
#      fi
#
#      echo "WALLET --> SEED + SCB "
#      /home/admin/_cache.sh set message "LND Wallet (SEED & SCB)"
#      macaroonPath="/home/admin/.lnd/data/chain/${network}/${chain}net/admin.macaroon"
#      source <(/home/admin/config.scripts/lnd.initwallet.py scb ${chain}net "/home/admin/channel.backup" "${macaroonPath}")
#      if [ "${err}" != "" ]; then
#        echo "lnd-wallet-seed+scb" "lnd.initwallet.py scb returned error" "/home/admin/config.scripts/lnd.initwallet.py scb ${chain}net ... --> ${err} + ${errMore}"
#        while [ $(echo "${errMore}" | grep -c "RPC server is in the process of starting up") -gt 0 ]; do
#          echo "# ${errMore}"
#          echo "# waiting 10 seconds (${counter})"
#          counter=$((counter+1))
#          if [ ${counter} -eq 60 ]; then
#            echo "# Giving up after 10 minutes"
#            echo
#            echo "lnd-wallet-seed+scb" "lnd.initwallet.py scb returned error" "/home/admin/config.scripts/lnd.initwallet.py scb ${chain}net ... --> ${err} + ${errMore}"
#            echo
#            echo "The SCB recovery is not possible now - use the RETRYSCB option the REPAIR-LND menu after LND is synced."
#            echo "Can repeat the SCB recovery until all peers have force closed the channels to this node."
#            echo
#            echo "# ${netprefix}lnd error logs:"
#            sudo journalctl -u ${netprefix}lnd
#            echo
#            echo "# ${netprefix}lnd logs:"
#            sudo tail /mnt/hdd/app-data/lnd/logs/bitcoin/${CHAIN}/lnd.log
#            exit 12
#          fi
#          sleep 10
#          source <(/home/admin/config.scripts/lnd.initwallet.py scb ${chain}net "/home/admin/channel.backup" "${macaroonPath}")
#        done
#
#      fi
#    fi
#
#    syncAndCheckLND

}

function removeLNDwallet 
{
  clear
  echo  
  echo "The next step WILL REMOVE the old LND wallet on ${CHAIN}"
  echo "Press ENTER to continue or CTRL+C to abort"
  read key
  echo "# Stopping lnd on ${CHAIN} ..."
  sudo systemctl stop ${netprefix}lnd
  sudo systemctl disable ${netprefix}lnd
  echo "Reset wallet on ${CHAIN}"
  sudo rm -f /mnt/hdd/app-data/lnd/${netprefix}lnd.conf
  sudo rm -f /mnt/hdd/app-data/lnd/${netprefix}v3_onion_private_key
  sudo rm -f /mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}/wallet.db
  sudo rm -f /mnt/hdd/app-data/lnd/data/graph/${CHAIN}/channel.db
  sudo rm -f /mnt/hdd/app-data/lnd/data/graph/${CHAIN}/sphinxreplay.db
  
  sudo rm -rf /mnt/hdd/app-data/lnd/data/chain/${network}/${CHAIN}
  sudo rm -rf /mnt/hdd/app-data/lnd/logs/${network}/${CHAIN}
  sudo rm -rf /mnt/hdd/app-data/lnd/data/graph/${CHAIN}
  sudo rm -rf home/bitcoin/.lnd/data/watchtower/${CHAIN}
}

# BASIC MENU INFO
WIDTH=64
BACKTITLE="RaspiBlitz"
TITLE="LND repair options for $CHAIN"
MENU=""
OPTIONS=()
if [ "${chain}" = "main" ]; then
  OPTIONS+=(COMPACT "Compact the LND channel.db")
  OPTIONS+=(GETSCB "Download channel.backup (StaticChannelBackup)")
fi
OPTIONS+=(BACKUP-LND "Backup your LND data (Rescue-File)")
OPTIONS+=(RESET-LND "Delete LND & start new node/wallet")
OPTIONS+=(LNDRESCUE "Restore from a rescue file")
OPTIONS+=(SEED+SCB "Restore from a seed and channel.backup")
OPTIONS+=(RETRYSCB "Retry closing channels with the channel.backup")
OPTIONS+=(ONLYSEED "Restore from a seed (onchain funds only)")
OPTIONS+=(RESCAN "Rescan the blockchain to recover onchain funds")

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
    echo "# Starting ${netprefix}lnd.service ..."
    sudo systemctl start lnd
    echo
    echo "Press ENTER to return to main menu."
    read key
    ;;
  GETSCB)
    /home/admin/config.scripts/lnd.backup.sh scb-export-gui
    ;;
  BACKUP-LND)
    /home/admin/config.scripts/lnd.compact.sh interactive
    sudo /home/admin/config.scripts/lnd.backup.sh ${netprefix}lnd-export-gui
    echo
    echo "Press ENTER when your backup download is done to shutdown."
    read key
    sudo /home/admin/config.scripts/blitz.shutdown.sh
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

    removeLNDwallet

    # create wallet
    /home/admin/config.scripts/lnd.install.sh on ${chain}net initwallet
    # display and delete the seed for ${chain}net
    sudo /home/admin/config.scripts/lnd.install.sh display-seed ${chain}net delete

    #TODO the new hostname is not taken into account on init (user can change set the lnd name in menu later)
    # make sure host is named like in the raspiblitz config
    # echo "Setting the Name/Alias/Hostname .."
    sudo /home/admin/config.scripts/lnd.setname.sh ${chain}net "${result}"
    # /home/admin/config.scripts/blitz.conf.sh set hostname "${result}"

    syncAndCheckLND

    echo "Press ENTER to return to main menu."
    read key    
    # go back to main menu (and show)
    /home/admin/00raspiblitz.sh
    exit 0
    ;;
  
  LNDRESCUE)
    askLNDbackupCopy

    #removeAllLNDwallets 
    clear
    echo
    echo "The next step WILL REMOVE the old LND wallets on ALL CHAINS"
    echo "Press ENTER to continue or CTRL+C to abort"
    read key
    echo "# Stopping lnd on mainnet ..."
    sudo systemctl stop lnd
    # don' t want to set CL as default if running parallel
    #/home/admin/config.scripts/lnd.install.sh off mainnet
    if [ "${tlnd}" == "on" ];then
      /home/admin/config.scripts/lnd.install.sh off testnet
    fi
    if [ "${slnd}" == "on" ];then
      /home/admin/config.scripts/lnd.install.sh off signet
    fi
    echo "Reset wallet"
    sudo rm -r /mnt/hdd/app-data/lnd

    ## from dialogLightningWallet.sh 
    # import file
    # run upload dialog and get result
    _temp="/var/cache/raspiblitz/temp/.temp.tmp"
    /home/admin/config.scripts/lnd.backup.sh lnd-import-gui production $_temp
    source $_temp 2>/dev/null
    sudo rm $_temp 2>/dev/null

    /home/admin/config.scripts/lnd.install.sh on ${CHAIN}
    sudo systemctl start ${netprefix}lnd
    
    syncAndCheckLND
    
    echo "Press ENTER to return to main menu."
    read key
    # go back to main menu (and show)
    /home/admin/00raspiblitz.sh
    exit 0
    ;;

  ONLYSEED)

    restoreFromSeed
    
    echo "Set lnd recovery mode & restart ..."
    sudo /home/admin/config.scripts/lnd.backup.sh "${chain}net" recoverymode on
    sudo systemctl restart ${netprefix}lnd
    sleep 3

    echo "# Unlock wallet ..."
    /home/admin/config.scripts/lnd.unlock.sh "${CHAIN}"

    echo
    echo "System will now go thru rescan for on-chain funds"
    echo "Press ENTER to return to main menu."
    read key
    # go back to main menu (and show)
    /home/admin/00raspiblitz.sh
    exit 0
    ;;

  SEED+SCB)

    restoreFromSeed
    restoreSCB
    
    echo "Set lnd recovery mode & restart ..."
    sudo /home/admin/config.scripts/lnd.backup.sh "${chain}net" recoverymode on
    sudo systemctl restart ${netprefix}lnd
    sleep 3

    echo "# Unlock wallet ..."
    /home/admin/config.scripts/lnd.unlock.sh "${CHAIN}"

    echo
    echo "System will now go thru rescan for on-chain funds and when done"
    echo "the Static-Channel-Backup will trigger to recover off-chain funds."
    echo "Press ENTER to return to main menu."
    read key

    # go back to main menu (and show)
    /home/admin/00raspiblitz.sh
    exit 0
    ;;

  RETRYSCB)

    restoreSCB

    # go back to main menu (and show)
    /home/admin/00raspiblitz.sh

    exit 0
    ;;

  RESCAN)
    clear

    source <(sudo /home/admin/config.scripts/lnd.backup.sh "${CHAIN}" recoverymode status)
    if [ "${recoverymode}" == "0" ]; then

      echo "Putting lnd back in recoverymode."
      sudo /home/admin/config.scripts/lnd.backup.sh "${CHAIN}" recoverymode on
      echo "Restarting lnd ..."
      sudo systemctl restart ${netprefix}lnd
      sleep 3

    else

      echo "lnd already in recoverymode."

    fi

    echo "# Unlock wallet ..."
    /home/admin/config.scripts/lnd.unlock.sh "${CHAIN}"

    echo
    echo "To show the scanning progress in the background will follow the lnd.log with:" 
    echo "'sudo tail -n 30 -f /mnt/hdd/app-data/lnd/logs/${network}/${chain}net/lnd.log'"
    echo
    echo "Press ENTER to continue"
    echo "use CTRL+C any time to exit .. then use the command 'raspiblitz' to return to the menu"
    echo "(the rescan will continue in the background)"
    echo "#######################################################################################"
    read key
    sudo tail -n 30 -f /mnt/hdd/app-data/lnd/logs/${network}/${chain}net/lnd.log    
    ;;

esac

exit 0