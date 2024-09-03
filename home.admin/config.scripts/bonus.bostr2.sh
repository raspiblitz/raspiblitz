#!/bin/bash

# https://codeberg.org/Yonle/bostr2/tags
VERSION="v1.0.6"

portTCP=8888
portSSL=8889

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch the bostr2 nostr relay on or off"
  echo "bonus.bostr2.sh [on|off]"
  echo "installs the version $VERSION"
  exit 1
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
listen: 0.0.0.0:8888

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
  echo "\
    [Unit]
    Description=bostr2 relay service

    [Service]
    User=bostr2
    WorkingDirectory=/home/bostr2
    ExecStart=/home/bostr2/go/bin/bostr2
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

  sudo ufw allow ${portTCP} comment 'bostr2 TCP'
  sudo ufw allow ${portSSL} comment 'bostr2 SSL'

  # nginx

  # test and reload nginx
  sudo nginx -t && sudo systemctl reload nginx

  # Tor
  /home/admin/config.scripts/tor.onion-service.sh bostr2 ${portTCP} ${portTCP} ${portSSL} ${portSSL}

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set bostr2 "on"
  exit 0
fi

if [ "$1" = "off" ]; then

  sudo systemctl disable --now bostr2
  sudo rm -f /etc/systemd/system/bostr2.service

  sudo ufw delete allow ${portTCP}
  sudo ufw delete allow ${portSSL}

  # Tor
  /home/admin/config.scripts/tor.onion-service.sh bostr2 off

  sudo userdel -rf bostr2

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set bostr2 "off"

  exit 0
fi
