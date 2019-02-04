#!/bin/bash

# get raspiblitz config
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# check if dynamic domain is set
if [ ${#dynDomain} -eq 0 ]; then
  dialog --title " Just Local Network? " --yesno "If you want to connect with your RaspiBlitz
also from outside your local network you need to 
activate 'Services' -> 'DynamicDNS' FIRST. 

For more details see chapter in GitHub README 
'Public Domain with DynamicDNS'
https://github.com/rootzoll/raspiblitz

Do you JUST want to connect with your mobile
when your are on the same LOCAL NETWORK?
" 14 54
  response=$?
  case $response in
    1) exit ;;
  esac
fi

# Basic Options
OPTIONS=(ZAP "Zap Wallet (iOS)" \
        SHANGO "Shango Wallet (iOS/Android)")

CHOICE=$(dialog --clear --title "Choose Mobile Wallet" --menu "" 10 40 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)

clear
case $CHOICE in
        CLOSE)
            exit 1;
            ;;
        SHANGO)
            ./97addMobileWalletShango.sh
            exit 1;
            ;;
        ZAP)
            ./97addMobileWalletZap.sh
            exit 1;
            ;;
esac