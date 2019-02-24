#!/bin/bash

# get raspiblitz config
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# check if dynamic domain is set
if [ ${#dynDomain} -eq 0 ]; then
  whiptail --title " Just Local Network? " --yesno "If you want to connect with your RaspiBlitz
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
         SHANGO_IOS "Shango Wallet for iOS"
	 SHANGO_ANDROID "Shango Wallet for Android"
	)

CHOICE=$(whiptail --clear --title "Choose Mobile Wallet" --menu "" 15 50 6 "${OPTIONS[@]}" 2>&1 >/dev/tty)

./XXdisplayQRlcd_hide.sh

clear
case $CHOICE in
        CLOSE)
            exit 1;
            ;;
	SHANGO_IOS)
	    echo "https://testflight.apple.com/join/WwCjFnS8" > qr.txt
	    ./XXdisplayLCD.sh /home/admin/assets/install_shango.jpg
	    
	    whiptail --title "Install Testflight and Shango on your iOS device" \
		     --yes-button "show link as QR" \
		     --no-button "continue" \
		     --yesno "At the moment this app is in public beta testing:\n\nhttps://testflight.apple.com/join/WwCjFnS8" 20 60

	    if [ $? -eq 0 ]; then
		/home/admin/XXdisplayQR.sh
	    fi

	    shred qr.txt
	    rm -f qr.txt
	    /home/admin/XXdisplayQRlcd_hide.sh

            ./97addMobileWalletShango.sh
	    exit 1;
	    ;;
	SHANGO_ANDROID)
	    echo "https://play.google.com/apps/testing/com.shango" > qr.txt
	    ./XXdisplayQRlcd.sh
	    whiptail --title "Install Shango on your Android Phone" \
		     --yes-button "show link as QR" \
		     --no-button "continue" \
		     --yesno "At the moment this app is in public beta testing:\n\nhttps://play.google.com/apps/testing/com.shango \n\nDo you want to see a QR code with an Playstore link?" 20 60

	    if [ $? -eq 0 ]; then
		/home/admin/XXdisplayQR.sh
	    fi

	    shred qr.txt
	    rm -f qr.txt
	    /home/admin/XXdisplayQRlcd_hide.sh

            ./97addMobileWalletShango.sh
            exit 1;
            ;;
        ZAP)
            ./97addMobileWalletZap.sh
            exit 1;
            ;;
esac
