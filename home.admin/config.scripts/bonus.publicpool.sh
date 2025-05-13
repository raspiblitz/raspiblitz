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
echo "# Script name: $0"
echo "# All parameters: $@"
echo "# First parameter: $1"
echo "# Parameter count: $#"

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# bonus.${APPID}.sh status            -> status information (key=value)"
  echo "# bonus.${APPID}.sh on                -> install the app"
  echo "# bonus.${APPID}.sh off [delete-data] -> uninstall the app"
  echo "# bonus.${APPID}.sh menu              -> SSH menu dialog"
  exit 1
fi

echo "# Running: 'bonus.${APPID}.sh $*'"

source /mnt/hdd/raspiblitz.conf

isInstalled=$(sudo ls /etc/systemd/system/${APPID}.service 2>/dev/null | grep -c "${APPID}.service")
isRunning=$(sudo systemctl status ${APPID} 2>/dev/null | grep -c 'active (running)')

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
In your miner configuration, set the
Stratum: ${localIP}:${PORT_STRATUM}\n"
  whiptail --title "Public Pool" --msgbox "${dialogText}" 14 57
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

  sudo apt install -y build-essential
  sudo apt install -y cmake
  sudo apt install -y libzmq3-dev

  echo "# create user"
  sudo adduser --system --group --shell /usr/sbin/nologin --home /home/${APPID} ${APPID} || exit 1

  sudo -u ${APPID} mkdir -p /home/${APPID}/.npm

  # I dont think this needs lnd admin privs
  # echo "# add user to special groups"
  # sudo /usr/sbin/usermod --append --groups lndadmin ${APPID}

  echo "# Install global dependencies"
  cd /home/${APPID}
  sudo npm install -g @nestjs/cli @angular/cli node-gyp node-pre-gyp

  echo "# Create app directory and set permissions"
  sudo mkdir -p ${APP_DATA_DIR}
  sudo chown -R ${APPID}:${APPID} ${APP_DATA_DIR}

  echo "# Clone repositories"
  sudo -u ${APPID} git clone ${GITHUB_REPO} /home/${APPID}/${APPID}
  sudo -u ${APPID} git clone ${GITHUB_REPO_UI} /home/${APPID}/${APPID}-ui

  # check that the repos were cloned
  if [ ! -d "/home/${APPID}/${APPID}" ] || [ ! -d "/home/${APPID}/${APPID}-ui" ]; then
    echo "# FAIL - Was not able to clone the GitHub repos."
    echo "# running uninstall script to clean up"
    /home/admin/config.scripts/bonus.publicpool.sh off
    exit 1
  fi 

  # Modify the environment.prod.ts file of WebUI
  localIP=$(hostname -I | awk '{print $1}')
  echo "# Updating environment.prod.ts with correct API and STRATUM URLs" 
  sudo -u ${APPID} tee /home/${APPID}/${APPID}-ui/src/environments/environment.ts > /dev/null << EOL
export const environment = {
  production: true,
  API_URL: 'http://${localIP}:${PORT_API}',
  STRATUM_URL: '${localIP}:${PORT_STRATUM}'
};
EOL

  echo "##### Install Backend"
  cd /home/${APPID}/${APPID}
  sudo npm install zeromq
  sudo chown publicpool:publicpool -R /home/${APPID}/${APPID}
  sudo -u ${APPID} npm install || exit 1
  echo "##### Build Backend"
  sudo -u ${APPID} npm run build || exit 1

  echo "##### Install Frontend"
  cd /home/${APPID}/${APPID}-ui
  sudo -u ${APPID} npm install || exit 1
  echo "##### Build Frontend"
  sudo -u ${APPID} npm run build || exit 1

  echo "# Set correct permissions for npm cache"
  sudo chown -R ${APPID}:${APPID} /home/${APPID}/.npm

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
POOL_IDENTIFIER=raspiblitz
NETWORK=mainnet
API_SECURE=false
" | sudo tee /home/${APPID}/${APPID}/.env >/dev/null

  echo "# create systemd service: ${APPID}.service"
  echo "
[Unit]
Description=${APPID}
Wants=bitcoind.service
After=bitcoind.service

[Service]
WorkingDirectory=/home/${APPID}/${APPID}
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
WorkingDirectory=/home/${APPID}/${APPID}-ui
ExecStart=/usr/bin/ng serve --host 0.0.0.0 --port ${PORT_UI} --no-watch --poll 2000
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
