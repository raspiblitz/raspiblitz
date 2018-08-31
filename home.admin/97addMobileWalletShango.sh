#!/bin/bash

# load network
network=`cat .network`

# get chain
chain="test"
isMainChain=$(sudo cat /mnt/hdd/${network}/${network}.conf 2>/dev/null | grep "#testnet=1" -c)
if [ ${isMainChain} -gt 0 ];then
  chain="main"
fi

# make sure qrcode-encoder in installed
clear
echo "*** Setup ***"
sudo apt-get install qrencode -y 

# get local IP
myip=$(ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')

clear
echo "******************************"
echo "Connect Shango Mobile Wallet"
echo "******************************"
echo ""
echo "GETTING THE APP"
echo "At the moment this app is in closed beta testing and the source code has not been published yet."
echo "Go to http://www.shangoapp.com/insider sign up with your email (confirmation can take time)"
echo "iOS: Read https://developer.apple.com/testflight/testers/"
echo "Android: https://play.google.com/apps/testing/com.shango (from device, after confirmation email)"
echo ""
echo "*** STEP 1 ***"
echo "Once you have the app is running make sure you are on the same local network (WLAN same as LAN)."
echo "Then go to --> 'Connect to your LND Server'"
echo "There you see three 3 form fields to fill out. Skip those and go right to the buttons below."
echo ""
echo "Click on the 'Scan OR' button"
echo "Make the this terminal as big as possible - fullscreen would be best."
echo "Then PRESS ENTER here in the terminal to generare the QR code and scan it with the app."
read key

clear
echo "*** STEP 2 : SCAN MACAROON (make whole QR code fill camera) ***"
echo -e "${myip}:10009,\n$(xxd -p -c2000 ./.lnd/data/chain/bitcoin/mainnet/admin.macaroon)," > qr.txt && cat ./.lnd/tls.cert >>qr.txt && qrencode -t ANSIUTF8 < qr.txt
echo "(To shrink QR code: OSX->CMD- / LINUX-> CTRL-) Press ENTER when finished."
read key

clear
echo "Now press 'Connect' within the Shango Wallet."
echo "If its not working - check issues on GitHub:"
echo "https://github.com/neogeno/shango-lightning-wallet/issues"
echo ""