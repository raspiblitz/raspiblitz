#!/bin/bash

# https://github.com/janoside/btc-rpc-explorer
# ~/.config/btc-rpc-explorer.env
# https://github.com/janoside/btc-rpc-explorer/blob/master/.env-sample

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# small config script to switch BTC-RPC-explorer on or off"
 echo "# bonus.btc-rpc-explorer.sh [install|uninstall]"
 echo "# bonus.btc-rpc-explorer.sh [status|on|off]"
 echo "# bonus.btc-rpc-explorer.sh prestart"
 exit 1
fi

PGPsigner="janoside"
PGPpubkeyLink="https://github.com/janoside.gpg"
PGPpubkeyFingerprint="70C0B166321C0AF8"

source /mnt/hdd/raspiblitz.conf

##########################
# MENU
#########################

# show info menu
if [ "$1" = "menu" ]; then

  # get status
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.btc-rpc-explorer.sh status)

  # check if index is ready
  if [ "${isIndexed}" == "0" ]; then
    dialog --title " Blockchain Index Not Ready " --msgbox "
The Blockchain Index is still getting built.
${indexInfo}
This can take multiple hours.
      " 9 48
    exit 0
  fi

  # check if password protected
  isBitcoinWalletOff=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep -c "^disablewallet=1")
  passwordInfo=""
  if [ "${isBitcoinWalletOff}" != "1" ]; then
    passwordInfo="Login is 'admin' with your Password B"
  fi

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then

    # TOR
    sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title " BTC-RPC-Explorer " --msgbox "Open in your local web browser:
http://${localIP}:3020\n
https://${localIP}:3021 with Fingerprint:
${fingerprint}\n
${passwordInfo}\n
Hidden Service address for TOR Browser (QR see LCD):
${toraddress}
" 16 67
    sudo /home/admin/config.scripts/blitz.display.sh hide
  else

    # IP + Domain
    whiptail --title " BTC-RPC-Explorer " --msgbox "Open in your local web browser:
http://${localIP}:3020\n
https://${localIP}:3021 with Fingerprint:
${fingerprint}\n
${passwordInfo}\n
Activate TOR to access the web block explorer from outside your local network.
" 16 54
  fi

  echo "please wait ..."
  exit 0
fi

# status
if [ "$1" = "status" ]; then

  if [ "${BTCRPCexplorer}" = "on" ]; then
    echo "configured=1"

    installed=$(sudo ls /etc/systemd/system/btc-rpc-explorer.service 2>/dev/null | grep -c 'btc-rpc-explorer.service')
    echo "installed=${installed}"

    # get network info
    localIP=$(hostname -I | awk '{print $1}')
    toraddress=$(sudo cat /mnt/hdd/tor/btc-rpc-explorer/hostname 2>/dev/null)
    fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

    authMethod="user_admin_password_b"
    isBitcoinWalletOff=$(cat /mnt/hdd/bitcoin/bitcoin.conf | grep -c "^disablewallet=1")
    if [ "${isBitcoinWalletOff}" == "1" ]; then
      authMethod="none"
    fi

    echo "localIP='${localIP}'"
    echo "httpPort='3020'"
    echo "httpsPort='3021'"
    echo "httpsForced='0'"
    echo "httpsSelfsigned='1'"
    echo "authMethod='${authMethod}'"
    echo "toraddress='${toraddress}'"
    echo "fingerprint='${fingerprint}'"

    # check indexing
    source <(sudo /home/admin/config.scripts/network.txindex.sh status)
    echo "isIndexed=${isIndexed}"
    echo "indexInfo='${indexInfo}'"

    # check for error
    isDead=$(sudo systemctl status btc-rpc-explorer | grep -c 'inactive (dead)')
    if [ ${isDead} -eq 1 ]; then
      echo "error='Service Failed'"
      exit 1
    fi

  else
    echo "configured=0"
    echo "installed=0"
  fi
  exit 0
fi

##########################
# PRESTART
# - will be called as prestart by systemd service (as user btcrpcexplorer)
#########################

if [ "$1" = "prestart" ]; then

  # users need to be `btcrpcexplorer` so that it can be run by systemd as prestart (no SUDO available)
  if [ "$USER" != "btcrpcexplorer" ]; then
    echo "# FAIL: run as user btcrpcexplorer"
    exit 1
  fi

  echo "## btc-rpc-explorer.service PRESTART CONFIG"
  echo "# --> /home/btcrpcexplorer/.config/btc-rpc-explorer.env"

  # check if electrs is installed & running
  if [ "${ElectRS}" == "on" ]; then

    # CHECK THAT ELECTRS INDEX IS BUILD (WAITLOOP)
    # electrs listening in port 50001 means index is build 
    # Use flags: t = tcp protocol only  /  a = list all connection states (includes LISTEN)  /  n = don't resolve names => no dns spam
    isElectrumReady=$(netstat -tan | grep -c "50001")
    if [ "${isElectrumReady}" == "0" ]; then
      echo "# electrs is ON but not ready .. might still building index - kick systemd service into fail/wait/restart"
      exit 1
    fi
    echo "# electrs is ON .. and ready (${isElectrumReady})"

    # CHECK THAT ELECTRS IS PART OF CONFIG
    echo "# updating BTCEXP_ADDRESS_API=electrumx"
    sed -i 's/^BTCEXP_ADDRESS_API=.*/BTCEXP_ADDRESS_API=electrumx/g' /home/btcrpcexplorer/.config/btc-rpc-explorer.env

  else

    # ELECTRS=OFF --> MAKE SURE IT IS NOT CONNECTED
    echo "# updating BTCEXP_ADDRESS_API=none"
    sed -i 's/^BTCEXP_ADDRESS_API=.*/BTCEXP_ADDRESS_API=none/g' /home/btcrpcexplorer/.config/btc-rpc-explorer.env

  fi

  #  UPDATE RPC PASSWORD
  RPCPASSWORD=$(cat /mnt/hdd/${network}/${network}.conf | grep "^rpcpassword=" | cut -d "=" -f2)
  echo "# updating BTCEXP_BITCOIND_PASS=${RPCPASSWORD}"
  sed -i "s/^BTCEXP_BITCOIND_PASS=.*/BTCEXP_BITCOIND_PASS=${RPCPASSWORD}/g" /home/btcrpcexplorer/.config/btc-rpc-explorer.env

  # WALLET PROTECTION (only if Bitcoin has wallet active protect BTC-RPC-Explorer with additional passwordB)
  isBitcoinWalletOff=$(cat /mnt/hdd/${network}/${network}.conf | grep -c "^disablewallet=1")
  if [ "${isBitcoinWalletOff}" == "1" ]; then
    echo "# updating BTCEXP_BASIC_AUTH_PASSWORD= --> no password needed because wallet is disabled"
    sed -i "s/^BTCEXP_BASIC_AUTH_PASSWORD=.*/BTCEXP_BASIC_AUTH_PASSWORD=/g" /home/btcrpcexplorer/.config/btc-rpc-explorer.env
  else
    echo "# updating BTCEXP_BASIC_AUTH_PASSWORD=${RPCPASSWORD} --> enable password to protect wallet"
    sed -i "s/^BTCEXP_BASIC_AUTH_PASSWORD=.*/BTCEXP_BASIC_AUTH_PASSWORD=${RPCPASSWORD}/g" /home/btcrpcexplorer/.config/btc-rpc-explorer.env
  fi

  exit 0 # exit with clean code
fi

# stop service (for all calls below)
echo "# making sure services are not running"
sudo systemctl stop btc-rpc-explorer 2>/dev/null

# install (code & compile)
if [ "$1" = "install" ]; then

  # check if already installed
  isInstalled=$(compgen -u | grep -c btcrpcexplorer)
  if [ "${isInstalled}" != "0" ]; then
    echo "result='already installed'"
    exit 0
  fi

  echo "# *** INSTALL BTC-RPC-EXPLORER ***"

  # install nodeJS
  /home/admin/config.scripts/bonus.nodejs.sh on

  # add btcrpcexplorer user
  sudo adduser --disabled-password --gecos "" btcrpcexplorer

  # install btc-rpc-explorer
  cd /home/btcrpcexplorer
  sudo -u btcrpcexplorer git clone https://github.com/janoside/btc-rpc-explorer.git
  cd btc-rpc-explorer
  sudo -u btcrpcexplorer git reset --hard v3.3.0
  sudo -u btcrpcexplorer /home/admin/config.scripts/blitz.git-verify.sh "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1
  sudo -u btcrpcexplorer npm install
  if ! [ $? -eq 0 ]; then
      echo "FAIL - npm install did not run correctly, aborting"
      echo "result='fail npm install'"
      exit 1
  fi

  exit 0
fi

# remove from system
if [ "$1" = "uninstall" ]; then

  # check if still active
  isActive=$(sudo ls /etc/systemd/system/btc-rpc-explorer.service 2>/dev/null | grep -c 'btc-rpc-explorer.service')
  if [ "${isActive}" != "0" ]; then
    echo "result='still in use'"
    exit 1
  fi

  echo "# *** UNINSTALL BTC-RPC-EXPLORER ***"

  # always delete user and home directory
  sudo userdel -rf btcrpcexplorer
  
  exit 0
fi

##########################
# ON
#########################

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check if code is already installed
  isInstalled=$(compgen -u | grep -c btcrpcexplorer)
  if [ "${isInstalled}" == "0" ]; then
    echo "# Installing code base & dependencies first .."
    /home/admin/config.scripts/bonus.btc-rpc-explorer.sh install || exit 1
  fi

  echo "# *** ACTIVATE BTC-RPC-EXPLORER ***"

  isInstalled=$(sudo ls /etc/systemd/system/btc-rpc-explorer.service 2>/dev/null | grep -c 'btc-rpc-explorer.service')
  if [ ${isInstalled} -eq 0 ]; then

    # make sure that txindex of blockchain is switched on
    /home/admin/config.scripts/network.txindex.sh on

    # prepare .env file
    echo "# getting RPC credentials from the ${network}.conf"

    RPC_USER=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcuser | cut -c 9-)
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)

    touch /var/cache/raspiblitz/btc-rpc-explorer.env
    chmod 600 /var/cache/raspiblitz/btc-rpc-explorer.env || exit 1
    cat > /var/cache/raspiblitz/btc-rpc-explorer.env <<EOF
# Host/Port to bind to
# Defaults: shown
BTCEXP_HOST=0.0.0.0
BTCEXP_PORT=3020
# Bitcoin RPC Credentials (URI -OR- HOST/PORT/USER/PASS)
# Defaults:
#   - [host/port]: 127.0.0.1:8332
#   - [username/password]: none
#   - cookie: '~/.bitcoin/.cookie'
#   - timeout: 5000 (ms)
BTCEXP_BITCOIND_HOST=127.0.0.1
BTCEXP_BITCOIND_PORT=8332
BTCEXP_BITCOIND_USER=$RPC_USER
BTCEXP_BITCOIND_PASS=$PASSWORD_B
#BTCEXP_BITCOIND_COOKIE=/path/to/bitcoind/.cookie
BTCEXP_BITCOIND_RPC_TIMEOUT=10000
# Privacy mode disables:
# Exchange-rate queries, IP-geolocation queries
# Default: false
BTCEXP_PRIVACY_MODE=true
# Password protection for site via basic auth (enter any username, only the password is checked)
# Default: none
#BTCEXP_BASIC_AUTH_PASSWORD=$PASSWORD_B
# Select optional "address API" to display address tx lists and balances
# Options: electrumx, blockchain.com, blockchair.com, blockcypher.com
# If electrumx set, the BTCEXP_ELECTRUMX_SERVERS variable must also be
# set.
# Default: none
BTCEXP_ADDRESS_API=none
BTCEXP_ELECTRUMX_SERVERS=tcp://127.0.0.1:50001
EOF
    sudo -u btcrpcexplorer mkdir /home/btcrpcexplorer/.config
    sudo mv /var/cache/raspiblitz/btc-rpc-explorer.env /home/btcrpcexplorer/.config/btc-rpc-explorer.env
    sudo chown btcrpcexplorer:btcrpcexplorer /home/btcrpcexplorer/.config/btc-rpc-explorer.env

    # open firewall
    echo "# *** Updating Firewall ***"
    sudo ufw allow 3020 comment 'btc-rpc-explorer HTTP'
    sudo ufw allow 3021 comment 'btc-rpc-explorer HTTPS'
    echo ""

    ##################
    # NGINX
    ##################
    # setup nginx symlinks
    if ! [ -f /etc/nginx/sites-available/btcrpcexplorer_ssl.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/btcrpcexplorer_ssl.conf /etc/nginx/sites-available/btcrpcexplorer_ssl.conf
    fi
    if ! [ -f /etc/nginx/sites-available/btcrpcexplorer_tor.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/btcrpcexplorer_tor.conf /etc/nginx/sites-available/btcrpcexplorer_tor.conf
    fi
    if ! [ -f /etc/nginx/sites-available/btcrpcexplorer_tor_ssl.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/btcrpcexplorer_tor_ssl.conf /etc/nginx/sites-available/btcrpcexplorer_tor_ssl.conf
    fi
    sudo ln -sf /etc/nginx/sites-available/btcrpcexplorer_ssl.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/btcrpcexplorer_tor.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/btcrpcexplorer_tor_ssl.conf /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl reload nginx

    # install service
    echo "*** Install btc-rpc-explorer systemd ***"
    cat > /var/cache/raspiblitz/btc-rpc-explorer.service <<EOF
# systemd unit for BTC RPC Explorer

[Unit]
Description=btc-rpc-explorer
Wants=${network}d.service
After=${network}d.service
StartLimitIntervalSec=0

[Service]
User=btcrpcexplorer
ExecStartPre=/home/admin/config.scripts/bonus.btc-rpc-explorer.sh prestart
WorkingDirectory=/home/btcrpcexplorer/btc-rpc-explorer
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=20
LogLevelMax=4

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /var/cache/raspiblitz/btc-rpc-explorer.service /etc/systemd/system/btc-rpc-explorer.service
    sudo systemctl enable btc-rpc-explorer
    echo "# OK - the BTC-RPC-explorer service is now enabled"

  else
    echo "# BTC-RPC-explorer already installed."
  fi

  # setting value in raspi blitz config
  sudo /home/admin/config.scripts/blitz.conf.sh set BTCRPCexplorer "on"
  
  echo "# needs to finish creating txindex to be functional"
  echo "# monitor with: sudo tail -n 20 -f /mnt/hdd/bitcoin/debug.log"
  echo "# npm audi fix"
  cd /home/btcrpcexplorer/btc-rpc-explorer/
  sudo npm audit fix

  # Hidden Service for BTC-RPC-explorer if Tor is active
  source /mnt/hdd/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with tor.network.sh script
    sudo /home/admin/config.scripts/tor.onion-service.sh btc-rpc-explorer 80 3022 443 3023
  fi

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    # start service
    echo "# starting service ..."
    sudo systemctl start btc-rpc-explorer 2>/dev/null
    sleep 10
  fi

  # needed for API/WebUI as signal that install ran thru 
  echo "result='OK'"
  exit 0
fi

##########################
# OFF
#########################

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo /home/admin/config.scripts/blitz.conf.sh set BTCRPCexplorer "off"

  isInstalled=$(sudo ls /etc/systemd/system/btc-rpc-explorer.service 2>/dev/null | grep -c 'btc-rpc-explorer.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# *** REMOVING BTC-RPC-explorer ***"
    sudo systemctl disable btc-rpc-explorer
    sudo rm /etc/systemd/system/btc-rpc-explorer.service

    # remove nginx symlinks
    sudo rm -f /etc/nginx/sites-enabled/btcrpcexplorer_ssl.conf
    sudo rm -f /etc/nginx/sites-enabled/btcrpcexplorer_tor.conf
    sudo rm -f /etc/nginx/sites-enabled/btcrpcexplorer_tor_ssl.conf
    sudo rm -f /etc/nginx/sites-available/btcrpcexplorer_ssl.conf
    sudo rm -f /etc/nginx/sites-available/btcrpcexplorer_tor.conf
    sudo rm -f /etc/nginx/sites-available/btcrpcexplorer_tor_ssl.conf
    sudo nginx -t
    sudo systemctl reload nginx

    # Hidden Service if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      # make sure to keep in sync with tor.network.sh script
      sudo /home/admin/config.scripts/tor.onion-service.sh off btc-rpc-explorer
    fi

    echo "# OK BTC-RPC-explorer removed."

  else
    echo "# BTC-RPC-explorer is not installed."
  fi

  # close ports on firewall
  sudo ufw deny 3020
  sudo ufw deny 3021

  # needed for API/WebUI as signal that install ran thru 
  echo "result='OK'"
  exit 0
fi

echo "error='unknown parameter'"
exit 1
