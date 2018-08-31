#!/bin/bash

# Basic Options
OPTIONS=(ZAP "Zap Wallet (iOS)" \
        SHANGO "Shango Wallet (iOS)")

CHOICE=$(dialog --clear \
                --title "Choose Mobile Wallet" \
                --menu "MENU" \
                8 40 2 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

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