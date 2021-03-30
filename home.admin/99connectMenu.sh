#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# get the local network IP to be displayed on the LCD
source <(/home/admin/config.scripts/internet.sh status local)

# BASIC MENU INFO
HEIGHT=8
WIDTH=64
CHOICE_HEIGHT=2
BACKTITLE="RaspiBlitz"
TITLE="Connect Options"
MENU=""
OPTIONS=()

OPTIONS+=(MOBILE "Connect Mobile Wallet")
OPTIONS+=(LNDCREDS "Manage LND Credentials")
if [ "${ElectRS}" == "on" ]; then
  OPTIONS+=(ELECTRS "Electrum Rust Server")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))  
fi
if [ "${BTCPayServer}" == "on" ]; then
  OPTIONS+=(BTCPAY "Show LND connection string")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))  
fi
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

esac

# go into loop - start script from beginning to load config/sate fresh
/home/admin/00mainMenu.sh