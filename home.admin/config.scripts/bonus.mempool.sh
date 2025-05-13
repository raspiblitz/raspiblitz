#!/bin/bash

# https://github.com/mempool/mempool

pinnedVersion="v3.0.0"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# small config script to switch Mempool on or off"
  echo "# installs the $pinnedVersion by default"
  echo "# bonus.mempool.sh [install|uninstall]"
  echo "# bonus.mempool.sh [status|on|off]"
  exit 1
fi

PGPsigner="wiz"
PGPpubkeyLink="https://github.com/wiz.gpg"
PGPpubkeyFingerprint="A394E332255A6173"

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

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then

    # Tor
    sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title " Mempool " --msgbox "Open in your local web browser:
http://${localIP}:${httpPort}\n
https://${localIP}:${httpsPort} with Fingerprint:
${fingerprint}\n
Hidden Service address for Tor Browser (QR see LCD):
${toraddress}
" 16 67
    sudo /home/admin/config.scripts/blitz.display.sh hide
  else

    # IP + Domain
    whiptail --title " Mempool " --msgbox "Open in your local web browser:
http://${localIP}:${httpPort}\n
https://${localIP}:${httpsPort} with Fingerprint:
${fingerprint}\n
Activate TOR to access the web block explorer from outside your local network.
" 16 54
  fi

  echo "please wait ..."
  exit 0
fi

# status
if [ "$1" = "status" ]; then

  echo "version='${pinnedVersion}'"

  isInstalled=$(compgen -u | grep -c mempool)
  echo "codebase=${isInstalled}"

  if [ "${mempoolExplorer}" = "on" ]; then
    echo "configured=1"

    # get network info
    localIP=$(hostname -I | awk '{print $1}')
    toraddress=$(sudo cat /mnt/hdd/tor/mempool/hostname 2>/dev/null)
    fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

    echo "installed=1"
    echo "localIP='${localIP}'"
    echo "httpPort='4080'"
    echo "httpsPort='4081'"
    echo "httpsForced='0'"
    echo "httpsSelfsigned='1'"
    echo "authMethod='none'"
    echo "fingerprint='${fingerprint}'"
    echo "toraddress='${toraddress}'"

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
    echo "installed=0"
    echo "active=0"
    echo "configured=0"
  fi
  exit 0
fi

# stop service
echo "# making sure services are not running"
sudo systemctl stop mempool 2>/dev/null

# install (code & compile)
if [ "$1" = "install" ]; then

  # check if already installed
  isInstalled=$(compgen -u | grep -c mempool)
  if [ "${isInstalled}" != "0" ]; then
    echo "result='already installed'"
    exit 0
  fi

  echo "# *** INSTALL MEMPOOL ***"

  # install nodeJS
  /home/admin/config.scripts/bonus.nodejs.sh on

  # make sure needed os dependencies are installed
  sudo apt-get install -y mariadb-server mariadb-client

  # stop mariadb - will be activated when switched "on"
  sudo systemctl stop mariadb
  sudo systemctl disable mariadb

  # add mempool user
  sudo adduser --system --group --home /home/mempool mempool

  # install mempool
  cd /home/mempool || exit 1
  sudo -u mempool git clone https://github.com/mempool/mempool.git
  cd mempool || exit 1
  sudo -u mempool git reset --hard $pinnedVersion
  sudo -u mempool /home/admin/config.scripts/blitz.git-verify.sh "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1

  echo "# npm install for mempool explorer (frontend)"

  cd frontend || exit 1
  if ! sudo -u mempool NG_CLI_ANALYTICS=false npm ci; then
    echo "FAIL - npm install did not run correctly, aborting"
    exit 1
  fi
  if ! sudo -u mempool NG_CLI_ANALYTICS=false npm run build; then
    echo "FAIL - npm run build did not run correctly, aborting (1)"
    exit 1
  fi

  echo "# install Rust for mempool"
  sudo -u mempool curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo -u mempool sh -s -- -y

  echo "# npm install for mempool explorer (backend)"

  cd ../backend/ || exit 1
  if ! sudo -u mempool NG_CLI_ANALYTICS=false PATH=$PATH:/home/mempool/.cargo/bin npm ci; then
    echo "# FAIL - npm install did not run correctly, aborting"
    echo "result='failed npm install'"
    exit 1
  fi
  if ! sudo -u mempool NG_CLI_ANALYTICS=false PATH=$PATH:/home/mempool/.cargo/bin npm run build; then
    echo "# FAIL - npm run build did not run correctly, aborting (2)"
    echo "result='failed npm run build'"
    exit 1
  fi

  exit 0
fi

# remove from system
if [ "$1" = "uninstall" ]; then

  # check if still active
  isActive=$(sudo ls /etc/systemd/system/mempool.service 2>/dev/null | grep -c 'mempool.service')
  if [ "${isActive}" != "0" ]; then
    echo "result='still in use'"
    exit 1
  fi

  echo "# *** UNINSTALL MEMPOOL ***"

  # always delete user and home directory
  sudo userdel -rf mempool

  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  isInstalled=$(compgen -u | grep -c mempool)
  if [ "${isInstalled}" == "0" ]; then
    echo "# Install code base first ...."
    if ! /home/admin/config.scripts/bonus.mempool.sh install; then
      /home/admin/config.scripts/bonus.mempool.sh uninstall 2>/dev/null
      echo "FAIL - install did not run correctly, aborting"
      exit 1
    fi
  fi

  # check if /home/mempool/mempool exists
  if [ ! -d "/home/mempool/mempool" ]; then
    /home/admin/config.scripts/bonus.mempool.sh uninstall 2>/dev/null
    echo "error='mempool code base install failed'"
    echo "# please run manually first: /home/admin/config.scripts/bonus.mempool.sh install"
    exit 1
  fi

  echo "# *** Activate MEMPOOL ***"

  # make sure mariadb is running
  sudo systemctl enable mariadb 2>/dev/null
  sudo systemctl start mariadb 2>/dev/null

  isActive=$(sudo ls /etc/systemd/system/mempool.service 2>/dev/null | grep -c 'mempool.service')
  if [ ${isActive} -eq 0 ]; then

    # make sure that txindex of blockchain is switched on
    /home/admin/config.scripts/network.txindex.sh on

    sudo mariadb -e "DROP DATABASE IF EXISTS mempool;"
    sudo mariadb -e "CREATE DATABASE mempool;"
    sudo mariadb -e "GRANT ALL PRIVILEGES ON mempool.* TO 'mempool' IDENTIFIED BY 'mempool';"
    sudo mariadb -e "FLUSH PRIVILEGES;"
    if [ -f "mariadb-structure.sql" ]; then
      mariadb -umempool -pmempool mempool <mariadb-structure.sql
    fi

    # prepare .env file
    echo "# getting RPC credentials from the ${network}.conf"

    RPC_USER=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcuser | cut -c 9-)
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)

    sudo rm /var/cache/raspiblitz/mempool-config.json 2>/dev/null
    touch /var/cache/raspiblitz/mempool-config.json
    chmod 600 /var/cache/raspiblitz/mempool-config.json || exit 1
    cat >/var/cache/raspiblitz/mempool-config.json <<EOF
{
  "MEMPOOL": {
    "NETWORK": "mainnet",
    "BACKEND": "electrum",
    "HTTP_PORT": 8999,
    "API_URL_PREFIX": "/api/v1/",
    "CACHE_DIR": "/mnt/hdd/app-storage/mempool/cache",
    "POLL_RATE_MS": 2000,
    "STDOUT_LOG_MIN_PRIORITY": "info"
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
    "SOCKET": "/var/run/mysqld/mysqld.sock",
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
    sudo mv /var/cache/raspiblitz/mempool-config.json /home/mempool/mempool/backend/mempool-config.json
    sudo chown mempool:mempool /home/mempool/mempool/backend/mempool-config.json
    cd /home/mempool/mempool/frontend || exit 1

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
    cat >/var/cache/raspiblitz/mempool.service <<EOF
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
LogLevelMax=4

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /var/cache/raspiblitz/mempool.service /etc/systemd/system/mempool.service
    sudo systemctl enable mempool
    echo "# OK - the mempool service is now enabled"

  else
    echo "# mempool already installed."
  fi

  # start the service if ready
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# OK - the mempool.service is enabled, system is on ready so starting service"
    sudo systemctl start mempool
    sleep 10

    # check install success by testing backend
    isWorking=$(sudo systemctl status mempool | grep -c "Active: active")
    if [ ${isWorking} -lt 1 ]; then
      # signal an error to WebUI
      echo "result='mempool service not active'"
      exit 1
    fi

  else
    echo "# OK - the mempool.service is enabled, to start manually use: sudo systemctl start mempool"
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set mempoolExplorer "on"

  echo "# needs to finish creating txindex to be functional"
  echo "# monitor with: sudo tail -n 20 -f /mnt/hdd/bitcoin/debug.log"

  # Hidden Service for Mempool if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with tor.network.sh script
    /home/admin/config.scripts/tor.onion-service.sh mempool 80 4082 443 4083
  fi

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0

fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # always remove nginx symlinks
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

  # remove Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with tor.network.sh script
    /home/admin/config.scripts/tor.onion-service.sh off mempool
  fi

  # always close ports on firewall
  sudo ufw deny 4080
  sudo ufw deny 4081

  isInstalled=$(sudo ls /etc/systemd/system/mempool.service 2>/dev/null | grep -c 'mempool.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# *** REMOVING Mempool ***"
    sudo systemctl disable mempool
    sudo rm /etc/systemd/system/mempool.service
    echo "# OK Mempool removed."

  else
    echo "# Mempool is not installed."
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set mempoolExplorer "off"

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "*** Checking Mempool Explorer Version ***"

  cd /home/mempool/mempool || exit 1

  localVersion=$(sudo -u mempool git describe --tag)
  updateVersion=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s https://api.github.com/repos/mempool/mempool/releases/latest | grep tag_name | head -1 | cut -d '"' -f4)

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

    echo "# install Rust for mempool"
    sudo -u mempool curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo -u mempool sh -s -- -y

    cd /home/mempool/mempool/backend/ || exit 1
    if ! sudo -u mempool NG_CLI_ANALYTICS=false PATH=$PATH:/home/mempool/.cargo/bin npm ci; then
      echo "FAIL - npm install did not run correctly, aborting"
      exit 1
    fi
    if ! sudo -u mempool NG_CLI_ANALYTICS=false PATH=$PATH:/home/mempool/.cargo/bin npm run build; then
      echo "FAIL - npm run build did not run correctly, aborting (3)"
      exit 1
    fi

    echo "# npm install for mempool explorer (frontend)"

    cd ../frontend || exit 1
    if ! sudo -u mempool NG_CLI_ANALYTICS=false npm ci; then
      echo "FAIL - npm install did not run correctly, aborting"
      exit 1
    fi
    if ! sudo -u mempool NG_CLI_ANALYTICS=false npm run build; then
      echo "FAIL - npm run build did not run correctly, aborting (4)"
      exit 1
    fi

    sudo mv /home/admin/mempool-config.json /home/mempool/mempool/backend/mempool-config.json
    sudo chown mempool:mempool /home/mempool/mempool/backend/mempool-config.json

    # Restore frontend files
    cd /home/mempool/mempool/frontend || exit 1
    sudo rsync -I -av --delete dist/mempool/ /var/www/mempool/
    sudo chown -R www-data:www-data /var/www/mempool

    cd /home/mempool/mempool || exit 1

    # Remove useless deps
    echo "Removing unnecessary modules..."
    sudo -u mempool npm prune --production

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

echo "error='unknown parameter'"
exit 1
