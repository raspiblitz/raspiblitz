#!/usr/bin/env bash

# TODO: On sd card install there might be no Bitcoin & Lightning confs - make sure backend runs without
# TODO: make a `update-config` that will update Bitcoin & Lightning to the latest passwords & credentials
# TODO: run `update-config` as a prescript in systemd service

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "Manage RaspiBlitz Web API"
  echo "blitz.web.api.sh on [?GITHUBUSER] [?REPO] [?BRANCH]"
  echo "blitz.web.api.sh update-config"
  echo "blitz.web.api.sh update-code"
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
  sudo apt install -y redis
  sudo rm -r /home/admin/blitz_api 2>/dev/null
  cd /home/admin
  # git clone https://github.com/fusion44/blitz_api.git /home/admin/blitz_api
  git clone https://github.com/${DEFAULT_GITHUB_USER}/${DEFAULT_GITHUB_REPO}.git /home/admin/blitz_api
  cd blitz_api
  git checkout ${DEFAULT_GITHUB_BRANCH}
  pip install -r requirements.txt

  # TODO: check if that manual install is still needed in a future version
  pip install sse_starlette

  # build the config and set unique secret (its OK to be a new secret every install/upadte)
  /home/admin/config.scripts/blitz.web.api.sh update-config
  secret=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64 ; echo '')
  sed -i "s/^secret=.*/secret='${secret}'/g" ./.env

  # prepare systemd service
  echo "
[Unit]
Description=BlitzBackendAPI
Wants=network.target
After=network.target

[Service]
WorkingDirectory=/home/admin/blitz_api
# before every start update the config with latest credentials/settings
ExecStartPre=-/home/admin/config.scripts/blitz.web.api.sh update-config
ExecStart=/usr/bin/python -m uvicorn main:app --reload --port 11111 --host=0.0.0.0 --root-path /api
User=admin
Group=admin
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

  # TODO: remove after experimental step
  sudo ufw allow 11111 comment 'WebAPI Develop'

  # install info
  echo "# the API should new be available under http://[LOCALHOST]/api and port 11111 for testing"
  echo "# check for systemd:  sudo systemctl status blitzapi"
  echo "# check for logs:     sudo journalctl -f -u blitzapi"

  exit 0
fi

###################
# UPDATE CONFIG
###################
if [ "$1" = "update-config" ]; then

  # prepare configs data
  source /mnt/hdd/raspiblitz.conf 2>/dev/null
  if [ "${network}" = "" ]; then
    network="bitcoin"
    chain="main"
  fi

  cd /home/admin/blitz_api
  # make it fixed on Bitcoin & Mainnet for now - the WebUI will start limited to this first
  dateStr=$(date)
  echo "# Update Web API CONFIG (${dateStr})"
  RPCUSER=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcuser | cut -c 9-)
  RPCPASS=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
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
  
  # configure LND
  if [ "${lightning}" == "lnd" ]; then

    echo "# CONFIG Web API Lightning --> LND"
    tlsCert=$(sudo cat /mnt/hdd/lnd/tls.cert)
    adminMacaroon=$(sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/bitcoin/mainnet/admin.macaroon)  sed -i "s/^ln_node=.*/ln_node=lnd/g" ./.env
    sed -i "s/^ln_node=.*/ln_node=lnd/g" ./.env
    sed -i "s/^lnd_grpc_ip=.*/lnd_grpc_ip=127.0.0.1/g" ./.env
    sed -i "s/^lnd_macaroon=.*/lnd_macaroon="${adminMacaroon}"/g" ./.env
    sed -i "s/^lnd_cert=.*/lnd_cert="${tlsCert}"/g" ./.env

  # configure CLN
  elif [ "${lightning}" == "cln" ]; then
    
    echo "# CONFIG Web API Lightning --> CLN"
    sed -i "s/^ln_node=.*/ln_node=cln/g" ./.env
    
    # TODO: ADD C-Lightning config as soon as available
    echo "# MISSING CLN CONFIG YET"

  else
    echo "# CONFIG Web API Lightning --> OFF"
    sed -i "s/^ln_node=.*/ln_node=/g" ./.env
  fi

  echo "# '.env' config updates - blitzapi maybe needs to be restarted"
  exit 0

fi

###################
# UPDATE CODE
###################
if [ "$1" = "update-code" ]; then

  echo "# Update Web API CODE"
  sudo systemctl stop blitzapi
  cd /home/admin/blitz_api
  git fetch
  git pull
  pip install -r requirements.txt
  sudo systemctl start blitzapi
  echo "# blitzapi updates and restarted"
  exit 0

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



