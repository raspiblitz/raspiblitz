#!/bin/bash

# https://github.com/joinmarket-webui/jam

WEBUI_VERSION=0.3.0
REPO=joinmarket-webui/jam
USERNAME=jam
HOME_DIR=/home/$USERNAME
APP_DIR=webui
RASPIBLITZ_INFO=/home/admin/raspiblitz.info
RASPIBLITZ_CONF=/mnt/hdd/raspiblitz.conf

# dergigi 89C4A25E69A5DE7F # theborakompanioni E8070AF0053AAC0D
PGPsigner="theborakompanioni"
PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
PGPpubkeyFingerprint="E8070AF0053AAC0D"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch Jam on or off"
  echo "bonus.jam.sh [install|uninstall]"
  echo "bonus.jam.sh [on|off|status|menu]"
  echo "bonus.jam.sh [update|update commit|precheck]"
  exit 1
fi

# check and load raspiblitz config to know which network is running
source $RASPIBLITZ_INFO
source $RASPIBLITZ_CONF 2>/dev/null

# check if already installed & active
isInstalled=$(compgen -u | grep -c ${USERNAME})
isActive=$(sudo ls /etc/systemd/system/joinmarket-api.service 2>/dev/null | grep -c 'joinmarket-api.service')
localip=$(hostname -I | awk '{print $1}')

if [ "$1" = "status" ]; then

  toraddress=$(sudo cat /mnt/hdd/tor/${USERNAME}/hostname 2>/dev/null)

  echo "version='${WEBUI_VERSION}'"
  echo "installed='${isActive}'"
  echo "localIP='${localip}'"
  echo "httpPort='7500'"
  echo "httpsPort='7501'"
  echo "httpsForced='1'"
  echo "httpsSelfsigned='1'"
  echo "authMethod='password_b'"
  echo "toraddress='${toraddress}'"
  exit 0
fi

# show info menu
if [ "$1" = "menu" ]; then

  if [ ${isActive} -eq 1 ]; then
    # get network info
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
    echo "# please wait ..."
  else
    echo "# *** JAM NOT INSTALLED ***"
  fi
  exit 0
fi


# install (code & compile)
if [ "$1" = "install" ]; then

  if [ "${isInstalled}" != "0" ]; then
    echo "result='already installed'"
    exit 0
  fi

  # make sure joinmarket is installed
  sudo /home/admin/config.scripts/bonus.joinmarket.sh install || exit 1

  echo "# *** INSTALL JAM (user & code) ***"

  echo "# Creating the ${USERNAME} user"
  sudo adduser --system --group --home /home/${USERNAME} ${USERNAME}

  # install nodeJS
  /home/admin/config.scripts/bonus.nodejs.sh on

  # install
  cd $HOME_DIR || exit 1

  sudo -u $USERNAME git clone https://github.com/$REPO

  cd jam || exit 1
  sudo -u $USERNAME git reset --hard v${WEBUI_VERSION}

  sudo -u $USERNAME /home/admin/config.scripts/blitz.git-verify.sh "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" "v${WEBUI_VERSION}" || exit 1

  cd $HOME_DIR || exit 1
  sudo -u $USERNAME mv jam $APP_DIR
  cd $APP_DIR || exit 1
  sudo -u $USERNAME rm -rf docker
  if ! sudo -u $USERNAME npm install; then
    echo "# FAIL - npm install did not run correctly, aborting"
    echo "result='fail - npm install did not run correctly'"
    exit 1
  fi

  sudo -u $USERNAME npm run build
  echo "#  OK JAM user/codebase installed"
  exit 0
fi

# remove from system
if [ "$1" = "uninstall" ]; then

  # check if still active
  if [ "${isActive}" != "0" ]; then
    echo "result='still in use'"
    exit 1
  fi

  echo "# *** UNINSTALL JAM ***"

  # always delete user and home directory
  sudo userdel -rf $USERNAME

  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check if already ON
  echo "# isActive(${isActive})" 1>&2
  if [ ${isActive} -gt 1 ]; then
    echo "# JAM already installed."
    echo "result='OK'"
    exit 0
  fi

  # check if user/codebase is already installed
  echo "# isInstalled(${isInstalled})" 1>&2
  if [ ${isInstalled} -eq 0 ]; then
    sudo /home/admin/config.scripts/bonus.jam.sh install 1>&2 || exit 1
  fi

  # make sure joinmarket base is also activated
  sudo /home/admin/config.scripts/bonus.joinmarket.sh on 1>&2 || exit 1

  echo "# *** ACTIVATING JAM ***"

  ##################
  # NGINX
  ##################
  # remove legacy nginx symlinks and configs
  sudo rm -f /etc/nginx/sites-enabled/joinmarket_webui_* 1>&2
  sudo rm -f /etc/nginx/sites-available/joinmarket_webui_* 1>&2
  # setup nginx symlinks
  sudo cp -f /home/admin/assets/nginx/sites-available/jam_ssl.conf /etc/nginx/sites-available/jam_ssl.conf 1>&2
  sudo cp -f /home/admin/assets/nginx/sites-available/jam_tor.conf /etc/nginx/sites-available/jam_tor.conf 1>&2
  sudo cp -f /home/admin/assets/nginx/sites-available/jam_tor_ssl.conf /etc/nginx/sites-available/jam_tor_ssl.conf 1>&2
  sudo ln -sf /etc/nginx/sites-available/jam_ssl.conf /etc/nginx/sites-enabled/ 1>&2
  sudo ln -sf /etc/nginx/sites-available/jam_tor.conf /etc/nginx/sites-enabled/ 1>&2
  sudo ln -sf /etc/nginx/sites-available/jam_tor_ssl.conf /etc/nginx/sites-enabled/ 1>&2
  sudo nginx -t 1>&2
  sudo systemctl reload nginx 1>&2

  # open the firewall
  echo "# *** Updating Firewall ***" 1>&2
  sudo ufw allow from any to any port 7500 comment 'allow Jam HTTP' 1>&2
  sudo ufw allow from any to any port 7501 comment 'allow Jam HTTPS' 1>&2

  #########################
  ## JOINMARKET-API SERVICE
  #########################
  # SSL
  if [ -d /home/joinmarket/.joinmarket/ssl ]; then
    sudo -u joinmarket rm -rf /home/joinmarket/.joinmarket/ssl 1>&2
  fi
  subj="/C=US/ST=Utah/L=Lehi/O=Your Company, Inc./OU=IT/CN=example.com"
  sudo -u joinmarket mkdir -p /home/joinmarket/.joinmarket/ssl/ 1>&2 \
    && pushd "$_" 1>&2 \
    && sudo -u joinmarket openssl req -newkey rsa:4096 -x509 -sha256 -days 3650 -nodes -out cert.pem -keyout key.pem -subj "$subj" 1>&2 \
    && popd 1>&2 || exit 1

  # SYSTEMD SERVICE
  echo "# Install JoinMarket API systemd" 1>&2
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
" | sudo tee /etc/systemd/system/joinmarket-api.service 1>&2
  sudo systemctl enable joinmarket-api 1>&2

  # remove legacy name
  /home/admin/config.scripts/blitz.conf.sh delete joinmarketWebUI $RASPIBLITZ_CONF 1>&2
  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set jam on $RASPIBLITZ_CONF 1>&2

  # Hidden Service for jam if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
      # remove legacy
      /home/admin/config.scripts/tor.onion-service.sh off joinmarket-webui 1>&2
      # add jam
      /home/admin/config.scripts/tor.onion-service.sh jam 80 7502 443 7503 1>&2
  fi
  source $RASPIBLITZ_INFO
  if [ "${state}" == "ready" ]; then
      echo "# OK - the joinmarket-api.service is enabled, system is ready so starting service"
      sudo systemctl start joinmarket-api
  else
      echo "# OK - the joinmarket-api.service is enabled, to start manually use: 'sudo systemctl start joinmarket-api'"
  fi

  echo "# Start the joinmarket ob-watcher.service"
  sudo -u joinmarket /home/joinmarket/menu.orderbook.sh startOrderBookService 1>&2
  echo "# For the connection details run: /home/admin/config.scripts/bonus.jam.sh menu"
  echo "result='OK'"
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
  # change the onion_serving_port toavoid collusion with LND REST port
  sed -i "s#^onion_serving_port = 8080#onion_serving_port = 8090#g" /home/joinmarket/.joinmarket/joinmarket.cfg
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

  echo "# *** DEACTIVATE JAM ***"

  echo "# Cleaning up Jam install ..."
  # remove systemd service
  sudo systemctl stop joinmarket-api 2>/dev/null
  sudo systemctl disable joinmarket-api 2>/dev/null
  sudo rm -f /etc/systemd/system/joinmarket-api.service

  # close ports on firewall
  sudo ufw delete allow from any to any port 7500 1>&2
  sudo ufw delete allow from any to any port 7501 1>&2

  # remove nginx symlinks and configs
  sudo rm -f /etc/nginx/sites-enabled/jam_* 1>&2
  sudo rm -f /etc/nginx/sites-available/jam_* 1>&2
  sudo rm /var/log/nginx/error_jam.log 1>/dev/null 2>/dev/null
  sudo rm /var/log/nginx/access_jam.log 1>/dev/null 2>/dev/null
  sudo nginx -t 1>&2
  sudo systemctl reload nginx 1>&2

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off jam 1>&2
  fi

  # remove SSL
  sudo rm -rf $HOME_DIR/.joinmarket/ssl 1>&2

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh delete jam $RASPIBLITZ_CONF

  echo "# OK, Jam is removed"
  echo "result='OK'"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
