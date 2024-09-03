#!/bin/bash

# https://github.com/hoytech/strfry/commits/master/
VERSION="32a367738c6db7430780058c4a6c98b271af73b2"

portTCP=7777
portSSL=7778

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch the strfry nostr relay on or off"
  echo "bonus.strfry.sh [on|off]"
  echo "installs the version $VERSION"
  exit 1
fi

if [ "$1" = "on" ]; then

  LIMITS=("strfry soft nofile 1000000" "strfry hard nofile 1000000")
  # Loop through each limit
  for LIMIT in "${LIMITS[@]}"; do
    # Check if the limit already exists
    if ! grep -q "$LIMIT" /etc/security/limits.conf; then
      echo "$LIMIT" | sudo tee -a /etc/security/limits.conf >/dev/null
      echo "Limit added: $LIMIT"
    else
      echo "Limit already exists: $LIMIT"
    fi
  done

  sudo adduser --system --group --shell /bin/bash --home /home/strfry strfry || exit 1

  sudo apt install -y build-essential libyaml-perl libtemplate-perl libregexp-grammars-perl libssl-dev zlib1g-dev liblmdb-dev libflatbuffers-dev libsecp256k1-dev libzstd-dev

  cd /home/strfry || exit 1

  sudo -u strfry git clone https://github.com/hoytech/strfry.git
  cd strfry || exit 1
  sudo -u strfry git reset --hard ${VERSION}

  sudo -u strfry git submodule update --init
  sudo -u strfry make setup-golpe
  sudo -u strfry make -j2

  sudo mkdir /mnt/hdd/app-storage/strfry-db
  sudo chown strfry:strfry /mnt/hdd/app-storage/strfry-db
  sudo chmod 755 /mnt/hdd/app-storage/strfry-db

  # config
  sudo mkdir -p /mnt/hdd/app-data/strfry
  sudo chown -R strfry:strfry /mnt/hdd/app-data/strfry
  sudo chmod 755 /mnt/hdd/app-data/strfry
  sudo -u strfry cp ./strfry.conf /mnt/hdd/app-data/strfry/strfry.conf

  # symlink
  sudo ln -s /mnt/hdd/app-data/strfry/strfry.conf /etc/strfry.conf

  # systemd
  echo "# Create a systemd service"
  echo "\
    [Unit]
    Description=strfry relay service

    [Service]
    User=strfry
    ExecStart=/home/strfry/strfry/strfry relay
    Restart=on-failure
    RestartSec=5
    NoNewPrivileges=yes
    ProtectSystem=full
    LimitCORE=1000000000

    [Install]
    WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/strfry.service

  sudo systemctl enable strfry
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# Starting the strfry.service"
    sudo systemctl start strfry
  fi

  sudo ufw allow ${portTCP} comment 'strfry TCP'
  sudo ufw allow ${portSSL} comment 'strfry SSL'

  # nginx

  # test and reload nginx
  sudo nginx -t && sudo systemctl reload nginx

  # Tor
  /home/admin/config.scripts/tor.onion-service.sh strfry ${portTCP} ${portTCP} ${portSSL} ${portSSL}

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set strfry "on"
  exit 0
fi

if [ "$1" = "off" ]; then

  sudo systemctl disable --now strfry
  sudo rm -f /etc/strfry.conf
  sudo rm -f /etc/systemd/system/strfry.service

  sudo ufw delete allow ${portTCP}
  sudo ufw delete allow ${portSSL}

  # Tor
  /home/admin/config.scripts/tor.onion-service.sh strfry off

  sudo userdel -rf strfry

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set strfry "off"

  exit 0
fi
