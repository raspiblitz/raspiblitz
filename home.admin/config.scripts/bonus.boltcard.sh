#!/bin/bash

# https://github.com/boltcard/boltcard
VERSION="v0.1.0"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install, update or uninstall Boltcard server"
 echo "bonus.boltcard.sh [on|off|newcard|menu|update|status]"
 echo "install $VERSION by default"
 exit 1
fi

# check and load raspiblitz config
# to know which network is running
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

if [ "$1" = "status" ] || [ "$1" = "menu" ]; then

  # get network info
  isInstalled=$(sudo ls /etc/systemd/system/boltcard.service 2>/dev/null | grep -c 'boltcard.service')
  localip=$(hostname -I | awk '{print $1}')
  toraddress=$(sudo cat /mnt/hdd/tor/boltcard/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)
  httpPort="59000"
  httpsPort="59001"

  if [ "$1" = "status" ]; then
    echo "installed='${isInstalled}'"
    echo "localIP='${localip}'"
    echo "httpPort='${httpPort}'"
    echo "httpsPort='${httpsPort}'"
    echo "httpsForced='0'"
    echo "httpsSelfsigned='1'"
    echo "toraddress='${toraddress}'"
    exit
  fi

fi

if [ "$1" = "newcard" ]; then

  pushd /home/boltcard/boltcard/createboltcard

  toraddress=$(sudo cat /mnt/hdd/tor/boltcard/hostname 2>/dev/null)
  (
    export $(grep -v '^#' /home/boltcard/.env | xargs)
    export HOST_DOMAIN="$toraddress"
    sudo -u boltcard /usr/local/go/bin/go build
    echo "buold"
    sudo -u boltcard ./createboltcard -enable -tx_max 50000 -day_max=500000 -name=my_card_1
  )

  echo "New card created. Scan the QR code above using the createboltcard mobile app to register your new card."
  popd
  exit 0

fi

# show info menu
if [ "$1" = "menu" ]; then
  echo "WORK IN PROGRESS"
  exit


  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    # Info with TOR
    sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title " Boltcard " --msgbox "Open in your local web browser:
http://${localip}:${httpPort}\n
https://${localip}:${httpsPort} with Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Hidden Service address for TOR Browser (see LCD for QR):\n${toraddress}
" 16 67
    sudo /home/admin/config.scripts/blitz.display.sh hide
  else
    # Info without TOR
    whiptail --title " ThunderHub " --msgbox "Open in your local web browser:
http://${localip}:${httpPort}\n
Or ttps://${localip}:${httpsPort} with Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Activate TOR to access the web interface from outside your local network.
" 15 57
  fi
  echo "please wait ..."
  exit 0
fi

# stop services
echo "making sure services are not running"
sudo systemctl stop boltcard 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL BOLTCARD ***"

  isInstalled=$(sudo ls /etc/systemd/system/boltcard.service 2>/dev/null | grep -c 'boltcard.service')
  if ! [ ${isInstalled} -eq 0 ]; then
    echo "Boltcard already installed."
  else
    ###############
    # INSTALL
    ###############

    # Preparations
    # check and install NodeJS
    /home/admin/config.scripts/bonus.go.sh on

    # create boltcard user
    sudo adduser --disabled-password --gecos "" boltcard

    # download and install
    sudo -u boltcard git clone https://github.com/boltcard/boltcard.git /home/boltcard/boltcard
    cd /home/boltcard/boltcard || exit 1
    # https://github.com/boltcard/boltcard/releases
    sudo -u boltcard git reset --hard $VERSION

    sudo -u postgres createuser -s boltcard
    sudo -u boltcard psql postgres -f create_db.sql

    # PATCH to allow configurable port
    patchFile = "/home/admin/assets/boltcard/mod.$VERSION.patch"
    if [ -f "$patchFile" ]; then
      sudo  -u boltcard git apply "$patchFile"
    fi

    go build

    ###############
    # LND PERMISSIONS
    ###############

    # make sure symlink to central app-data directory exists ***"
    echo "*** create .lnd link ***"
    sudo rm -rf /home/boltcard/.lnd  # not a symlink.. delete it silently
    # create symlink
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/boltcard/.lnd"

    # Creating lncli macaroons
    echo "*** create boltcard macaroon ***"
    lncli bakemacaroon uri:/routerrpc.Router/SendPaymentV2 > /tmp/boltcard.macaroon.hex
    xxd -r -p /tmp/boltcard.macaroon.hex /tmp/boltcard.macaroon
    chown boltcard:boltcard /tmp/boltcard.macaroon
    sudo mv /tmp/boltcard.macaroon /mnt/hdd/app-data/lnd/data/chain/bitcoin/mainnet/boltcard.macaroon
    sudo rm /tmp/boltcard.macaroon.hex /tmp/boltcard.macaroon

    #################
    # .env
    #################

  # TODO: Use PasswordB? and ensure setup sql files use the same passwords 
  DB_PASSWORD="database_password"
    echo "*** create boltcard .env file ***"
    cat > /tmp/boltcard.env <<EOF
# -----------
# DB Config
# -----------
DB_HOST=localhost
DB_PORT=5432
DB_USER=cardapp
DB_PASSWORD=$DB_PASSWORD
DB_NAME=card_db

# -----------
# LND Config
# -----------
LN_HOST=localhost
LN_PORT=10009
LN_TLS_FILE=/home/boltcard/.lnd/tls.cert
LN_MACAROON_FILE=/home/boltcard/.lnd/data/chain/bitcoin/mainnet/boltcard.macaroon
FEE_LIMIT_SAT=10

# -----------
# API Config
# -----------
HOST_DOMAIN=localhost
HOST_PORT=59000
LOG_LEVEL=PRODUCTION
AES_DECRYPT_KEY=00000000000000000000000000000000
MIN_WITHDRAW_SATS=1
MAX_WITHDRAW_SATS=1000000
EOF
    # remove symlink or old file
    sudo rm -f /home/boltcard/.env
    # move to app-data
    sudo mkdir -p /mnt/hdd/app-data/boltcard
    sudo mv /tmp/boltcard.env /mnt/hdd/app-data/boltcard/.env
    sudo chown boltcard:boltcard /mnt/hdd/app-data/boltcard/.env
    # symlink to app directory
    sudo ln -s /mnt/hdd/app-data/boltcard/.env /home/boltcard/

    ##################
    # NGINX
    ##################
    # setup nginx symlinks
    if ! [ -f /etc/nginx/sites-available/boltcard_ssl.conf ]; then
       sudo cp -f /home/admin/assets/nginx/sites-available/boltcard_ssl.conf /etc/nginx/sites-available/boltcard_ssl.conf
    fi
    if ! [ -f /etc/nginx/sites-available/boltcard_tor.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/boltcard_tor.conf /etc/nginx/sites-available/boltcard_tor.conf
    fi
    if ! [ -f /etc/nginx/sites-available/boltcard_tor_ssl.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/boltcard_tor_ssl.conf /etc/nginx/sites-available/boltcard_tor_ssl.conf
    fi
    sudo ln -sf /etc/nginx/sites-available/boltcard_ssl.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/boltcard_tor.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/boltcard_tor_ssl.conf /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl reload nginx

    # open the firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow from any to any port 59000 comment 'allow Boltcard HTTP'
    sudo ufw allow from any to any port 59001 comment 'allow Boltcard HTTPS'
    echo ""

    ##################
    # SYSTEMD SERVICE
    ##################

    echo "# Install ThunderHub systemd for ${network} on ${chain}"
    echo "
# Systemd unit for boltcard
# /etc/systemd/system/boltcard.service
[Unit]
Description=bolt card service
After=network.target network-online.target
Requires=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=10
User=boltcard
EnvironmentFile=/home/boltcard/.env
WorkingDirectory=/home/boltcard/boltcard
ExecStart=/home/boltcard/boltcard/boltcard

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/boltcard.service
    sudo systemctl enable boltcard

    # setting value in raspiblitz config
    /home/admin/config.scripts/blitz.conf.sh set boltcard "on"

    # Hidden Service for boltcard if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      # make sure to keep in sync with tor.network.sh script
      /home/admin/config.scripts/tor.onion-service.sh boltcard 80 59002 443 59003
    fi
    source <(/home/admin/_cache.sh get state)
    if [ "${state}" == "ready" ]; then
      echo "# OK - the boltcard.service is enabled, system is ready so starting service"
      sudo systemctl start boltcard
      echo "# Wait startup grace period 60 secs ... "
      sleep 60
    else
      echo "# OK - the boltcard.service is enabled, to start manually use: 'sudo systemctl start boltcard'"
    fi
  fi

  # needed for API/WebUI as signal that install ran thru 
  echo "result='OK'"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # TODO: Remove DB??

  echo "*** REMOVING BOLTCARD ***"
  # remove systemd service
  sudo systemctl disable boltcard
  sudo rm -f /etc/systemd/system/boltcard.service
  # delete user and home directory
  sudo userdel -rf boltcard
  # close ports on firewall
  sudo ufw deny 59000
  sudo ufw deny 59001

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/boltcard_ssl.conf
  sudo rm -f /etc/nginx/sites-enabled/boltcard_tor.conf
  sudo rm -f /etc/nginx/sites-enabled/boltcard_tor_ssl.conf
  sudo rm -f /etc/nginx/sites-available/boltcard_ssl.conf
  sudo rm -f /etc/nginx/sites-available/boltcard_tor.conf
  sudo rm -f /etc/nginx/sites-available/boltcard_tor_ssl.conf
  sudo nginx -t
  sudo systemctl reload nginx

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off boltcard
  fi

  echo "OK Boltcard removed."

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set boltcard "off"

  # needed for API/WebUI as signal that install ran thru 
  echo "result='OK'"
  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "WORK IN PROGRESS"
  exit

  echo "# UPDATING BOLTCARD"
  cd /home/boltcard/boltcard || exit 1
  # fetch latest master
  sudo -u boltcard git fetch
  # unset $1
  set --
  UPSTREAM=${1:-'@{u}'}
  LOCAL=$(git rev-parse @)
  REMOTE=$(git rev-parse "$UPSTREAM")

  if [ $LOCAL = $REMOTE ]; then
    TAG=$(git tag | sort -V | tail -1)
    echo "# Up-to-date on version" $TAG
  else
    echo "# Pulling latest changes..."
    sudo -u boltcard git pull -p
    echo "# Reset to the latest release tag"
    TAG=$(git tag | sort -V | tail -1)
    sudo -u boltcard git reset --hard $TAG

    # install deps
    echo "# Installing dependencies..."
    sudo -u boltcard npm install --quiet --yes
    if ! [ $? -eq 0 ]; then
        echo "# FAIL - npm install did not run correctly, aborting"
        exit 1
    fi

    # opt out of telemetry 
    echo "# opt out of telemetry .. "
    sudo -u thunderhub npx next telemetry disable

    # build nextjs
    echo "# Building application..."
    sudo -u thunderhub npm run build

    echo "# Updated to version" $TAG
  fi

  echo "# Updated to the release in https://github.com/apotdevin/thunderhub"
  echo
  echo "# Starting the ThunderHub service ... *** "
  sudo systemctl start thunderhub

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
