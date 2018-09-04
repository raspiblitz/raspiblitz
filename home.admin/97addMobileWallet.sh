#!/bin/bash

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