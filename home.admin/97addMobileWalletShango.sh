#!/bin/bash
clear

# load raspiblitz config data
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

# default host to local IP & port 10009
local=1
host=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
port="10009"

# change host to dynDNS if set
if [ ${#dynDomain} -gt 0 ]; then
  local=0
  host="${dynDomain}"
  echo "port 10009 forwarding from dynDomain ${host}"
fi

# check if port 10009 is forwarded
if [ ${#sshtunnel} -gt 0 ]; then
  isForwarded=$(echo ${sshtunnel} | grep -c "10009<")
  if [ ${isForwarded} -gt 0 ]; then
    local=0
    host=$(echo $sshtunnel | cut -d '@' -f2 | cut -d ' ' -f1)
    port=$(echo $sshtunnel | awk '{split($0,a,"10009<"); print a[2]}' | cut -d ' ' -f1 | sed 's/[^0-9]//g')
    echo "port 10009 forwarding from port ${port} from server ${host}"
  else
    echo "port 10009 is not part of the ssh forwarding - keep default port 10009"
  fi
fi

# write qr code data to text file
echo -e "${host}:${port},\n$(xxd -p -c2000 ./.lnd/data/chain/${network}/${chain}net/admin.macaroon)," > qr.txt

# display qr code on LCD
./XXdisplayQRlcd.sh

# show pairing info
clear
msg=""
if [ ${local} -eq 1 ]; then 
  msg="Once you have the app running make sure you are on the same local network (WLAN same as LAN).\n\n"
fi
msg="${msg}On Setup Step 'Choose LND Server Type' connect to 'DIY SELF HOSTED'\n\n(Or in the App go to --> 'Settings' > 'Connect to your LND Server') \n\nThere you see three 3 form fields to fill out. Skip those and go right to the buttons below.\n\nClick on the 'Scan QR' button. Scan the QR on the LCD and <continue> or <show QR code> to see it in this window."
whiptail --backtitle "Connecting Shango Mobile Wallet" \
	 --title "Setup Shango Step 1" \
	 --yes-button "continue" \
	 --no-button "show QR code" \
	 --yesno "${msg}" 20 65
if [ $? -eq 1 ]; then
    /home/admin/XXdisplayQR.sh
fi

# clean up
./XXdisplayQRlcd_hide.sh
shred qr.png 2> /dev/null
rm -f qr.png 2> /dev/null
shred qr.txt 2> /dev/null
rm -f qr.txt 2> /dev/null

# follow up dialog
whiptail --backtitle "Connecting Shango Mobile Wallet" \
	 --title "Press Connect on Shango" \
	 --msgbox "Now press 'Connect' within the Shango Wallet.\n\nIf its not working - check issues on GitHub:\n\nhttps://github.com/neogeno/shango-lightning-wallet/issues" 15 65