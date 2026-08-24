#!/bin/bash

# https://github.com/dennisreimann/kindle-display

USERNAME=kindledisplay
SERVER_PORT=3030
APP_DATA_DIR=/mnt/hdd/app-data/kindle-display
HOME_DIR=/home/$USERNAME
CONFIG_FILE=$APP_DATA_DIR/.env
APP_ROOT_DIR=$HOME_DIR/kindle-display
APP_SERVER_DIR=$APP_ROOT_DIR/server
CRON_FILE=$APP_SERVER_DIR/cron.sh
APP_VERSION=1.1.0

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to switch kindle-display on or off"
 echo "bonus.kindle-display.sh [on|off]"
 echo "bonus.kindle-display.sh [update]"
 exit 1
fi

source /home/admin/raspiblitz.info
source <(/home/admin/_cache.sh get state)

# detects and returns the local mempool instance URL
# (empty when there is no local instance running)
mempoolBaseURL() {
  local localIP localMempoolURL mempoolActive
  localMempoolURL=""
  source /mnt/hdd/app-data/raspiblitz.conf 2>/dev/null
  if [ "${mempoolExplorer}" = "on" ]; then
    mempoolActive=$(sudo systemctl is-active mempool 2>/dev/null)
    if [ "${mempoolActive}" = "active" ]; then
      localIP=$(hostname -I | awk '{print $1}')
      if [ -n "${localIP}" ]; then
        localMempoolURL="http://${localIP}:4080"
      fi
    fi
  fi
  echo "${localMempoolURL}"
}

# renders the kindle-display env file
# usage: kindleDisplayEnv <DISPLAY_RATE1> <DISPLAY_RATE2> <DISPLAY_THEME>
kindleDisplayEnv() {
  local mempoolLine mempoolURL
  mempoolURL=$(mempoolBaseURL)
  if [ -n "${mempoolURL}" ]; then
    mempoolLine="MEMPOOL_BASE_URL=\"${mempoolURL}\""
  else
    mempoolLine="# MEMPOOL_BASE_URL=\"https://mempool.space\""
  fi
  cat <<EOF
# Server port
DISPLAY_SERVER_PORT=$SERVER_PORT

# Local Mempool instance to use for data fetching.
# When unset, the public mempool.space is used.
${mempoolLine}

# Exchange rates to show.
# Supported currencies: USD, EUR, GBP, CHF, CAD, AUD, JPY
DISPLAY_RATE1="$1"
DISPLAY_RATE2="$2"

# Display settings: plain (default), onchain, lightning, mining, random
DISPLAY_THEME="$3"
EOF
}

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL KINDLE-DISPLAY ***"

  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c 'kindle-display')
  if [ ${isInstalled} -eq 0 ]; then
    # install dependencies
    sudo apt update
    sudo apt install -y firefox-esr pngcrush

    # install nodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    # add user
    sudo adduser --system --group --home /home/$USERNAME $USERNAME

    # install kindle-display
    echo "# install .."
    cd $HOME_DIR
    sudo -u $USERNAME wget https://github.com/dennisreimann/kindle-display/archive/v$APP_VERSION.tar.gz
    sudo -u $USERNAME tar -xzf v$APP_VERSION.tar.gz kindle-display-$APP_VERSION/server
    sudo -u $USERNAME mv kindle-display{-$APP_VERSION,}
    sudo -u $USERNAME rm v$APP_VERSION.tar.gz
    cd kindle-display/server
    sudo -u $USERNAME npm install
    if ! [ $? -eq 0 ]; then
        echo "FAIL - npm install did not run correctly, aborting"
        exit 1
    fi

    # setup kindle-display config
    sudo mkdir -p $APP_DATA_DIR
    sudo chown $USERNAME:$USERNAME $APP_DATA_DIR

    echo "# create config file"
    if [[ ! -f "$CONFIG_FILE" ]]; then
      configFile=/home/admin/kindle-display.env
      touch $configFile
      sudo chmod 600 $configFile || exit 1
      kindleDisplayEnv "USD" "EUR" "random" > $configFile
      sudo mv $configFile $CONFIG_FILE
    fi

    sudo chown $USERNAME:$USERNAME $CONFIG_FILE

    # link config to app
    sudo -u $USERNAME ln -s $CONFIG_FILE $APP_SERVER_DIR/.env

    # generate initial data
    echo "# run data script"
    sudo -u $USERNAME npm run data

    # open firewall
    echo "# firewall kindle-display service"
    sudo ufw allow $SERVER_PORT comment 'kindle-display HTTP'

    # install service
    echo "# prepare kindle-display service"
    cat > /home/admin/kindle-display.service <<EOF
# systemd unit for kindle-display

[Unit]
Description=kindle-display
Wants=${network}d.service
After=${network}d.service

[Service]
WorkingDirectory=${APP_SERVER_DIR}
ExecStart=/usr/bin/npm start
User=$USERNAME

# Restart on failure but no more than 2 time every 10 minutes (600 seconds). Otherwise stop
Restart=on-failure
StartLimitIntervalSec=600
StartLimitBurst=2

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF
    sudo mv /home/admin/kindle-display.service /etc/systemd/system/kindle-display.service

    echo "# enable kindle-display service"
    sudo systemctl enable kindle-display

    # https://github.com/rootzoll/raspiblitz/issues/1375
    if [ "${state}" == "ready" ]; then
      echo "# starting kindle-display service"
      sudo systemctl start kindle-display

      # generate initial screenshot
      echo "# run cronfile"
      sudo -u $USERNAME $CRON_FILE
    fi

    # set cronjob
    echo "# setting cronjob for kindle-display (default: every 2 minutes)"
    echo "# /etc/cron.d/kindle-display
SHELL=/bin/bash
PATH=/bin:/usr/bin:/usr/local/bin
# m h dom mon dow user-name command to be executed
*/2 * * * * $USERNAME $CRON_FILE >/dev/null 2>&1" | sudo tee /etc/cron.d/kindle-display >/dev/null

    echo "OK - the KINDLE-DISPLAY script is now installed."
    echo ""
    echo "Switch to the '$USERNAME' user and adapt the settings in $CONFIG_FILE"

    # setting value in raspi blitz config
    /home/admin/config.scripts/blitz.conf.sh set kindleDisplay "on"
  else
    echo "KINDLE-DISPLAY already installed."
  fi

  exit 0
fi

# update
if [ "$1" = "update" ]; then
  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c kindle-display)
  if [ ${isInstalled} -gt 0 ]; then
    echo "*** UPDATE KINDLE-DISPLAY ***"
    cd $HOME_DIR || exit 1

    current=$(node -p "require('./kindle-display/server/package.json').version")
    if [ "$current" = "$APP_VERSION" ]; then
      echo "*** KINDLE-DISPLAY IS ALREADY UPDATED TO $APP_VERSION ***"
      exit 0
    fi

    sudo systemctl stop kindle-display
    sudo -u $USERNAME wget https://github.com/dennisreimann/kindle-display/archive/v$APP_VERSION.tar.gz
    sudo -u $USERNAME tar -xzf v$APP_VERSION.tar.gz kindle-display-$APP_VERSION/server
    sudo -u $USERNAME mv kindle-display{,-backup}
    sudo -u $USERNAME mv kindle-display{-$APP_VERSION,}
    sudo -u $USERNAME rm v$APP_VERSION.tar.gz
    cd kindle-display/server
    sudo -u $USERNAME npm install
    if ! [ $? -eq 0 ]; then
        echo "FAIL - npm install did not run correctly, aborting"
        exit 1
    fi

    # migrate config file
    echo "# migrate config file"
    rate1=$(grep -m1 '^DISPLAY_RATE1=' $CONFIG_FILE 2>/dev/null | cut -d'"' -f2)
    rate1=${rate1:-USD}
    rate2=$(grep -m1 '^DISPLAY_RATE2=' $CONFIG_FILE 2>/dev/null | cut -d'"' -f2)
    rate2=${rate2:-EUR}
    theme=$(grep -m1 '^DISPLAY_THEME=' $CONFIG_FILE 2>/dev/null | cut -d'"' -f2)
    theme=${theme:-random}
    sudo -u $USERNAME cp $CONFIG_FILE ${CONFIG_FILE}.backup 2>/dev/null
    configFile=/home/admin/kindle-display.env
    touch $configFile
    sudo chmod 600 $configFile || exit 1
    kindleDisplayEnv "$rate1" "$rate2" "$theme" > $configFile
    sudo mv $configFile $CONFIG_FILE
    sudo chown $USERNAME:$USERNAME $CONFIG_FILE

    # link config to app
    sudo -u $USERNAME ln -s $CONFIG_FILE $APP_SERVER_DIR/.env
    # generate initial data
    echo "# run data script"
    sudo -u $USERNAME npm run data
    cd -
    sudo systemctl start kindle-display
    sudo -u $USERNAME rm -rf kindle-display-backup

    echo "*** KINDLE-DISPLAY UPDATED to $APP_VERSION ***"
  else
    echo "*** KINDLE-DISPLAY IS NOT INSTALLED ***"
  fi

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "*** UNINSTALL KINDLE-DISPLAY ***"
  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c 'kindle-display')

  if [ ${isInstalled} -eq 1 ]; then
    echo "*** REMOVING KINDLE-DISPLAY ***"

    # setting value in raspi blitz config
    /home/admin/config.scripts/blitz.conf.sh set kindleDisplay "off"

    # uninstall service
    sudo systemctl stop kindle-display
    sudo systemctl disable kindle-display
    sudo rm /etc/systemd/system/kindle-display.service
    sudo rm -f /etc/cron.d/kindle-display

    # close port on firewall
    sudo ufw deny $SERVER_PORT

    # remove config
    sudo rm -rf $APP_DATA_DIR

    # delete user and home directory
    sudo userdel -rf $USERNAME

    echo "OK KINDLE-DISPLAY removed."
  else
    echo "KINDLE-DISPLAY is not installed."
  fi

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
