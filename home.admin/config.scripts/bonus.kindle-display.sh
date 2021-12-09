#!/bin/bash

# https://github.com/dennisreimann/kindle-display

USERNAME=kindledisplay
SERVER_PORT=3030
APP_DATA_DIR=/mnt/hdd/app-data/kindle-display
HOME_DIR=/home/$USERNAME
CONFIG_FILE=$APP_DATA_DIR/.env
RASPIBLITZ_FILE=/mnt/hdd/raspiblitz.conf
APP_ROOT_DIR=$HOME_DIR/kindle-display
APP_SERVER_DIR=$APP_ROOT_DIR/server
CRON_FILE=$APP_SERVER_DIR/cron.sh
APP_VERSION=0.4.0

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to switch kindle-display on or off"
 echo "bonus.kindle-display.sh [on|off]"
 exit 1
fi

source /home/admin/raspiblitz.info

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL KINDLE-DISPLAY ***"

  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c 'kindle-display')
  if [ ${isInstalled} -eq 0 ]; then
    # install dependencies
    sudo apt update
    sudo apt install -y firefox-esr pngcrush jo jq torsocks

    # install nodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    # add user
    sudo adduser --disabled-password --gecos "" $USERNAME

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
    RPC_USER=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcuser | cut -c 9-)
    RPC_PASS=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)

    sudo mkdir -p $APP_DATA_DIR
    sudo chown $USERNAME:$USERNAME $APP_DATA_DIR

    echo "# create config file"
    if [[ ! -f "$CONFIG_FILE" ]]; then
      configFile=/home/admin/kindle-display.env
      touch $configFile
      sudo chmod 600 $configFile || exit 1
      cat > $configFile <<EOF
# Server port
DISPLAY_SERVER_PORT=$SERVER_PORT

# Require Tor for outside API calls
DISPLAY_FORCE_TOR=true

# Bitcoin RPC credentials for getting the blockcount.
# Omit these setting to use blockchain.info as a fallback.
DISPLAY_BITCOIN_RPC_USER="$RPC_USER"
DISPLAY_BITCOIN_RPC_PASS="$RPC_PASS"

# Exchange rates to show.
# Use identifiers supported by BTCPay/Kraken, e.g. EUR, CHF
DISPLAY_RATE1="USD"
DISPLAY_RATE2="EUR"

# BTCPay Settings for rate fetching.
# Generate API via Store > Access Tokens > Legacy API Keys
# Omit these setting to use Kraken as a fallback.
# BTCPAY_HOST="https://my.btcpayserver.com"
# BTCPAY_API_TOKEN="myBtcPayLegacyApiKey"

# Shall the fallbacks be used?
DISPLAY_FALLBACK_BLOCK=false
DISPLAY_FALLBACK_RATES=true
EOF
      sudo mv $configFile $CONFIG_FILE
    fi

    sudo chown $USERNAME:$USERNAME $CONFIG_FILE

    # link config to app
    sudo -u $USERNAME ln -s $CONFIG_FILE $APP_SERVER_DIR/.env

    # generate initial data
    echo "# run data.sh"
    sudo -u $USERNAME $APP_SERVER_DIR/data.sh

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
    echo "# setting cronbjob for kindle-display (default: every 5 minutes)"
    echo "# /etc/cron.d/kindle-display
SHELL=/bin/bash
PATH=/bin:/usr/bin:/usr/local/bin
# m h dom mon dow user-name command to be executed
*/5 * * * * $USERNAME $CRON_FILE >/dev/null 2>&1" | sudo tee /etc/cron.d/kindle-display >/dev/null

    echo "OK - the KINDLE-DISPLAY script is now installed."
    echo ""
    echo "Switch to the '$USERNAME' user and adapt the settings in $CONFIG_FILE"

    # setting value in raspi blitz config
    grep -q '^kindleDisplay' $RASPIBLITZ_FILE && sudo sed -i "s/^kindleDisplay=.*/kindleDisplay=on/g" $RASPIBLITZ_FILE || echo 'kindleDisplay=on' >> $RASPIBLITZ_FILE
  else
    echo "KINDLE-DISPLAY already installed."
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
    sudo sed -i "s/^kindleDisplay=.*/kindleDisplay=off/g" $RASPIBLITZ_FILE

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
