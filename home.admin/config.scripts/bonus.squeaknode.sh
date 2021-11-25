#!/bin/bash

# https://github.com/yzernik/squeaknode
pinnedVersion="v0.1.176"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "small config script to switch squeaknode on or off"
  echo "bonus.squeaknode.sh on"
  echo "bonus.squeaknode.sh [off|status|menu|write-macaroons]"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then

  # get squeaknode status info
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.squeaknode.sh status)

  text="Local Web Browser: http://${localIP}:${httpPort}"

  whiptail --title " squeaknode " --msgbox "${text}" 16 69

  /home/admin/config.scripts/blitz.display.sh hide
  echo "please wait ..."
  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^squeaknode=" /mnt/hdd/raspiblitz.conf; then
  echo "squeaknode=off" >> /mnt/hdd/raspiblitz.conf
fi

# status
if [ "$1" = "status" ]; then

  if [ "${squeaknode}" = "on" ]; then
    echo "installed=1"

    localIP=$(hostname -I | awk '{print $1}')
    echo "localIP='${localIP}'"
    echo "httpPort='12994'"

    # check for error
    isDead=$(sudo systemctl status squeaknode | grep -c 'inactive (dead)')
    if [ ${isDead} -eq 1 ]; then
      echo "error='Service Failed'"
      exit 1
    fi

  else
    echo "installed=0"
  fi
  exit 0
fi

# status
if [ "$1" = "write-macaroons" ]; then

  # make sure its run as user admin
  adminUserId=$(id -u admin)
  if [ "${EUID}" != "${adminUserId}" ]; then
    echo "error='please run as admin user'"
    exit 1
  fi

  echo "make sure symlink to central app-data directory exists"
  if ! [[ -L "/home/squeaknode/.lnd" ]]; then
    sudo rm -rf "/home/squeaknode/.lnd"                          # not a symlink.. delete it silently
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/squeaknode/.lnd"  # and create symlink
  fi

  # set tls.cert path (use | as separator to avoid escaping file path slashes)
  sudo -u squeaknode sed -i "s|^SQUEAKNODE_LND_TLS_CERT_PATH=.*|SQUEAKNODE_LND_TLS_CERT_PATH=/home/squeaknode/.lnd/tls.cert|g" /home/squeaknode/squeaknode/.env

  # set macaroon path info in .env
  # sudo chmod 600 /home/squeaknode/squeaknode/.env
  lndMacaroonPath=$(sudo echo /home/squeaknode/.lnd/data/chain/${network}/${chain}net/admin.macaroon)
  sudo chown squeaknode ${lndMacaroonPath}
  sudo -u squeaknode sed -i "s|^SQUEAKNODE_LND_MACAROON_PATH=.*|SQUEAKNODE_LND_MACAROON_PATH=${lndMacaroonPath}|g" /home/squeaknode/squeaknode/.env

  #echo "make sure squeaknode is member of lndreadonly, lndinvoice, lndadmin"
  #sudo /usr/sbin/usermod --append --groups lndinvoice squeaknode
  #sudo /usr/sbin/usermod --append --groups lndreadonly squeaknode
  #sudo /usr/sbin/usermod --append --groups lndadmin squeaknode

  toraddress=$(sudo cat /mnt/hdd/tor/squeaknode/hostname 2>/dev/null)
  sudo -u squeaknode sed -i "s|^SQUEAKNODE_SERVER_EXTERNAL_ADDRESS=.*|SQUEAKNODE_SERVER_EXTERNAL_ADDRESS=${toraddress}|g" /home/squeaknode/squeaknode/.env

  # set macaroon  path info in .env - USING PATH
  #sudo sed -i "s|^LND_REST_ADMIN_MACAROON=.*|LND_REST_ADMIN_MACAROON=/home/squeaknode/.lnd/data/chain/${network}/${chain}net/admin.macaroon|g" /home/squeaknode/squeaknode/.env
  #sudo sed -i "s|^LND_REST_INVOICE_MACAROON=.*|LND_REST_INVOICE_MACAROON=/home/squeaknode/.lnd/data/chain/${network}/${chain}net/invoice.macaroon|g" /home/squeaknode/squeaknode/.env
  #sudo sed -i "s|^LND_REST_READ_MACAROON=.*|LND_REST_READ_MACAROON=/home/squeaknode/.lnd/data/chain/${network}/${chain}net/read.macaroon|g" /home/squeaknode/squeaknode/.env
  echo "# OK - macaroons written to /home/squeaknode/squeaknode/.env"

  exit 0
fi

# stop service
echo "making sure services are not running"
sudo systemctl stop squeaknode 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL squeaknode ***"

  isInstalled=$(sudo ls /etc/systemd/system/squeaknode.service 2>/dev/null | grep -c 'squeaknode.service')
  if [ ${isInstalled} -eq 0 ]; then

    echo "*** Add the 'squeaknode' user ***"
    sudo adduser --disabled-password --gecos "" squeaknode

    # make sure needed debian packages are installed
    echo "# installing needed packages"

    # install from GitHub
    githubRepo="https://github.com/yzernik/squeaknode"
    echo "# get the github code ${githubRepo}"
    sudo rm -r /home/squeaknode/squeaknode 2>/dev/null
    cd /home/squeaknode
    sudo -u squeaknode git clone ${githubRepo}.git
    cd /home/squeaknode/squeaknode
    sudo -u squeaknode git checkout ${pinnedVersion}

    # Prepare configs
    RPCHOST="localhost"
    RPCPORT="8332"
    RPCUSER=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcuser | cut -c 9-)
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
    ZEROMQ_HASHBLOCK_PORT=28334

    LNDHOST="localhost"
    LNDRPCPORT=10009

    MAX_SQUEAKS=100000

    # prepare .env file
    echo "# preparing env file"
    sudo rm /home/squeaknode/squeaknode/.env 2>/dev/null
    sudo -u squeaknode touch /home/squeaknode/squeaknode/.env
    sudo bash -c "echo 'SQUEAKNODE_BITCOIN_RPC_HOST=${RPCHOST}' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_BITCOIN_RPC_PORT=${RPCPORT}' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_BITCOIN_RPC_USER=${RPCUSER}' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_BITCOIN_RPC_PASS=${PASSWORD_B}' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_BITCOIN_ZEROMQ_HASHBLOCK_PORT=${ZEROMQ_HASHBLOCK_PORT}' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_LND_HOST=${LNDHOST}' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_LND_RPC_PORT=${LNDRPCPORT}' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_LND_TLS_CERT_PATH=' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_LND_MACAROON_PATH=' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_TOR_PROXY_IP=localhost' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_TOR_PROXY_PORT=9050' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_WEBADMIN_ENABLED=true' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_WEBADMIN_USERNAME=raspiblitz' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_WEBADMIN_PASSWORD=pass' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_NODE_NETWORK=${chain}net' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_NODE_MAX_SQUEAKS=${MAX_SQUEAKS}' >> /home/squeaknode/squeaknode/.env"
    sudo bash -c "echo 'SQUEAKNODE_SERVER_EXTERNAL_ADDRESS=' >> /home/squeaknode/squeaknode/.env"
    /home/admin/config.scripts/bonus.squeaknode.sh write-macaroons

    # set database path to HDD data so that its survives updates and migrations
    sudo mkdir /mnt/hdd/app-data/squeaknode 2>/dev/null
    sudo chown squeaknode:squeaknode -R /mnt/hdd/app-data/squeaknode
    sudo bash -c "echo 'SQUEAKNODE_NODE_SQK_DIR_PATH=/mnt/hdd/app-data/squeaknode' >> /home/squeaknode/squeaknode/.env"

    # to the install
    echo "# installing application dependencies"

    sudo apt update
    sudo apt-get install -y libffi-dev libudev-dev

    cd /home/squeaknode/squeaknode
    sudo -u squeaknode python3 -m venv venv
    sudo -u squeaknode ./venv/bin/pip install --upgrade pip
    sudo -u squeaknode ./venv/bin/pip install --upgrade setuptools
    sudo -u squeaknode ./venv/bin/pip install --no-cache-dir  --force-reinstall -Iv grpcio==1.39.0
    # sudo -u squeaknode ./venv/bin/pip install wheel
    # sudo -u squeaknode ./venv/bin/pip install -r requirements.txt
    # sudo -u squeaknode ./venv/bin/pip install .
    sudo -u squeaknode ./venv/bin/pip install squeaknode==${pinnedVersion}

    # open firewall
    echo
    echo "*** Updating Firewall ***"
    sudo ufw allow 12994 comment 'squeaknode HTTP'
    echo ""

    # install service
    echo "*** Install systemd ***"
    cat <<EOF | sudo tee /etc/systemd/system/squeaknode.service >/dev/null
# systemd unit for squeaknode

[Unit]
Description=squeaknode
Wants=bitcoind.service
After=bitcoind.service

[Service]
EnvironmentFile=/home/squeaknode/squeaknode/.env
WorkingDirectory=/home/squeaknode/squeaknode
ExecStart=/bin/sh -c 'cd /home/squeaknode/squeaknode && ./venv/bin/squeaknode'
User=squeaknode
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl enable squeaknode

    source /home/admin/raspiblitz.info
    if [ "${state}" == "ready" ]; then
      echo "# OK - squeaknode service is enabled, system is on ready so starting squeaknode service"
      sudo systemctl start squeaknode
    else
      echo "# OK - squeaknode service is enabled, but needs reboot or manual starting: sudo systemctl start squeaknode"
    fi

  else
    echo "squeaknode already installed."
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^squeaknode=.*/squeaknode=on/g" /mnt/hdd/raspiblitz.conf

  # Hidden Service if Tor is active
  source /mnt/hdd/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with internet.tor.sh script
    /home/admin/config.scripts/internet.hiddenservice.sh squeaknode 80 12994
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # check for second parameter: should data be deleted?
  deleteData=0
  if [ "$2" = "--delete-data" ]; then
    deleteData=1
  elif [ "$2" = "--keep-data" ]; then
    deleteData=0
  else
    if (whiptail --title " DELETE DATA? " --yesno "Do you want to delete\nthe squeaknode Server Data?" 8 30); then
      deleteData=1
   else
      deleteData=0
    fi
  fi
  echo "# deleteData(${deleteData})"

  # setting value in raspi blitz config
  sudo sed -i "s/^squeaknode=.*/squeaknode=off/g" /mnt/hdd/raspiblitz.conf

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/internet.hiddenservice.sh off squeaknode
  fi

  isInstalled=$(sudo ls /etc/systemd/system/squeaknode.service 2>/dev/null | grep -c 'squeaknode.service')
  if [ ${isInstalled} -eq 1 ] || [ "${squeaknode}" == "on" ]; then
    echo "*** REMOVING squeaknode ***"
    sudo systemctl stop squeaknode
    sudo systemctl disable squeaknode
    sudo rm /etc/systemd/system/squeaknode.service
    sudo userdel -rf squeaknode

    if [ ${deleteData} -eq 1 ]; then
      echo "# deleting data"
      sudo rm -R /mnt/hdd/app-data/squeaknode
    else
      echo "# keeping data"
    fi

    echo "OK squeaknode removed."
  else
    echo "squeaknode is not installed."
  fi
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
