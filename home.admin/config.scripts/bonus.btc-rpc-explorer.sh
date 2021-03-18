#!/bin/bash

# https://github.com/janoside/btc-rpc-explorer
# ~/.config/btc-rpc-explorer.env
# https://github.com/janoside/btc-rpc-explorer/blob/master/.env-sample

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# small config script to switch BTC-RPC-explorer on or off"
 echo "# bonus.btc-rpc-explorer.sh [status|on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

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

  # get network info
  localip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0|veth' | grep 'eth0\|wlan0\|enp0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  toraddress=$(sudo cat /mnt/hdd/tor/btc-rpc-explorer/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then

    # TOR
    /home/admin/config.scripts/blitz.lcd.sh qr "${toraddress}"
    whiptail --title " BTC-RPC-Explorer " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:3021\n
SHA1 Thumb/Fingerprint:
${fingerprint}\n
Login is 'admin' with your Password B\n
Hidden Service address for TOR Browser (QR see LCD):
${toraddress}
" 16 67
    /home/admin/config.scripts/blitz.lcd.sh hide
  else

    # IP + Domain
    whiptail --title " BTC-RPC-Explorer " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:3021\n
SHA1 Thumb/Fingerprint:
${fingerprint}\n
Login is 'admin' with your Password B\n
Activate TOR to access the web block explorer from outside your local network.
" 16 54
  fi

  echo "please wait ..."
  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^BTCRPCexplorer=" /mnt/hdd/raspiblitz.conf; then
  echo "BTCRPCexplorer=off" >> /mnt/hdd/raspiblitz.conf
fi

# status
if [ "$1" = "status" ]; then

  if [ "${BTCRPCexplorer}" = "on" ]; then
    echo "configured=1"

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
  fi
  exit 0
fi

# stop service
echo "# making sure services are not running"
sudo systemctl stop btc-rpc-explorer 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# *** INSTALL BTC-RPC-EXPLORER ***"

  isInstalled=$(sudo ls /etc/systemd/system/btc-rpc-explorer.service 2>/dev/null | grep -c 'btc-rpc-explorer.service')
  if [ ${isInstalled} -eq 0 ]; then

    # install nodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    # make sure that txindex of blockchain is switched on
    /home/admin/config.scripts/network.txindex.sh on
    
    # add btcrpcexplorer user
    sudo adduser --disabled-password --gecos "" btcrpcexplorer

    # install btc-rpc-explorer
    cd /home/btcrpcexplorer
    sudo -u btcrpcexplorer git clone https://github.com/janoside/btc-rpc-explorer.git
    cd btc-rpc-explorer
    sudo -u btcrpcexplorer git reset --hard v2.2.0
    sudo -u btcrpcexplorer npm install
    if ! [ $? -eq 0 ]; then
        echo "FAIL - npm install did not run correctly, aborting"
        exit 1
    fi

    # prepare .env file
    echo "# getting RPC credentials from the ${network}.conf"

    RPC_USER=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcuser | cut -c 9-)
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)

    touch /home/admin/btc-rpc-explorer.env
    sudo chmod 600 /home/admin/btc-rpc-explorer.env || exit 1 
    cat > /home/admin/btc-rpc-explorer.env <<EOF
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
# Password protection for site via basic auth (enter any username, only the password is checked)
# Default: none
BTCEXP_BASIC_AUTH_PASSWORD=$PASSWORD_B
# Select optional "address API" to display address tx lists and balances
# Options: electrumx, blockchain.com, blockchair.com, blockcypher.com
# If electrumx set, the BTCEXP_ELECTRUMX_SERVERS variable must also be
# set.
# Default: none
BTCEXP_ADDRESS_API=none
BTCEXP_ELECTRUMX_SERVERS=tcp://127.0.0.1:50001
EOF
    sudo mv /home/admin/btc-rpc-explorer.env /home/btcrpcexplorer/.config/btc-rpc-explorer.env
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
    cat > /home/admin/btc-rpc-explorer.service <<EOF
# systemd unit for BTC RPC Explorer

[Unit]
Description=btc-rpc-explorer
Wants=${network}d.service
After=${network}d.service

[Service]
WorkingDirectory=/home/btcrpcexplorer/btc-rpc-explorer
ExecStart=/usr/bin/npm start
User=btcrpcexplorer
# Restart on failure but no more than default times (DefaultStartLimitBurst=5) every 10 minutes (600 seconds). Otherwise stop
Restart=on-failure
RestartSec=600

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /home/admin/btc-rpc-explorer.service /etc/systemd/system/btc-rpc-explorer.service 
    sudo systemctl enable btc-rpc-explorer
    echo "# OK - the BTC-RPC-explorer service is now enabled"

  else 
    echo "# BTC-RPC-explorer already installed."
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^BTCRPCexplorer=.*/BTCRPCexplorer=on/g" /mnt/hdd/raspiblitz.conf
  
  echo "# needs to finish creating txindex to be functional"
  echo "# monitor with: sudo tail -n 20 -f /mnt/hdd/bitcoin/debug.log"

  ## Enable BTCEXP_ADDRESS_API if BTC-RPC-Explorer is active
  # see /home/admin/config.scripts/bonus.electrsexplorer.sh
  # run every 10 min by _background.sh

  # Hidden Service for BTC-RPC-explorer if Tor is active
  source /mnt/hdd/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with internet.tor.sh script
    /home/admin/config.scripts/internet.hiddenservice.sh btc-rpc-explorer 80 3022 443 3023
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^BTCRPCexplorer=.*/BTCRPCexplorer=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/btc-rpc-explorer.service 2>/dev/null | grep -c 'btc-rpc-explorer.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# *** REMOVING BTC-RPC-explorer ***"
    sudo systemctl disable btc-rpc-explorer
    sudo rm /etc/systemd/system/btc-rpc-explorer.service
    # delete user and home directory
    sudo userdel -rf btcrpcexplorer

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
      # make sure to keep in sync with internet.tor.sh script
      /home/admin/config.scripts/internet.hiddenservice.sh off btc-rpc-explorer
    fi

    echo "# OK BTC-RPC-explorer removed."
  
  else 
    echo "# BTC-RPC-explorer is not installed."
  fi

  # close ports on firewall
  sudo ufw deny 3020
  sudo ufw deny 3021
  exit 0
fi

echo "error='unknown parameter'
exit 1
