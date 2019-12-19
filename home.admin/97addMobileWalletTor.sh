#!/bin/bash
clear

# get wallet from argument
if [ $1 == zeus ]; then
  echo "pairing Zeus"
elif [ $1 == zap ]; then
  echo "pairing Zap"
else 
  echo "pair either Zap or Zeus"
fi

./config.scripts/internet.hiddenservice.sh lnd_REST 8080 8080

# make sure Go is installed
/home/admin/config.scripts/bonus.go.sh

# make sure lndconnect is installed
/home/admin/config.scripts/bonus.lndconnect.sh

# get Go vars
source /etc/profile

if [ $1 == zeus ]; then
  echo ""
  echo "Set up on your mobile: " 
  echo "Zeus: https://zeusln.app/"
  echo "Orbot: https://github.com/openoms/bitcoin-tutorials/blob/master/Zeus_to_RaspiBlitz_through_Tor.md#set-up-orbot"
elif [ $1 == zap ]; then
  echo ""
  echo "Download the Zap Mainnet Wallet from iOS Testflight:"
  echo "https://zap.jackmallers.com/download/"
fi
echo ""
echo "        ***WARNING***"
echo ""
echo "The QR code to allow connecting to your node remotely"
echo "will show on the RaspiBlitz LCD and/or your screen."
echo "Be aware of the windows, cameras, mirrors and bystanders!"
echo ""
echo "Press ENTER to continue, CTRL+C to cancel."
echo ""
read key

./XXdisplayQRlcd_hide.sh

# write QR code to image
if [ $1 == zeus ]; then
  lndconnect --host=$(sudo cat /mnt/hdd/tor/lnd_REST/hostname) --port=8080 --image
elif [ $1 == zap ]; then
  lndconnect --host=$(sudo cat /mnt/hdd/tor/lnd_REST/hostname) --port=8080 --nocert --image
fi
# display qr code image on LCD
./XXdisplayLCD.sh lndconnect-qr.png
# show pairing info dialog
msg=""
msg="You should now see the pairing QR code on the RaspiBlitz LCD.\n\n${msg}When you start the App choose to connect to your own node.\n(DIY / Remote-Node / lndconnect)\n\nClick on the 'Scan QR' button. Scan the QR on the LCD and <continue> or <show QR code> to see it in this window."
whiptail --backtitle "Connecting Mobile Wallet" \
	 --title "Pairing by QR code" \
	 --yes-button "continue" \
	 --no-button "show QR code" \
	 --yesno "${msg}" 18 65
if [ $? -eq 1 ]; then
  if [ $1 == zeus ]; then
    lndconnect --host=$(sudo cat /mnt/hdd/tor/lnd_REST/hostname) --port=8080
  elif [ $1 == zap ]; then
    lndconnect --host=$(sudo cat /mnt/hdd/tor/lnd_REST/hostname) --port=8080 --nocert
  fi
  echo "(To shrink QR code: OSX->CMD- / LINUX-> CTRL-) Press ENTER when finished."
  read key
fi

# clean up
./XXdisplayQRlcd_hide.sh
shred lndconnect-qr.png 2> /dev/null
rm -f lndconnect-qr.png 2> /dev/null
shred qr.txt 2> /dev/null
rm -f qr.txt 2> /dev/null

echo "------------------------------"
echo "If the connection was not working:"
echo "- try to refresh the TLS & macaroons: Main Menu 'EXPORT > 'RESET'"
echo "- check issues: https://github.com/LN-Zap/lndconnect/issues"
echo "- check issues: https://github.com/rootzoll/raspiblitz/issues"
echo ""
