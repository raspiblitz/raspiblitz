#!/bin/bash

# https://github.com/Ride-The-Lightning/c-lightning-REST/releases/
CLRESTVERSION="v0.4.4"

# help
if [ $# -eq 0 ]||[ "$1" = "-h" ]||[ "$1" = "--help" ];then
  echo
  echo "C-lightning-REST install script"
  echo "the default version is: $CLRESTVERSION"
  echo "setting up on ${chain}net unless otherwise specified"
  echo "mainnet | testnet | signet instances cannot run parallel"
  echo
  echo "usage:"
  echo "cln.rest.sh [on|off|connect] <mainnet|testnet|signet>"
  echo
  exit 1
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars cln $2)

echo "# Running 'cln.rest.sh $*'"

if [ $1 = connect ];then
  echo "# Allowing port ${portprefix}6100 through the firewall"
  sudo ufw allow "${portprefix}6100" comment "${netprefix}clnrest"
  localip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0|veth' | grep 'eth0\|wlan0\|enp0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  # hidden service to https://xx.onion
  /home/admin/config.scripts/internet.hiddenservice.sh ${netprefix}clnrest 443 ${portprefix}6100
  
  toraddress=$(sudo cat /mnt/hdd/tor/${netprefix}clnrest/hostname)
  hex_macaroon=$(xxd -plain /home/bitcoin/c-lightning-REST/certs/access.macaroon | tr -d '\n') 
  url="https://${localip}:${portprefix}6100/"
  string="${url}?${hex_macaroon}"

  /home/admin/config.scripts/blitz.display.sh qr "$string"
  clear
  echo "connection string (shown as a QRcode on the top and on the LCD):"
  echo "$string"
  qrencode -t ANSIUTF8 "${string}"
  echo
  echo "Tor address (shown as a QRcode below):"
  echo "${toraddress}"
  qrencode -t ANSIUTF8 "${toraddress}"
  echo
  echo "# Press enter to hide the QRcode from the LCD"
  read key
  /home/admin/config.scripts/blitz.display.sh hide
fi

if [ $1 = on ];then
  echo "# Setting up c-lightning-REST for $CHAIN"

  sudo systemctl stop clnrest
  sudo systemctl disable clnrest

  cd /home/bitcoin || exit 1
  sudo -u bitcoin git clone https://github.com/saubyk/c-lightning-REST
  cd c-lightning-REST || exit 1
  sudo -u bitcoin git reset --hard $CLRESTVERSION
  sudo -u bitcoin npm install
  sudo -u bitcoin cp sample-cl-rest-config.json cl-rest-config.json
  sudo -u bitcoin sed -i "s/3001/${portprefix}6100/g" cl-rest-config.json

  # symlink to /home/bitcoin/.lightning/lightning-rpc from the chosen network directory
  sudo rm /home/bitcoin/.lightning/lightning-rpc # delete old symlink
  sudo ln -s /home/bitcoin/.lightning/${NETWORK}/lightning-rpc /home/bitcoin/.lightning/
  
  echo "
# systemd unit for c-lightning-REST for ${CHAIN}
#/etc/systemd/system/clnrest.service
[Unit]
Description=c-lightning-REST daemon for ${CHAIN}
Wants=${netprefix}lightningd.service
After=${netprefix}lightningd.service

[Service]
ExecStart=/usr/bin/node /home/bitcoin/c-lightning-REST/cl-rest.js
User=bitcoin
Restart=always
TimeoutSec=120
RestartSec=30

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/clnrest.service

  sudo systemctl enable clnrest
  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    echo "# OK - the clnrest.service is enabled, system is ready so starting service"
    sudo systemctl start clnrest
  else
    echo "# OK - the clnrest.service is enabled, to start manually use: 'sudo systemctl start clnrest'"
  fi
  echo
  echo "# Monitor with:"
  echo "sudo journalctl -f -u clnrest"
  echo
fi

if [ $1 = off ];then
  echo "# Removing c-lightning-REST for ${CHAIN}"
  sudo systemctl stop clnrest
  sudo systemctl disable clnrest
  sudo rm -rf /home/bitcoin/c-lightning-REST
  echo "# Deny port ${portprefix}6100 through the firewall"
  sudo ufw deny "${portprefix}6100"
  /home/admin/config.scripts/internet.hiddenservice.sh off ${netprefix}clnrest
fi
