#!/usr/bin/env bash

# main repo: https://github.com/fusion44/blitz_api

# restart the systemd `blitzapi` when credentials of lnd or bitcoind are changeing and it will
# excute the `update-config` automatically before restarting

# TODO: On sd card install there might be no Bitcoin & Lightning confs - make sure backend runs without

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "Manage RaspiBlitz Web API"
  echo "blitz.web.api.sh on [?GITHUBUSER] [?REPO] [?BRANCH]"
  echo "blitz.web.api.sh update-config"
  echo "blitz.web.api.sh update-code"
  echo "blitz.web.api.sh off"
  exit 1
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='run as root'"
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
  rm -r /root/blitz_api 2>/dev/null
  cd /root
  # git clone https://github.com/fusion44/blitz_api.git /root/blitz_api
  git clone https://github.com/${DEFAULT_GITHUB_USER}/${DEFAULT_GITHUB_REPO}.git /root/blitz_api
  if [ "$?" != "0"]; then
    echo "error='git clone failed'"
    exit 1
  fi
  cd blitz_api
  git checkout ${DEFAULT_GITHUB_BRANCH}
  if [ "$?" != "0"]; then
    echo "error='git checkout failed'"
    exit 1
  fi
  pip install -r requirements.txt
  if [ "$?" != "0"]; then
    echo "error='pip install failed'"
    exit 1
  fi
  chown -R admin:admin /root/blitz_api
  chmod a+x /root
  chmod -R a+x /root/blitz_api

  # build the config and set unique secret (its OK to be a new secret every install/upadte)
  /home/admin/config.scripts/blitz.web.api.sh update-config
  secret=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64 ; echo '')
  sed -i "s/^secret=.*/secret=${secret}/g" ./.env

  # prepare systemd service
  echo "
[Unit]
Description=BlitzBackendAPI
Wants=network.target
After=network.target mnt-hdd.mount

[Service]
WorkingDirectory=/root/blitz_api
# before every start update the config with latest credentials/settings
ExecStartPre=-/home/admin/config.scripts/blitz.web.api.sh update-config
ExecStart=/usr/bin/python -m uvicorn app.main:app --port 11111 --host=0.0.0.0 --root-path /api
User=root
Group=root
Type=simple
Restart=always
StandardOutput=journal
StandardError=journal
RestartSec=60

# Hardening measures
PrivateTmp=true
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | tee /etc/systemd/system/blitzapi.service

  systemctl enable blitzapi
  systemctl start blitzapi

  # TODO: remove after experimental step (only have forward on nginx:80 /api)
  ufw allow 11111 comment 'WebAPI Develop'

  source <(/home/admin/_cache.sh export internet_localip)

  # install info
  echo "# the API is now running on port 11111 & doc available under:"
  echo "# http://${internet_localip}/api/docs"
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

  # prepare config update
  cd /root/blitz_api
  cp ./.env_sample ./.env
  dateStr=$(date)
  echo "# Update Web API CONFIG (${dateStr})"
  sed -i "s/^# platform=.*/platform=raspiblitz/g" ./.env
  sed -i "s/^platform=.*/platform=raspiblitz/g" ./.env

  source <(/home/admin/config.scripts/blitz.datadrive.sh status)
  if [ "${isMounted}" == "1" ]; then

    # configure bitcoin
    RPCUSER=$(cat /mnt/hdd/${network}/${network}.conf 2>/dev/null | grep rpcuser | cut -c 9-)
    RPCPASS=$(cat /mnt/hdd/${network}/${network}.conf 2>/dev/null | grep rpcpassword | cut -c 13-)
    if [ "${RPCUSER}" == "" ]; then
      RPCUSER="raspibolt"
    fi
    if [ "${RPCPASS}" == "" ]; then
      RPCPASS="passwordB"
    fi
    sed -i "s/^network=.*/network=mainnet/g" ./.env
    sed -i "s/^bitcoind_ip_mainnet=.*/bitcoind_ip_mainnet=127.0.0.1/g" ./.env
    sed -i "s/^bitcoind_ip_testnet=.*/bitcoind_ip_testnet=127.0.0.1/g" ./.env
    sed -i "s/^bitcoind_user=.*/bitcoind_user=${RPCUSER}/g" ./.env
    sed -i "s/^bitcoind_pw=.*/bitcoind_pw=${RPCPASS}/g" ./.env


    # configure LND
    if [ "${lightning}" == "lnd" ]; then

      echo "# CONFIG Web API Lightning --> LND"
      tlsCert=$(xxd -ps -u -c 1000 /mnt/hdd/lnd/tls.cert)
      adminMacaroon=$(xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/bitcoin/${chain}net/admin.macaroon)
      sed -i "s/^ln_node=.*/ln_node=lnd_grpc/g" ./.env
      sed -i "s/^lnd_grpc_ip=.*/lnd_grpc_ip=127.0.0.1/g" ./.env
      sed -i "s/^lnd_macaroon=.*/lnd_macaroon=${adminMacaroon}/g" ./.env
      sed -i "s/^lnd_cert=.*/lnd_cert=${tlsCert}/g" ./.env
      if [ "${chain}" == "main" ];then
        L2rpcportmod=0
        portprefix=""
      elif [ "${chain}" == "test" ];then
        L2rpcportmod=1
        portprefix=1
      elif [ "${chain}" == "sig" ];then
        L2rpcportmod=3
        portprefix=3
      fi
      lnd_grpc_port=1${L2rpcportmod}009
      lnd_rest_port=${portprefix}8080

    # configure CL
    elif [ "${lightning}" == "cl" ]; then
    
      echo "# CONFIG Web API Lightning --> CL"
      sed -i "s/^ln_node=.*/ln_node=cln_grpc/g" ./.env

      # get hex values of pem files
      hexClient=$(xxd -p -c2000 /home/bitcoin/.lightning/bitcoin/client.pem)
      hexClientKey=$(xxd -p -c2000 /home/bitcoin/.lightning/bitcoin/client-key.pem)
      hexCa=$(xxd -p -c2000 /home/bitcoin/.lightning/bitcoin/ca.pem)
      if [ "${hexClient}" == "" ]; then
        echo "# FAIL /home/bitcoin/.lightning/bitcoin/*.pem files maybe missing"
      fi

      # update config with hex values
      sed -i "s/^cln_grpc_cert=.*/cln_grpc_cert=${hexClient}/g" ./.env
      sed -i "s/^cln_grpc_key=.*/cln_grpc_key=${hexClientKey}/g" ./.env
      sed -i "s/^cln_grpc_ca=.*/cln_grpc_ca=${hexCa}/g" ./.env
      sed -i "s/^cln_grpc_ip=.*/cln_grpc_ip=127.0.0.1/g" ./.env
      sed -i "s/^cln_grpc_port=.*/cln_grpc_port=9537/g" ./.env

    else
      echo "# CONFIG Web API Lightning --> OFF"
      sed -i "s/^ln_node=.*/ln_node=none/g" ./.env
    fi

  else
      echo "# CONFIG Web API ... still in setup, skip bitcoin & lightning"
      sed -i "s/^network=.*/network=/g" ./.env
      sed -i "s/^ln_node=.*/ln_node=/g" ./.env
  fi

  echo "# '.env' config updates - blitzapi maybe needs to be restarted"
  exit 0

fi

###################
# UPDATE CODE
###################
if [ "$1" = "update-code" ]; then

  apiActive=$(ls /etc/systemd/system/blitzapi.service | grep -c blitzapi.service)
  if [ "${apiActive}" != "0" ]; then
    echo "# Update Web API CODE"
    systemctl stop blitzapi
    cd /root/blitz_api
    currentBranch=$(git rev-parse --abbrev-ref HEAD)
    echo "# updating local repo ..."
    oldCommit=$(git rev-parse HEAD)
    git fetch
    git reset --hard origin/${currentBranch}
    newCommit=$(git rev-parse HEAD)
    if [ "${oldCommit}" != "${newCommit}" ]; then
      pip install -r requirements.txt
    else
      echo "# no code changes"
    fi
    systemctl start blitzapi
    echo "# BRANCH ---> ${currentBranch}"
    echo "# old commit -> ${oldCommit}"
    echo "# new commit -> ${newCommit}"
    echo "# blitzapi updates and restarted"
    exit 0
  else
    echo "# blitzapi not active"
    exit 1
  fi
fi

###################
# OFF / UNINSTALL
###################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# UNINSTALL Web API"
  systemctl stop blitzapi
  systemctl disable blitzapi
  rm /etc/systemd/system/blitzapi.service
  rm -r /root/blitz_api
  rm -r /root/.blitz_api 2>/dev/null
  exit 0

fi
