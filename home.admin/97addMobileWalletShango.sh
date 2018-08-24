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
echo "SETUP"
echo "Once you have the app running make sure you are on the same local network (WLAN same as LAN)."
echo "Then go to --> 'Connect to your LND Server'"
echo "There you see three 3 form fields to fill out."
echo ""
echo "*** STEP 1 ***"
echo "ENTER into IP & PORT the following:"
echo "${myip}:10009"
echo ""
echo "NOTE: You can replace IP with dyndns if available and port forwarding on router."
echo ""
echo "The following two steps, will be a QR code - press scan icon in app next to field."
echo "PRESS ENTER to make RaspiBlitz displaying the MACAROON QR code ..."
read key

clear
echo "*** STEP 2 : SCAN MACAROON (make whole QR code fill camera) ***"
qrencode $(xxd -p -c3000 /home/admin/.lnd/data/chain/${network}/${chain}net/admin.macaroon) -t ANSIUTF8
echo "Press ENTER to make RaspiBlitz displaying the TLS-CERT QR code ..."
echo "(To shrink QR code: OSX->CMD- / LINUX-> CTRL-) Press ENTER for next step."
read key

clear
echo "*** STEP 3_ SCAN TLS-Cert (make whole QR code fill camera) ***"
qrencode $(xxd -p -c3000 /home/admin/.lnd/tls.cert) -t ANSIUTF8
echo "(To shrink QR code: OSX->CMD- / LINUX-> CTRL-) Press ENTER when Done."
read key

clear
echo "Now press 'Connect' within the Shango Wallet."
echo "If its not working - check issues on GitHub:"
echo "https://github.com/neogeno/shango-lightning-wallet/issues"
echo ""