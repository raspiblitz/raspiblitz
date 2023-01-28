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
localip=$(hostname -I | awk '{print $1}')

# menu
if [ "$1" = "menu" ]; then

  if systemctl is-active --quiet lnproxy; then
    # get network info
    toraddressApi=$(sudo cat /mnt/hdd/tor/lnproxy/hostname 2>/dev/null)
    toraddressWebui=$(sudo cat /mnt/hdd/tor/lnproxy-webui/hostname 2>/dev/null)

    if [ "${runBehindTor}" = "on" ] && [ -n "${toraddressApi}" ]; then
      # Info with Tor
      sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddressWebui}"
      whiptail --title " lnproxy-webui " --msgbox "Open in your local web browser:
http://${localip}:4748\n
Hidden Service address for Tor Browser (see LCD for QR):\n${toraddressWebui}

To use the API:
curl http://${localip}:4747/{your_invoice}?routing_msat={routing_budget}
The Tor Hidden service to share:
${toraddressApi}
" 16 67
      sudo /home/admin/config.scripts/blitz.display.sh hide
    else
      # Info without Tor
      whiptail --title " lnproxy-webui " --msgbox "Open in your local web browser:
http://${localip}:4748\n
Activate Tor to access the web interface from outside your local network.
" 15 57
    fi
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

  # make sure symlink to central app-data directory exists
  sudo rm -rf /home/lnproxy/.lnd  # not a symlink.. delete it silently
  # create symlink
  sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/lnproxy/.lnd"

  # download source code
  cd /home/lnproxy/ || exit 1
  sudo -u lnproxy git clone https://github.com/lnproxy/lnproxy.git /home/lnproxy/lnproxy
  cd /home/lnproxy/lnproxy || exit 1

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

  # lnproxy-webui
  cd /home/lnproxy/ || exit 1
  sudo -u lnproxy git clone https://github.com/lnproxy/lnproxy-webui
  cd /home/lnproxy/lnproxy-webui || exit 1

  # build
  sudo -u lnproxy /usr/local/go/bin/go get lnproxy-webui
  sudo -u lnproxy /usr/local/go/bin/go build

  # create systemd service
  cat <<EOF | sudo tee /etc/systemd/system/lnproxy-webui.service
[Unit]
Description=lnproxy-webui
After=lnproxy.service

[Service]
WorkingDirectory=/home/lnproxy/lnproxy-webui
User=lnproxy
Group=lnproxy
Type=simple
ExecStart=/home/lnproxy/lnproxy-webui/lnproxy-webui
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
  sudo systemctl enable lnproxy-webui

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# OK - the lnproxy-webui.service is enabled, system is on ready so starting service"
    sudo systemctl start lnproxy-webui
  else
    echo "# OK - the lnproxy-webui.service is enabled, to start manually use: sudo systemctl start lnproxy-webui"
  fi

  sudo ufw allow 4747 comment lnproxy-HTTP
  sudo ufw allow 4748 comment lnproxy-webui-HTTP

  /home/admin/config.scripts/tor.onion-service.sh lnproxy 80 4747
  /home/admin/config.scripts/tor.onion-service.sh lnproxy-webui 80 4748

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set lnproxy "on"

  echo "# API:"
  echo "curl http://${localip}:4747/{your_invoice}?routing_msat={routing_budget}"
  echo "# WebUI:"
  echo "http://${localip}:4748"
  echo "# More info at:"
  echo "https://github.com/lnproxy/lnproxy"

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "*** REMOVING LNPROXY***"
  # remove user and home directory
  sudo userdel -rf lnproxy

  # remove systemd services
  sudo systemctl disable --now lnproxy
  /etc/systemd/system/lnproxy.service
  sudo systemctl disable --now lnproxy-webui
  /etc/systemd/system/lnproxy-webui.service

  # remove Tor service
  /home/admin/config.scripts/tor.onion-service.sh off lnproxy
  /home/admin/config.scripts/tor.onion-service.sh off lnproxy-webui

  # close ports on firewall
  sudo ufw delete allow 4747
  sudo ufw delete allow 4748

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set lnproxy "off"

  echo "# OK, lnproxy is removed."

  exit 0
fi
