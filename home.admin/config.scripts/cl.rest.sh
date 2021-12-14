#!/bin/bash

# https://github.com/Ride-The-Lightning/c-lightning-REST/releases/
CLRESTVERSION="v0.5.2"

# help
if [ $# -eq 0 ]||[ "$1" = "-h" ]||[ "$1" = "--help" ];then
  echo
  echo "C-lightning-REST install script"
  echo "The default version is: $CLRESTVERSION"
  echo "mainnet | testnet | signet instances can run parallel"
  echo "The same macaroon and certs will be used for the parallel networks"
  echo
  echo "Usage:"
  echo "cl.rest.sh [on|off|connect] <mainnet|testnet|signet>"
  echo
  exit 1
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

echo "# Running 'cl.rest.sh $*'"

if [ "$1" = connect ];then
  echo "# Allowing port ${portprefix}6100 through the firewall"
  sudo ufw allow "${portprefix}6100" comment "${netprefix}clrest"
  localip=$(ip addr | grep 'state UP' -A2 | grep -E -v 'docker0|veth' | grep 'eth0\|wlan0\|enp0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  # hidden service to https://xx.onion
  /home/admin/config.scripts/tor.onion-service.sh ${netprefix}clrest 443 ${portprefix}6100

  toraddress=$(sudo cat /mnt/hdd/tor/${netprefix}clrest/hostname)
  hex_macaroon=$(xxd -plain /home/bitcoin/c-lightning-REST/certs/access.macaroon | tr -d '\n')
  url="https://${localip}:${portprefix}6100/"
  #string="${url}?${hex_macaroon}"
  #/home/admin/config.scripts/blitz.display.sh qr "$string"
  #clear
  #echo "connection string (shown as a QRcode on the top and on the LCD):"
  #echo "$string"
  #qrencode -t ANSIUTF8 "${string}"
  clear
  echo
  /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
  echo "The Tor address is shown as a QRcode below and on the LCD"
  echo "Scan it to your phone with a QR scanner app and paste it to: 'Host'"
  echo
  echo "Host: ${toraddress}"
  echo "REST Port: 443"
  echo
  qrencode -t ANSIUTF8 "${toraddress}"
  echo
  echo
  echo "Alternatively to connect through the LAN the address is:"
  echo "https://${localip}"
  echo "REST Port: ${portprefix}6100"
  echo
  echo "# Press enter to continue to show the Macaroon"
  read key
  /home/admin/config.scripts/blitz.display.sh hide
  /home/admin/config.scripts/blitz.display.sh qr "${hex_macaroon}"
  clear
  echo
  echo "The Macaroon is shown as a QRcode below and on the LCD"
  echo "Scan it to your phone with a QR scanner app and paste it to: 'Macaroon (Hex format)'"
  echo
  echo "Macaroon: ${hex_macaroon}"
  echo
  qrencode -t ANSIUTF8 "${hex_macaroon}"
  echo
  echo "# Press enter to hide the QRcode from the LCD"
  read key
  /home/admin/config.scripts/blitz.display.sh hide
  exit 0
fi

if [ "$1" = on ];then
  echo "# Setting up c-lightning-REST for $CHAIN"

  sudo systemctl stop ${netprefix}clrest
  sudo systemctl disable ${netprefix}clrest

  if [ ! -f /home/bitcoin/c-lightning-REST/cl-rest.js ];then
    cd /home/bitcoin || exit 1
    sudo -u bitcoin git clone https://github.com/saubyk/c-lightning-REST
    cd c-lightning-REST || exit 1
    sudo -u bitcoin git reset --hard $CLRESTVERSION
    
    PGPsigner="saubyk"
    PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
    PGPpubkeyFingerprint="00C9E2BC2E45666F"
    sudo -u bitcoin /home/admin/config.scripts/blitz.git-verify.sh \
     "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1
    
    sudo -u bitcoin npm install
  fi

  # config
  cd /home/bitcoin/c-lightning-REST || exit 1
  sudo -u bitcoin mkdir ${CLNETWORK}
  echo "
{
    \"PORT\": ${portprefix}6100,
    \"DOCPORT\": ${portprefix}4001,
    \"PROTOCOL\": \"https\",
    \"EXECMODE\": \"production\",
    \"LNRPCPATH\": \"/home/bitcoin/.lightning/${CLNETWORK}/lightning-rpc\",
    \"RPCCOMMANDS\": [\"*\"]
}" | sudo -u bitcoin tee ./${CLNETWORK}/cl-rest-config.json

  echo "
# systemd unit for c-lightning-REST for ${CHAIN}
# /etc/systemd/system/${netprefix}clrest.service
[Unit]
Description=c-lightning-REST daemon for ${CHAIN}
Wants=${netprefix}lightningd.service
After=${netprefix}lightningd.service

[Service]
WorkingDirectory=/home/bitcoin/c-lightning-REST/${CLNETWORK}
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
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${netprefix}clrest.service

  sudo systemctl enable ${netprefix}clrest
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# OK - the clrest.service is enabled, system is ready so starting service"
    sudo systemctl start ${netprefix}clrest
  else
    echo "# OK - the clrest.service is enabled, to start manually use: 'sudo systemctl start clrest'"
  fi
  echo
  echo "# Monitor with:"
  echo "sudo journalctl -f -u clrest"
  echo
fi

if [ $1 = off ];then
  echo "# Removing c-lightning-REST for ${CHAIN}"
  sudo systemctl stop ${netprefix}clrest
  sudo systemctl disable ${netprefix}clrest
  sudo rm -rf /home/bitcoin/c-lightning-REST/${CLNETWORK}
  echo "# Deny port ${portprefix}6100 through the firewall"
  sudo ufw deny "${portprefix}6100"
  /home/admin/config.scripts/tor.onion-service.sh off ${netprefix}clrest
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
    echo "# Removing the source code and binaries"
    sudo rm -rf /home/bitcoin/c-lightning-REST
  fi
fi
