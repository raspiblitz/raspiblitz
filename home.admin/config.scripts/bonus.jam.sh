#!/bin/bash

# https://github.com/joinmarket-webui/jam

WEBUI_VERSION=0.1.0
REPO=joinmarket-webui/jam
USERNAME=joinmarket
HOME_DIR=/home/$USERNAME
APP_DIR=webui
RASPIBLITZ_INFO=/home/admin/raspiblitz.info
RASPIBLITZ_CONF=/mnt/hdd/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch joinmarket_webui on or off"
  echo "bonus.jam.sh [on|off|menu|update|update commit|precheck]"
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
      whiptail --title " Jam (JoinMarket Web UI) " --msgbox "Open in your local web browser:
https://${localip}:7501\n
with Fingerprint:
${fingerprint}\n
Hidden Service address for Tor Browser (see LCD for QR):\n${toraddress}
" 16 67
      sudo /home/admin/config.scripts/blitz.display.sh hide
    else
      # Info without Tor
      whiptail --title " JAM (JoinMarket Web UI) " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:7501\n
with Fingerprint:
${fingerprint}\n
Activate Tor to access the web interface from outside your local network.
" 15 57
    fi
    echo "please wait ..."
  else
    echo "*** JAM NOT INSTALLED ***"
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

    echo "*** INSTALL JAM ***"

    # install nodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    # install JAM
    cd $HOME_DIR || exit 1

    sudo -u $USERNAME git clone https://github.com/$REPO

    cd jam || exit 1
    sudo -u $USERNAME git reset --hard v${WEBUI_VERSION}

    GITHUB_SIGN_AUTHOR="web-flow"
    GITHUB_SIGN_PUBKEYLINK="https://github.com/web-flow.gpg"
    GITHUB_SIGN_FINGERPRINT="4AEE18F83AFDEB23"
    sudo -u $USERNAME /home/admin/config.scripts/blitz.git-verify.sh \
     "${GITHUB_SIGN_AUTHOR}" "${GITHUB_SIGN_PUBKEYLINK}" "${GITHUB_SIGN_FINGERPRINT}" || exit 1

    cd $HOME_DIR || exit 1
    sudo -u $USERNAME mv jam $APP_DIR
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
ExecStartPre=-/home/admin/config.scripts/bonus.jam.sh precheck
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

    # Hidden Service for jam if Tor is active
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
    echo "*** JAM ALREADY INSTALLED ***"
  fi
  echo
  echo "# For the connection details run:"
  echo "/home/admin/config.scripts/bonus.jam.sh menu"
  echo
  exit 0
fi


# precheck
if [ "$1" = "precheck" ]; then
  if [ $(/usr/local/bin/bitcoin-cli -conf=/mnt/hdd/bitcoin/bitcoin.conf listwallets | grep -c wallet.dat) -eq 0 ];then
    echo "# Create a non-descriptor wallet.dat"
    /usr/local/bin/bitcoin-cli -conf=/mnt/hdd/bitcoin/bitcoin.conf -named createwallet wallet_name=wallet.dat descriptors=false
  else
    isDescriptor=$(/usr/local/bin/bitcoin-cli -conf=/mnt/hdd/bitcoin/bitcoin.conf -rpcwallet=wallet.dat getwalletinfo | grep -c '"descriptors": true,')
    if [ "$isDescriptor" -gt 0 ]; then
      # unload
      /usr/local/bin/bitcoin-cli -conf=/mnt/hdd/bitcoin/bitcoin.conf unloadwallet wallet.dat
      echo "# Move the wallet.dat with descriptors to /mnt/hdd/bitcoin/descriptors"
      mv /mnt/hdd/bitcoin/wallet.dat /mnt/hdd/bitcoin/descriptors
      echo "# Create a non-descriptor wallet.dat"
      /usr/local/bin/bitcoin-cli -conf=/mnt/hdd/bitcoin/bitcoin.conf -named createwallet wallet_name=wallet.dat descriptors=false
    else
      echo "# The non-descriptor wallet.dat is loaded in bitcoind."
    fi
  fi
  exit 0
fi


# update
if [ "$1" = "update" ]; then
  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c "$APP_DIR")
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** UPDATE JAM ***"
    cd $HOME_DIR

    if [ "$2" = "commit" ]; then
      echo "# Updating to the latest commit in the default branch"
      sudo -u $USERNAME wget https://github.com/$REPO/archive/refs/heads/master.tar.gz -O master.tar.gz
      sudo -u $USERNAME tar -xzf master.tar.gz
      sudo -u $USERNAME rm -rf master.tar.gz
      sudo -u $USERNAME mv jam-master $APP_DIR-update
    else
      version=$(curl --silent "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
      cd $APP_DIR
      current=$(node -p "require('./package.json').version")
      cd ..
      if [ "$current" = "$version" ]; then
        echo "*** JAM IS ALREADY UPDATED TO LATEST VERSION ***"
        exit 0
      fi
      sudo -u $USERNAME wget https://github.com/$REPO/archive/refs/tags/v$version.tar.gz -O v$version.tar.gz
      sudo -u $USERNAME tar -xzf v$version.tar.gz
      sudo -u $USERNAME rm v$version.tar.gz
      sudo -u $USERNAME mv jam-$version $APP_DIR-update
    fi

    cd $APP_DIR-update || exit 1
    sudo -u $USERNAME rm -rf docker
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
    sudo -u $USERNAME mv $APP_DIR-update $APP_DIR

    echo "*** JAM UPDATED ***"
  else
    echo "*** JAM NOT INSTALLED ***"
  fi

  exit 0
fi


# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c "$APP_DIR")
  if [ "${isInstalled}" -eq 1 ]; then
    echo "*** UNINSTALL JAM ***"

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

    echo "OK JAM removed."
  else
    echo "*** JAM NOT INSTALLED ***"
  fi

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
