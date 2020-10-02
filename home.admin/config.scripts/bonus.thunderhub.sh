#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install, update or uninstall ThunderHub"
 echo "bonus.thunderhub.sh [on|off|menu|update]"
 exit 1
fi

# check and load raspiblitz config
# to know which network is running
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then
 echo "FAIL - missing /mnt/hdd/raspiblitz.conf"
 exit 1
fi

# show info menu
if [ "$1" = "menu" ]; then

  # get network info
  localip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0' | grep 'eth0\|wlan0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  toraddress=$(sudo cat /mnt/hdd/tor/thunderhub/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    # Info with TOR
    /home/admin/config.scripts/blitz.lcd.sh qr "${toraddress}"
    whiptail --title " ThunderHub " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:3011\n
SHA1 Thumb/Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Hidden Service address for TOR Browser (see LCD for QR):\n${toraddress}
" 16 67
    /home/admin/config.scripts/blitz.lcd.sh hide
  else
    # Info without TOR
    whiptail --title " ThunderHub " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:3011\n
SHA1 Thumb/Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Activate TOR to access the web interface from outside your local network.
" 15 57
  fi
  echo "please wait ..."
  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^thunderhub=" /mnt/hdd/raspiblitz.conf; then
  echo "thunderhub=off" >> /mnt/hdd/raspiblitz.conf
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
    cd /home/thunderhub/thunderhub
    # https://github.com/apotdevin/thunderhub/releases
    sudo -u thunderhub git reset --hard v0.9.15
    echo "Running npm install and run build..."
    sudo -u thunderhub npm install
    if ! [ $? -eq 0 ]; then
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
# HODL_KEY='HODL_HODL_API_KEY'
# BASE_PATH='/basePath'

# -----------
# Interface Configs
# -----------
THEME='dark'
CURRENCY='sat'

# -----------
# Privacy Configs
# -----------
FETCH_PRICES=false
FETCH_FEES=false
HODL_HODL=false
DISABLE_LINKS=true
NO_CLIENT_ACCOUNTS=true
NO_VERSION_CHECK=true

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
    echo "*** Install ThunderHub systemd for ${network} on ${chain} ***"
    cat > /home/admin/thunderhub.service <<EOF
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

[Install]
WantedBy=multi-user.target
EOF
    sudo mv /home/admin/thunderhub.service /etc/systemd/system/thunderhub.service 
    sudo chown root:root /etc/systemd/system/thunderhub.service
    sudo systemctl enable thunderhub
    echo "OK - the ThunderHub service is now enabled"

    # setting value in raspiblitz config
    sudo sed -i "s/^thunderhub=.*/thunderhub=on/g" /mnt/hdd/raspiblitz.conf

    # Hidden Service for thunderhub if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      # make sure to keep in sync with internet.tor.sh script
      /home/admin/config.scripts/internet.hiddenservice.sh thunderhub 80 3012 443 3013
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
    /home/admin/config.scripts/internet.hiddenservice.sh off thunderhub
  fi

  echo "OK ThunderHub removed."

  # setting value in raspi blitz config
  sudo sed -i "s/^thunderhub=.*/thunderhub=off/g" /mnt/hdd/raspiblitz.conf

  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "*** UPDATING THUNDERHUB ***"
  cd /home/thunderhub/thunderhub
  # from https://github.com/apotdevin/thunderhub/blob/master/scripts/updateToLatest.sh
  # fetch latest master
  sudo -u thunderhub git fetch
  UPSTREAM=${1:-'@{u}'}
  LOCAL=$(git rev-parse @)
  REMOTE=$(git rev-parse "$UPSTREAM")
  
  if [ $LOCAL = $REMOTE ]; then
    TAG=$(git tag | sort -V | tail -1)
    echo "You are up-to-date on version" $TAG
  else
    echo "Pulling latest changes..."
    sudo -u thunderhub git pull -p

    # install deps
    echo "Installing dependencies..."
    sudo -u thunderhub npm install --quiet
    if ! [ $? -eq 0 ]; then
        echo "FAIL - npm install did not run correctly, aborting"
        exit 1
    fi

    # build nextjs
    echo "Building application..."
    sudo -u thunderhub npm run build

    TAG=$(git tag | sort -V | tail -1)
    echo "Updated to version" $TAG
  fi

  echo "*** Updated to the latest in https://github.com/apotdevin/thunderhub ***"
  echo ""
  echo "*** Starting the ThunderHub service ... *** "
  sudo systemctl start thunderhub
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
