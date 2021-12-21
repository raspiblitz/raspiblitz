#!/bin/bash

# https://github.com/djbooth007/tallycoin_connect

USERNAME=tallycoin
APP_DATA_DIR=/mnt/hdd/app-data/tallycoin-connect
HOME_DIR=/home/$USERNAME
CONFIG_FILE=$APP_DATA_DIR/tallycoin_api.key
RASPIBLITZ_INFO=/home/admin/raspiblitz.info
RASPIBLITZ_CONF=/mnt/hdd/raspiblitz.conf
SERVICE_FILE=/etc/systemd/system/tallycoin-connect.service
TC_VERSION=1.7.0

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch tallycoin_connect on or off"
 echo "bonus.tallycoin-connect.sh [on|off|menu]"
 exit 1
fi

# check and load raspiblitz config to know which network is running
source $RASPIBLITZ_INFO
source $RASPIBLITZ_CONF

# show info menu
if [ "$1" = "menu" ]; then
  # get network info
  localip=$(hostname -I | awk '{print $1}')
  toraddress=$(sudo cat /mnt/hdd/tor/tallycoin-connect/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    # Info with TOR
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title " Tallycoin Connect " --msgbox "Open in your local web browser:
http://${localip}:8123\n
https://${localip}:8124 with Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Hidden Service address for TOR Browser (see LCD for QR):\n${toraddress}
" 16 67
    /home/admin/config.scripts/blitz.display.sh hide
  else
    # Info without TOR
    whiptail --title " Tallycoin Connect " --msgbox "Open in your local web browser & accept self-signed cert:
http://${localip}:8123\n
https://${localip}:8124 with Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Activate TOR to access the web interface from outside your local network.
" 15 57
  fi
  echo "please wait ..."
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c 'tallycoin_connect')
  if [ ${isInstalled} -eq 0 ]; then
    echo "*** INSTALL TALLYCOIN CONNECT ***"

    # install nodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    # add user
    sudo adduser --disabled-password --gecos "" $USERNAME

    # install tallycoin_connect
    cd $HOME_DIR
    sudo -u $USERNAME wget https://github.com/djbooth007/tallycoin_connect/archive/refs/tags/v$TC_VERSION.tar.gz
    sudo -u $USERNAME tar -xzf v$TC_VERSION.tar.gz
    sudo -u $USERNAME mv tallycoin_connect{-$TC_VERSION,}
    sudo -u $USERNAME rm v$TC_VERSION.tar.gz
    cd tallycoin_connect
    sudo -u $USERNAME cat .dockerignore | xargs rm -rf
    sudo -u $USERNAME rm .dockerignore
    sudo -u $USERNAME npm install
    if ! [ $? -eq 0 ]; then
        echo "FAIL - npm install did not run correctly, aborting"
        exit 1
    fi

    # setup config
    sudo mkdir -p $APP_DATA_DIR
    sudo chown $USERNAME:$USERNAME $APP_DATA_DIR

    if [[ ! -f "$CONFIG_FILE" ]]; then
      configFile=/home/admin/tallycoin_api.key
      touch $configFile
      sudo chmod 600 $configFile || exit 1
      passwordB=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
      passwd=$(printf $passwordB | sha256sum | tr -d ' -')
      tlsCert=$(base64 /mnt/hdd/app-data/lnd/tls.cert | tr -d '=' | tr '/+' '_-' | tr -d '\n')
      macaroon=$(base64 /mnt/hdd/app-data/lnd/data/chain/${network}/${chain}net/admin.macaroon | tr -d '=' | tr '/+' '_-' | tr -d '\n')
      echo "{\"tls_cert\":\"$tlsCert\",\"macaroon\":\"$macaroon\",\"tallycoin_passwd\":\"$passwd\"}" > $configFile

      sudo mv $configFile $CONFIG_FILE
      sudo chown $USERNAME:$USERNAME $CONFIG_FILE
    fi

    ##################
    # NGINX
    ##################
    # setup nginx symlinks
    if ! [ -f /etc/nginx/sites-available/tallycoin_connect_ssl.conf ]; then
       sudo cp -f /home/admin/assets/nginx/sites-available/tallycoin_connect_ssl.conf /etc/nginx/sites-available/tallycoin_connect_ssl.conf
    fi
    if ! [ -f /etc/nginx/sites-available/tallycoin_connect_tor.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/tallycoin_connect_tor.conf /etc/nginx/sites-available/tallycoin_connect_tor.conf
    fi
    if ! [ -f /etc/nginx/sites-available/tallycoin_connect_tor_ssl.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/tallycoin_connect_tor_ssl.conf /etc/nginx/sites-available/tallycoin_connect_tor_ssl.conf
    fi
    sudo ln -sf /etc/nginx/sites-available/tallycoin_connect_ssl.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/tallycoin_connect_tor.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/tallycoin_connect_tor_ssl.conf /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl reload nginx

    # open the firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow from any to any port 8123 comment 'allow Tallycoin Connect HTTP'
    sudo ufw allow from any to any port 8124 comment 'allow Tallycoin Connect HTTPS'
    echo ""

    ##################
    # SYSTEMD SERVICE
    ##################

    echo "# Install Tallycoin Connect systemd for ${network} on ${chain}"
    echo "
# Systemd unit for Tallycoin Connect

[Unit]
Description=Tallycoin Connect daemon
Wants=lnd.service
After=lnd.service

[Service]
WorkingDirectory=$HOME_DIR/tallycoin_connect
Environment=\"CONFIG_FILE=$CONFIG_FILE\"
ExecStart=/usr/bin/npm start
User=tallycoin
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
" | sudo tee $SERVICE_FILE
    sudo systemctl enable tallycoin-connect

    # setting value in raspiblitz config
    sudo sed -i "s/^tallycoinConnect=.*/tallycoinConnect=on/g" $RASPIBLITZ_CONF

    # Hidden Service for tallycoin-connect if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      # make sure to keep in sync with internet.tor.sh script
      /home/admin/config.scripts/internet.hiddenservice.sh tallycoin-connect 80 8125 443 8126
    fi
    source $RASPIBLITZ_INFO
    if [ "${state}" == "ready" ]; then
      echo "# OK - the tallycoin-connect.service is enabled, system is ready so starting service"
      sudo systemctl start tallycoin-connect
    else
      echo "# OK - the tallycoin-connect.service is enabled, to start manually use: 'sudo systemctl start tallycoin-connect'"
    fi
  else
    echo "*** TALLYCOIN CONNECT ALREADY INSTALLED ***"
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  isInstalled=$(sudo ls $HOME_DIR 2>/dev/null | grep -c 'tallycoin_connect')
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** UNINSTALL TALLYCOIN CONNECT ***"

    # remove systemd service
    sudo systemctl stop tallycoin-connect
    sudo systemctl disable tallycoin-connect
    sudo rm -f $SERVICE_FILE

    # close ports on firewall
    sudo ufw delete allow from any to any port 8123 comment 'allow Tallycoin Connect HTTP'
    sudo ufw delete allow from any to any port 8124 comment 'allow Tallycoin Connect HTTPS'

    # remove nginx symlinks
    sudo rm -f /etc/nginx/sites-enabled/tallycoin_connect_*
    sudo nginx -t
    sudo systemctl reload nginx

    # Hidden Service if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      /home/admin/config.scripts/internet.hiddenservice.sh off tallycoin-connect
    fi

    # remove config
    sudo rm -rf $APP_DATA_DIR

    # delete user and home directory
    sudo userdel -rf $USERNAME

    # setting value in raspi blitz config
    sudo sed -i "s/^tallycoinConnect=.*/tallycoinConnect=off/g" $RASPIBLITZ_CONF

    echo "OK TALLYCOIN CONNECT removed."
  else
    echo "*** TALLYCOIN CONNECT NOT INSTALLED ***"
  fi

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
