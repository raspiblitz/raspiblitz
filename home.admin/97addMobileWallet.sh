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
  whiptail --title " Just Local Network? " --yesno "If you want to connect with your RaspiBlitz
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
        SHANGO_IOS "Shango Wallet (iOS)" \
        SHANGO_ANDROID "Shango Wallet (Android)" \
        ZEUS_IOS "Zeus Wallet (iOS)" \
        ZEUS_ANDROID "Zeus Wallet (Android)"
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
			--yes-button "continue" \
		  --no-button "link as QR code" \
		  --yesno "At the moment this app is in public beta testing:\n\nhttps://testflight.apple.com/join/WwCjFnS8\n\nJoin testing and follow ALL instructions.\n\nWhen installed and started -> continue" 10 60

	  if [ $? -eq 1 ]; then
			/home/admin/XXdisplayQR.sh
	  fi
	  shred qr.txt
	  rm -f qr.txt
	  /home/admin/XXdisplayQRlcd_hide.sh

    ./97addMobileWalletShango.sh
	  exit 1;
	  ;;
	SHANGO_ANDROID)
		echo "market://details?id=com.shango" > qr.txt
	  ./XXdisplayQRlcd.sh
	  whiptail --title "Install Shango on your Android Phone" \
			--yes-button "continue" \
			--no-button "link as QR code" \
		  --yesno "At the moment this app is in public beta testing:\n\nhttps://play.google.com/apps/testing/com.shango\n\nEasiest way to install scan QR code on LCD with phone.\n\nWhen installed and started -> continue" 10 60

	  if [ $? -eq 1 ]; then
			/home/admin/XXdisplayQR.sh
	  fi
	  shred qr.txt
	  rm -f qr.txt
	  /home/admin/XXdisplayQRlcd_hide.sh

    ./97addMobileWalletShango.sh
    exit 1;
    ;;
  ZAP)
	  echo "https://testflight.apple.com/join/P32C380R" > qr.txt
		./XXdisplayQRlcd.sh
	    
	  whiptail --title "Install Testflight and Zap on your iOS device" \
			--yes-button "continue" \
		  --no-button "link as QR code" \
		  --yesno "At the moment this app is in public beta testing:\n\nhttps://testflight.apple.com/join/P32C380R\n\nJoin testing and follow ALL instructions.\n\nWhen installed and started -> continue" 10 60

	  if [ $? -eq 1 ]; then
			/home/admin/XXdisplayQR.sh
	  fi
	  shred qr.txt
	  rm -f qr.txt
	  /home/admin/XXdisplayQRlcd_hide.sh

  	./97addMobileWalletLNDconnect.sh RPC
    exit 1;
    ;;
  ZEUS_IOS)
	  echo "https://testflight.apple.com/join/gpVFzEHN" > qr.txt
		./XXdisplayQRlcd.sh
	    
	  whiptail --title "Install Testflight and Zeus on your iOS device" \
			--yes-button "continue" \
		  --no-button "link as QR code" \
		  --yesno "At the moment this app is in public beta testing:\n\nhttps://testflight.apple.com/join/gpVFzEHN\n\nJoin testing and follow ALL instructions.\n\nWhen installed and started -> continue" 10 60

	  if [ $? -eq 1 ]; then
			/home/admin/XXdisplayQR.sh
	  fi
	  shred qr.txt
	  rm -f qr.txt
	  /home/admin/XXdisplayQRlcd_hide.sh
	
  	./97addMobileWalletLNDconnect.sh REST
  	exit 1;
  	;;
  ZEUS_ANDROID)
		echo "market://details?id=com.zeusln.zeus" > qr.txt
	  ./XXdisplayQRlcd.sh
	  whiptail --title "Install Shango on your Android Phone" \
			--yes-button "continue" \
			--no-button "link as QR code" \
		  --yesno "Find the Zeus Wallet on the Android Play Store:\n\nhttps://play.google.com/store/apps/details?id=com.zeusln.zeus\n\nEasiest way to install scan QR code on LCD with phone.\n\nWhen installed and started -> continue." 10 60
	  if [ $? -eq 1 ]; then
			/home/admin/XXdisplayQR.sh
	  fi
	  shred qr.txt
	  rm -f qr.txt
	  /home/admin/XXdisplayQRlcd_hide.sh

  	./97addMobileWalletLNDconnect.sh REST
  	exit 1;
  	;;
esac
