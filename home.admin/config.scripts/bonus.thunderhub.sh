#!/bin/bash

# https://github.com/apotdevin/thunderhub
THUBVERSION="v0.12.31"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install, update or uninstall ThunderHub"
 echo "bonus.thunderhub.sh [on|off|menu|update]"
 echo "install $THUBVERSION by default"
 exit 1
fi

PGPsigner="apotdevin"
PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
PGPpubkeyFingerprint="4403F1DFBE779457"

# check and load raspiblitz config
# to know which network is running
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then

  # get network info
  localip=$(hostname -I | awk '{print $1}')
  toraddress=$(sudo cat /mnt/hdd/tor/thunderhub/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    # Info with TOR
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title " ThunderHub " --msgbox "Open in your local web browser:
http://${localip}:3010\n
https://${localip}:3011 with Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Hidden Service address for TOR Browser (see LCD for QR):\n${toraddress}
" 16 67
    /home/admin/config.scripts/blitz.display.sh hide
  else
    # Info without TOR
    whiptail --title " ThunderHub " --msgbox "Open in your local web browser & accept self-signed cert:
http://${localip}:3010\n
https://${localip}:3011 with Fingerprint:
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
sudo systemctl stop thunderhub 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL THUNDERHUB ***"

  isInstalled=$(sudo ls /etc/systemd/system/thunderhub.service 2>/dev/null | grep -c 'thunderhub.service')
  if ! [ ${isInstalled} -eq 0 ]; then
    echo "ThunderHub already installed."
  else
    ###############
    # INSTALL
    ###############

    # Preparations
    # check and install NodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    # create thunderhub user
    sudo adduser --disabled-password --gecos "" thunderhub

    # download and install
    sudo -u thunderhub git clone https://github.com/apotdevin/thunderhub.git /home/thunderhub/thunderhub
    cd /home/thunderhub/thunderhub || exit 1
    # https://github.com/apotdevin/thunderhub/releases
    sudo -u thunderhub git reset --hard $THUBVERSION

    sudo -u thunderhub /home/admin/config.scripts/blitz.git-verify.sh \
     "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1

    # opt out of telemetry 
    sudo -u thunderhub npx next telemetry disable
    echo "Running npm install and run build..."
    if ! sudo -u thunderhub npm install; then
      echo "FAIL - npm install did not run correctly, aborting"
      exit 1
    fi

    sudo -u thunderhub npm run build

    ###############
    # CONFIG
    ###############

    # make sure symlink to central app-data directory exists ***"
    sudo rm -rf /home/thunderhub/.lnd  # not a symlink.. delete it silently
    # create symlink
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/thunderhub/.lnd"

    # make sure thunderhub is member of lndadmin
    sudo /usr/sbin/usermod --append --groups lndadmin thunderhub

    # persist settings in app-data
    sudo mkdir -p /mnt/hdd/app-data/thunderhub

    #################
    # .env
    #################

    echo "*** create ThunderHub .env file ***"
    cat > /home/admin/thunderhub.env <<EOF
# -----------
# Server Configs
# -----------
LOG_LEVEL='debug'
TOR_PROXY_SERVER='socks://127.0.0.1:9050'

# -----------
# Interface Configs
# -----------
THEME='dark'
CURRENCY='sat'

# -----------
# Privacy Configs
# -----------
FETCH_PRICES = false
FETCH_FEES = false
DISABLE_LINKS = true
DISABLE_LNMARKETS = true
NO_VERSION_CHECK = true
# https://nextjs.org/telemetry#how-do-i-opt-out
NEXT_TELEMETRY_DISABLED=1

# -----------
# Account Configs
# -----------
ACCOUNT_CONFIG_PATH='/home/thunderhub/thubConfig.yaml'
EOF
    # remove symlink or old file
    sudo rm -f /home/thunderhub/thunderhub/.env.local
    # move to app-data
    sudo mv /home/admin/thunderhub.env /mnt/hdd/app-data/thunderhub/.env.local
    sudo chown thunderhub:thunderhub /mnt/hdd/app-data/thunderhub/.env.local
    # symlink to app directory
    sudo ln -s /mnt/hdd/app-data/thunderhub/.env.local /home/thunderhub/thunderhub/

    ##################
    # thubConfig.yaml
    ##################

    echo "*** create thubConfig.yaml ***"
    # use Password_B
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
    cat > /home/admin/thubConfig.yaml <<EOF
masterPassword: '$PASSWORD_B' # Default password unless defined in account
accounts:
  - name: '$hostname'
    serverUrl: '127.0.0.1:10009'
    macaroonPath: '/home/thunderhub/.lnd/data/chain/${network}/${chain}net/admin.macaroon'
    certificatePath: '/home/thunderhub/.lnd/tls.cert'
EOF
    # remove symlink or old file
    sudo rm -f /home/thunderhub/thubConfig.yaml
    # move to app-data
    sudo mv /home/admin/thubConfig.yaml /mnt/hdd/app-data/thunderhub/thubConfig.yaml
    # secure
    sudo chown thunderhub:thunderhub /mnt/hdd/app-data/thunderhub/thubConfig.yaml
    sudo chmod 600 /mnt/hdd/app-data/thunderhub/thubConfig.yaml | exit 1
    # symlink
    sudo ln -s /mnt/hdd/app-data/thunderhub/thubConfig.yaml /home/thunderhub/

    ##################
    # NGINX
    ##################
    # setup nginx symlinks
    if ! [ -f /etc/nginx/sites-available/thub_ssl.conf ]; then
       sudo cp -f /home/admin/assets/nginx/sites-available/thub_ssl.conf /etc/nginx/sites-available/thub_ssl.conf
    fi
    if ! [ -f /etc/nginx/sites-available/thub_tor.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/thub_tor.conf /etc/nginx/sites-available/thub_tor.conf
    fi
    if ! [ -f /etc/nginx/sites-available/thub_tor_ssl.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/thub_tor_ssl.conf /etc/nginx/sites-available/thub_tor_ssl.conf
    fi
    sudo ln -sf /etc/nginx/sites-available/thub_ssl.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/thub_tor.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/thub_tor_ssl.conf /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl reload nginx

    # open the firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow from any to any port 3010 comment 'allow ThunderHub HTTP'
    sudo ufw allow from any to any port 3011 comment 'allow ThunderHub HTTPS'
    echo ""

    ##################
    # SYSTEMD SERVICE
    ##################

    echo "# Install ThunderHub systemd for ${network} on ${chain}"
    echo "
# Systemd unit for thunderhub
# /etc/systemd/system/thunderhub.service

[Unit]
Description=ThunderHub daemon
Wants=lnd.service
After=lnd.service

[Service]
WorkingDirectory=/home/thunderhub/thunderhub
ExecStart=/usr/bin/npm run start -- -p 3010
User=thunderhub
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/thunderhub.service
    sudo systemctl enable thunderhub

    # setting value in raspiblitz config
    /home/admin/config.scripts/blitz.conf.sh set thunderhub "on"

    # Hidden Service for thunderhub if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      # make sure to keep in sync with tor.network.sh script
      /home/admin/config.scripts/tor.onion-service.sh thunderhub 80 3012 443 3013
    fi
    source <(/home/admin/_cache.sh get state)
    if [ "${state}" == "ready" ]; then
      echo "# OK - the thunderhub.service is enabled, system is ready so starting service"
      sudo systemctl start thunderhub
    else
      echo "# OK - the thunderhub.service is enabled, to start manually use: 'sudo systemctl start thunderhub'"
    fi
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "*** REMOVING THUNDERHUB ***"
  # remove systemd service
  sudo systemctl disable thunderhub
  sudo rm -f /etc/systemd/system/thunderhub.service
  # delete user and home directory
  sudo userdel -rf thunderhub
  # close ports on firewall
  sudo ufw deny 3010
  sudo ufw deny 3011

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/thub_ssl.conf
  sudo rm -f /etc/nginx/sites-enabled/thub_tor.conf
  sudo rm -f /etc/nginx/sites-enabled/thub_tor_ssl.conf
  sudo rm -f /etc/nginx/sites-available/thub_ssl.conf
  sudo rm -f /etc/nginx/sites-available/thub_tor.conf
  sudo rm -f /etc/nginx/sites-available/thub_tor_ssl.conf
  sudo nginx -t
  sudo systemctl reload nginx

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off thunderhub
  fi

  echo "OK ThunderHub removed."

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set thunderhub "off"

  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "# UPDATING THUNDERHUB"
  cd /home/thunderhub/thunderhub || exit 1
  # from https://github.com/apotdevin/thunderhub/blob/master/scripts/updateToLatest.sh
  # fetch latest master
  sudo -u thunderhub git fetch
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
    sudo -u thunderhub git pull -p
    echo "# Reset to the latest release tag"
    TAG=$(git tag | sort -V | tail -1)
    sudo -u thunderhub git reset --hard $TAG
    sudo -u thunderhub /home/admin/config.scripts/blitz.git-verify.sh \
     "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1

    # install deps
    # opt out of telemetry 
    sudo -u thunderhub npx next telemetry disable
    echo "# Installing dependencies..."
    sudo -u thunderhub npm install --quiet
    if ! [ $? -eq 0 ]; then
        echo "# FAIL - npm install did not run correctly, aborting"
        exit 1
    fi

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
