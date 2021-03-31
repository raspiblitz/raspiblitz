#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# get the local network IP to be displayed on the LCD
source <(/home/admin/config.scripts/internet.sh status local)

# BASIC MENU INFO
HEIGHT=10
WIDTH=64
CHOICE_HEIGHT=4
BACKTITLE="RaspiBlitz"
TITLE="Connect Options"
MENU=""
OPTIONS=()

OPTIONS+=(MOBILE "Connect Mobile Wallet")
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
OPTIONS+=(EXPORT "Get Macaroons and TLS.cert")
OPTIONS+=(RESET "Recreate LND Macaroons + TLS")
OPTIONS+=(SYNC "Sync Macaroons + TLS with Apps/Users")

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

        MOBILE)
          /home/admin/97addMobileWallet.sh;;
        ELECTRS)
          /home/admin/config.scripts/bonus.electrs.sh menu;;
        BTCPAY)
          /home/admin/config.scripts/lnd.export.sh btcpay;;
        RESET)
          sudo /home/admin/config.scripts/lnd.credentials.sh reset
          echo "Press ENTER to return to main menu."
          read key
          exit 0;;
        SYNC)
          sudo /home/admin/config.scripts/lnd.credentials.sh sync
          echo "Press ENTER to return to main menu."
          read key
          exit 0;;
        EXPORT)
          sudo /home/admin/config.scripts/lnd.export.sh
          exit 0;;
esac

# go into loop - start script from beginning to load config/sate fresh
/home/admin/00mainMenu.sh