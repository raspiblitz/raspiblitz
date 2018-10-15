#!/bin/bash

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

    # make sure to have a init pause aufter fresh boot
    uptimesecs=$(awk '{print $1}' /proc/uptime | awk '{print int($1)}')
    waittimesecs=$(expr 150 - $uptimesecs)
    if [ ${waittimesecs} -gt 0 ]; then
      dialog --pause "  Waiting for ${network} to startup and init ..." 8 58 ${waittimesecs}
    fi

    # continue setup
    BACKTITLE="${name} / ${network} / ${chain}"
    TITLE="⚡ Welcome to your RaspiBlitz ⚡"
    MENU="\nThe setup process is not finished yet: \n "
    OPTIONS+=(CONTINUE "Continue Setup of your RaspiBlitz")
    HEIGHT=10

else

    # make sure to have a init pause aufter fresh boot
    uptimesecs=$(awk '{print $1}' /proc/uptime | awk '{print int($1)}')
    waittimesecs=$(expr 150 - $uptimesecs)
    if [ ${waittimesecs} -gt 0 ]; then
      dialog --pause "  Waiting for ${network} to startup and init ..." 8 58 ${waittimesecs}
    fi

    # MAIN MENU AFTER SETUP

    BACKTITLE="${name} / ${network} / ${chain}"

    locked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep -c unlock)
    if [ ${locked} -gt 0 ]; then

      # LOCK SCREEN
      MENU="!!! YOUR WALLET IS LOCKED !!!"
      OPTIONS+=(U "Unlock your Lightning Wallet with 'lncli unlock'")

    else

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

      # final Options
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
        X)
            lncli -h
            echo "SUCH WOW come back with ./00mainMenu.sh"
            ;;           
        U) # unlock
            ./AAunlockLND.sh
            ./00mainMenu.sh
            ;;
esac