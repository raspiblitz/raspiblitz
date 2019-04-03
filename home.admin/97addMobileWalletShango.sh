#!/bin/bash

# load raspiblitz config data
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

# make sure qrcode-encoder in installed
clear
echo "*** Setup ***"
sudo apt-get install qrencode -y 

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
if [ ${justLocal} -eq 1 ]; then 
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

# default host to local IP
host=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
# default port to 10009
port="10009"

# change host to dynDNS if set
if [ ${#dynDomain} -gt 0 ]; then
  host="${dynDomain}"
  echo "port 10009 forwarding from dynDomain ${host}"
fi

# check if port 10009 is forwarded
if [ ${#sshtunnel} -gt 0 ]; then
  isForwarded=$(echo ${sshtunnel} | grep -c "10009<")
  if [ ${isForwarded} -gt 0 ]; then
    host=$(echo $sshtunnel | cut -d '@' -f2 | cut -d ' ' -f1)
    port=$(echo $sshtunnel | awk '{split($0,a,"10009<"); print a[2]}' | cut -d ' ' -f1)
    echo "port 10009 forwarding from port ${port} from server ${host}"
  else
    echo "port 10009 is not part of the ssh forwarding - keep default port 10009"
  fi
fi

clear
echo "*** STEP 2 : SCAN MACAROON (make whole QR code fill camera) ***"
#echo -e "${myip}:10009,\n$(xxd -p -c2000 ~/.lnd/data/chain/${network}/${chain}net/admin.macaroon)," > qr.txt && qrencode -t ANSIUTF8 < qr.txt
echo -e "${host}:${port},\n$(xxd -p -c2000 ./.lnd/data/chain/${network}/${chain}net/admin.macaroon)," > qr.txt && qrencode -t ANSI256 < qr.txt
echo "(To shrink QR code: OSX->CMD- / LINUX-> CTRL-) Press ENTER when finished."
read key
shred qr.txt

clear
echo "Now press 'Connect' within the Shango Wallet."
echo "If its not working - check issues on GitHub:"
echo "https://github.com/neogeno/shango-lightning-wallet/issues"
echo ""

