#!/usr/bin/env bash

# TODO: On sd card install there might be no Bitcoin & Lightning confs - make sure backend runs without
# TODO: make a `update-config` that will update Bitcoin & Lightning to the latest passwords & credentials

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "Manage RaspiBlitz Web API"
  echo "blitz.web.api.sh on [?GITHUBUSER] [?REPO] [?BRANCH]"
  echo "blitz.web.api.sh off"
  exit 1
fi

DEFAULT_GITHUB_USER="fusion44"
DEFAULT_GITHUB_REPO="blitz_api"
DEFAULT_GITHUB_BRANCH="main"

###################
# ON / INSTALL
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ "$2" != "" ]; then
    DEFAULT_GITHUB_USER="$2"
  fi

  if [ "$3" != "" ]; then
    DEFAULT_GITHUB_REPO="$3"
  fi

  if [ "$4" != "" ]; then
    DEFAULT_GITHUB_BRANCH="$4"
  fi

  echo "# INSTALL Web API ..."
  sudo rm -r /home/admin/blitz_api 2>/dev/null
  cd /home/admin
  git clone https://github.com/${DEFAULT_GITHUB_USER}/${DEFAULT_GITHUB_REPO}.git /home/admin/blitz_api
  cd blitz_api
  git checkout ${DEFAULT_GITHUB_BRANCH}
  pip install -r requirements.txt

  # make it fixed on Bitcoin & Mainnet - the WebUI will start limited to this first
  echo "# CONFIG Web API Bitcoin"
  RPCUSER=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
  RPCPASS=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
  if [ "${RPCUSER}" == "" ]; then
    RPCUSER="raspibolt"
  fi
  if [ "${RPCPASS}" == "" ]; then
    RPCPASS="passwordB"
  fi
  sed -i "s/^network=.*/network=mainnet/g" ./.env
  sed -i "s/^bitcoind_ip_mainnet=.*/bitcoind_ip_mainnet=127.0.0.1/g" ./.env
  sed -i "s/^bitcoind_user=.*/bitcoind_user=${RPCUSER}/g" ./.env
  sed -i "s/^bitcoind_pw=.*/bitcoind_pw=${RPCPASS}/g" ./.env
  
  # add c-lightnign as soon as possible
  echo "# CONFIG Web API Lightning"
  tlsCert=$(sudo cat /mnt/hdd/lnd/tls.cert)
  adminMacaroon=$(sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/bitcoin/mainnet/admin.macaroon)  sed -i "s/^ln_node=.*/ln_node=lnd/g" ./.env
  sed -i "s/^lnd_grpc_ip=.*/lnd_grpc_ip=127.0.0.1/g" ./.env
  sed -i "s/^lnd_cert=.*/lnd_cert="${tlsCert}"/g" ./.env
  sed -i "s/^lnd_macaroon=.*/lnd_macaroon="${adminMacaroon}"/g" ./.env

  # prepare systemd service
  echo "
[Unit]
Description=BlitzBackendAPI
Wants=network.target
After=network.target

[Service]
WorkingDirectory=/home/admin/blitz_api
ExecStart=python -m uvicorn main:app --reload --port 11111
User=root
Group=root
Type=simple
Restart=always
StandardOutput=journal
StandardError=journal

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/blitzapi.service

  sudo systemctl enable blitzapi
  sudo systemctl start blitzapi
  sudo ufw allow 11111 comment 'WebAPI Develop'
  
  exit 1
fi

###################
# OFF / UNINSTALL
###################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# UNINSTALL Web API"
  sudo systemctl stop blitzapi
  sudo systemctl disable blitzapi
  sudo rm /etc/systemd/system/blitzapi.service
  sudo rm -r /home/admin/blitz_api
  exit 0

fi



