#!/bin/bash

# https://github.com/mempool/mempool

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# small config script to switch Mempool on or off"
 echo "# bonus.mempool.sh [status|on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then

  # get status
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.mempool.sh status)

  # check if index is ready
  if [ "${isIndexed}" == "0" ]; then
    dialog --title " Blockchain Index Not Ready " --msgbox "
The Blockchain Index is still getting built.
${indexInfo}
This can take multiple hours.
      " 9 48
    exit 0
  fi

  # get network info
  localip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0' | grep 'eth0\|wlan0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  toraddress=$(sudo cat /mnt/hdd/tor/mempool/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then

    # TOR
    /home/admin/config.scripts/blitz.lcd.sh qr "${toraddress}"
    whiptail --title " Mempool " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:4081\n
SHA1 Thumb/Fingerprint:
${fingerprint}\n
Hidden Service address for TOR Browser (QR see LCD):
${toraddress}
" 16 67
    /home/admin/config.scripts/blitz.lcd.sh hide
  else

    # IP + Domain
    whiptail --title " Mempool " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:4081\n
SHA1 Thumb/Fingerprint:
${fingerprint}\n
Activate TOR to access the web block explorer from outside your local network.
" 16 54
  fi

  echo "please wait ..."
  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^Mempool=" /mnt/hdd/raspiblitz.conf; then
  echo "Mempool=off" >> /mnt/hdd/raspiblitz.conf
fi

# status
if [ "$1" = "status" ]; then

  if [ "${Mempool}" = "on" ]; then
    echo "configured=1"

    # check indexing
    source <(sudo /home/admin/config.scripts/network.txindex.sh status)
    echo "isIndexed=${isIndexed}"
    echo "indexInfo='${indexInfo}'"

    # check for error
    isDead=$(sudo systemctl status mempool | grep -c 'inactive (dead)')
    if [ ${isDead} -eq 1 ]; then
      echo "error='Service Failed'"
      exit 1
    fi

  else
    echo "configured=0"
  fi
  exit 0
fi

# stop service
echo "# making sure services are not running"
sudo systemctl stop mempool 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# *** INSTALL MEMPOOL ***"

  isInstalled=$(sudo ls /etc/systemd/system/mempool.service 2>/dev/null | grep -c 'mempool.service')
  if [ ${isInstalled} -eq 0 ]; then

    # install nodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on
    /home/admin/config.scripts/bonus.typescript.sh on
    /home/admin/config.scripts/bonus.angular_cli.sh on

    # make sure that txindex of blockchain is switched on
    /home/admin/config.scripts/network.txindex.sh on

    # make sure needed os dependencies are installed
    sudo apt-get install -y mariadb-server mariadb-client

    # add mempool user
    sudo adduser --disabled-password --gecos "" mempool

    # install mempool
    cd /home/mempool
    sudo -u mempool git clone https://github.com/mempool/mempool.git
    cd mempool

    sudo mariadb -e "DROP DATABASE mempool;"
    sudo mariadb -e "CREATE DATABASE mempool;"
    sudo mariadb -e "GRANT ALL PRIVILEGES ON mempool.* TO 'mempool' IDENTIFIED BY 'mempool';"
    sudo mariadb -e "FLUSH PRIVILEGES;"
    mariadb -umempool -pmempool mempool < mariadb-structure.sql

    sudo -u mempool git reset --hard v1.0.0
    cd frontend
    sudo -u mempool npm install
    sudo -u mempool npm run build
    cd ../backend/
    sudo -u mempool npm install
    sudo -u mempool npm run build
    sudo -u mempool touch cache.json
    if ! [ $? -eq 0 ]; then
        echo "FAIL - npm install did not run correctly, aborting"
        exit 1
    fi

    # prepare .env file
    echo "# getting RPC credentials from the ${network}.conf"

    RPC_USER=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcuser | cut -c 9-)
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)

    touch /home/admin/mempool-config.json
    sudo chmod 600 /home/admin/mempool-config.json || exit 1 
    cat > /home/admin/mempool-config.json <<EOF
{
  "ENV": "dev",
  "DB_HOST": "localhost",
  "DB_PORT": 3306,
  "DB_USER": "mempool",
  "DB_PASSWORD": "mempool",
  "DB_DATABASE": "mempool",
  "HTTP_PORT": 8999,
  "API_ENDPOINT": "/api/v1/",
  "CHAT_SSL_ENABLED": false,
  "CHAT_SSL_PRIVKEY": "",
  "CHAT_SSL_CERT": "",
  "CHAT_SSL_CHAIN": "",
  "MEMPOOL_REFRESH_RATE_MS": 500,
  "INITIAL_BLOCK_AMOUNT": 8,
  "DEFAULT_PROJECTED_BLOCKS_AMOUNT": 3,
  "KEEP_BLOCK_AMOUNT": 24,
  "BITCOIN_NODE_HOST": "127.0.0.1",
  "BITCOIN_NODE_PORT": 8332,
  "BITCOIN_NODE_USER": "$RPC_USER",
  "BITCOIN_NODE_PASS": "$PASSWORD_B",
  "BACKEND_API": "bitcoind",
  "ELECTRS_API_URL": "http://localhost:50001",
  "TX_PER_SECOND_SPAN_SECONDS": 150
}
EOF
    sudo mv /home/admin/mempool-config.json /home/mempool/mempool/backend/mempool-config.json
    sudo chown mempool:mempool /home/mempool/mempool/backend/mempool-config.json


    touch /home/admin/proxy.conf.json
    sudo chmod 600 /home/admin/proxy.conf.json || exit 1 
    cat > /home/admin/proxy.conf.json <<EOF
{
  "/api": {
    "target": "http://localhost:8999/",
    "secure": false
  },
  "/ws": {
    "target": "http://localhost:8999/",
    "secure": false,
    "ws": true
  }
}
EOF
    sudo mv /home/admin/proxy.conf.json /home/mempool/mempool/frontend/proxy.conf.json
    sudo chown mempool:mempool /home/mempool/mempool/frontend/proxy.conf.json
    cd /home/mempool/mempool/frontend
    sudo -u mempool npm run build

    sudo mkdir -p /var/www/mempool
    sudo rsync -av --delete dist/mempool/ /var/www/mempool/
    sudo chown -R www-data:www-data /var/www/mempool

    # open firewall
    echo "# *** Updating Firewall ***"
    sudo ufw allow 4081 comment 'mempool HTTPS'
    echo ""

    
    ##################
    # NGINX
    ##################
    # setup nginx symlinks
    if ! [ -f /etc/nginx/sites-available/mempool_ssl.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/mempool_ssl.conf /etc/nginx/sites-available/mempool_ssl.conf
    fi
    if ! [ -f /etc/nginx/sites-available/mempool_tor.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/mempool_tor.conf /etc/nginx/sites-available/mempool_tor.conf
    fi
    if ! [ -f /etc/nginx/sites-available/mempool_tor_ssl.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/mempool_tor_ssl.conf /etc/nginx/sites-available/mempool_tor_ssl.conf
    fi

    sudo ln -sf /etc/nginx/sites-available/mempool_ssl.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/mempool_tor.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/mempool_tor_ssl.conf /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl reload nginx

    # install service
    echo "*** Install mempool systemd ***"
    cat > /home/admin/mempool.service <<EOF
# systemd unit for Mempool

[Unit]
Description=mempool
Wants=${network}d.service
After=${network}d.service

[Service]
WorkingDirectory=/home/mempool/mempool/backend
# ExecStartPre=/usr/bin/npm run build 
ExecStart=/usr/bin/node --max-old-space-size=2048 dist/index.js
User=mempool
# Restart on failure but no more than default times (DefaultStartLimitBurst=5) every 10 minutes (600 seconds). Otherwise stop
Restart=on-failure
RestartSec=600

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /home/admin/mempool.service /etc/systemd/system/mempool.service 
    sudo systemctl enable mempool
    echo "# OK - the mempool service is now enabled"

  else 
    echo "# mempool already installed."
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^Mempool=.*/Mempool=on/g" /mnt/hdd/raspiblitz.conf
  
  echo "# needs to finish creating txindex to be functional"
  echo "# monitor with: sudo tail -n 20 -f /mnt/hdd/bitcoin/debug.log"


  # Hidden Service for Mempool if Tor is active
  source /mnt/hdd/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with internet.tor.sh script
    /home/admin/config.scripts/internet.hiddenservice.sh mempool 80 4082 443 4083
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^Mempool=.*/Mempool=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/mempool.service 2>/dev/null | grep -c 'mempool.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# *** REMOVING Mempool ***"
    sudo systemctl disable mempool
    sudo rm /etc/systemd/system/mempool.service
    # delete user and home directory
    sudo userdel -rf mempool

    # remove nginx symlinks
    sudo rm -f /etc/nginx/sites-enabled/mempool_ssl.conf
    sudo rm -f /etc/nginx/sites-enabled/mempool_tor.conf
    sudo rm -f /etc/nginx/sites-enabled/mempool_tor_ssl.conf
    sudo rm -f /etc/nginx/sites-available/mempool_ssl.conf
    sudo rm -f /etc/nginx/sites-available/mempool_tor.conf
    sudo rm -f /etc/nginx/sites-available/mempool_tor_ssl.conf
    sudo nginx -t
    sudo systemctl reload nginx

    sudo rm -rf /var/www/mempool

    # Hidden Service if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      # make sure to keep in sync with internet.tor.sh script
      /home/admin/config.scripts/internet.hiddenservice.sh off mempool
    fi

    echo "# OK Mempool removed."
  
  else 
    echo "# Mempool is not installed."
  fi

  # close ports on firewall
  sudo ufw deny 4081
  exit 0
fi

echo "error='unknown parameter'
exit 1
