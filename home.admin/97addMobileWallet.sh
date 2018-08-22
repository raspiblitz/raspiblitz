#!/bin/bash

# location of lnd.conf
lnd_config=/home/bitcoin/.lnd/lnd.conf

# add qrcode-encoder to pass info
sudo apt-get install qrencode -y 

cd /home/admin/.lnd
# save LAN IP
myip="ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p'"

# display qr code
echo -e "${myip},\n$(xxd -p -c2000 admin.macaroon)," > qr.txt && cat tls.cert >>qr.txt && qrencode -t ANSIUTF8 < qr.txt