#!/bin/bash

# https://github.com/joinmarket-webui/jm-web-client
# https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/master/docs/JSON-RPC-API-using-jmwalletd.md

USERNAME=joinmarket
HOME_DIR=/home/$USERNAME
APP_DIR=webui
RASPIBLITZ_INFO=/home/admin/raspiblitz.info
RASPIBLITZ_CONF=/mnt/hdd/raspiblitz.conf
WEBUI_VERSION=0.1.0

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch joinmarket_webui on or off"
 echo "bonus.joinmarket-webui.sh [on|off|update|menu]"
 exit 1
fi

# check and load raspiblitz config to know which network is running
source $RASPIBLITZ_INFO
source $RASPIBLITZ_CONF

# show info menu
if [ "$1" = "menu" ]; then
  # get network info
  localip=$(hostname -I | awk '{print $1}')
  toraddress=$(sudo cat /mnt/hdd/tor/joinmarket-webui/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    # Info with TOR
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title " JoinMarket Web UI " --msgbox "Open in your local web browser:
http://${localip}:7500\n
https://${localip}:7501 with Fingerprint:
${fingerprint}\n
Hidden Service address for TOR Browser (see LCD for QR):\n${toraddress}
" 16 67
    /home/admin/config.scripts/blitz.display.sh hide
  else
    # Info without TOR
    whiptail --title " JoinMarket Web UI " --msgbox "Open in your local web browser & accept self-signed cert:
http://${localip}:7500\n
https://${localip}:7501 with Fingerprint:
${fingerprint}\n
Activate TOR to access the web interface from outside your local network.
" 15 57
  fi
  echo "please wait ..."
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c "$APP_DIR")
  if [ ${isInstalled} -eq 0 ]; then
    echo "*** INSTALL JOINMARKET WEB UI ***"

    # install nodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    # install JoinMarket Web UI
    cd $HOME_DIR

    #sudo -u $USERNAME wget https://github.com/joinmarket-webui/jm-web-client/archive/refs/tags/v$WEBUI_VERSION.tar.gz
    #sudo -u $USERNAME tar -xzf v$WEBUI_VERSION.tar.gz
    #sudo -u $USERNAME mv jm-web-client-$WEBUI_VERSION $APP_DIR
    #sudo -u $USERNAME rm v$WEBUI_VERSION.tar.gz
    sudo -u $USERNAME wget https://github.com/joinmarket-webui/jm-web-client/archive/refs/heads/main.tar.gz
    sudo -u $USERNAME tar -xzf main.tar.gz
    sudo -u $USERNAME mv jm-web-client-main $APP_DIR
    sudo -u $USERNAME rm main.tar.gz

    cd $APP_DIR
    sudo -u $USERNAME npm install
    if ! [ $? -eq 0 ]; then
        echo "FAIL - npm install did not run correctly, aborting"
        exit 1
    fi

    sudo -u $USERNAME npm run build

    ##################
    # NGINX
    ##################
    # setup nginx symlinks
    if ! [ -f /etc/nginx/sites-available/joinmarket_webui_ssl.conf ]; then
       sudo cp -f /home/admin/assets/nginx/sites-available/joinmarket_webui_ssl.conf /etc/nginx/sites-available/joinmarket_webui_ssl.conf
    fi
    if ! [ -f /etc/nginx/sites-available/joinmarket_webui_tor.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/joinmarket_webui_tor.conf /etc/nginx/sites-available/joinmarket_webui_tor.conf
    fi
    if ! [ -f /etc/nginx/sites-available/joinmarket_webui_tor_ssl.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/joinmarket_webui_tor_ssl.conf /etc/nginx/sites-available/joinmarket_webui_tor_ssl.conf
    fi
    sudo ln -sf /etc/nginx/sites-available/joinmarket_webui_ssl.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/joinmarket_webui_tor.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/joinmarket_webui_tor_ssl.conf /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl reload nginx

    # open the firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow from any to any port 7500 comment 'allow JoinMarket Web UI HTTP'
    sudo ufw allow from any to any port 7501 comment 'allow JoinMarket Web UI HTTPS'
    echo ""

    # SSL
    if ! [ -d $HOME_DIR/.joinmarket/ssl ]; then
      sudo -u $USERNAME mkdir -p $HOME_DIR/.joinmarket/ssl
    fi
    if ! [ -f $HOME_DIR/.joinmarket/ssl/cert.pem ]; then
      sudo ln -sf /mnt/hdd/app-data/nginx/tls.cert $HOME_DIR/.joinmarket/ssl/cert.pem
      sudo chown $USERNAME:$USERNAME $HOME_DIR/.joinmarket/ssl/cert.pem
    fi
    if ! [ -f $HOME_DIR/.joinmarket/ssl/key.pem ]; then
      sudo ln -sf /mnt/hdd/app-data/nginx/tls.key $HOME_DIR/.joinmarket/ssl/key.pem
      sudo chown $USERNAME:$USERNAME $HOME_DIR/.joinmarket/ssl/key.pem
    fi

    ##################
    # SYSTEMD SERVICE
    ##################

    echo "# Install JoinMarket API systemd"
    echo "
# Systemd unit for JoinMarket API

[Unit]
Description=JoinMarket API daemon

[Service]
WorkingDirectory=$HOME_DIR/joinmarket-clientserver/scripts/
ExecStart=/bin/sh -c '. $HOME_DIR/joinmarket-clientserver/jmvenv/bin/activate && python jmwalletd.py'
User=joinmarket
Group=joinmarket
Restart=always
TimeoutSec=120
RestartSec=30

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/joinmarket-api.service
    sudo systemctl enable joinmarket-api

    # setting value in raspiblitz config
    sudo sed -i "s/^joinmarketWebUI=.*/joinmarketWebUI=on/g" $RASPIBLITZ_CONF

    # Hidden Service for joinmarket-webui if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      # make sure to keep in sync with internet.tor.sh script
      /home/admin/config.scripts/internet.hiddenservice.sh joinmarket-webui 80 7502 443 7503
    fi
    source $RASPIBLITZ_INFO
    if [ "${state}" == "ready" ]; then
      echo "# OK - the joinmarket-api.service is enabled, system is ready so starting service"
      sudo systemctl start joinmarket-api
    else
      echo "# OK - the joinmarket-api.service is enabled, to start manually use: 'sudo systemctl start joinmarket-api'"
    fi
  else
    echo "*** JOINMARKET WEB UI ALREADY INSTALLED ***"
  fi
  exit 0
fi

# update
if [ "$1" = "update" ]; then
  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c "$APP_DIR")
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** UPDATE JOINMARKET WEB UI ***"
    cd $HOME_DIR

    sudo -u $USERNAME wget https://github.com/joinmarket-webui/jm-web-client/archive/refs/heads/main.tar.gz
    sudo -u $USERNAME tar -xzf main.tar.gz
    sudo -u $USERNAME rm -rf main.tar.gz
    cd jm-web-client-main

    sudo -u $USERNAME npm install
    if ! [ $? -eq 0 ]; then
      echo "FAIL - npm install did not run correctly, aborting"
      exit 1
    fi

    sudo -u $USERNAME npm run build
    if ! [ $? -eq 0 ]; then
      echo "FAIL - npm run build did not run correctly, aborting"
      exit 1
    fi
    cd ..
    sudo -u $USERNAME rm -rf $APP_DIR
    sudo -u $USERNAME mv jm-web-client-main $APP_DIR

    echo "*** JOINMARKET WEB UI UPDATED ***"
  else
    echo "*** JOINMARKET WEB UI NOT INSTALLED ***"
  fi

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c "$APP_DIR")
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** UNINSTALL JOINMARKET WEB UI ***"

    # remove systemd service
    sudo systemctl stop joinmarket-api
    sudo systemctl disable joinmarket-api
    sudo rm -f /etc/systemd/system/joinmarket-api.service

    # close ports on firewall
    sudo ufw delete allow from any to any port 7500 comment 'allow JoinMarket Web UI HTTP'
    sudo ufw delete allow from any to any port 7501 comment 'allow JoinMarket Web UI HTTPS'

    # remove nginx symlinks
    sudo rm -f /etc/nginx/sites-enabled/joinmarket_webui_*
    sudo rm -f /etc/nginx/sites-available/joinmarket_webui_*
    sudo nginx -t
    sudo systemctl reload nginx

    # Hidden Service if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      /home/admin/config.scripts/internet.hiddenservice.sh off joinmarket-webui
    fi

    # remove the app
    sudo rm -rf $HOME_DIR/$APP_DIR

    # remove SSL
    sudo rm -rf $HOME_DIR/.joinmarket/ssl

    # setting value in raspi blitz config
    sudo sed -i "s/^joinmarketWebUI=.*/joinmarketWebUI=off/g" $RASPIBLITZ_CONF

    echo "OK JOINMARKET WEB UI removed."
  else
    echo "*** JOINMARKET WEB UI NOT INSTALLED ***"
  fi

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
