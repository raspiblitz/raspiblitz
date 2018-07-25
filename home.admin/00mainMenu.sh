#!/bin/bash

## default menu settings
HEIGHT=9
WIDTH=64
CHOICE_HEIGHT=4
BACKTITLE="RaspiBlitz"
TITLE=""
MENU="Choose one of the following options:"
OPTIONS=()

## get actual setup state
setupState=0;
if [ -f "/home/admin/.setup" ]; then
  setupState=$( cat /home/admin/.setup )
fi

if [ ${setupState} -eq 0 ]; then

    # start setup
    BACKTITLE="RaspiBlitz - SetUp"
    TITLE="⚡ Welcome to your RaspiBlitz ⚡"
    MENU="\nYou need to setup and init Bitcoin and Lightning services: \n "
    OPTIONS+=(1 "Start the SetUp of your RaspiBlitz")
    HEIGHT=10

elif [ ${setupState} -lt 100 ]; then

    # continue setup
    BACKTITLE="RaspiBlitz - SetUp"
    TITLE="⚡ Welcome to your RaspiBlitz ⚡"
    MENU="\nContinue setup and init of Bitcoin and Lightning services: \n "
    OPTIONS+=(1 "Continue SetUp of your RaspiBlitz")
    HEIGHT=10

else

    # make sure to have a init pause aufter fresh boot
    uptimesecs=$(awk '{print $1}' /proc/uptime | awk '{print int($1)}')
    waittimesecs=$(expr 150 - $uptimesecs)
    if [ ${waittimesecs} -gt 0 ]; then
      dialog --pause "  Waiting for Bitcoin to startup and init ..." 8 58 ${waittimesecs}
    fi

    # MAIN MENU AFTER SETUP

    chain=$(bitcoin-cli -datadir=/home/bitcoin/.bitcoin getblockchaininfo | jq -r '.chain')
    locked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/bitcoin/${chain}net/lnd.log | grep -c unlock)
    if [ ${locked} -gt 0 ]; then

      # LOCK SCREEN
      MENU="!!! YOUR WALLET IS LOCKED !!!"
      OPTIONS+=(X "Unlock your Lightning Wallet with 'lncli unlock'")

    else

     # REGULAR MENU
      OPTIONS+=(INFO "Show RaspiBlitz Status Screen" \
		ADD "Add lnbalance and lnchannels command")

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
        1)  # SETUP
            ./10setupBlitz.sh
            exit 1;
            ;;
        INFO)
            ./00infoBlitz.sh
            echo "Screen is not updating ... press ENTER to continue."
	    read key
            ./00mainMenu.sh;
            ;;
	ADD) # add scripts
	    ./67addAdditionalScripts.sh	
	    ;;
        X) # unlock
            ./AAunlockLND.sh
	    ./00mainMenu.sh
            ;;
esac
