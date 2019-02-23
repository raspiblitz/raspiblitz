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

clear
echo "******************************"
echo "Connect Shango Mobile Wallet"
echo "******************************"
echo ""
echo "*** STEP 1 ***"
if [ ${#dynDomain} -eq 0 ]; then 
  echo "Once you have the app is running make sure you are on the same local network (WLAN same as LAN)."
fi  
echo "On Setup Step 'Choose LND Server Type' connect to 'DIY SELF HOSTED'"
echo "(Or in the App go to --> 'Settings' > 'Connect to your LND Server')"
echo "There you see three 3 form fields to fill out. Skip those and go right to the buttons below."
echo ""
echo "Click on the 'Scan QR' button and PRESS ENTER"

read key
clear
echo "*** STEP 2 : SCAN MACAROON (make whole QR code fill camera) ***"

echo -e "${myip}:10009,\n$(xxd -p -c2000 ./.lnd/data/chain/${network}/${chain}net/admin.macaroon)," > qr.txt && cat ./.lnd/tls.cert >>qr.txt

./XXdisplayQR.sh

clear
echo
echo "Now press 'Connect' within the Shango Wallet."
echo "If its not working - check issues on GitHub:"
echo
echo "https://github.com/neogeno/shango-lightning-wallet/issues"
echo ""
