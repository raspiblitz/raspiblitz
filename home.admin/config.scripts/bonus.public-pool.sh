#!/bin/bash

APPID="publicpool"
VERSION="0.1"
GITHUB_REPO="https://github.com/benjamin-wilson/public-pool.git"
GITHUB_REPO_UI="https://github.com/benjamin-wilson/public-pool-ui.git"
GITHUB_TAG=""

PORT_API="3334"
PORT_STRATUM="3333"
PORT_UI="3335"

# Use /mnt/hdd for app data
APP_DATA_DIR="/mnt/hdd/app-data/${APPID}"

# Debug information
echo "Script name: $0"
echo "All parameters: $@"
echo "First parameter: $1"
echo "Parameter count: $#"

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# bonus.${APPID}.sh status    -> status information (key=value)"
  echo "# bonus.${APPID}.sh on        -> install the app"
  echo "# bonus.${APPID}.sh off       -> uninstall the app"
  echo "# bonus.${APPID}.sh menu      -> SSH menu dialog"
  exit 1
fi

echo "# Running: 'bonus.${APPID}.sh $*'"

source /mnt/hdd/raspiblitz.conf

isInstalled=$(sudo ls /etc/systemd/system/${APPID}.service 2>/dev/null | grep -c "${APPID}.service")
isRunning=$(systemctl status ${APPID} 2>/dev/null | grep -c 'active (running)')

if [ "${isInstalled}" == "1" ]; then
  localIP=$(hostname -I | awk '{print $1}')
fi

if [ "$1" = "status" ]; then
  echo "appID='${APPID}'"
  echo "version='${VERSION}'"
  echo "githubRepo='${GITHUB_REPO}'"
  echo "githubRepoUI='${GITHUB_REPO_UI}'"
  echo "githubVersion='${GITHUB_TAG}'"
  echo "isInstalled=${isInstalled}"
  echo "isRunning=${isRunning}"
  if [ "${isInstalled}" == "1" ]; then
    echo "portAPI=${PORT_API}"
    echo "portStratum=${PORT_STRATUM}"
    echo "portUI=${PORT_UI}"
    echo "localIP='${localIP}'"
  fi
  exit 0
fi

if [ "$1" = "menu" ]; then
  dialogTitle=" ${APPID} "
  dialogText="Open in your local web browser:
http://${localIP}:${PORT_UI}\n
API: http://${localIP}:${PORT_API}\n
Stratum: ${localIP}:${PORT_STRATUM}\n
Use your Password B to login.\n"

  whiptail --title "${dialogTitle}" --msgbox "${dialogText}" 15 67
  echo "please wait ..."
  exit 0
fi

if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  if [ ${isInstalled} -eq 1 ]; then
    echo "# ${APPID} is already installed."
    exit 1
  fi

  echo "# Installing ${APPID} ..."

  /home/admin/config.scripts/bonus.nodejs.sh on

  echo "# create user"
  sudo adduser --system --group --shell /bin/bash --home ${APP_DATA_DIR} ${APPID} || exit 1
  sudo -u ${APPID} mkdir -p ${APP_DATA_DIR}/.npm

  echo "# add user to special groups"
  sudo /usr/sbin/usermod --append --groups lndadmin ${APPID}

  echo "# Install global dependencies"
  sudo npm install -g @nestjs/cli @angular/cli node-gyp node-pre-gyp

  echo "# Create app directory and set permissions"
  sudo mkdir -p ${APP_DATA_DIR}
  sudo chown -R ${APPID}:${APPID} ${APP_DATA_DIR}

  echo "# Clone repositories"
  sudo -u ${APPID} git clone ${GITHUB_REPO} ${APP_DATA_DIR}/${APPID}
  sudo -u ${APPID} git clone ${GITHUB_REPO_UI} ${APP_DATA_DIR}/${APPID}-ui

  echo "# Install and build backend"
  cd ${APP_DATA_DIR}/${APPID}
  sudo -u ${APPID} npm install
  sudo -u ${APPID} npm run build

  echo "# Install and build frontend"
  cd ${APP_DATA_DIR}/${APPID}-ui
  sudo -u ${APPID} npm install
  sudo -u ${APPID} npm run build

  echo "# Set correct permissions for npm cache"
  sudo chown -R ${APPID}:${APPID} ${APP_DATA_DIR}/.npm

  echo "# updating Firewall"
  sudo ufw allow ${PORT_API} comment "${APPID} API"
  sudo ufw allow ${PORT_STRATUM} comment "${APPID} Stratum"
  sudo ufw allow ${PORT_UI} comment "${APPID} UI"

  # get RPC credentials
  RPC_USER=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
  RPC_PASS=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)

  echo "# create .env file"
  echo "
BITCOIN_RPC_URL=http://127.0.0.1
BITCOIN_RPC_USER=$RPC_USER
BITCOIN_RPC_PASSWORD=$RPC_PASS
BITCOIN_RPC_PORT=8332
BITCOIN_RPC_TIMEOUT=10000
API_PORT=${PORT_API}
STRATUM_PORT=${PORT_STRATUM}
NETWORK=mainnet
API_SECURE=false
" | sudo tee ${APP_DATA_DIR}/${APPID}/.env >/dev/null

  echo "# create systemd service: ${APPID}.service"
  echo "
[Unit]
Description=${APPID}
Wants=bitcoind
After=bitcoind

[Service]
WorkingDirectory=${APP_DATA_DIR}/${APPID}
ExecStart=/usr/bin/npm start
User=${APPID}
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${APPID}.service
  sudo chown root:root /etc/systemd/system/${APPID}.service

  echo "# create systemd service: ${APPID}-ui.service"
  echo "
[Unit]
Description=${APPID} UI
After=${APPID}.service

[Service]
WorkingDirectory=${APP_DATA_DIR}/${APPID}-ui
ExecStart=/usr/bin/npm run start
User=${APPID}
Restart=always
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${APPID}-ui.service
  sudo chown root:root /etc/systemd/system/${APPID}-ui.service

  # mark app as installed in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ${APPID} "on"

  # enable and start services
  sudo systemctl enable ${APPID}
  sudo systemctl enable ${APPID}-ui
  sudo systemctl start ${APPID}
  sudo systemctl start ${APPID}-ui
  
  echo "# OK - the ${APPID} and ${APPID}-ui services are now enabled and started"
  exit 0
fi

if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# Uninstalling ${APPID} ..."

  sudo systemctl stop ${APPID} 2>/dev/null
  sudo systemctl stop ${APPID}-ui 2>/dev/null
  sudo systemctl disable ${APPID}.service
  sudo systemctl disable ${APPID}-ui.service
  sudo rm /etc/systemd/system/${APPID}.service
  sudo rm /etc/systemd/system/${APPID}-ui.service

  echo "# close ports on firewall"
  sudo ufw deny "${PORT_API}"
  sudo ufw deny "${PORT_STRATUM}"
  sudo ufw deny "${PORT_UI}"

  echo "# delete user"
  sudo userdel -rf ${APPID}

  echo "# mark app as uninstalled in raspiblitz config"
  /home/admin/config.scripts/blitz.conf.sh set ${APPID} "off"

  if [ "$(echo "$@" | grep -c delete-data)" -gt 0 ]; then
    echo "# found 'delete-data' parameter --> also deleting the app-data"
    sudo rm -r ${APP_DATA_DIR}
  fi

  echo "# OK - app should be uninstalled now"
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
exit 1
