#!/bin/bash
echo "Starting the main menu ..."

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# check if HDD is connected
hddExists=$(lsblk | grep -c sda1)
if [ ${hddExists} -eq 0 ]; then

  # check if there is maybe a HDD but woth no partitions
  noPartition=$(lsblk | grep -c sda)
  if [ ${noPartition} -eq 1 ]; then
    echo "***********************************************************"
    echo "WARNING: HDD HAS NO PARTITIONS"
    echo "***********************************************************"
    echo "Press ENTER to create a Partition - or CTRL+C to abort"
    read key
    echo "Creating Partition ..."
    sudo parted -s /dev/sda unit s mkpart primary `sudo parted /dev/sda unit s print free | grep 'Free Space' | tail -n 1`
    echo "DONE."
    sleep 3
  else 
    echo "***********************************************************"
    echo "WARNING: NO HDD FOUND -> Shutdown, connect HDD and restart."
    echo "***********************************************************"
    exit
  fi
fi

# check data from _bootstrap.sh that was running on device setup
bootstrapInfoExists=$(ls $infoFile | grep -c '.info')
if [ ${bootstrapInfoExists} -eq 0 ]; then
  echo "***********************************************************"
  echo "WARNING: NO raspiblitz.info FOUND -> bootstrap not running?"
  echo "***********************************************************"
  exit
fi

# load the data from the info file (will get produced on every startup)
source ${infoFile}

if [ "${state}" = "recovering" ]; then
  echo "***********************************************************"
  echo "WARNING: bootstrap still updating - close SSH, login later"
  echo "To monitor progress --> tail -n1000 -f raspiblitz.log"
  echo "***********************************************************"
  exit
fi

# signal that after bootstrap recover user dialog is needed
if [ "${state}" = "recovered" ]; then
  echo "System recovered - needs final user settings"
  ./20recoverDialog.sh 
  exit 1
fi 

# signal that a reindex was triggered
if [ "${state}" = "reindex" ]; then
  echo "Re-Index in progress ... start monitoring:"
  /home/admin/config.scripts/network.reindex.sh
  exit 1
fi 

# singal that torrent is in re-download
if [ "${state}" = "retorrent" ]; then
  echo "Re-Index in progress ... start monitoring:"
  /home/admin/50torrentHDD.sh
  sudo sed -i "s/^state=.*/state=repair/g" /home/admin/raspiblitz.info
  /home/admin/00mainMenu.sh
  exit
fi

# if pre-sync is running - stop it - before continue
if [ "${state}" = "presync" ]; then
  # stopping the pre-sync
  echo ""
  # analyse if blockchain was detected broken by pre-sync
  blockchainBroken=$(sudo tail /mnt/hdd/bitcoin/debug.log | grep -c "Please restart with -reindex or -reindex-chainstate to recover.")
  if [ ${blockchainBroken} -eq 1 ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "Detected corrupted blockchain on pre-sync !"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "Deleting blockchain data ..."
    echo "(needs to get downloaded fresh during setup)"
    sudo rm -f -r /mnt/hdd/bitcoin
  else
    echo "********************************************"
    echo "Stopping pre-sync ... pls wait (up to 1min)"
    echo "********************************************"
    sudo -u root bitcoin-cli -conf=/home/admin/assets/bitcoin.conf stop
    echo "bitcoind called to stop .."
    sleep 50
  fi

  # unmount the temporary mount
  echo "Unmount HDD .."
  sudo umount -l /mnt/hdd
  sleep 3

  # update info file
  state=waitsetup
  sudo sed -i "s/^state=.*/state=waitsetup/g" $infoFile
  sudo sed -i "s/^message=.*/message='Pre-Sync Stopped'/g" $infoFile
fi

# if state=ready -> setup is done or started
if [ "${state}" = "ready" ]; then
  configExists=$(ls ${configFile} | grep -c '.conf')
  if [ ${configExists} -eq 1 ]; then
    echo "loading config data"
    source ${configFile}
  else
    echo "setup still in progress - setupStep(${setupStep})"
  fi
fi

## default menu settings
# to fit the main menu without scrolling: 
# HEIGHT=23
# CHOICE_HEIGHT=20 
HEIGHT=13
WIDTH=64
CHOICE_HEIGHT=6
BACKTITLE="RaspiBlitz"
TITLE=""
MENU="Choose one of the following options:"
OPTIONS=()

# check if RTL web interface is installed
runningRTL=$(sudo ls /etc/systemd/system/RTL.service 2>/dev/null | grep -c 'RTL.service')

# get the local network IP to be displayed on the lCD
localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

# function to use later
waitUntilChainNetworkIsReady()
{
    echo "checking ${network}d - please wait .."
    echo "can take longer if device was off or first time"
    while :
    do
      
      # check for error on network
      sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo 1>/dev/null 2>error.tmp
      clienterror=`cat error.tmp`
      rm error.tmp

      # check for missing blockchain data
      minSize=250000000000
      if [ "${network}" = "litecoin" ]; then
        minSize=20000000000
      fi
      blockchainsize=$(sudo du -shbc /mnt/hdd/${network} | head -n1 | awk '{print $1;}')
      if [ ${#blockchainsize} -gt 0 ]; then
        if [ ${blockchainsize} -lt ${minSize} ]; then
          echo "blockchainsize(${blockchainsize})"
          echo "Missing Blockchain Data (<${minSize}) ..."
          clienterror="missing blockchain"
          sleep 3
        fi
      fi

      if [ ${#clienterror} -gt 0 ]; then

        # analyse LOGS for possible reindex
        reindex=$(sudo cat /mnt/hdd/${network}/debug.log | grep -c 'Please restart with -reindex or -reindex-chainstate to recover')
        if [ ${reindex} -gt 0 ] || [ "${clienterror}" = "missing blockchain" ]; then
          echo "!! DETECTED NEED FOR RE-INDEX in debug.log ... starting repair options."
          sudo sed -i "s/^state=.*/state=repair/g" /home/admin/raspiblitz.info
          sleep 3

          dialog --backtitle "RaspiBlitz - Repair Script" --msgbox "Your blockchain data needs to be repaired.
This can be due to power problems or a failing HDD.
Please check the FAQ on RaspiBlitz Github
'My blockchain data is corrupted - what can I do?'
https://github.com/rootzoll/raspiblitz/blob/master/FAQ.md

The RaspiBlitz will now try to help you on with the repair.
To run a BACKUP of funds & channels first is recommended.
" 13 65

          clear
          # Basic Options
          OPTIONS=(TORRENT "Redownload Prepared Torrent (DEFAULT)" \
                   COPY "Copy from another Computer (SKILLED)" \
                   REINDEX "Resync thru ${network}d (TAKES VERY VERY LONG)" \
                   BACKUP "Run Backup LND data first (optional)"
          )

          CHOICE=$(dialog --backtitle "RaspiBlitz - Repair Script" --clear --title "Repair Blockchain Data" --menu "Choose a repair/recovery option:" 11 60 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)

          clear
          if [ "${CHOICE}" = "TORRENT" ]; then
            echo "Starting TORRENT ..."
            sudo sed -i "s/^state=.*/state=retorrent/g" /home/admin/raspiblitz.info
            /home/admin/50torrentHDD.sh
            sudo sed -i "s/^state=.*/state=repair/g" /home/admin/raspiblitz.info
            /home/admin/00mainMenu.sh
            exit

          elif [ "${CHOICE}" = "COPY" ]; then
            echo "Starting COPY ..."
            sudo sed -i "s/^state=.*/state=recopy/g" /home/admin/raspiblitz.info
            /home/admin/50copyHDD.sh
            sudo sed -i "s/^state=.*/state=repair/g" /home/admin/raspiblitz.info
            /home/admin/00mainMenu.sh
            exit

          elif [ "${CHOICE}" = "REINDEX" ]; then
            echo "Starting REINDEX ..."
            sudo /home/admin/config.scripts/network.reindex.sh
            exit

          elif [ "${CHOICE}" = "BACKUP" ]; then
            sudo /home/admin/config.scripts/lnd.rescue.sh backup
            echo "PRESS ENTER to return to menu."
            read key
            /home/admin/00mainMenu.sh
            exit

          else
            echo "CANCEL"
            exit
          fi

        else
          echo "${network} error: ${clienterror}"
        fi

        # normal info
        boxwidth=40
        l1="Waiting for ${network}d to get ready.\n"
        l2="---> ${clienterror/error*:/}\n"
        l3="Can take longer if device was off."
        uptimeSeconds="$(cat /proc/uptime | grep -o '^[0-9]\+')"
        # after 2 min show complete long string (full detail)
        if [ ${uptimeSeconds} -gt 120 ]; then
          boxwidth=80
          l2="${clienterror}\n"
          l3="CTRL+C => terminal"
        fi
        dialog --backtitle "RaspiBlitz ${localip} - Welcome" --infobox "$l1$l2$l3" 5 ${boxwidth}
      else
        locked=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net getinfo 2>&1 | grep -c unlock)
        if [ ${locked} -gt 0 ]; then
          ./AAunlockLND.sh
          echo "please wait ... update to next screen can be slow"
        fi
        lndSynced=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net getinfo 2>/dev/null | jq -r '.synced_to_chain' | grep -c true)
        if [ ${lndSynced} -eq 0 ]; then
          ./80scanLND.sh
        else
          # everything is ready - return from loop
          return
        fi
      fi
      sleep 5
    done
}

if [ ${#setupStep} -eq 0 ]; then
  echo "WARN: no setup step found in raspiblitz.info"
  setupStep=0
fi
if [ ${setupStep} -eq 0 ]; then

  # check data from boostrap
  # TODO: when olddata --> CLEAN OR MANUAL-UPDATE-INFO
  if [ "${state}" = "olddata" ]; then

    # old data setup
    BACKTITLE="RaspiBlitz - Manual Update"
    TITLE="⚡ Found old RaspiBlitz Data on HDD ⚡"
    MENU="\n         ATTENTION: OLD DATA COULD CONTAIN FUNDS\n"
    OPTIONS+=(MANUAL "read how to recover your old funds" \
              DELETE "erase old data, keep blockchain, reboot" )
    HEIGHT=11

  else

    # start setup
    BACKTITLE="RaspiBlitz - Setup"
    TITLE="⚡ Welcome to your RaspiBlitz ⚡"
    MENU="\nChoose how you want to setup your RaspiBlitz: \n "
    OPTIONS+=(BITCOIN "Setup BITCOIN and Lightning (DEFAULT)" \
              LITECOIN "Setup LITECOIN and Lightning (EXPERIMENTAL)" )
    HEIGHT=11

  fi

elif [ ${setupStep} -lt 100 ]; then

    # see function above
    if [ ${setupStep} -gt 59 ]; then
      waitUntilChainNetworkIsReady
    fi

    # continue setup
    BACKTITLE="${hostname} / ${network} / ${chain}"
    TITLE="⚡ Welcome to your RaspiBlitz ⚡"
    MENU="\nThe setup process is not finished yet: \n "
    OPTIONS+=(CONTINUE "Continue Setup of your RaspiBlitz")
    HEIGHT=10

else

    # see function above
    waitUntilChainNetworkIsReady

    # MAIN MENU AFTER SETUP

    plus=""
    if [ "${runBehindTor}" = "on" ]; then
      plus=" / TOR"
    fi
    if [ ${#dynDomain} -gt 0 ]; then
      plus="${plus} / ${dynDomain}"
    fi
    BACKTITLE="${localip} / ${hostname} / ${network} / ${chain}${plus}"

    locked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep -c unlock)
    if [ ${locked} -gt 0 ]; then

      if [ "${rtlWebinterface}" = "on" ]; then
        # WEBINTERFACE INFO LOCK SCREEN
        TITLE="SSH UNLOCK"
        MENU="IMPORTANT: Please unlock thru the RTL Webinterface.\nWebinterface --> http://${localip}:3000\nThen TRY AGAIN to get to main menu."
        OPTIONS+=(R "TRY AGAIN - check again if unlocked"  \
          U "FALLBACK -> Unlock with 'lncli unlock'")
      else
        # NORMAL LOCK SCREEN
        MENU="!!! YOUR WALLET IS LOCKED !!!"
        OPTIONS+=(U "Unlock your Lightning Wallet with 'lncli unlock'")
      fi

    else

      if [ ${runningRTL} -eq 1 ]; then
        TITLE="Webinterface: http://${localip}:3000"
      fi

      # Basic Options
      OPTIONS+=(INFO "RaspiBlitz Status Screen" \
        FUNDING "Fund your on-chain Wallet" \
        CONNECT "Connect to a Peer" \
        CHANNEL "Open a Channel with Peer" \
        SEND "Pay an Invoice/PaymentRequest" \
        RECEIVE "Create Invoice/PaymentRequest" \
        SERVICES "Activate/Deactivate Services" \
        MOBILE "Connect Mobile Wallet" \
        EXPORT "Macaroons and TLS.cert" \
        NAME "Change Name/Alias of Node" \
        PASSWORD "Change Passwords" \
        CASHOUT "Remove Funds from on-chain Wallet")

      # dont offer lnbalance/lnchannels on testnet
      if [ "${chain}" = "main" ]; then
        OPTIONS+=(lnbalance "Detailed Wallet Balances" \
        lnchannels "Lightning Channel List")  
      fi

      # Depending Options
      openChannels=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net listchannels 2>/dev/null | jq '.[] | length')
      if [ ${openChannels} -gt 0 ]; then
        OPTIONS+=(CLOSEALL "Close all open Channels")  
      fi
      if [ "${runBehindTor}" = "on" ]; then
        OPTIONS+=(NYX "Monitor TOR")  
      fi

      # final Options
      OPTIONS+=(OFF "PowerOff RaspiBlitz")   
      OPTIONS+=(X "Console / Terminal")

    fi

fi

CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

clear
case $CHOICE in
        CLOSE)
            exit 1;
            ;;
        BITCOIN)
            sed -i "s/^network=.*/network=bitcoin/g" ${infoFile}
            sed -i "s/^chain=.*/chain=main/g" ${infoFile}
            ./10setupBlitz.sh
            exit 1;
            ;;
        LITECOIN)
            sed -i "s/^network=.*/network=litecoin/g" ${infoFile}
            sed -i "s/^chain=.*/chain=main/g" ${infoFile}
            ./10setupBlitz.sh
            exit 1;
            ;;
        CONTINUE)
            ./10setupBlitz.sh
            exit 1;
            ;;
        INFO)
            ./00infoBlitz.sh
            echo "Screen is not updating ... press ENTER to continue."
            read key
            ./00mainMenu.sh
            ;;
        lnbalance)
            lnbalance ${network}
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        NYX)
            sudo nyx
            ./00mainMenu.sh
            ;;
        lnchannels)
            lnchannels ${network}
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        CONNECT)
            ./BBconnectPeer.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        FUNDING)
            ./BBfundWallet.sh
            ./00mainMenu.sh
            ;;
        CASHOUT)
            ./BBcashoutWallet.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        CHANNEL)
            ./BBopenChannel.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        SEND)
            ./BBpayInvoice.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        RECEIVE)
            ./BBcreateInvoice.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        SERVICES)
            ./00settingsMenuServices.sh
            ./00mainMenu.sh
            ;;
        CLOSEALL)
            ./BBcloseAllChannels.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        SWITCH)
            sudo ./95switchMainTest.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        MOBILE)
            ./97addMobileWallet.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        TOR)
            sudo ./96addTorService.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        RTL)
            sudo ./98installRTL.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        EXPORT)
            sudo /home/admin/config.scripts/lnd.export.sh
            echo "Press ENTER to return to main menu."
            read key
            ./00mainMenu.sh
            ;;
        NAME)
            sudo /home/admin/config.scripts/lnd.setname.sh
            noreboot=$?
            if [ "${noreboot}" = "0" ]; then
              sudo -u bitcoin ${network}-cli stop
              echo "Press ENTER to Reboot."
              read key
              sudo shutdown -r now
            else
              ./00mainMenu.sh
            fi
            ;;
        PASSWORD)
            sudo /home/admin/config.scripts/blitz.setpassword.sh
            noreboot=$?
            if [ "${noreboot}" = "0" ]; then
              sudo -u bitcoin ${network}-cli stop
              echo "Press ENTER to Reboot .."
              read key
              sudo shutdown -r now
            else
              echo "Press ENTER to return to main menu .."
              read key
              ./00mainMenu.sh
            fi
            ;;
        OFF)
            echo ""
            echo "LCD turns white when shutdown complete."
            echo "Then wait 5 seconds and disconnect power."
            echo "-----------------------------------------------"
            echo "stop lnd - please wait .."
            sudo systemctl stop lnd
            echo "stop ${network}d (1) - please wait .."
            sudo -u bitcoin ${network}-cli stop
            sleep 10
            echo "stop ${network}d (2) - please wait .."
            sudo systemctl stop ${network}d
            sleep 3
            sync
            echo "starting shutdown ..."
            sudo shutdown now
            exit 0
            ;;
        MANUAL)
            echo "************************************************************************************"
            echo "PLEASE go to RaspiBlitz FAQ:"
            echo "https://github.com/rootzoll/raspiblitz"
            echo "And check: How can I recover my coins from a failing RaspiBlitz?"
            echo "************************************************************************************"
            exit 0
            ;;
        DELETE)
            sudo ./XXcleanHDD.sh
            sudo shutdown -r now
            exit 0
            ;;   
        X)
            lncli -h
            echo "OK you now on the command line."
            echo "You can return to the main menu with the command:"
            echo "raspiblitz"
            ;;
        R)
            ./00mainMenu.sh
            ;;
        U) # unlock
            ./AAunlockLND.sh
            ./00mainMenu.sh
            ;;
esac