#!/bin/bash

# https://github.com/joinmarket-webui/joinmarket-webui

USERNAME=joinmarket
HOME_DIR=/home/$USERNAME
REPO=joinmarket-webui/joinmarket-webui
APP_DIR=webui
RASPIBLITZ_INFO=/home/admin/raspiblitz.info
RASPIBLITZ_CONF=/mnt/hdd/raspiblitz.conf
WEBUI_VERSION=0.0.3

GITHUB_SIGN_AUTHOR="web-flow"
GITHUB_SIGN_PUBKEYLINK="https://github.com/web-flow.gpg"
GITHUB_SIGN_FINGERPRINT="4AEE18F83AFDEB23"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch joinmarket_webui on or off"
  echo "bonus.joinmarket-webui.sh [on|off|menu|update|update commit|precheck]"
  exit 1
fi

# check and load raspiblitz config to know which network is running
source $RASPIBLITZ_INFO
source $RASPIBLITZ_CONF

# show info menu
if [ "$1" = "menu" ]; then
  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c "$APP_DIR")
  if [ ${isInstalled} -eq 1 ]; then
    # get network info
    localip=$(hostname -I | awk '{print $1}')
    toraddress=$(sudo cat /mnt/hdd/tor/joinmarket-webui/hostname 2>/dev/null)
    fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

    if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
      # Info with Tor
      sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
      whiptail --title " JoinMarket Web UI " --msgbox "Open in your local web browser:
https://${localip}:7501\n
with Fingerprint:
${fingerprint}\n
Hidden Service address for Tor Browser (see LCD for QR):\n${toraddress}
" 16 67
      sudo /home/admin/config.scripts/blitz.display.sh hide
    else
      # Info without Tor
      whiptail --title " JoinMarket Web UI " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:7501\n
with Fingerprint:
${fingerprint}\n
Activate Tor to access the web interface from outside your local network.
" 15 57
    fi
    echo "please wait ..."
  else
    echo "*** JOINMARKET WEB UI NOT INSTALLED ***"
  fi
  exit 0
fi


# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c "$APP_DIR")
  if [ ${isInstalled} -eq 0 ]; then
    # check if joinmarket is installed
    if [ -f "/home/joinmarket/.joinmarket/joinamrket.cfg" ]; then
      echo "# JoinMarket is already installed and configured."
    else
      sudo /home/admin/config.scripts/bonus.joinmarket.sh on
    fi

    echo "*** INSTALL JOINMARKET WEB UI ***"

    # install nodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    # install JoinMarket Web UI
    cd $HOME_DIR || exit 1

    sudo -u $USERNAME git clone https://github.com/$REPO

    cd joinmarket-webui || exit 1
    sudo -u $USERNAME git reset --hard v${WEBUI_VERSION}
    sudo -u $USERNAME /home/admin/config.scripts/blitz.git-verify.sh \
      "${GITHUB_SIGN_AUTHOR}" "${GITHUB_SIGN_PUBKEYLINK}" "${GITHUB_SIGN_FINGERPRINT}" || exit 1

    cd $HOME_DIR || exit 1
    sudo -u $USERNAME mv joinmarket-webui $APP_DIR
    cd $APP_DIR || exit 1
    sudo -u $USERNAME rm -rf docker
    if ! sudo -u $USERNAME npm install; then
      echo "FAIL - npm install did not run correctly, aborting"
      exit 1
    fi

    sudo -u $USERNAME npm run build

    ##################
    # NGINX
    ##################
    # setup nginx symlinks
    sudo cp -f /home/admin/assets/nginx/sites-available/joinmarket_webui_ssl.conf /etc/nginx/sites-available/joinmarket_webui_ssl.conf
    sudo cp -f /home/admin/assets/nginx/sites-available/joinmarket_webui_tor.conf /etc/nginx/sites-available/joinmarket_webui_tor.conf
    sudo cp -f /home/admin/assets/nginx/sites-available/joinmarket_webui_tor_ssl.conf /etc/nginx/sites-available/joinmarket_webui_tor_ssl.conf
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
    if [ -d $HOME_DIR/.joinmarket/ssl ]; then
      sudo -u $USERNAME rm -rf $HOME_DIR/.joinmarket/ssl
    fi
    subj="/C=US/ST=Utah/L=Lehi/O=Your Company, Inc./OU=IT/CN=example.com"
    sudo -u $USERNAME mkdir -p $HOME_DIR/.joinmarket/ssl/ \
      && pushd "$_" \
      && sudo -u $USERNAME openssl req -newkey rsa:4096 -x509 -sha256 -days 3650 -nodes -out cert.pem -keyout key.pem -subj "$subj" \
      && popd || exit 1

    ##################
    # SYSTEMD SERVICE
    ##################

    echo "# Install JoinMarket API systemd"
    echo "\
# Systemd unit for JoinMarket API

[Unit]
Description=JoinMarket API daemon
Requires=bitcoind.service
After=bitcoind.service

[Service]
WorkingDirectory=$HOME_DIR/joinmarket-clientserver/scripts/
ExecStartPre=/home/admin/config.scripts/bonus.joinmarket-webui.sh precheck
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
      /home/admin/config.scripts/tor.onion-service.sh joinmarket-webui 80 7502 443 7503
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
  echo
  echo "# For the connection details run:"
  echo "/home/admin/config.scripts/bonus.joinmarket-webui.sh menu"
  echo
  exit 0
fi


# precheck
if [ "$1" = "precheck" ]; then
  if [ $(/usr/local/bin/bitcoin-cli -conf=/mnt/hdd/bitcoin/bitcoin.conf listwallets | grep -c wallet.dat) -eq 0 ];then
    echo "# Create wallet.dat"
    /usr/local/bin/bitcoin-cli -conf=/mnt/hdd/bitcoin/bitcoin.conf createwallet wallet.dat
  else
    echo "# The wallet.dat is loaded in bitcoind."
  fi
  exit 0
fi


# update
if [ "$1" = "update" ]; then
  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c "$APP_DIR")
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** UPDATE JOINMARKET WEB UI ***"
    cd $HOME_DIR/$APP_DIR || exit 1

    sudo -u $USERNAME git fetch origin
    if [ "$2" = "commit" ]; then
      echo "# Updating to the latest commit in the master branch"

      sudo -u $USERNAME git reset --hard
      sudo -u $USERNAME git pull origin master --rebase
      sudo -u $USERNAME /home/admin/config.scripts/blitz.git-verify.sh \
        "${GITHUB_SIGN_AUTHOR}" "${GITHUB_SIGN_PUBKEYLINK}" "${GITHUB_SIGN_FINGERPRINT}" || exit 1
    else
      TAG=$(git tag | sort -V | tail -1)
      echo "# Updating to $TAG"

      sudo -u $USERNAME git reset --hard ${TAG}
      sudo -u $USERNAME /home/admin/config.scripts/blitz.git-verify.sh \
        "${GITHUB_SIGN_AUTHOR}" "${GITHUB_SIGN_PUBKEYLINK}" "${GITHUB_SIGN_FINGERPRINT}" || exit 1
    fi

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
    echo "*** JOINMARKET WEB UI UPDATED ***"
  else
    echo "*** JOINMARKET WEB UI NOT INSTALLED ***"
  fi

  exit 0
fi


# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c "$APP_DIR")
  if [ "${isInstalled}" -eq 1 ]; then
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
      /home/admin/config.scripts/tor.onion-service.sh off joinmarket-webui
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
