#!/bin/bash

# https://github.com/joinmarket-webui/jam

WEBUI_VERSION=0.1.4
REPO=joinmarket-webui/jam
USERNAME=jam
HOME_DIR=/home/$USERNAME
APP_DIR=webui
RASPIBLITZ_INFO=/home/admin/raspiblitz.info
RASPIBLITZ_CONF=/mnt/hdd/raspiblitz.conf

PGPsigner="dergigi"
PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
PGPpubkeyFingerprint="89C4A25E69A5DE7F"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch Jam on or off"
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
    toraddress=$(sudo cat /mnt/hdd/tor/jam/hostname 2>/dev/null)
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
      whiptail --title " Jam (JoinMarket Web UI) " --msgbox "Open in your local web browser & accept self-signed cert:
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

    echo "# Creating the ${USERNAME} user"
    echo
    sudo adduser --disabled-password --gecos "" ${USERNAME}

    # install nodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    # install
    cd $HOME_DIR || exit 1

    sudo -u $USERNAME git clone https://github.com/$REPO

    cd jam || exit 1
    sudo -u $USERNAME git reset --hard v${WEBUI_VERSION}

    sudo -u $USERNAME /home/admin/config.scripts/blitz.git-verify.sh \
     "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" "v${WEBUI_VERSION}" || exit 1

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
    # remove legacy nginx symlinks and configs
    sudo rm -f /etc/nginx/sites-enabled/joinmarket_webui_*
    sudo rm -f /etc/nginx/sites-available/joinmarket_webui_*
    # setup nginx symlinks
    sudo cp -f /home/admin/assets/nginx/sites-available/jam_ssl.conf /etc/nginx/sites-available/jam_ssl.conf
    sudo cp -f /home/admin/assets/nginx/sites-available/jam_tor.conf /etc/nginx/sites-available/jam_tor.conf
    sudo cp -f /home/admin/assets/nginx/sites-available/jam_tor_ssl.conf /etc/nginx/sites-available/jam_tor_ssl.conf
    sudo ln -sf /etc/nginx/sites-available/jam_ssl.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/jam_tor.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/jam_tor_ssl.conf /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl reload nginx

    # open the firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow from any to any port 7500 comment 'allow Jam HTTP'
    sudo ufw allow from any to any port 7501 comment 'allow Jam HTTPS'
    echo ""

    #########################
    ## JOINMARKET-API SERVICE
    #########################
    # SSL
    if [ -d /home/joinmarket/.joinmarket/ssl ]; then
      sudo -u joinmarket rm -rf /home/joinmarket/.joinmarket/ssl
    fi
    subj="/C=US/ST=Utah/L=Lehi/O=Your Company, Inc./OU=IT/CN=example.com"
    sudo -u joinmarket mkdir -p /home/joinmarket/.joinmarket/ssl/ \
      && pushd "$_" \
      && sudo -u joinmarket openssl req -newkey rsa:4096 -x509 -sha256 -days 3650 -nodes -out cert.pem -keyout key.pem -subj "$subj" \
      && popd || exit 1

    # SYSTEMD SERVICE
    echo "# Install JoinMarket API systemd"
    echo "\
# Systemd unit for JoinMarket API

[Unit]
Description=JoinMarket API daemon

[Service]
WorkingDirectory=/home/joinmarket/joinmarket-clientserver/scripts/
ExecStartPre=-/home/admin/config.scripts/bonus.jam.sh precheck
ExecStart=/bin/sh -c '. /home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate && python jmwalletd.py'
User=joinmarket
Group=joinmarket
Restart=always
TimeoutSec=120
RestartSec=60
LogLevelMax=4

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/joinmarket-api.service
    sudo systemctl enable joinmarket-api

    # remove legacy name
    /home/admin/config.scripts/blitz.conf.sh delete joinmarketWebUI $RASPIBLITZ_CONF
    # setting value in raspiblitz config
    /home/admin/config.scripts/blitz.conf.sh set jam on $RASPIBLITZ_CONF

    # Hidden Service for jam if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      # remove legacy
      /home/admin/config.scripts/tor.onion-service.sh off joinmarket-webui
      # add jam
      /home/admin/config.scripts/tor.onion-service.sh jam 80 7502 443 7503

    fi
    source $RASPIBLITZ_INFO
    if [ "${state}" == "ready" ]; then
      echo "# OK - the joinmarket-api.service is enabled, system is ready so starting service"
      sudo systemctl start joinmarket-api
    else
      echo "# OK - the joinmarket-api.service is enabled, to start manually use: 'sudo systemctl start joinmarket-api'"
    fi
  else
    echo "*** JAM IS ALREADY INSTALLED ***"
  fi
  echo
  echo "# Start the joinmarket ob-watcher.service"
  sudo -u joinmarket /home/joinmarket/menu.orderbook.sh startOrderBookService
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
  echo "# Make sure max_cj_fee_abs and max_cj_fee_rel are set"
  # max_cj_fee_abs between 5000 - 10000 sats
  sed -i "s/#max_cj_fee_abs = x/max_cj_fee_abs = $(shuf -i 5000-10000 -n1)/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  # max_cj_fee_rel between 0.01 - 0.03%
  sed -i "s/#max_cj_fee_rel = x/max_cj_fee_rel = 0.000$((RANDOM%3+1))/g" /home/joinmarket/.joinmarket/joinmarket.cfg
  exit 0
fi


# update
if [ "$1" = "update" ]; then
  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c "$APP_DIR")
  if [ ${isInstalled} -gt 0 ]; then
    echo "*** UPDATE JAM ***"
    cd $HOME_DIR || exit 1

    if [ "$2" = "commit" ]; then
      echo "# Remove old source code"
      sudo rm -rf jam
      sudo rm -rf $APP_DIR
      echo "# Downloading the latest commit in the default branch of $REPO"
      sudo -u $USERNAME git clone https://github.com/$REPO
    else
      version=$(curl --header "X-GitHub-Api-Version:2022-11-28" --silent "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
      cd $APP_DIR || exit 1
      current=$(node -p "require('./package.json').version")
      cd ..
      if [ "$current" = "$version" ]; then
        echo "*** JAM IS ALREADY UPDATED TO LATEST RELEASE ***"
        exit 0
      fi

      echo "# Remove old source code"
      sudo rm -rf jam
      sudo rm -rf $APP_DIR
      sudo -u $USERNAME git clone https://github.com/$REPO
      cd jam || exit 1
      sudo -u $USERNAME git reset --hard v${version}

      sudo -u $USERNAME /home/admin/config.scripts/blitz.git-verify.sh \
       "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" "v${version}" || exit 1

      cd $HOME_DIR || exit 1
    fi

    sudo -u $USERNAME mv jam $APP_DIR
    cd $APP_DIR || exit 1
    sudo -u $USERNAME rm -rf docker
    if ! sudo -u $USERNAME npm install; then
      echo "FAIL - npm install did not run correctly, aborting"
      exit 1
    fi

    sudo -u $USERNAME npm run build
    echo "*** JAM UPDATED to $version ***"
  else
    echo "*** JAM IS NOT INSTALLED ***"
  fi

  exit 0
fi


# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "*** UNINSTALL JAM ***"

  if [ -d /home/$USERNAME ]; then
    sudo userdel -rf $USERNAME 2>/dev/null
    echo "Removed the $USERNAME user"
  else
    echo "There is no /home/$USERNAME present"
  fi

  echo "Cleaning up Jam install ..."
  # remove systemd service
  sudo systemctl stop joinmarket-api 2>/dev/null
  sudo systemctl disable joinmarket-api 2>/dev/null
  sudo rm -f /etc/systemd/system/joinmarket-api.service

  # close ports on firewall
  sudo ufw delete allow from any to any port 7500
  sudo ufw delete allow from any to any port 7501

  # remove nginx symlinks and configs
  sudo rm -f /etc/nginx/sites-enabled/jam_*
  sudo rm -f /etc/nginx/sites-available/jam_*
  sudo nginx -t
  sudo systemctl reload nginx

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off jam
  fi

  # remove the app
  sudo rm -rf $HOME_DIR/$APP_DIR 2>/dev/null

  # remove SSL
  sudo rm -rf $HOME_DIR/.joinmarket/ssl

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh delete jam $RASPIBLITZ_CONF

  echo "OK, Jam is removed"

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
