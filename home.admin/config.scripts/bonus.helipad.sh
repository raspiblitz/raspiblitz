#!/bin/bash

#https://github.com/Podcastindex-org/helipad
HELIPAD_VERSION="v0.2.0"
HELIPAD_USER=helipad
HELIPAD_HOME_DIR=/home/$HELIPAD_USER
HELIPAD_DATA_DIR=/mnt/hdd/app-data/helipad
HELIPAD_BUILD_DIR=$HELIPAD_HOME_DIR/helipad
HELIPAD_RELEASE_URL="https://github.com/Podcastindex-org/helipad/archive/refs/tags/$HELIPAD_VERSION.tar.gz"
HELIPAD_DB=$HELIPAD_DATA_DIR/database.db
HELIPAD_SOUND_DIR=$HELIPAD_DATA_DIR/sounds
HELIPAD_HTTP_PORT=2112
HELIPAD_HTTPS_PORT=2113
HELIPAD_MACAROON=/mnt/hdd/app-data/lnd/data/chain/bitcoin/mainnet/admin.macaroon
HELIPAD_CERT=/mnt/hdd/app-data/lnd/tls.cert
HELIPAD_CARGO_BIN=/home/$HELIPAD_USER/.cargo/bin/cargo
HELIPAD_BIN=$HELIPAD_HOME_DIR/.cargo/bin/helipad

# check and load raspiblitz config
# to know which network is running
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install, update or uninstall helipad"
 echo "$0 [on|off|menu|update]"
 echo "install $HELIPAD_VERSION by default"
 exit 1
fi

###############
#    MENU
###############

# show info menu
if [ "$1" = "menu" ]; then

  # get network info
  localip=$(hostname -I | awk '{print $1}')
  toraddress=$(sudo cat /mnt/hdd/tor/helipad/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    # Info with TOR
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title " Helipad " --msgbox "Open in your local web browser:
http://${localip}:${HELIPAD_HTTP_PORT}\n
https://${localip}:${HELIPAD_HTTPS_PORT} with Fingerprint:
${fingerprint}\n\n
Hidden Service address for TOR Browser (see LCD for QR):\n${toraddress}
" 16 67
    /home/admin/config.scripts/blitz.display.sh hide
  else
    # Info without TOR
    whiptail --title " Helipad " --msgbox "Open in your local web browser:
http://${localip}:${HELIPAD_HTTP_PORT}\n
https://${localip}:${HELIPAD_HTTPS_PORT} with Fingerprint:
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
sudo systemctl stop helipad 2>/dev/null

###############
#  SWITCH ON
###############

#check if install exists:

if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL HELIPAD ***"

  isInstalled=$(sudo ls /etc/systemd/system/helipad.service 2>/dev/null | grep -c 'helipad.service')
  if ! [ ${isInstalled} -eq 0 ]; then
    echo "Helipad already installed."
  else 
    ###############
    # INSTALL
    ###############
    
    # create helipad user:
    sudo adduser --system --group --home /home/$HELIPAD_USER $HELIPAD_USER

    # install system dependencies:
    sudo apt --assume-yes update
    sudo apt --assume-yes --show-upgraded install libssl-dev libsqlite3-dev pkg-config

    # install Rust dependencies:
    echo "*** Installing rustup for the Helipad user ***"
    curl --proto '=https' --tlsv1.2 -sSs https://sh.rustup.rs | sudo -u $HELIPAD_USER sh -s -- -y

    # download source
    sudo -u $HELIPAD_USER mkdir -p $HELIPAD_BUILD_DIR
    sudo rm -fR $HELIPAD_BUILD_DIR/*
    wget -qO- $HELIPAD_RELEASE_URL | sudo -u $HELIPAD_USER tar -zxvf- --strip-components=1 -C $HELIPAD_BUILD_DIR

    # install helipad
    sudo -u $HELIPAD_USER $HELIPAD_CARGO_BIN install --path $HELIPAD_BUILD_DIR

    # clean up
    sudo rm -R $HELIPAD_HOME_DIR/.rustup

    ###############
    # CONFIG
    ###############

    # make sure helipad is member of lndadmin
    sudo /usr/sbin/usermod --append --groups lndadmin $HELIPAD_USER

    # persist settings in app-data
    sudo mkdir -p $HELIPAD_DATA_DIR
    sudo chown $HELIPAD_USER:$HELIPAD_USER $HELIPAD_DATA_DIR
    sudo -u $HELIPAD_USER touch $HELIPAD_DB
    sudo chown $HELIPAD_USER:$HELIPAD_USER $HELIPAD_DB
    sudo mkdir -p $HELIPAD_SOUND_DIR
    sudo chown $HELIPAD_USER:$HELIPAD_USER $HELIPAD_SOUND_DIR

    ##################
    # NGINX
    ##################
    
    # setup nginx symlinks
    if ! [ -f /etc/nginx/sites-available/helipad_ssl.conf ]; then
       sudo cp -f /home/admin/assets/nginx/sites-available/helipad_ssl.conf /etc/nginx/sites-available/helipad_ssl.conf
    fi
    if ! [ -f /etc/nginx/sites-available/helipad_tor.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/helipad_tor.conf /etc/nginx/sites-available/helipad_tor.conf
    fi
    if ! [ -f /etc/nginx/sites-available/helipad_tor_ssl.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/helipad_tor_ssl.conf /etc/nginx/sites-available/helipad_tor_ssl.conf
    fi
    sudo ln -sf /etc/nginx/sites-available/helipad_ssl.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/helipad_tor.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/helipad_tor_ssl.conf /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl reload nginx

    #################
    # FIREWALL
    #################
    # open the firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow from any to any port $HELIPAD_HTTP_PORT comment 'allow Helipad HTTP'
    sudo ufw allow from any to any port $HELIPAD_HTTPS_PORT comment 'allow Helipad HTTPS'
    echo ""

    ##################
    # SYSTEMD SERVICE
    ##################
    
    echo "# Install Helipad systemd for ${network} on ${chain}"
    echo "
# Systemd unit for Helipad
# /etc/systemd/system/helipad.service
[Unit]
Description=Helipad daemon
Wants=lnd.service
After=lnd.service
PartOf=lnd.service
[Service]
WorkingDirectory=$HELIPAD_BUILD_DIR/
ExecStart=$HELIPAD_BIN $HELIPAD_HTTP_PORT
User=$HELIPAD_USER
Restart=always
TimeoutSec=120
RestartSec=30
Environment="LND_TLSCERT=$HELIPAD_CERT"
Environment="LND_ADMINMACAROON=$HELIPAD_MACAROON"
Environment="HELIPAD_DATABASE_DIR=$HELIPAD_DB"
Environment="HELIPAD_SOUND_DIR=$HELIPAD_SOUND_DIR"
LogLevelMax=4
[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/helipad.service

    sudo systemctl enable helipad

    # setting value in raspiblitz conf
    /home/admin/config.scripts/blitz.conf.sh set helipad "on"

    # Hidden Service for Helipad if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
        # make sure to keep in sync with internet.tor.sh script
        /home/admin/config.scripts/tor.onion-service.sh helipad 80 $HELIPAD_HTTP_PORT 443 $HELIPAD_HTTPS_PORT
    fi

    source /home/admin/raspiblitz.info
    if [ "${state}" == "ready" ]; then
        echo "# OK - the helipad.service is enabled, system is ready so starting service"
        sudo systemctl start helipad
    else
        echo "# OK - the helipad.service is enabled, to start manually use: 'sudo systemctl start helipad'"
    fi

  fi
  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "# Updating Helipad"

  # Remove Helipad, keeping database
  /home/admin/config.scripts/bonus.helipad.sh off --keep-data

  # Reinstall Helilpad w/ existing database
  /home/admin/config.scripts/bonus.helipad.sh on

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

 # Keep or delete Helipad database?
  deleteData=0
  if [ "$2" = "--delete-data" ]; then
    deleteData=1
  elif [ "$2" = "--keep-data" ]; then
    deleteData=0
  else
    if (whiptail --title " DELETE HELIPAD DATABASE? " --yesno "Do you want to delete\nthe Helipad database?" 8 30); then
      deleteData=1
   else
      deleteData=0
    fi
  fi
  echo "# deleteData(${deleteData})"
  echo "*** REMOVING HELIPAD ***"
  # remove systemd service
  sudo systemctl disable helipad
  sudo rm -f /etc/systemd/system/helipad.service
  sudo rm -fR $HELIPAD_BUILD_DIR
  if [ ${deleteData} -eq 1 ]; then
    echo "# deleting Helipad database"
    sudo rm -fR $HELIPAD_DATA_DIR
  else
    echo "# keeping Helipad database"
  fi
  # delete user and home directory
  sudo userdel -rf $HELIPAD_USER
  # close ports on firewall
  sudo ufw deny $HELIPAD_HTTP_PORT
  sudo ufw deny $HELIPAD_HTTPS_PORT

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/helipad_ssl.conf
  sudo rm -f /etc/nginx/sites-enabled/helipad_tor.conf
  sudo rm -f /etc/nginx/sites-enabled/helipad_tor_ssl.conf
  sudo rm -f /etc/nginx/sites-available/helipad_ssl.conf
  sudo rm -f /etc/nginx/sites-available/helipad_tor.conf
  sudo rm -f /etc/nginx/sites-available/helipad_tor_ssl.conf
  sudo nginx -t
  sudo systemctl reload nginx

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off helipad
  fi

  echo "OK Helipad removed."

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set helipad "off"

  exit 0
fi
