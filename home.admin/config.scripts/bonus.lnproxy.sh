#!/bin/bash

# https://github.com/lnproxy/lnproxy/commits/main
LNPROXYVERSION="423723b58cc45daa2fdf6c8b22537d560aca4d7a"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install or uninstall lnproxy"
 echo "bonus.lnproxy.sh [on|off]"
 echo "installs the version $LNPROXYVERSION by default"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# install
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if systemctl is-active --quite lnproxy; then
    echo "# FAIL - lnproxy already installed"
    sleep 3
    exit 1
  fi

  echo "*** INSTALL LNPROXY ***"
  # check and install Go
  /home/admin/config.scripts/bonus.go.sh on

  # create lnproxy user
  sudo adduser --disabled-password --gecos "" lnproxy

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

  # download source code
  cd /home/lnproxy/ || exit 1
  sudo -u lnproxy git clone https://github.com/lnproxy/lnproxy.git /home/lnproxy/lnproxy
  cd /home/lnproxy/lnproxy || exit 1

  # make sure symlink to central app-data directory exists
  sudo rm -rf /home/lnproxy/.lnd  # not a symlink.. delete it silently
  # create symlink
  sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/lnproxy/.lnd"

  # build
  sudo -u lnproxy /usr/local/go/bin/go get lnproxy
  sudo -u lnproxy /usr/local/go/bin/go build

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
RestartSec=5
TimeoutSec=120
KillMode=process

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

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set lnproxy "on"

  echo "Usage:"
  echo "curl http://localhost:4747/${your_invoice}?routing_msat={routing_budget}"
  echo "# More info at: https://github.com/lnproxy/lnproxy"

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "*** REMOVING LNPROXY***"
  sudo userdel -rf lnproxy
  echo "# OK, lnproxy is removed."
  exit 0

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set lnproxy "off"
fi
