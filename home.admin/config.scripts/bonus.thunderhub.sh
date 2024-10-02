#!/bin/bash

# https://github.com/apotdevin/thunderhub
THUBVERSION="v0.13.31"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install, update or uninstall ThunderHub"
 echo "bonus.thunderhub.sh [install|uninstall]"
 echo "bonus.thunderhub.sh [on|off|menu|update|status]"
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

if [ "$1" = "status" ] || [ "$1" = "menu" ]; then

  # get network info
  isInstalled=$(sudo ls /etc/systemd/system/thunderhub.service 2>/dev/null | grep -c 'thunderhub.service')
  localip=$(hostname -I | awk '{print $1}')
  toraddress=$(sudo cat /mnt/hdd/tor/thunderhub/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)
  httpPort="3010"
  httpsPort="3011"

  if [ "$1" = "status" ]; then
    echo "version='${THUBVERSION}'"
    echo "installed='${isInstalled}'"
    echo "localIP='${localip}'"
    echo "httpPort='${httpPort}'"
    echo "httpsPort='${httpsPort}'"
    echo "httpsForced='0'"
    echo "httpsSelfsigned='1'"
    echo "authMethod='password_b'"
    echo "toraddress='${toraddress}'"
    exit
  fi

fi

# show info menu
if [ "$1" = "menu" ]; then

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    # Info with TOR
    sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title " ThunderHub " --msgbox "Open in your local web browser:
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
sudo systemctl stop thunderhub 2>/dev/null


# install (code & compile)
if [ "$1" = "install" ]; then

  # check if already installed
  isInstalled=$(compgen -u | grep -c thunderhub)
  if [ "${isInstalled}" != "0" ]; then
    echo "result='already installed'"
    exit 0
  fi

  echo "# *** INSTALL THUNDERHUB ***"

    # Preparations
    # check and install NodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    # create thunderhub user
    sudo adduser --system --group --home /home/thunderhub thunderhub

    # download and install
    sudo -u thunderhub git clone https://github.com/apotdevin/thunderhub.git /home/thunderhub/thunderhub
    cd /home/thunderhub/thunderhub || exit 1
    # https://github.com/apotdevin/thunderhub/releases
    sudo -u thunderhub git reset --hard $THUBVERSION

    sudo -u thunderhub /home/admin/config.scripts/blitz.git-verify.sh "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1

    echo "Running npm install ..."
    sudo rm -r /home/thunderhub/thunderhub/node_modules 2>/dev/null
    if ! sudo -u thunderhub npm install; then
      echo "FAIL - npm install did not run correctly, aborting"
      echo "result='fail npm install '"
      exit 1
    fi

    echo "# opt out of telemetry ..."
    sudo -u thunderhub npx next telemetry disable

    echo "# run build ..."
    sudo -u thunderhub npm run build

  exit 0
fi

# remove from system
if [ "$1" = "uninstall" ]; then

  # check if still active
  isActive=$(sudo ls /etc/systemd/system/thunderhub.service 2>/dev/null | grep -c 'thunderhub.service')
  if [ "${isActive}" != "0" ]; then
    echo "result='still in use'"
    exit 1
  fi

  echo "# *** UNINSTALL THUNDERHUB ***"

  # always delete user and home directory
  sudo userdel -rf thunderhub

  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check if code is already installed
  isInstalled=$(compgen -u | grep -c thunderhub)
  if [ "${isInstalled}" == "0" ]; then
    echo "# Installing code base & dependencies first .."
    /home/admin/config.scripts/bonus.thunderhub.sh install || exit 1
  fi

  echo "*** INSTALL THUNDERHUB ***"

  isActive=$(sudo ls /etc/systemd/system/thunderhub.service 2>/dev/null | grep -c 'thunderhub.service')
  if ! [ ${isActive} -eq 0 ]; then
    echo "ThunderHub already installed."
  else

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
PORT=3010

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
# disable balance sharing server side
DISABLE_BALANCE_PUSHES = true

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
ExecStart=/usr/bin/npm run start
User=thunderhub
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=journal
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
      echo "# Wait startup grace period 60 secs ... "
      sleep 60
    else
      echo "# OK - the thunderhub.service is enabled, to start manually use: 'sudo systemctl start thunderhub'"
    fi
  fi

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "*** REMOVING THUNDERHUB ***"
  # remove systemd service
  sudo systemctl disable thunderhub
  sudo rm -f /etc/systemd/system/thunderhub.service

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

  echo "OK ThunderHub deactivated"

  # disable balance sharing server side
  /home/admin/config.scripts/blitz.conf.sh set DISABLE_BALANCE_PUSHES true /mnt/hdd/app-data/thunderhub/.env.local noquotes

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set thunderhub "off"

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
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
  LOCAL=$(sudo -u thunderhub git rev-parse @)
  REMOTE=$(sudo -u thunderhub git rev-parse "$UPSTREAM")

  if [ $LOCAL = $REMOTE ]; then
    TAG=$(sudo -u thunderhub git tag | sort -V | tail -1)
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
    echo "# Installing dependencies..."
    sudo -u thunderhub npm install --quiet --yes
    if ! [ $? -eq 0 ]; then
        echo "# FAIL - npm install did not run correctly, aborting"
        exit 1
    fi

    # opt out of telemetry
    echo "# opt out of telemetry .. "
    sudo -u thunderhub npx next telemetry disable

    # disable balance sharing server side
    /home/admin/config.scripts/blitz.conf.sh set blitzapi "on" /home/admin/raspiblitz.info

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
