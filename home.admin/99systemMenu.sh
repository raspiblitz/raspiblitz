#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# BASIC MENU INFO
HEIGHT=12 # add 6 to CHOICE_HEIGHT + MENU lines
WIDTH=64
CHOICE_HEIGHT=6 # 1 line / OPTIONS
BACKTITLE="RaspiBlitz"
TITLE="System Options"
MENU=""    # adds lines to HEIGHT
OPTIONS=() # adds lines to HEIGHt + CHOICE_HEIGHT

OPTIONS+=(BITCOINLOG "Monitor the debug.log")
OPTIONS+=(BITCOINCONF "Edit the bitcoin.conf")
OPTIONS+=(LNDLOG "Monitor the LND log")
OPTIONS+=(LNDCONF "Edit the LND.conf")

if [ "${runBehindTor}" == "on" ]; then
  OPTIONS+=(NYX "Monitor the Tor Service")
  OPTIONS+=(TORRC "Connect Mobile Wallet")
    HEIGHT=$((HEIGHT+2))
    CHOICE_HEIGHT=$((CHOICE_HEIGHT+2))
fi
OPTIONS+=(CUSTOM "Monitor a custom service")
OPTIONS+=(RESTART "Restart a custom service")
CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --ok-label "Select" \
                --cancel-label "Back" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

case $CHOICE in

        MOBILE)
            /home/admin/97addMobileWallet.sh
            ;;
        LNDCREDS)
            sudo /home/admin/config.scripts/lnd.credentials.sh
            ;;
        BTCPAY)
            /home/admin/config.scripts/lnd.export.sh btcpay
            ;;
        ELECTRS)
            /home/admin/config.scripts/bonus.electrs.sh menu
            ;;
        TORLOG)
            sudo -u debian-tor nyx
esac

# go into loop - start script from beginning to load config/sate fresh
/home/admin/00mainMenu.sh