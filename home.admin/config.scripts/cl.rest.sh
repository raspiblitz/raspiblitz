#!/bin/bash

# https://github.com/Ride-The-Lightning/c-lightning-REST/releases/
CLRESTVERSION="v0.10.3"

# help
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "Core-Lightning-REST install script"
  echo "The default version is: $CLRESTVERSION"
  echo "mainnet | testnet | signet instances can run parallel"
  echo
  echo "Usage:"
  echo "cl.rest.sh on <mainnet|testnet|signet>"
  echo "cl.rest.sh connect <mainnet|testnet|signet> [?key-value]"
  echo "cl.rest.sh off <mainnet|testnet|signet> <purge>"
  echo "cl.rest.sh update <mainnet|testnet|signet>"
  exit 1
fi

# Example for commits created on GitHub:
#PGPsigner="web-flow"
#PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
#PGPpubkeyFingerprint="4AEE18F83AFDEB23"

PGPsigner="saubyk"
PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
PGPpubkeyFingerprint="00C9E2BC2E45666F"

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

echo "# Running 'cl.rest.sh $*'"

if [ "$1" = connect ]; then
  if ! systemctl is-active --quiet ${netprefix}clrest; then
    /home/admin/config.scripts/cl.rest.sh on ${CHAIN}
  fi

  echo "# Allowing port ${portprefix}6100 through the firewall"
  sudo ufw allow "${portprefix}6100" comment "${netprefix}clrest" 1>/dev/null
  localip=$(hostname -I | awk '{print $1}')
  # hidden service to https://xx.onion
  /home/admin/config.scripts/tor.onion-service.sh ${netprefix}clrest 443 ${portprefix}6100 1>/dev/null

  toraddress=$(sudo cat /mnt/hdd/tor/${netprefix}clrest/hostname)
  hex_macaroon=$(xxd -plain /home/bitcoin/c-lightning-REST/${CLNETWORK}/certs/access.macaroon | tr -d '\n')
  url="https://${localip}:${portprefix}6100/"
  lndconnect="lndconnect://${toraddress}:443?macaroon=${hex_macaroon}"
  # c-lightning-rest://http://your_hidden_service.onion:your_port?&macaroon=your_macaroon_file_in_HEX&protocol=http
  clrestlan="c-lightning-rest://${localip}:${portprefix}6100?&macaroon=${hex_macaroon}&protocol=http"
  clresttor="c-lightning-rest://${toraddress}:443?&macaroon=${hex_macaroon}&protocol=http"

  if [ "$3" == "key-value" ]; then
    echo "toraddress='${toraddress}:443'"
    echo "local='${url}'"
    echo "macaroon='${hex_macaroon}'"
    echo "connectstring='${clresttor}'"
    exit 0
  fi

  # deactivated
  function showStepByStepQR() {
    clear
    echo
    sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
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
    sudo /home/admin/config.scripts/blitz.display.sh hide
    sudo /home/admin/config.scripts/blitz.display.sh qr "${hex_macaroon}"
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
    sudo /home/admin/config.scripts/blitz.display.sh hide
    exit 0
  }

  function showClRestQr() {
    # c-lightning-rest://http://your_hidden_service.onion:your_port?&macaroon=your_macaroon_file_in_HEX&protocol=http
    clear
    echo
    sudo /home/admin/config.scripts/blitz.display.sh qr "${clresttor}"
    echo "The string to connect over Tor is shown as a QRcode below and on the LCD"
    echo "Scan it to Zeus using the c-lightning-REST option"
    echo
    echo "c-lightning-REST connection string:"
    echo "${clresttor}"
    echo
    qrencode -t ANSIUTF8 "${clresttor}"
    echo
    echo "# Press enter to show the string to connect over LAN"
    read key
    sudo /home/admin/config.scripts/blitz.display.sh hide
    sudo /home/admin/config.scripts/blitz.display.sh qr "${clrestlan}"
    clear
    echo
    echo "The string to connect over the local the network is shown as a QRcode below and on the LCD"
    echo "Scan it to Zeus using the c-lightning-REST option"
    echo "This will only work if your node si connected to the same network"
    echo "To connect reemotely consider using a VPN like ZeroTier or Tailscale"
    echo
    echo "c-lightning-REST connection string:"
    echo "${clrestlan}"
    echo
    qrencode -t ANSIUTF8 "${clrestlan}"
    echo
    echo "# Press enter to hide the QRcode from the LCD"
    read key
    sudo /home/admin/config.scripts/blitz.display.sh hide
    exit 0
  }

  showClRestQr

fi

if [ "$1" = on ]; then
  echo "# Setting up c-lightning-REST for $CHAIN"

  sudo systemctl stop ${netprefix}clrest
  sudo systemctl disable ${netprefix}clrest

  if [ ! -f /home/bitcoin/c-lightning-REST/cl-rest.js ]; then
    cd /home/bitcoin || exit 1
    sudo -u bitcoin git clone https://github.com/saubyk/c-lightning-REST
    cd c-lightning-REST || exit 1
    sudo -u bitcoin git reset --hard $CLRESTVERSION

    sudo -u bitcoin /home/admin/config.scripts/blitz.git-verify.sh \
      "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" "${CLRESTVERSION}" || exit 1

    export NG_CLI_ANALYTICS=false
    sudo -u bitcoin npm install
  fi

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

  # copy clrest to a CLNETWORK subdir to make parallel networks possible
  sudo -u bitcoin mkdir /home/bitcoin/c-lightning-REST/${CLNETWORK}
  sudo -u bitcoin cp -r /home/bitcoin/c-lightning-REST/* \
    /home/bitcoin/c-lightning-REST/${CLNETWORK}

  echo "
# systemd unit for c-lightning-REST for ${CHAIN}
# /etc/systemd/system/${netprefix}clrest.service
[Unit]
Description=c-lightning-REST daemon for ${CHAIN}
Wants=${netprefix}lightningd.service
After=${netprefix}lightningd.service

[Service]
ExecStart=/usr/bin/node /home/bitcoin/c-lightning-REST/${CLNETWORK}/cl-rest.js
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
  echo "sudo journalctl -fu clrest"
  echo
  exit 0
fi

if [ "$1" = off ]; then
  echo "# Removing c-lightning-REST for ${CHAIN}"
  sudo systemctl stop ${netprefix}clrest
  sudo systemctl disable ${netprefix}clrest
  sudo rm -rf /home/bitcoin/c-lightning-REST/${CLNETWORK}
  echo "# Remove the firewall rule"
  sudo ufw delete allow "${portprefix}6100"
  /home/admin/config.scripts/tor.onion-service.sh off ${netprefix}clrest
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ]; then
    echo "# Removing the source code and binaries"
    sudo rm -rf /home/bitcoin/c-lightning-REST
  fi
  exit 0
fi

if [ "$1" = "update" ]; then
  echo "# UPDATING c-lightning-REST for ${CHAIN}"
  cd /home/bitcoin/c-lightning-REST/${CLNETWORK} || exit 1
  # fetch latest master
  sudo -u bitcoin git fetch
  # unset $1
  set --
  UPSTREAM=${1:-'@{u}'}
  LOCAL=$(sudo -u bitcoin git rev-parse @)
  REMOTE=$(sudo -u bitcoin git rev-parse "$UPSTREAM")
  if [ "$LOCAL" = "$REMOTE" ]; then
    TAG=$(sudo -u bitcoin git tag | sort -V | grep -v rc | tail -1)
    echo "# You are up-to-date on version" "$TAG"
  else
    sudo systemctl stop ${netprefix}clrest
    echo "# Pulling latest changes..."
    sudo -u bitcoin git pull -p
    echo "# Reset to the latest release tag"
    TAG=$(sudo -u bitcoin git tag | sort -V | grep -v rc | tail -1)
    sudo -u bitcoin git reset --hard "$TAG"
    sudo -u bitcoin /home/admin/config.scripts/blitz.git-verify.sh \
      "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" "${TAG}" || exit 1
    echo "# Updating to the latest"
    echo "# Running npm install ..."
    export NG_CLI_ANALYTICS=false
    if sudo -u bitcoin npm install; then
      echo "# OK - c-lightning-REST install looks good"
      echo
    else
      echo "# FAIL - npm install did not run correctly - deleting code and exit"
      /home/admin/config.scripts/cl.rest.sh off "" purge
      exit 1
    fi
    echo "# Updated to version" "$TAG"
    echo
    echo "# Starting the ${netprefix}clrest service ..."
    sudo systemctl start ${netprefix}clrest
    echo
  fi
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
exit 1
