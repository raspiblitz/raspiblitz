#!/bin/bash
echo "Starting the main menu - please wait ..."

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# check if HDD is connected
hddExists=$(lsblk | grep -c sda1)
if [ ${hddExists} -eq 0 ]; then
  echo "***********************************************************"
  echo "WARNING: NO HDD FOUND -> Shutdown, connect HDD and restart."
  echo "***********************************************************"
  exit
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
  echo "***********************************************************"
  exit
fi

# signal that after bootstrap recover user dialog is needed
if [ "${state}" = "recovered" ]; then
  echo "System recovered - needs final user settings"
  ./20recoverDialog.sh 
  exit 1
fi 

# if pre-sync is running - stop it - before continue
if [ "${state}" = "presync" ]; then
  # stopping the pre-sync
  echo ""
  echo "********************************************"
  echo "Stopping pre-sync ... pls wait (up to 1min)"
  echo "********************************************"
  sudo -u root bitcoin-cli -conf=/home/admin/assets/bitcoin.conf stop
  echo "bitcoind called to stop .."
  sleep 50

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
    echo "setup is done - loading config data"
    source ${configFile}
    setupStep=100
  else
    echo "setup still in progress - setupStep(${setupStep})"
  fi
fi

## default menu settings
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
    while :
    do
      sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo 1>/dev/null 2>error.tmp
      clienterror=`cat error.tmp`
      rm error.tmp
      if [ ${#clienterror} -gt 0 ]; then
        l1="Waiting for ${network}d to get ready.\n"
        l2="---> Starting Up\n"
        l3="Can take longer if device was off."
        isVerifying=$(echo "${clienterror}" | grep -c 'Verifying blocks')
        if [ ${isVerifying} -gt 0 ]; then
          l2="---> Verifying Blocks\n"
        fi
        boxwidth=40
        dialog --backtitle "RaspiBlitz ${localip} - Welcome" --infobox "$l1$l2$l3" 5 ${boxwidth}
        sleep 5
      else
        return
      fi
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
    MENU="\n         ATTENTION: OLD DATA COULD COINTAIN FUNDS\n"
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

    BACKTITLE="${localip} / ${hostname} / ${network} / ${chain}"

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
        CASHOUT "Remove Funds from on-chain Wallet")

      # dont offer lnbalance/lnchannels on testnet
      if [ "${chain}" = "main" ]; then
        OPTIONS+=(lnbalance "Detailed Wallet Balances" \
        lnchannels "Lightning Channel List")  
      fi

      # Depending Options
      openChannels=$(sudo -u bitcoin /usr/local/bin/lncli listchannels 2>/dev/null | jq '.[] | length')
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
            echo "Press ENTER to return to main menu."
            read key
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
        OFF)
            echo ""
            echo "LCD turns white when shutdown complete."
            echo "Then wait 5 seconds and disconnect power."
            echo "-----------------------------------------------"
            echo "PRESS ENTER to start shutdown (CTRL+C to abort)"
            read key
            echo "stop lnd - please wait .."
            sudo systemctl stop lnd
            echo "stop bitcoind (1) - please wait .."
            sudo -u bitcoin bitcoin-cli stop
            slepp 10
            echo "stop bitcoind (2) - please wait .."
            sudo systemctl stop ${network}d
            echo "starting shutdown"
            sudo shutdown now
            exit 0
            ;;
        MANUAL)
            echo "************************************************************************************"
            echo "PLEASE open in browser for more information:"
            echo "https://github.com/rootzoll/raspiblitz#recover-your-coins-from-a-failing-raspiblitz"
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
            echo "SUCH WOW come back with ./00mainMenu.sh"
            ;;
        R)
            ./00mainMenu.sh
            ;;
        U) # unlock
            ./AAunlockLND.sh
            ./00mainMenu.sh
            ;;
esac
