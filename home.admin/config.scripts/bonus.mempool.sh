#!/bin/bash

# https://github.com/mempool/mempool

pinnedVersion="v2.2.2"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# small config script to switch Mempool on or off"
  echo "# installs the $pinnedVersion by default"
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
  localip=$(hostname -I | awk '{print $1}')
  toraddress=$(sudo cat /mnt/hdd/tor/mempool/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then

    # TOR
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title " Mempool " --msgbox "Open in your local web browser:
http://${localip}:4080\n
https://${localip}:4081 with Fingerprint:
${fingerprint}\n
Hidden Service address for TOR Browser (QR see LCD):
${toraddress}
" 16 67
    /home/admin/config.scripts/blitz.display.sh hide
  else

    # IP + Domain
    whiptail --title " Mempool " --msgbox "Open in your local web browser:
http://${localip}:4080\n
https://${localip}:4081 with Fingerprint:
${fingerprint}\n
Activate TOR to access the web block explorer from outside your local network.
" 16 54
  fi

  echo "please wait ..."
  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^mempoolExplorer=" /mnt/hdd/raspiblitz.conf; then
  echo "mempoolExplorer=off" >> /mnt/hdd/raspiblitz.conf
fi

# status
if [ "$1" = "status" ]; then

  if [ "${mempoolExplorer}" = "on" ]; then
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
    sudo -u mempool git reset --hard $pinnedVersion

    # modify an
    #echo "# try to suppress question on statistics report .."
    #sudo sed -i "s/^}/,\"cli\": {\"analytics\": false}}/g" /home/mempool/mempool/frontend/angular.json

    sudo mariadb -e "DROP DATABASE IF EXISTS mempool;"
    sudo mariadb -e "CREATE DATABASE mempool;"
    sudo mariadb -e "GRANT ALL PRIVILEGES ON mempool.* TO 'mempool' IDENTIFIED BY 'mempool';"
    sudo mariadb -e "FLUSH PRIVILEGES;"
    mariadb -umempool -pmempool mempool < mariadb-structure.sql

    echo "# npm install for mempool explorer (frontend)"

    cd frontend
    sudo -u mempool NG_CLI_ANALYTICS=false npm install --no-optional
    if ! [ $? -eq 0 ]; then
        echo "FAIL - npm install did not run correctly, aborting"
        exit 1
    fi
    sudo -u mempool NG_CLI_ANALYTICS=false npm run build
    if ! [ $? -eq 0 ]; then
        echo "FAIL - npm run build did not run correctly, aborting"
        exit 1
    fi

    echo "# npm install for mempool explorer (backend)"

    cd ../backend/
    sudo -u mempool NG_CLI_ANALYTICS=false npm install --no-optional
    if ! [ $? -eq 0 ]; then
        echo "FAIL - npm install did not run correctly, aborting"
        exit 1
    fi
    sudo -u mempool NG_CLI_ANALYTICS=false npm run build
    if ! [ $? -eq 0 ]; then
        echo "FAIL - npm run build did not run correctly, aborting"
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
  "MEMPOOL": {
    "NETWORK": "mainnet",
    "BACKEND": "electrum",
    "HTTP_PORT": 8999,
    "API_URL_PREFIX": "/api/v1/",
    "CACHE_DIR": "/mnt/hdd/app-storage/mempool/cache",
    "POLL_RATE_MS": 2000
  },
  "CORE_RPC": {
    "USERNAME": "$RPC_USER",
    "PASSWORD": "$PASSWORD_B"
  },
  "ELECTRUM": {
    "HOST": "127.0.0.1",
    "PORT": 50002,
    "TLS_ENABLED": true
  },
  "DATABASE": {
    "ENABLED": true,
    "HOST": "localhost",
    "PORT": 3306,
    "USERNAME": "mempool",
    "PASSWORD": "mempool",
    "DATABASE": "mempool"
  },
  "STATISTICS": {
    "ENABLED": true,
    "TX_PER_SECOND_SAMPLE_PERIOD": 150
  }
}
EOF
    sudo mv /home/admin/mempool-config.json /home/mempool/mempool/backend/mempool-config.json
    sudo chown mempool:mempool /home/mempool/mempool/backend/mempool-config.json
    cd /home/mempool/mempool/frontend

    sudo mkdir -p /mnt/hdd/app-storage/mempool/cache
    sudo chown mempool:mempool /mnt/hdd/app-storage/mempool/cache

    sudo mkdir -p /var/www/mempool
    sudo rsync -av --delete dist/mempool/ /var/www/mempool/
    sudo chown -R www-data:www-data /var/www/mempool

    # open firewall
    echo "# *** Updating Firewall ***"
    sudo ufw allow 4080 comment 'mempool HTTP'
    sudo ufw allow 4081 comment 'mempool HTTPS'
    echo ""


    ##################
    # NGINX
    ##################
    # setup nginx symlinks
    sudo cp /home/admin/assets/nginx/snippets/mempool.conf /etc/nginx/snippets/mempool.conf
    sudo cp /home/admin/assets/nginx/snippets/mempool-http.conf /etc/nginx/snippets/mempool-http.conf
    sudo cp /home/admin/assets/nginx/sites-available/mempool_.conf /etc/nginx/sites-available/mempool_.conf
    sudo cp /home/admin/assets/nginx/sites-available/mempool_ssl.conf /etc/nginx/sites-available/mempool_ssl.conf
    sudo cp /home/admin/assets/nginx/sites-available/mempool_tor.conf /etc/nginx/sites-available/mempool_tor.conf
    sudo cp /home/admin/assets/nginx/sites-available/mempool_tor_ssl.conf /etc/nginx/sites-available/mempool_tor_ssl.conf

    sudo ln -sf /etc/nginx/sites-available/mempool_.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/mempool_ssl.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/mempool_tor.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/mempool_tor_ssl.conf /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl restart nginx

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

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /home/admin/mempool.service /etc/systemd/system/mempool.service
    sudo systemctl enable mempool
    echo "# OK - the mempool service is now enabled"

  else
    echo "# mempool already installed."
  fi

  # start the service if ready
  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    echo "# OK - the mempool.service is enabled, system is on ready so starting service"
    sudo systemctl start mempool
  else
    echo "# OK - the mempool.service is enabled, to start manually use: sudo systemctl start mempool"
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^mempoolExplorer=.*/mempoolExplorer=on/g" /mnt/hdd/raspiblitz.conf

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
  sudo sed -i "s/^mempoolExplorer=.*/mempoolExplorer=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/mempool.service 2>/dev/null | grep -c 'mempool.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# *** REMOVING Mempool ***"
    sudo systemctl disable mempool
    sudo rm /etc/systemd/system/mempool.service
    # delete user and home directory
    sudo userdel -rf mempool

    # remove nginx symlinks
    sudo rm -f /etc/nginx/snippets/mempool.conf
    sudo rm -f /etc/nginx/snippets/mempool-http.conf
    sudo rm -f /etc/nginx/sites-enabled/mempool_.conf
    sudo rm -f /etc/nginx/sites-enabled/mempool_ssl.conf
    sudo rm -f /etc/nginx/sites-enabled/mempool_tor.conf
    sudo rm -f /etc/nginx/sites-enabled/mempool_tor_ssl.conf
    sudo rm -f /etc/nginx/sites-available/mempool_.conf
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
  sudo ufw deny 4080
  sudo ufw deny 4081
  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "*** Checking Mempool Explorer Version ***"
  
  cd /home/mempool/mempool

  localVersion=$(git describe --tag)
  updateVersion=$(curl -s https://api.github.com/repos/mempool/mempool/releases/latest|grep tag_name|head -1|cut -d '"' -f4)

  if [ $localVersion = $updateVersion ]; then
      echo "***  You are up-to-date on version $localVersion ***" 
      sudo systemctl restart mempool 2>/dev/null
      echo "***  Restarting Mempool  ***"
  else
      # Preserve Config
      sudo cp backend/mempool-config.json /home/admin

      sudo -u mempool git fetch
      sudo -u mempool git checkout $updateVersion

      echo "# npm install for mempool explorer (backend)"

      cd /home/mempool/mempool/backend/

      sudo -u mempool NG_CLI_ANALYTICS=false npm install
      if ! [ $? -eq 0 ]; then
          echo "FAIL - npm install did not run correctly, aborting"
          exit 1
      fi
      sudo -u mempool NG_CLI_ANALYTICS=false npm run build
      if ! [ $? -eq 0 ]; then
          echo "FAIL - npm run build did not run correctly, aborting"
          exit 1
      fi

      echo "# npm install for mempool explorer (frontend)"

      cd ../frontend
      sudo -u mempool NG_CLI_ANALYTICS=false npm install
      if ! [ $? -eq 0 ]; then
          echo "FAIL - npm install did not run correctly, aborting"
          exit 1
      fi
      sudo -u mempool NG_CLI_ANALYTICS=false npm run build
      if ! [ $? -eq 0 ]; then
          echo "FAIL - npm run build did not run correctly, aborting"
          exit 1
      fi

      sudo mv /home/admin/mempool-config.json /home/mempool/mempool/backend/mempool-config.json
      sudo chown mempool:mempool /home/mempool/mempool/backend/mempool-config.json


      # Restore frontend files 
      cd /home/mempool/mempool/frontend
      sudo rsync -I -av --delete dist/mempool/ /var/www/mempool/
      sudo chown -R www-data:www-data /var/www/mempool

      cd /home/mempool/mempool

      # Reinstall the mempool configuration for nginx
      cp nginx.conf nginx-mempool.conf /etc/nginx/nginx.conf
      sudo systemctl restart nginx

      # Remove useless deps
      echo "Removing unnecessary modules..."
      npm prune --production


      echo "***  Restarting Mempool  ***"
      sudo systemctl start mempool

  fi

  # check for error
  isDead=$(sudo systemctl status mempool | grep -c 'inactive (dead)')
  if [ ${isDead} -eq 1 ]; then
    echo "error='Mempool service start failed'"
    exit 1
  else
    echo "***  Mempool version ${updateVersion} now running  ***"
  fi
  exit 0
fi

if [ "$1" = "branch" ] || [ "$1" = "pr" ]; then
  if [ -z "$2" ]; then
    echo "no pr or branch specified, aborting"
    exit 1
  else
	  cd /home/mempool/mempool
      # Preserve Config
      sudo cp backend/mempool-config.json /home/admin

	  if [ "$1" = "pr" ]; then
      echo "checking out PR $2"
      git fetch origin pull/$2/head:pr-$2
      git checkout pr-$2
    else
      echo "checking out branch $2"
      git fetch origin $2
      git checkout $2
    fi

      echo "# npm install for mempool explorer (backend)"

      cd /home/mempool/mempool/backend/

      sudo -u mempool NG_CLI_ANALYTICS=false npm install
      if ! [ $? -eq 0 ]; then
          echo "FAIL - npm install did not run correctly, aborting"
          exit 1
      fi
      sudo -u mempool NG_CLI_ANALYTICS=false npm run build
      if ! [ $? -eq 0 ]; then
          echo "FAIL - npm run build did not run correctly, aborting"
          exit 1
      fi

      echo "# npm install for mempool explorer (frontend)"

      cd ../frontend
      sudo -u mempool NG_CLI_ANALYTICS=false npm install
      if ! [ $? -eq 0 ]; then
          echo "FAIL - npm install did not run correctly, aborting"
          exit 1
      fi
      sudo -u mempool NG_CLI_ANALYTICS=false npm run build
      if ! [ $? -eq 0 ]; then
          echo "FAIL - npm run build did not run correctly, aborting"
          exit 1
      fi

      sudo mv /home/admin/mempool-config.json /home/mempool/mempool/backend/mempool-config.json
      sudo chown mempool:mempool /home/mempool/mempool/backend/mempool-config.json


      # Restore frontend files
      cd /home/mempool/mempool/frontend
      sudo rsync -I -av --delete dist/mempool/ /var/www/mempool/
      sudo chown -R www-data:www-data /var/www/mempool

      cd /home/mempool/mempool

      # Reinstall the mempool configuration for nginx
      cp nginx.conf nginx-mempool.conf /etc/nginx/nginx.conf
      sudo systemctl restart nginx

      # Remove useless deps
      echo "Removing unnecessary modules..."
      npm prune --production


      echo "***  Restarting Mempool  ***"
      sudo systemctl start mempool

  fi

  # check for error
  isDead=$(sudo systemctl status mempool | grep -c 'inactive (dead)')
  if [ ${isDead} -eq 1 ]; then
    echo "error='Mempool service start failed'"
    exit 1
  else
    echo "***  Mempool pr/branch $2 now running  ***"
  fi
  exit 0
fi


echo "error='unknown parameter'
exit 1
