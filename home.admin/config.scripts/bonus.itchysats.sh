#!/bin/bash

#https://github.com/itchysats/itchysats

ITCHYSATS_USER=itchsyats
ITCHYSATS_HOME_DIR=/home/$ITCHYSATS_USER
ITCHYSATS_DATA_DIR=/mnt/hdd/app-data/itchysats
ITCHYSATS_BUILD_DIR=$ITCHYSATS_HOME_DIR/itchysats
ITCHYSATS_HTTP_PORT=8888
ITCHYSATS_HTTPS_PORT=8889
ITCHYSATS_CARGO_BIN=/home/$ITCHYSATS_USER/.cargo/bin/cargo
ITCHYSATS_BIN=$ITCHYSATS_HOME_DIR/.cargo/bin/taker


ITCHYSATS_VERSION=$( curl -s https://api.github.com/repos/itchysats/itchysats/releases | jq -r '.[].tag_name' | grep -v "rc" | head -n1)
ITCHYSATS_REPOSITORY_URL="https://github.com/itchysats/itchysats"

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

    # install Rust dependencies:
    echo
    echo "*** Installing rustup for the ItchySats user ***"
    echo
    curl --proto '=https' --tlsv1.2 -sSs https://sh.rustup.rs | sudo -u $ITCHYSATS_USER sh -s -- -y

    # download source
    sudo -u $ITCHYSATS_USER mkdir -p $ITCHYSATS_BUILD_DIR
    sudo rm -fR $ITCHYSATS_BUILD_DIR/*
    cd $ITCHYSATS_BUILD_DIR || exit 1
    sudo -u $ITCHYSATS_USER git clone $ITCHYSATS_REPOSITORY_URL
    cd itchysats || exit 1

    # checkout latest version
    sudo -u $ITCHYSATS_USER git reset --hard $ITCHYSATS_VERSION

    echo
    echo "*** Building ItchySats $ITCHYSATS_VERSION. This will take some time.."
    echo
    # build from source
    sudo -u $ITCHYSATS_USER $ITCHYSATS_CARGO_BIN install --path taker --locked || exit 1

    ###############
    # CONFIG
    ###############

    # make sure itchysats is member of lndadmin
    sudo /usr/sbin/usermod --append --groups lndadmin $ITCHYSATS_USER

    # persist settings in app-data
    sudo mkdir -p $ITCHYSATS_DATA_DIR
    sudo chown $ITCHYSATS_USER: $ITCHYSATS_DATA_DIR

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
WorkingDirectory=$ITCHYSATS_BUILD_DIR/
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
  sudo rm -fR $ITCHYSATS_BUILD_DIR
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

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off itchysats
  fi

  echo "OK ItchySats removed."

  # setting value in raspi blitz config
  sudo sed -i "s/^itchysats=.*/itchysats=off/g" /mnt/hdd/raspiblitz.conf

  exit 0
fi
