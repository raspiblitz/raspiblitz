#!/bin/bash

# load raspiblitz config data
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

# make sure qrcode-encoder in installed
clear
echo "*** Setup ***"
sudo apt-get install qrencode -y 

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
echo "GETTING THE APP"
echo "At the moment this app is in public beta testing:"
echo "iOS: Read https://testflight.apple.com/join/WwCjFnS8 (open on device)"
echo "Android: https://play.google.com/apps/testing/com.shango (open on device)"
echo ""
echo "*** STEP 1 ***"
if [ ${#dynDomain} -eq 0 ]; then 
  echo "Once you have the app is running make sure you are on the same local network (WLAN same as LAN)."
fi  
echo "On Setup Step 'Choose LND Server Type' connect to 'DIY SELF HOSTED'"
echo "(Or in the App go to --> 'Settings' > 'Connect to your LND Server')"
echo "There you see three 3 form fields to fill out. Skip those and go right to the buttons below."
echo ""
echo "Click on the 'Scan QR' button"
echo "Make the this terminal as big as possible - fullscreen would be best."
echo "Then PRESS ENTER here in the terminal to generare the QR code and scan it with the app."
read key

clear
echo "*** STEP 2 : SCAN MACAROON (make whole QR code fill camera) ***"
#echo -e "${myip}:10009,\n$(xxd -p -c2000 ~/.lnd/data/chain/${network}/${chain}net/admin.macaroon)," > qr.txt && qrencode -t ANSIUTF8 < qr.txt
echo -e "${myip}:10009,\n$(xxd -p -c2000 ./.lnd/data/chain/${network}/${chain}net/admin.macaroon)," > qr.txt && qrencode -t ANSI256 < qr.txt
echo "(To shrink QR code: OSX->CMD- / LINUX-> CTRL-) Press ENTER when finished."
read key
shred qr.txt

clear
echo "Now press 'Connect' within the Shango Wallet."
echo "If its not working - check issues on GitHub:"
echo "https://github.com/neogeno/shango-lightning-wallet/issues"
echo ""