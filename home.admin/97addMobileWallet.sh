#!/bin/bash

# location of lnd.conf
lnd_config=/home/bitcoin/.lnd/lnd.conf

# allow in firewall
sudo ufw allow from 0.0.0.0/24 to any port 10009 comment 'allow LND grpc'

# delete certificates as they need to be recreated with correct settings
sudo rm /home/bitcoin/.lnd/tls.*
# copy over certificates to admin
sudo cp /home/bitcoin/.lnd/tls.cert /home/admin/.lnd

# enable fw
sudo ufw enable

# restart lnd
sudo systemctl restart lnd

# unlock wallet
lncli unlock

# add qrcode-encoder to pass info
sudo apt-get install qrencode -y 

cd /home/admin/.lnd
# save LAN IP
myip="ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p'"

# display qr code
echo -e "${myip},\n$(xxd -p -c2000 admin.macaroon)," > qr.txt && cat tls.cert >>qr.txt && qrencode -t ANSIUTF8 < qr.txt

