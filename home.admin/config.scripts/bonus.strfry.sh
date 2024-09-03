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

source /mnt/hdd/raspiblitz.conf

isInstalled=$(compgen -u | grep -c strfry)
isActive=$(sudo ls /etc/systemd/system/strfry.service 2>/dev/null | grep -c 'strfry.service')
localip=$(hostname -I | awk '{print $1}')
toraddress=$(sudo cat /mnt/hdd/tor/strfry/hostname 2>/dev/null)

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
      whiptail --title " strfry " --msgbox "Connect to:
wss://${localip}:${portSSL}\n
with Fingerprint:
${fingerprint}\n
Hidden Service address is (see LCD for QR):
${toraddress}
" 16 67
      sudo /home/admin/config.scripts/blitz.display.sh hide
    else
      # Info without Tor
      whiptail --title " strfry " --msgbox "Connect to:
wss://${localip}:${portSSL}\n
with Fingerprint:
${fingerprint}\n
Activate Tor to serve an .onion address.
" 15 57
    fi
    echo "# please wait ..."
  else
    echo "# *** strfry is not installed ***"
  fi
  exit 0
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

  sudo ufw allow ${portSSL} comment 'strfry SSL'

  # nginx
  cat <<EOF | sudo tee /etc/nginx/sites-available/strfry
server {
    listen ${portSSL} ssl http2;
    listen [::]:${portSSL} ssl http2;
    server_name _;

    include /etc/nginx/snippets/ssl-params.conf;
    include /etc/nginx/snippets/ssl-certificate-app-data.conf;

    include /etc/nginx/snippets/gzip-params.conf;

    access_log /var/log/nginx/access_strfry.log;
    error_log /var/log/nginx/error_strfry.log;

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

  sudo ln -sf /etc/nginx/sites-available/strfry /etc/nginx/sites-enabled/strfry

  # test and reload nginx
  sudo nginx -t && sudo systemctl reload nginx

  # Tor
  /home/admin/config.scripts/tor.onion-service.sh strfry 80 ${portTCP}

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set strfry "on"
  exit 0
fi

if [ "$1" = "off" ]; then

  sudo systemctl disable --now strfry
  sudo rm -f /etc/strfry.conf
  sudo rm -f /etc/systemd/system/strfry.service

  sudo ufw delete allow ${portSSL}

  # Tor
  /home/admin/config.scripts/tor.onion-service.sh off strfry

  sudo userdel -rf strfry

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set strfry "off"

  exit 0
fi
