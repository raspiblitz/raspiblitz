#!/bin/bash

# https://codeberg.org/Yonle/bostr2/tags
VERSION="v1.0.6"

portTCP=8800
portSSL=8801

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch the bostr2 nostr relay on or off"
  echo "bonus.bostr2.sh [on|off]"
  echo "installs the version $VERSION"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

isInstalled=$(compgen -u | grep -c bostr2)
isActive=$(sudo ls /etc/systemd/system/bostr2.service 2>/dev/null | grep -c 'bostr2.service')
localip=$(hostname -I | awk '{print $1}')
toraddress=$(sudo cat /mnt/hdd/tor/bostr2/hostname 2>/dev/null)

if [ "$1" = "status" ]; then
  echo "version='${VERSION}'"
  echo "installed='${isInstalled}'"
  echo "active='${isActive}'"
  echo "localIP='${localip}'"
  echo "httpPort='${portTCP}'"
  echo "httpsPort='${portSSL}'"
  echo "toraddress='${toraddress}'"
  exit 0
fi

# show info menu
if [ "$1" = "menu" ]; then

  if [ ${isActive} -eq 1 ]; then
    # get network info
    fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

    if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
      # Info with Tor
      sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
      whiptail --title " bostr2 " --msgbox "Connect to:
wss://${localip}:${portSSL}\n
with Fingerprint:
${fingerprint}\n
Hidden Service address is (see LCD for QR):
${toraddress}
" 16 67
      sudo /home/admin/config.scripts/blitz.display.sh hide
    else
      # Info without Tor
      whiptail --title " bostr2 " --msgbox "Connect to:
wss://${localip}:${portSSL}\n
with Fingerprint:
${fingerprint}\n
Activate Tor to serve an .onion address.
" 15 57
    fi
    echo "# please wait ..."
  else
    echo "# *** bostr2 is not installed ***"
  fi
  exit 0
fi

if [ "$1" = "on" ]; then

  /home/admin/config.scripts/bonus.go.sh on

  sudo adduser --system --group --shell /bin/bash --home /home/bostr2 bostr2 || exit 1

  cd /home/bostr2 || exit 1

  # set PATH for the user
  sudo bash -c "echo 'PATH=\$PATH:/usr/local/go/bin/:/home/bostr2/go/bin/' >> /home/bostr2/.profile"

  sudo -u bostr2 /usr/local/go/bin/go install codeberg.org/Yonle/bostr2@${VERSION} || exit 1

  # config
  sudo mkdir -p /mnt/hdd/app-data/bostr2
  sudo chown -R bostr2:bostr2 /mnt/hdd/app-data/bostr2
  sudo chmod 755 /mnt/hdd/app-data/bostr2

  cat <<EOF | sudo -u bostr2 tee /mnt/hdd/app-data/bostr2/config.yaml
---
listen: 0.0.0.0:${portTCP}

favicon:

relays:
- wss://relay.damus.io
- wss://nostr.wine
- wss://nostr.lu.ke
- wss://nostr.l00p.org
- wss://relay.primal.net
- wss://nostr.mutinywallet.com
- wss://nostr-verif.slothy.win
- wss://nostr-pub.wellorder.net
- wss://nostr.bitcoiner.social
- wss://nostr.oxtr.dev
- wss://nostr.fmt.wiz.biz
- wss://eden.nostr.land
- wss://relay.current.fyi
- wss://cache1.primal.net/v1

nip_11:
  name: bostr2
  description: Nostr relay bouncer
  software: git+https://codeberg.org/Yonle/bostr2
  pubkey: 0000000000000000000000000000000000000000000000000000000000000000
  contact: unset
  supported_nips:
  - 1
  - 2
  - 9
  - 11
  - 12
  - 15
  - 16
  - 20
  - 22
  - 33
  - 40

# 0 is infinity
max_connections_per_ip: 3
EOF

  # symlink
  sudo rm -rf /home/bostr2/config.yaml
  sudo ln -s /mnt/hdd/app-data/bostr2/config.yaml /home/bostr2/config.yaml

  # systemd
  echo "# Create a systemd service"
  if [ "${runBehindTor}" = "on" ]; then
    echo "# Run all connections through Tor."
    tor="torsocks"
  else
    echo "# Run connections without Tor."
    tor=""
  fi
  echo "\
[Unit]
Description=bostr2 relay service

[Service]
User=bostr2
WorkingDirectory=/home/bostr2
ExecStart=$tor /home/bostr2/go/bin/bostr2
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=full

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/bostr2.service

  sudo systemctl enable bostr2
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# Starting the bostr2.service"
    sudo systemctl start bostr2
  fi

  sudo ufw allow ${portSSL} comment 'bostr2 SSL'

  # nginx
  cat <<EOF | sudo tee /etc/nginx/sites-available/bostr2
server {
    listen ${portSSL} ssl http2;
    listen [::]:${portSSL} ssl http2;
    server_name _;

    include /etc/nginx/snippets/ssl-params.conf;
    include /etc/nginx/snippets/ssl-certificate-app-data.conf;

    include /etc/nginx/snippets/gzip-params.conf;

    access_log /var/log/nginx/access_bostr2.log;
    error_log /var/log/nginx/error_bostr2.log;

    location / {
        proxy_pass http://127.0.0.1:${portTCP};

        # needed for websocket connections
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        include /etc/nginx/snippets/ssl-proxy-params.conf;
    }
}
EOF

  sudo ln -sf /etc/nginx/sites-available/bostr2 /etc/nginx/sites-enabled/bostr2

  # test and reload nginx
  sudo nginx -t && sudo systemctl reload nginx

  # Tor
  /home/admin/config.scripts/tor.onion-service.sh bostr2 ${portTCP} ${portTCP}

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set bostr2 "on"
  exit 0
fi

if [ "$1" = "off" ]; then

  sudo systemctl disable --now bostr2
  sudo rm -f /etc/systemd/system/bostr2.service

  sudo ufw delete allow ${portSSL}

  # Tor
  /home/admin/config.scripts/tor.onion-service.sh off bostr2

  sudo userdel -rf bostr2

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set bostr2 "off"

  exit 0
fi
