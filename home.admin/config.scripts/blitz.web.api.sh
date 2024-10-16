#!/usr/bin/env bash

# main repo: https://github.com/fusion44/blitz_api

# restart the systemd `blitzapi` when credentials of lnd or bitcoind are changed and it will
# excute the `update-config` automatically before restarting

# NORMALLY user/repo/version will be defined by calling script - see build_sdcard.sh
# the following is just a fallback to try during development if script given branch does not exist
FALLACK_BRANCH="dev"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "Manage RaspiBlitz Web API"
  echo "blitz.web.api.sh info"
  echo "blitz.web.api.sh on [GITHUBUSER] [REPO] [BRANCH] [?COMMITORTAG]"
  echo "blitz.web.api.sh on DEFAULT"
  echo "blitz.web.api.sh update-config"
  echo "blitz.web.api.sh update-code [?BRANCH]"
  echo "blitz.web.api.sh off"
  exit 1
fi

###################
# INFO
###################
if [ "$1" = "info" ]; then

  # check if installed
  cd /home/blitzapi/blitz_api 2>/dev/null
  if [ "$?" != "0" ]; then
    echo "installed=0"
    exit 1
  fi
  echo "installed=1"

  # get github origin repo from repo directory with git command
  origin=$(sudo -u blitzapi git config --get remote.origin.url)
  echo "repo='${origin}'"

  # get github branch from repo directory with git command 
  branch=$(sudo -u blitzapi git rev-parse --abbrev-ref HEAD)
  echo "branch='${branch}'"

  # get github commit from repo directory with git command
  commit=$(sudo -u blitzapi git rev-parse HEAD)
  echo "commit='${commit}'"

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
  cd /home/blitzapi/blitz_api || exit 1
  secret=$(cat ./.env 2>/dev/null | grep "secret=" | cut -d "=" -f2)
  cp ./.env_sample ./.env
  dateStr=$(date)
  echo "# Update Web API CONFIG (${dateStr})"
  sed -i "s/^# platform=.*/platform=raspiblitz/g" ./.env
  sed -i "s/^platform=.*/platform=raspiblitz/g" ./.env

  # configure access token secret
  if [ "${secret}" == "" ] || [ "${secret}" == "please_please_update_me_please" ]; then
    echo "# init secret ..."
    secret=$(dd if=/dev/urandom bs=256 count=1 2>/dev/null | shasum -a256 | cut -d " " -f1)
  else
    echo "# use existing secret"
  fi
  sed -i "s/^secret=.*/secret=${secret}/g" ./.env

  source /home/admin/raspiblitz.info 2>/dev/null
  if [ "${setupPhase}" == "done" ]; then

    # configure bitcoin
    RPCUSER=$(sudo cat /mnt/hdd/${network}/${network}.conf 2>/dev/null | grep rpcuser | cut -c 9-)
    RPCPASS=$(sudo cat /mnt/hdd/${network}/${network}.conf 2>/dev/null | grep rpcpassword | cut -c 13-)
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
      tlsCert=$(sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/tls.cert)
      adminMacaroon=$(sudo xxd -ps -u -c 1000 /mnt/hdd/lnd/data/chain/bitcoin/${chain}net/admin.macaroon)
      sed -i "s/^ln_node=.*/ln_node=lnd_grpc/g" ./.env
      sed -i "s/^lnd_grpc_ip=.*/lnd_grpc_ip=127.0.0.1/g" ./.env
      sed -i "s/^lnd_macaroon=.*/lnd_macaroon=${adminMacaroon}/g" ./.env
      sed -i "s/^lnd_cert=.*/lnd_cert=${tlsCert}/g" ./.env
      if [ "${chain}" == "main" ]; then
        L2rpcportmod=0
        portprefix=""
      elif [ "${chain}" == "test" ]; then
        L2rpcportmod=1
        portprefix=1
      elif [ "${chain}" == "sig" ]; then
        L2rpcportmod=3
        portprefix=3
      fi
      lnd_grpc_port=1${L2rpcportmod}009
      lnd_rest_port=${portprefix}8080

    # configure CL
    elif [ "${lightning}" == "cl" ]; then

      echo "# CONFIG Web API Lightning --> CL"
      sed -i "s/^ln_node=.*/ln_node=cln_jrpc/g" ./.env
      sed -i "s#^cln_jrpc_path=.*#cln_jrpc_path=\"/mnt/hdd/app-data/.lightning/bitcoin/lightning-rpc\"#g" ./.env

      # get hex values of pem files
      # hexClient=$(sudo xxd -p -c2000 /home/bitcoin/.lightning/bitcoin/client.pem)
      # hexClientKey=$(sudo xxd -p -c2000 /home/bitcoin/.lightning/bitcoin/client-key.pem)
      # hexCa=$(sudo xxd -p -c2000 /home/bitcoin/.lightning/bitcoin/ca.pem)
      # if [ "${hexClient}" == "" ]; then
      #   echo "# FAIL /home/bitcoin/.lightning/bitcoin/*.pem files maybe missing"
      # fi

      # update config with hex values
      # sed -i "s/^cln_grpc_cert=.*/cln_grpc_cert=${hexClient}/g" ./.env
      # sed -i "s/^cln_grpc_key=.*/cln_grpc_key=${hexClientKey}/g" ./.env
      # sed -i "s/^cln_grpc_ca=.*/cln_grpc_ca=${hexCa}/g" ./.env
      # sed -i "s/^cln_grpc_ip=.*/cln_grpc_ip=127.0.0.1/g" ./.env
      # sed -i "s/^cln_grpc_port=.*/cln_grpc_port=4772/g" ./.env

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

# all other actions need to be sudo
if [ "$EUID" -ne 0 ]; then
  echo "error='run as root'"
  exit 1
fi

###################
# ON / INSTALL
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ "$2" == "DEFAULT" ]; then
    echo "# API: getting default user/repo from build_sdcard.sh"
    # copy build_sdcard.sh out of raspiblitz diretcory to not create "changes" in git
    sudo cp /home/admin/raspiblitz/build_sdcard.sh /home/admin/build_sdcard.sh
    sudo chmod +x /home/admin/build_sdcard.sh 2>/dev/null
    source <(sudo /home/admin/build_sdcard.sh -EXPORT)
    GITHUB_USER="${defaultAPIuser}"
    GITHUB_REPO="${defaultAPIrepo}"
    activeBranch=$(git -C /home/admin/raspiblitz branch --show-current)
    echo "# activeBranch detected by raspiblitz repo: ${activeBranch}"
    if [[ "$activeBranch" == *"dev"* ]]; then
      echo "# RELEASE CANDIDATE: using dev branch"
      GITHUB_BRANCH="dev"
    else
      GITHUB_BRANCH="blitz-${githubBranch}"
    fi

    GITHUB_COMMITORTAG=""
  else
    # get parameters
    GITHUB_USER=$2
    GITHUB_REPO=$3
    GITHUB_BRANCH=$4
    GITHUB_COMMITORTAG=$5
  fi

  # check & output info
  echo "# GITHUB_USER(${GITHUB_USER})"
  if [ "${GITHUB_USER}" == "" ]; then
    echo "# FAIL: No GITHUB_USER provided"
    exit 1
  fi
  echo "# GITHUB_REPO(${GITHUB_REPO})"
  if [ "${GITHUB_REPO}" == "" ]; then
    echo "# FAIL: No GITHUB_REPO provided"
    exit 1
  fi
  echo "# GITHUB_BRANCH(${GITHUB_BRANCH})"
  if [ "${GITHUB_BRANCH}" == "" ]; then
    echo "# FAIL: No GITHUB_BRANCH provided"
    exit 1
  fi
  echo "# GITHUB_COMMITORTAG(${GITHUB_COMMITORTAG})"
  if [ "${GITHUB_COMMITORTAG}" == "" ]; then
    echo "# INFO: No GITHUB_COMMITORTAG provided .. will use latest code on branch"
  fi

  # check if given branch exits on that github user/repo
  branchExists=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/branches/${GITHUB_BRANCH}" | grep -c "\"name\": \"${GITHUB_BRANCH}\"")
  if [ ${branchExists} -lt 1 ]; then
    echo
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "# WARNING! The given API repo is not available:"
    echo "# user(${GITHUB_USER}) repo(${GITHUB_REPO}) branch(${GITHUB_BRANCH})"
    GITHUB_BRANCH="${FALLACK_BRANCH}"
    echo "# SO WORKING WITH FALLBACK REPO:"
    echo "# user(${GITHUB_USER}) repo(${GITHUB_REPO}) branch(${GITHUB_BRANCH})"
    echo "# USE JUST FOR DEVELOPMENT - DONT USE IN PRODUCTION"
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo
    sleep 10
    GITHUB_BRANCH="${FALLACK_BRANCH}"
  fi

  # re-check (if case its fallback)
  branchExists=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/branches/${GITHUB_BRANCH}" | grep -c "\"name\": \"${GITHUB_BRANCH}\"")
  if [ ${branchExists} -lt 1 ]; then
    echo
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "# FAIL! user(${GITHUB_USER}) repo(${GITHUB_REPO}) branch(${GITHUB_BRANCH})"
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
  fi

  echo "# INSTALL Web API ..."
  # clean old source
  rm -r /root/blitz_api 2>/dev/null
  rm -r /home/blitzapi/blitz_api 2>/dev/null

  # create user
  adduser --system --group --home /home/blitzapi blitzapi

  # sudo capability for manipulating passwords
  /usr/sbin/usermod --append --groups sudo blitzapi
  # access password hash and salt
  /usr/sbin/usermod --append --groups admin blitzapi
  # access lnd creds
  /usr/sbin/usermod --append --groups lndadmin blitzapi
  # access cln creds
  /usr/sbin/usermod --append --groups bitcoin blitzapi
  echo "# allowing user as part of the bitcoin group to RW RPC hook"
  chmod 770 /home/bitcoin/.lightning/bitcoin
  chmod 660 /home/bitcoin/.lightning/bitcoin/lightning-rpc
  CLCONF="/home/bitcoin/.lightning/config"
  if [ "$(cat ${CLCONF} | grep -c "^rpc-file-mode=0660")" -eq 0 ]; then
    echo "rpc-file-mode=0660" | tee -a ${CLCONF}
  fi
  /usr/sbin/usermod --append --groups bitcoin blitzapi
  # symlink the CLN data dir for blitzapi
  sudo rm -rf /home/blitzapi/.lightning # not a symlink.. delete it silently
  # create symlink
  sudo -u blitzapi ln -s /mnt/hdd/app-data/.lightning /home/blitzapi/

  cd /home/blitzapi || exit 1

  # git clone https://github.com/fusion44/blitz_api.git /home/blitzapi/blitz_api
  echo "# clone github: ${GITHUB_USER}/${GITHUB_REPO}"
  if ! sudo -u blitzapi git clone https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git blitz_api; then
    echo "error='git clone failed'"
    exit 1
  fi
  cd blitz_api || exit 1
  echo "# checkout branch: ${GITHUB_BRANCH}"
  if ! sudo -u blitzapi git checkout ${GITHUB_BRANCH}; then
    echo "error='git checkout failed'"
    exit 1
  fi
  if [ "${GITHUB_COMMITORTAG}" != "" ]; then
    echo "# setting code to tag/commit: ${GITHUB_COMMITORTAG}"
    if ! git reset --hard ${GITHUB_COMMITORTAG}; then
      echo "error='git reset failed'"
      exit 1
    fi
  else
    echo "# using the latest code in branch"
  fi
  # install
  echo "# running install"
  sudo -u blitzapi python3 -m venv venv
  # see https://github.com/raspiblitz/raspiblitz/issues/4169 - requires a Cython upgrade.
  if ! sudo -u blitzapi ./venv/bin/pip install --upgrade Cython; then
    echo "error='pip install upgrade Cython'"
    exit 1
  fi
  if ! sudo -u blitzapi ./venv/bin/pip install -r requirements.txt --no-deps; then
    echo "error='pip install failed'"
    exit 1
  fi

  # prepare systemd service
  echo "
[Unit]
Description=BlitzBackendAPI
Wants=network.target
After=network.target mnt-hdd.mount

[Service]
WorkingDirectory=/home/blitzapi/blitz_api
# before every start update the config with latest credentials/settings
ExecStartPre=-/home/admin/config.scripts/blitz.web.api.sh update-config
ExecStart=/home/blitzapi/blitz_api/venv/bin/python -m uvicorn app.main:app --port 11111 --host=0.0.0.0 --root-path /api
User=blitzapi
Group=blitzapi
Type=simple
Restart=always
StandardOutput=journal
StandardError=journal
RestartSec=60

# Hardening
PrivateTmp=true

[Install]
WantedBy=multi-user.target
" | tee /etc/systemd/system/blitzapi.service

  chown -R blitzapi:blitzapi /home/blitzapi/blitz_api

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

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set blitzapi "on"
  /home/admin/config.scripts/blitz.conf.sh set blitzapi "on" /home/admin/raspiblitz.info

  exit 0
fi

###################
# UPDATE CODE
###################
if [ "$1" = "update-code" ]; then

  # the branch on which to get the latest code from
  if [ "$2" != "" ]; then
    currentBranch="$2"
  fi

  apiActive=$(ls /etc/systemd/system/blitzapi.service | grep -c blitzapi.service)
  if [ "${apiActive}" != "0" ]; then
    echo "# Update Web API CODE"
    systemctl stop blitzapi
    sudo chown -R blitzapi:blitzapi /home/blitzapi/blitz_api
    cd /home/blitzapi/blitz_api || exit 1
    if [ "$currentBranch" == "" ]; then
      currentBranch=$(sudo -u blitzapi git rev-parse --abbrev-ref HEAD)
    fi
    echo "# updating local repo ..."
    oldCommit=$(sudo -u blitzapi git rev-parse HEAD)
    sudo -u blitzapi git fetch
    sudo -u blitzapi git reset --hard origin/${currentBranch}
    newCommit=$(sudo -u blitzapi git rev-parse HEAD)
    if [ "${oldCommit}" != "${newCommit}" ]; then
      sudo -u blitzapi ./venv/bin/pip install -r requirements.txt
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
  userdel -rf blitzapi
  # clean old source
  rm -r /root/blitz_api 2>/dev/null

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set blitzapi "off"
  /home/admin/config.scripts/blitz.conf.sh set blitzapi "off" /home/admin/raspiblitz.info

  exit 0

fi
