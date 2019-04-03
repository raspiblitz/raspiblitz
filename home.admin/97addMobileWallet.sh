#!/bin/bash

# get raspiblitz config
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

justLocal=1

# if dynDomain is set connect from outside is possible (no notice)
if [ ${#dynDomain} -gt 0 ]; then
  justLocal=0
fi

# if sshtunnel to 10009/8080 then outside reach is possible (no notice)
isForwarded=$(echo ${sshtunnel} | grep -c "10009<")
if [ ${isForwarded} -gt 0 ]; then
  justLocal=0
fi
isForwarded=$(echo ${sshtunnel} | grep -c "8080<")
if [ ${isForwarded} -gt 0 ]; then
  justLocal=0
fi

# check if dynamic domain is set
if [ ${justLocal} -eq 1 ]; then
  dialog --title " Just Local Network? " --yesno "If you want to connect with your RaspiBlitz
also from outside your local network you need to 
activate 'Services' -> 'DynamicDNS' FIRST.
Or use SSH tunnel forwarding for port 10009.

For more details see chapter in GitHub README 
on the service 'DynamicDNS'
https://github.com/rootzoll/raspiblitz

Do you JUST want to connect with your mobile
when your are on the same LOCAL NETWORK?
" 15 54
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