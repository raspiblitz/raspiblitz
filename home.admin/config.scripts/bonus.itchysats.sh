#!/bin/bash

#https://github.com/itchysats/itchysats

ITCHYSATS_USER=itchsyats
ITCHYSATS_HOME_DIR=/home/$ITCHYSATS_USER
ITCHYSATS_DATA_DIR=/mnt/hdd/app-data/itchysats
ITCHYSATS_DOWNLOAD_DIR=$ITCHYSATS_HOME_DIR/download
ITCHYSATS_HTTP_PORT=8888
ITCHYSATS_HTTPS_PORT=8889
ITCHYSATS_BIN=$ITCHYSATS_HOME_DIR/bin/taker


ITCHYSATS_VERSION=$( curl -s https://api.github.com/repos/itchysats/itchysats/releases | jq -r '.[].tag_name' | grep -v "rc" | head -n1)

# check and load raspiblitz config
# to know which network is running
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install or uninstall itchysats"
 echo "$0 [on|off|menu|update]"
 echo "install $ITCHYSATS_VERSION by default"
 exit 1
fi

###############
#    MENU
###############

# get network info
localip=$(hostname -I | awk '{print $1}')

# show info menu
if [ "$1" = "menu" ]; then

  toraddress=$(sudo cat /mnt/hdd/tor/itchysats/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    # Info with TOR
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title " ItchySats " --msgbox "Open in your local web browser:
http://${localip}:${ITCHYSATS_HTTP_PORT}\n
https://${localip}:${ITCHYSATS_HTTPS_PORT} with Fingerprint:
${fingerprint}\n\n
Hidden Service address for TOR Browser (see LCD for QR):\n${toraddress}
" 16 67
    /home/admin/config.scripts/blitz.display.sh hide
  else
    # Info without TOR
    whiptail --title " ItchySats " --msgbox "Open in your local web browser & accept self-signed cert:
http://${localip}:${ITCHYSATS_HTTP_PORT}\n
https://${localip}:${ITCHYSATS_HTTPS_PORT} with Fingerprint:
${fingerprint}\n
Use 'itchysats' as username and your Password B to login.\n
Activate TOR to access the web interface from outside your local network.
" 15 57
  fi
  echo "please wait ..."
  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^itchysats=" /mnt/hdd/raspiblitz.conf; then
  echo "itchysats=off" >> /mnt/hdd/raspiblitz.conf
fi

# stop services
echo "making sure services are not running"
sudo systemctl stop itchysats 2>/dev/null

###############
#  SWITCH ON
###############

#check if install exists:

if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo
  echo "*** INSTALL ITCHYSATS ***"
  echo

  isInstalled=$(sudo ls /etc/systemd/system/itchysats.service 2>/dev/null | grep -c 'itchysats.service')
  if ! [ ${isInstalled} -eq 0 ]; then
    echo "ItchySats already installed."
  else 
    ###############
    # INSTALL
    ###############

    # create itchysats user:
    sudo adduser --disabled-password --gecos "" $ITCHYSATS_USER

    echo
    echo "*** Detect CPU architecture ..."
    echo
    architecture=$(uname -m)
    isAARCH64=$(uname -m | grep -c 'aarch64')
    isX86_64=$(uname -m | grep -c 'x86_64')
    if [ ${isAARCH64} -eq 0 ] && [ ${isX86_64} -eq 0 ] ; then
        echo "*** !!! FAIL !!!"
        echo "*** Can only build on aarch64 or x86_64 not on:"
        uname -m
        exit 1
    else
        echo "*** OK running on $architecture architecture."
    fi

    # create directories
    sudo -u $ITCHYSATS_USER mkdir -p $ITCHYSATS_DOWNLOAD_DIR
    sudo rm -fR $ITCHYSATS_DOWNLOAD_DIR/*
    cd $ITCHYSATS_DOWNLOAD_DIR || exit 1

    echo
    echo "*** Downloading Binary"
    echo
    binaryName="taker_${ITCHYSATS_VERSION}_Linux_${architecture}.tar"
    sudo -u $ITCHYSATS_USER wget -N https://github.com/itchysats/itchysats/releases/download/${ITCHYSATS_VERSION}/${binaryName}
    checkDownload=$(ls ${binaryName} 2>/dev/null | grep -c ${binaryName})
    if [ ${checkDownload} -eq 0 ]; then
        echo "*** !!! FAIL !!!"
        echo "*** Downloading the binary failed"
        exit 1
    fi

    # set PATH for the user
    sudo bash -c "echo 'PATH=\$PATH:/home/itchysats/bin/' >> /home/itchysats/.profile"

    # install
    echo
    echo "*** unzip binary: ${binaryName}"
    echo
    sudo -u $ITCHYSATS_USER tar -xvf ${binaryName}
    echo
    echo "*** install binary"
    echo
    sudo -u $ITCHYSATS_USER mkdir -p $ITCHYSATS_HOME_DIR/bin
    sudo install -m 0755 -o $ITCHYSATS_USER -g $ITCHYSATS_USER -t $ITCHYSATS_HOME_DIR/bin taker
    sleep 3

    installed=$(sudo -u $ITCHYSATS_USER $ITCHYSATS_BIN --help)
    if [ ${#installed} -eq 0 ]; then
        echo "error='install failed'"
        exit 1
    fi

    ###############
    # CONFIG
    ###############

    # make sure itchysats is member of lndadmin
    sudo /usr/sbin/usermod --append --groups lndadmin $ITCHYSATS_USER

    # persist settings in app-data
    sudo mkdir -p $ITCHYSATS_DATA_DIR
    sudo chown $ITCHYSATS_USER: $ITCHYSATS_DATA_DIR

    ##################
    # NGINX
    ##################
    # setup nginx symlinks
    if ! [ -f /etc/nginx/sites-available/itchysats_ssl.conf ]; then
       sudo cp -f /home/admin/assets/nginx/sites-available/itchysats_ssl.conf /etc/nginx/sites-available/itchysats_ssl.conf
    fi
    if ! [ -f /etc/nginx/sites-available/itchysats_tor.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/itchysats_tor.conf /etc/nginx/sites-available/itchysats_tor.conf
    fi
    if ! [ -f /etc/nginx/sites-available/itchysats_tor_ssl.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/itchysats_tor_ssl.conf /etc/nginx/sites-available/itchysats_tor_ssl.conf
    fi
    sudo ln -sf /etc/nginx/sites-available/itchysats_ssl.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/itchysats_tor.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/itchysats_tor_ssl.conf /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl reload nginx

    #################
    # FIREWALL
    #################

    # open the firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow from any to any port $ITCHYSATS_HTTP_PORT comment 'allow ItchySats HTTP'
    sudo ufw allow from any to any port $ITCHYSATS_HTTPS_PORT comment 'allow ItchySats HTTPS'
    echo ""

    echo
    echo "*** Getting RPC credentials from the bitcoin.conf"
    echo
    PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)

    ##################
    # SYSTEMD SERVICE
    ##################

    itchysats_network="mainnet"
    if [ "${chain}" = "test" ]; then
    	  itchysats_network="testnet"
    fi

    echo "*** Install ItchySats systemd for ${network} on ${itchysats_network}"
    echo "
# Systemd unit for ItchySats
# /etc/systemd/system/itchysats.service
[Unit]
Description=ItchySats daemon
Wants=bitcoind.service
After=bitcoind.service
[Service]
WorkingDirectory=$ITCHYSATS_HOME_DIR/
ExecStart=$ITCHYSATS_BIN --http-address=0.0.0.0:$ITCHYSATS_HTTP_PORT --password=$PASSWORD_B ${itchysats_network}
User=$ITCHYSATS_USER
Restart=always
TimeoutSec=120
RestartSec=30
Environment=ENVIRONMENT=RASPIBLITZ
[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/itchysats.service

    sudo systemctl enable itchysats

    # setting value in raspiblitz config
    sudo sed -i "s/^itchysats=.*/itchysats=on/g" /mnt/hdd/raspiblitz.conf

    # Hidden Service for ItchySats if Tor is active
    TOR_HTTP=8890
    TOR_HTTPS=8891
    if [ "${runBehindTor}" = "on" ]; then
        # make sure to keep in sync with internet.tor.sh script
        /home/admin/config.scripts/tor.onion-service.sh itchysats 80 "$TOR_HTTP" 443 "$TOR_HTTPS"
    fi

    source /home/admin/raspiblitz.info
    if [ "${state}" == "ready" ]; then
        echo "# OK - the itchysats.service is enabled, system is ready so starting service"
        sudo systemctl start itchysats
    else
        echo "# OK - the itchysats.service is enabled, to start manually use: 'sudo systemctl start itchysats'"
    fi

  fi
  exit 0
fi

###############
#  UPDATE
###############
if [ "$1" = "update" ]; then
  echo "# Updating ItchySats"

  # Remove ItchySats, keeping database
  /home/admin/config.scripts/bonus.itchysats.sh off --keep-data

  # Reinstall ItchySats witch existing database
  /home/admin/config.scripts/bonus.itchysats.sh on

  exit 0
fi

###############
#  SWITCH OFF
###############
if [ "$1" = "0" ] || [ "$1" = "off" ]; then


  # Keep or delete ItchySats data?
  deleteData=0
  if [ "$2" = "--delete-data" ]; then
    deleteData=1
  elif [ "$2" = "--keep-data" ]; then
    deleteData=0
  else
    if (whiptail --title " DELETE ITCHYSATS DATA? " --yesno "Do you want to delete\nthe ItchySats data?" 8 30); then
      deleteData=1
   else
      deleteData=0
    fi
  fi
  echo "# deleteData(${deleteData})"

  echo "*** REMOVING ITCHYSATS ***"
  # remove systemd service
  sudo systemctl disable itchysats
  sudo rm -f /etc/systemd/system/itchysats.service
  sudo rm -fR $ITCHYSATS_DOWNLOAD_DIR
  if [ ${deleteData} -eq 1 ]; then
    echo "# deleting ItchySats data"
  sudo rm -fR $ITCHYSATS_DATA_DIR
  else
    echo "# keeping ItchySats data"
  fi
  # delete user and home directory
  sudo userdel -rf $ITCHYSATS_USER
  # close ports on firewall
  sudo ufw deny $ITCHYSATS_HTTP_PORT
  sudo ufw deny $ITCHYSATS_HTTPS_PORT

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/itchysats_ssl.conf
  sudo rm -f /etc/nginx/sites-enabled/itchysats_tor.conf
  sudo rm -f /etc/nginx/sites-enabled/itchysats_tor_ssl.conf
  sudo rm -f /etc/nginx/sites-available/itchysats_ssl.conf
  sudo rm -f /etc/nginx/sites-available/itchysats_tor.conf
  sudo rm -f /etc/nginx/sites-available/itchysats_tor_ssl.conf
  sudo nginx -t
  sudo systemctl reload nginx

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off itchysats
  fi

  echo "OK ItchySats removed."

  # setting value in raspi blitz config
  sudo sed -i "s/^itchysats=.*/itchysats=off/g" /mnt/hdd/raspiblitz.conf

  exit 0
fi
