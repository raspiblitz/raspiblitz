#!/bin/bash

# Deactivated - see https://github.com/raspiblitz/raspiblitz/issues/4122
# Needs comitted maintainer or will be removed in future versions

# https://github.com/lnproxy/lnproxy/commits/main
LNPROXYVERSION="c1031bbe507623f8f196ff83aa5ea504cca05143"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "DEACTIVATED FOR REPAIR - see #4122"
  echo "config script to install or uninstall the lnproxy server"
  echo "bonus.lnproxy.sh [on|off|menu]"
  echo "installs the version $LNPROXYVERSION by default"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf
localip=$(hostname -I | awk '{print $1}')

# menu
if [ "$1" = "menu" ]; then

  if systemctl is-active --quiet lnproxy; then
    torAddress=$(sudo cat /mnt/hdd/tor/lnproxy/hostname 2>/dev/null)
    sudo /home/admin/config.scripts/blitz.display.sh qr "${torAddress}"
    whiptail --title " lnproxy server API" --msgbox "\
Use your hidden service as a relay on the lnproxy Tor website:
dx7pn6ehykq6cadce4bjbxn5tf64z7e3fufpxgxce7n4f5eja476cpyd.onion
Your address to be used as the relay:
http://${torAddress}/spec

To use the API from another computer on your LAN:
curl -k https://${localip}:4748/api/{invoice}?routing_msat={budget}

The Tor Hidden Service address to share for using the API:
${torAddress}/api
" 16 78
    sudo /home/admin/config.scripts/blitz.display.sh hide
    echo "# please wait ..."
  else
    echo "# *** LNPROXY IS NOT INSTALLED ***"
  fi
  exit 0
fi

# install
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if systemctl is-active --quiet lnproxy; then
    echo "# FAIL - lnproxy already installed"
    sleep 3
    exit 1
  fi

  echo "*** INSTALL LNPROXY ***"
  # check and install Go
  /home/admin/config.scripts/bonus.go.sh on

  # create lnproxy user
  sudo adduser --system --group --home /home/lnproxy lnproxy

  # create macaroon
  cd /home/bitcoin || exit 1
  sudo -u bitcoin lncli bakemacaroon --save_to lnproxy.macaroon \
    uri:/lnrpc.Lightning/DecodePayReq \
    uri:/lnrpc.Lightning/LookupInvoice \
    uri:/invoicesrpc.Invoices/AddHoldInvoice \
    uri:/invoicesrpc.Invoices/SubscribeSingleInvoice \
    uri:/invoicesrpc.Invoices/CancelInvoice \
    uri:/invoicesrpc.Invoices/SettleInvoice \
    uri:/routerrpc.Router/SendPaymentV2
  sudo mv ./lnproxy.macaroon /home/lnproxy/
  sudo chown lnproxy:lnproxy /home/lnproxy/lnproxy.macaroon
  sudo chmod 600 /home/lnproxy/lnproxy.macaroon

  # make sure symlink to central app-data directory exists
  sudo rm -rf /home/lnproxy/.lnd # not a symlink.. delete it silently
  # create symlink
  sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/lnproxy/.lnd"

  # download source code
  cd /home/lnproxy/ || exit 1
  sudo -u lnproxy git clone https://github.com/lnproxy/lnproxy.git /home/lnproxy/lnproxy
  cd /home/lnproxy/lnproxy || exit 1
  sudo -u lnproxy git reset --hard ${LNPROXYVERSION} || exit 1

  # build
  sudo -u lnproxy /usr/local/go/bin/go get lnproxy
  if [ $? -ne 0 ]; then
    echo "# FAIL -> go get lnproxy"
    sudo userdel -rf lnproxy 2>/dev/null
    exit 1
  fi

  sudo -u lnproxy /usr/local/go/bin/go build
  if [ $? -ne 0 ]; then
    echo "# FAIL -> go build"
    sudo userdel -rf lnproxy 2>/dev/null
    exit 1
  fi

  # manual start (in tmux)
  # sudo -u lnproxy /home/lnproxy/lnproxy/lnproxy -lnd-cert /home/lnproxy/.lnd/tls.cert /home/lnproxy/lnproxy.macaroon

  # create systemd service
  cat <<EOF | sudo tee /etc/systemd/system/lnproxy.service
[Unit]
Description=lnproxy
After=lnd.service

[Service]
User=lnproxy
Group=lnproxy
Type=simple
ExecStart=/home/lnproxy/lnproxy/lnproxy -lnd-cert /home/lnproxy/.lnd/tls.cert /home/lnproxy/lnproxy.macaroon
Restart=on-failure
RestartSec=30
TimeoutSec=120

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

  # enable and start service
  sudo systemctl enable lnproxy

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# OK - the lnproxy.service is enabled, system is on ready so starting service"
    sudo systemctl start lnproxy
  else
    echo "# OK - the lnproxy.service is enabled, to start manually use: sudo systemctl start lnproxy"
  fi

  ##################
  # NGINX
  ##################
  # setup nginx symlinks
  if ! [ -f /etc/nginx/sites-available/lnproxy_ssl.conf ]; then
    sudo cp -f /home/admin/assets/nginx/sites-available/lnproxy_ssl.conf /etc/nginx/sites-available/lnproxy_ssl.conf
  fi
  if ! [ -f /etc/nginx/sites-available/lnproxy_tor.conf ]; then
    sudo cp /home/admin/assets/nginx/sites-available/lnproxy_tor.conf /etc/nginx/sites-available/lnproxy_tor.conf
  fi
  if ! [ -f /etc/nginx/sites-available/lnproxy_tor_ssl.conf ]; then
    sudo cp /home/admin/assets/nginx/sites-available/lnproxy_tor_ssl.conf /etc/nginx/sites-available/lnproxy_tor_ssl.conf
  fi
  sudo ln -sf /etc/nginx/sites-available/lnproxy_ssl.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/lnproxy_tor.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/lnproxy_tor_ssl.conf /etc/nginx/sites-enabled/
  sudo nginx -t || exit 1
  sudo systemctl reload nginx

  sudo ufw allow 4748 comment lnproxy-HTTPS

  /home/admin/config.scripts/tor.onion-service.sh lnproxy 80 4749 443 4750

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set lnproxy "on"

  torAddress=$(sudo cat /mnt/hdd/tor/lnproxy/hostname 2>/dev/null)
  echo
  echo "# Use your hidden service as a relay on the lnproxy Tor website:"
  echo "dx7pn6ehykq6cadce4bjbxn5tf64z7e3fufpxgxce7n4f5eja476cpyd.onion"
  echo "# Your address to be used as the relay:"
  echo "http://${torAddress}/spec"
  echo "# To use the API from another computer on your LAN:"
  echo "curl -k https://${localip}:4748/api/{invoice}?routing_msat={budget}\n"
  echo "# The Tor Hidden Service address to share for using the API:"
  echo "${torAddress}/api"
  echo "# More info at:"
  echo "https://github.com/lnproxy"

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "*** REMOVING LNPROXY***"
  # remove user and home directory
  sudo userdel -rf lnproxy

  # remove systemd services
  sudo systemctl disable --now lnproxy
  sudo rm -f /etc/systemd/system/lnproxy.service

  # remove Tor service
  /home/admin/config.scripts/tor.onion-service.sh off lnproxy

  sudo rm /etc/nginx/sites-available/lnproxy_ssl.conf
  sudo rm /etc/nginx/sites-available/lnproxy_tor.conf
  sudo rm /etc/nginx/sites-available/lnproxy_tor_ssl.conf
  sudo rm /etc/nginx/sites-enabled/lnproxy_ssl.conf
  sudo rm /etc/nginx/sites-enabled/lnproxy_tor.conf
  sudo rm /etc/nginx/sites-enabled/lnproxy_tor_ssl.conf

  sudo nginx -t || exit 1
  sudo systemctl reload nginx

  # close ports on firewall
  sudo ufw delete allow 4748

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set lnproxy "off"

  echo "# OK, lnproxy is removed."

  exit 0
fi
