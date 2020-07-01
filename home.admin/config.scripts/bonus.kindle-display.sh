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
APP_VERSION=0.2.0

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to switch kindle-display on or off"
 echo "bonus.kindle-display.sh [on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL KINDLE-DISPLAY ***"

  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c 'kindle-display')
  if [ ${isInstalled} -eq 0 ]; then
    # install dependencies
    sudo apt install -y firefox-esr pngcrush jo

    # install nodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    # add user
    sudo adduser --disabled-password --gecos "" $USERNAME

    # install kindle-display
    cd $HOME_DIR
    sudo -u $USERNAME wget https://github.com/dennisreimann/kindle-display/archive/v$APP_VERSION.tar.gz
    sudo -u $USERNAME tar -xzf v$APP_VERSION.tar.gz kindle-display-$APP_VERSION/server
    sudo -u $USERNAME mv kindle-display{-$APP_VERSION,}
    sudo -u $USERNAME rm v$APP_VERSION.tar.gz
    cd kindle-display/server
    sudo -u $USERNAME npm install

    # setup kindle-display config
    RPC_USER=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcuser | cut -c 9-)
    RPC_PASS=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)

    sudo mkdir -p $APP_DATA_DIR
    sudo chown $USERNAME:$USERNAME $APP_DATA_DIR

    if [[ ! -f "$CONFIG_FILE" ]]; then
      configFile=/home/admin/kindle-display.env
      touch $configFile
      sudo chmod 600 $configFile || exit 1
      cat > $configFile <<EOF
# Server port
DISPLAY_SERVER_PORT=$SERVER_PORT
DISPLAY_BITCOIN_RPC_USER="$RPC_USER"
DISPLAY_BITCOIN_RPC_PASS="$RPC_PASS"
# BTCPay Settings for rate fetching – omit these setting to use Bitstamp as a fallback
# Generate API via Store > Access Tokens > Legacy API Keys
# BTCPAY_HOST="https://my.btcpayserver.com"
# BTCPAY_API_TOKEN="myBtcPayLegacyApiKey"
EOF
      sudo mv $configFile $CONFIG_FILE
    fi

    sudo chown $USERNAME:$USERNAME $CONFIG_FILE

    # link config to app
    sudo -u $USERNAME ln -s $CONFIG_FILE $APP_SERVER_DIR/.env

    # generate initial data
    sudo -u $USERNAME $APP_SERVER_DIR/data.sh

    # open firewall
    sudo ufw allow $SERVER_PORT comment 'kindle-display HTTP'

    # install service
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

[Install]
WantedBy=multi-user.target
EOF
    sudo mv /home/admin/kindle-display.service /etc/systemd/system/kindle-display.service
    sudo systemctl enable kindle-display
    sudo systemctl start kindle-display

    # generate initial screenshot
    sudo -u $USERNAME $CRON_FILE

    echo "OK - the KINDLE-DISPLAY script is now installed."
    echo ""
    echo "Switch to the '$USERNAME' user and adapt the settings in $CONFIG_FILE"

    # setting value in raspi blitz config
    sudo sed -i "s/^kindleDisplay=.*/kindleDisplay=on/g" /mnt/hdd/raspiblitz.conf
  else
    echo "KINDLE-DISPLAY already installed."
  fi

  cron_count=$(sudo -u $USERNAME crontab -l | grep "$CRON_FILE" -c)
  if [ "${cron_count}" = "0" ]; then
    echo ""
    echo "You might want to set up a cronjob to run the script in regular intervals."
    echo "As the '$USERNAME' user you can run the 'crontab -e' command."
    echo ""
    echo "Here is an example for updating every five minutes ..."
    echo ""
    echo "SHELL=/bin/bash"
    echo "PATH=/bin:/usr/bin:/usr/local/bin"
    echo "*/5 * * * * /bin/bash $CRON_FILE > /dev/null 2>&1 || true"
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
    sudo sed -i "s/^kindleDisplay=.*/kindleDisplay=off/g" /mnt/hdd/raspiblitz.conf

    # uninstall service
    sudo systemctl disable kindle-display
    sudo rm /etc/systemd/system/kindle-display.service

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
