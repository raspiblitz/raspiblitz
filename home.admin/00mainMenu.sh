#!/bin/bash

# check data from _bootstrap.sh that was running on device setup
infoFile='/home/admin/raspiblitz.info'
bootstrapInfoExists=$(ls $infoFile | grep -c '.info')
if [ ${bootstrapInfoExists} -eq 1 ]; then

  # load the data from the info file
  source /home/admin/raspiblitz.info
  echo "Found raspiblitz.info from bootstrap - processing ..."
  sleep 2

  # if pre-sync is running - stop it
  if [ "${state}" = "presync" ]; then
    echo "TODO: Stop pre-sync ... press key to continue"
    read key
    # update info file
    state=waitsetup
    echo "state=waitsetup" > $infoFile
    echo "message='Pre-Sync Stopped'" >> $infoFile
    echo "device=${device}" >> $infoFile
  fi

  # wait until boostrap process is done
  keepWaiting=1
  while [ ${keepWaiting} -eq 1 ] 
   do

    # 1) when bootstrap on configured device
    if [ "${state}" = "ready" ]; then
      echo "detected bootstrap ready"
      keepWaiting=0

    # 2) when bootstrap on a fresh sd card
    elif [ "${state}" = "waitsetup" ]; then
      echo "detected bootstrap waitinmg for setup"
      
      # unmount the temporary mount
      sudo umount -l /mnt/hdd

      # update info file - that setup started
      echo "state=setup" > $infoFile
      echo "message='SetUp Started'" >> $infoFile
      echo "device=${device}" >> $infoFile
      keepWaiting=0

    # 3) when bootstap is still running 
    else
      # wait 2 sevs and check again
      echo "bootstrap still running - state(${state}) message(${message})"
      echo "please wait, act or CTRL+c --> Exit to terminal"
      sleep 2
      keepWaiting=1
    fi

   done

fi

## default menu settings
HEIGHT=13
WIDTH=64
CHOICE_HEIGHT=6
BACKTITLE="RaspiBlitz"
TITLE=""
MENU="Choose one of the following options:"
OPTIONS=()

## get basic info (its OK if not set yet)

# get name
name=`sudo cat /home/admin/.hostname`

# get network
network=`sudo cat /home/admin/.network`

# get chain
chain="test"
isMainChain=$(sudo cat /mnt/hdd/${network}/${network}.conf 2>/dev/null | grep "#testnet=1" -c)
if [ ${isMainChain} -gt 0 ];then
  chain="main"
fi

# check if RTL web interface is installed
runningRTL=$(sudo ls /etc/systemd/system/RTL.service 2>/dev/null | grep -c 'RTL.service')

# get the local network IP to be displayed on the lCD
localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

# function to use later
waitUntilChainNetworkIsReady()
{
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

## get actual setup state
setupState=0;
if [ -f "/home/admin/.setup" ]; then
  setupState=$( cat /home/admin/.setup )
fi
if [ ${setupState} -eq 0 ]; then

    # start setup
    BACKTITLE="RaspiBlitz - Setup"
    TITLE="⚡ Welcome to your RaspiBlitz ⚡"
    MENU="\nChoose how you want to setup your RaspiBlitz: \n "
    OPTIONS+=(BITCOIN "Setup BITCOIN and Lightning (DEFAULT)" \
              LITECOIN "Setup LITECOIN and Lightning (EXPERIMENTAL)" )
    HEIGHT=11

elif [ ${setupState} -lt 100 ]; then

    # see function above
    if [ ${setupState} -gt 59 ]; then
      waitUntilChainNetworkIsReady
    fi  

    # continue setup
    BACKTITLE="${name} / ${network} / ${chain}"
    TITLE="⚡ Welcome to your RaspiBlitz ⚡"
    MENU="\nThe setup process is not finished yet: \n "
    OPTIONS+=(CONTINUE "Continue Setup of your RaspiBlitz")
    HEIGHT=10

else

    # see function above
    waitUntilChainNetworkIsReady

    # MAIN MENU AFTER SETUP

    BACKTITLE="${name} / ${network} / ${chain}"

    locked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep -c unlock)
    if [ ${locked} -gt 0 ]; then

      # LOCK SCREEN
      MENU="!!! YOUR WALLET IS LOCKED !!!"
      OPTIONS+=(U "Unlock your Lightning Wallet with 'lncli unlock'")

    else

      if [ ${runningRTL} -eq 1 ]; then
        TITLE="Webinterface: http://${localip}:3000"
      fi

      switchOption="to MAINNET"
      if [ "${chain}" = "main" ]; then
        switchOption="back to TESTNET"
      fi

      # Basic Options
      OPTIONS+=(INFO "RaspiBlitz Status Screen" \
        FUNDING "Fund your on-chain Wallet" \
        CASHOUT "Remove Funds from on-chain Wallet" \
        CONNECT "Connect to a Peer" \
        CHANNEL "Open a Channel with Peer" \
        SEND "Pay an Invoice/PaymentRequest" \
        RECEIVE "Create Invoice/PaymentRequest" \
        SERVICES "Activate/Deactivate Services" \
        lnbalance "Detailed Wallet Balances" \
        lnchannels "Lightning Channel List" \
        MOBILE "Connect Mobile Wallet")

      # Depending Options
      openChannels=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} listchannels 2>/dev/null | grep chan_id -c)
      if [ ${openChannels} -gt 0 ]; then
        OPTIONS+=(CLOSEALL "Close all open Channels")  
      fi
      if [ "${network}" = "bitcoin" ]; then
        OPTIONS+=(SWITCH "Switch ${switchOption}")  
      fi
      torInstalled=$(sudo ls /mnt/hdd/tor/lnd9735/hostname 2>/dev/null | grep 'hostname' -c)
      if [ ${torInstalled} -eq 0 ]; then
        OPTIONS+=(TOR "Make reachable thru TOR")   
      else
        OPTIONS+=(NYX "Monitor TOR")  
      fi

      if [ ${runningRTL} -eq 0 ]; then
        OPTIONS+=(RTL "Install RTL Web Interface")  
      else
        OPTIONS+=(RTL "REMOVE RTL Web Interface")  
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
            echo "bitcoin" > /home/admin/.network
            ./10setupBlitz.sh
            exit 1;
            ;;
        LITECOIN)
            echo "litecoin" > /home/admin/.network
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
            echo "After Shutdown remove power from RaspiBlitz."
            echo "Press ENTER to start shutdown - then wait some seconds."
            read key
            sudo shutdown now
            exit 0
            ;;   
        X)
            lncli -h
            echo "SUCH WOW come back with ./00mainMenu.sh"
            ;;           
        U) # unlock
            ./AAunlockLND.sh
            ./00mainMenu.sh
            ;;
esac
