#!/bin/bash

# load raspiblitz config data
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

clear

# get local IP
myip=$(ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')

# replace dyndomain if available
if [ ${#dynDomain} -gt 0 ]; then 
  myip="${dynDomain}"
fi

#echo -e "${myip}:10009,\n$(xxd -p -c2000 ./.lnd/data/chain/${network}/${chain}net/admin.macaroon)," > qr.txt && cat ./.lnd/tls.cert >>qr.txt
echo -e "${myip}:10009,\n$(xxd -p -c2000 ./.lnd/data/chain/${network}/${chain}net/admin.macaroon)," > qr.txt

./XXdisplayQRlcd.sh

msg=""
if [ ${#dynDomain} -eq 0 ]; then 
  msg="Once you have the app is running make sure you are on the same local network (WLAN same as LAN)."
fi  
msg="${msg}On Setup Step 'Choose LND Server Type' connect to 'DIY SELF HOSTED' \n\n (Or in the App go to --> 'Settings' > 'Connect to your LND Server') \n\nThere you see three 3 form fields to fill out. Skip those and go right to the buttons below.\n\nClick on the 'Scan QR' button. Scan the QR on the LCD and <continue> or <show QR> to see it in this window."

whiptail --backtitle "Connecting Shango Mobile Wallet" \
	 --title "Setup Shango Step 1" \
	 --yes-button "show QR" \
	 --no-button "continue" \
	 --yesno "${msg}" 20 65

if [ $? -eq 0 ]; then
    /home/admin/XXdisplayQR.sh
fi
shred qr.txt
rm -f qr.txt

whiptail --backtitle "Connecting Shango Mobile Wallet" \
	 --title "Press Connect on Shango" \
	 --msgbox "Now press 'Connect' within the Shango Wallet.\n\nIf its not working - check issues on GitHub:\n\nhttps://github.com/neogeno/shango-lightning-wallet/issues" 15 65

./XXdisplayQRlcd_hide.sh
shred qr.png 2> /dev/null
rm -f qr.png
