#!/bin/bash

# https://github.com/cculianu/Fulcrum/releases
fulcrumVersion="1.7.0"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch the Fulcrum electrum server on or off"
  # echo "bonus.fulcrum.sh status [?showAddress]"
  echo "bonus.fulcrum.sh [on|off]"
  echo "installs the version $fulcrumVersion"
  exit 1
fi


if [ "$1" = on ]; then
  # ?wait until txindex finishes?
  /home/admin/config.scripts/network.txindex.sh on

  # activate zram
  /home/admin/config.scripts/blitz.zram.sh on

  /home/admin/config.scripts/blitz.conf.sh set rpcworkqueue 512 /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh set rpcthreads 128 /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh set zmqpubhashblock 'tcp://0.0.0.0:8433' /mnt/hdd/bitcoin/bitcoin.conf noquotes

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    sudo systemctl restart bitcoind
  fi

  # create a dedicated user
  sudo adduser --disabled-password --gecos "" fulcrum
  cd /home/fulcrum || exit 1

  sudo apt install -y libssl-dev # was needed on Debian Bullseye

  # set the platform
  if [ $(uname -m) = "aarch64" ]; then
    build="arm64-linux"
  elif [ $(uname -m) = "x86_64" ]; then
    build="x86_64-linux-ub16"
  fi

  # download the prebuilt binary
  sudo -u fulcrum wget https://github.com/cculianu/Fulcrum/releases/download/v${fulcrumVersion}/Fulcrum-${fulcrumVersion}-${build}.tar.gz
  sudo -u fulcrum wget https://github.com/cculianu/Fulcrum/releases/download/v${fulcrumVersion}/Fulcrum-${fulcrumVersion}-${build}.tar.gz.asc
  sudo -u fulcrum wget https://github.com/cculianu/Fulcrum/releases/download/v${fulcrumVersion}/Fulcrum-${fulcrumVersion}-${build}.tar.gz.sha256sum

  # Verify
  # get the PGP key
  curl https://raw.githubusercontent.com/Electron-Cash/keys-n-hashes/master/pubkeys/calinkey.txt | sudo -u fulcrum gpg --import

  # look for 'Good signature'
  sudo -u fulcrum gpg --verify Fulcrum-${fulcrumVersion}-${build}.tar.gz.asc || (echo "Failed to verify the GPG signature of Fulcrum-${fulcrumVersion}-${build}.tar.gz"; exit 1)

  # look for 'OK'
  sudo -u fulcrum sha256sum -c Fulcrum-${fulcrumVersion}-${build}.tar.gz.sha256sum --ignore-missing || (echo "Failed to verify the sha256 hash of Fulcrum-${fulcrumVersion}-${build}.tar.gz"; exit 1)

  # decompress
  sudo -u fulcrum tar -xvf Fulcrum-${fulcrumVersion}-${build}.tar.gz

  # create the database directory in /mnt/hdd/app-storage (on the disk)
  sudo mkdir -p /mnt/hdd/app-storage/fulcrum/db
  sudo chown -R fulcrum:fulcrum /mnt/hdd/app-storage/fulcrum

  # create a symlink to /home/fulcrum/.fulcrum
  sudo ln -s /mnt/hdd/app-storage/fulcrum /home/fulcrum/.fulcrum
  sudo chown -R fulcrum:fulcrum /home/fulcrum/.fulcrum

  # Create a config file
  echo "# Getting RPC credentials from the bitcoin.conf"
  #read PASSWORD_B
  RPC_USER=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
  PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
  echo "\
datadir = /home/fulcrum/.fulcrum/db
bitcoind = 127.0.0.1:8332
rpcuser = ${RPC_USER}
rpcpassword = ${PASSWORD_B}
# RPi optimizations
# avoid 'bitcoind request timed out'
bitcoind_timeout = 600
# reduce load (4 cores only)
bitcoind_clients = 1
worker_threads = 1
db_mem=1024
# for 4GB RAM
db_max_open_files=200
fast-sync = 1024
# server connections
# disable peer discovery and public server options
peering = false
announce = false
tcp = 0.0.0.0:50021
# ssl via nginx
" | sudo -u fulcrum tee /home/fulcrum/.fulcrum/fulcrum.conf

  # Create a systemd service
  echo "\
[Unit]
Description=Fulcrum
After=network.target bitcoind.service
StartLimitBurst=2
StartLimitIntervalSec=20

[Service]
ExecStart=/home/fulcrum/Fulcrum-${fulcrumVersion}-${build}/Fulcrum /home/fulcrum/.fulcrum/fulcrum.conf
KillSignal=SIGINT
User=fulcrum
LimitNOFILE=8192
TimeoutStopSec=300
RestartSec=5
Restart=on-failure

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/fulcrum.service

  sudo systemctl enable fulcrum
  if [ "${state}" == "ready" ]; then
    sudo systemctl start fulcrum
  fi

  # sudo journalctl -fu fulcrum
  # sudo systemctl status fulcrum

  sudo ufw allow 50021 comment 'Fulcrum TCP'
  sudo ufw allow 50022 comment 'Fulcrum SSL'

  # Setting up the nginx.conf with the existing SSL cert
  isConfigured=$(sudo cat /etc/nginx/nginx.conf 2>/dev/null | grep -c 'upstream fulcrum')
  if [ ${isConfigured} -gt 0 ]; then
    echo "fulcrum is already configured with Nginx. To edit manually run 'sudo nano /etc/nginx/nginx.conf'"
  elif [ ${isConfigured} -eq 0 ]; then
    isStream=$(sudo cat /etc/nginx/nginx.conf 2>/dev/null | grep -c 'stream {')
    if [ ${isStream} -eq 0 ]; then
    echo "
stream {
        upstream fulcrum {
                server 127.0.0.1:50021;
        }
        server {
                listen 50022 ssl;
                proxy_pass fulcrum;
                ssl_certificate /mnt/hdd/app-data/nginx/tls.cert;
                ssl_certificate_key /mnt/hdd/app-data/nginx/tls.key;
                ssl_session_cache shared:SSL-fulcrum:1m;
                ssl_session_timeout 4h;
                ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
                ssl_prefer_server_ciphers on;
        }
}" | sudo tee -a /etc/nginx/nginx.conf

      elif [ ${isStream} -eq 1 ]; then
            sudo truncate -s-2 /etc/nginx/nginx.conf
            echo "
        upstream fulcrum {
                server 127.0.0.1:50021;
        }
        server {
                listen 50022 ssl;
                proxy_pass fulcrum;
                ssl_certificate /mnt/hdd/app-data/nginx/tls.cert;
                ssl_certificate_key /mnt/hdd/app-data/nginx/tls.key;
                ssl_session_cache shared:SSL-fulcrum:1m;
                ssl_session_timeout 4h;
                ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
                ssl_prefer_server_ciphers on;
        }
}" | sudo tee -a /etc/nginx/nginx.conf

    elif [ ${isStream} -gt 1 ]; then
      echo " Too many \`stream\` commands in nginx.conf. Please edit manually: \`sudo nano /etc/nginx/nginx.conf\` and retry"
      exit 1
    fi
  fi

  # test and reload nginx
  sudo nginx -t && sudo systemctl reload nginx

  # Tor
  /home/admin/config.scripts/tor.onion-service.sh fulcrum 50021 50021 50022 50022

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set fulcrum "on"
fi


if [ "$1" = off ]; then
  sudo systemctl disable fulcrum
  sudo systemctl stop fulcrum
  sudo userdel -rf fulcrum
  # remove Tor service
  /home/admin/config.scripts/tor.onion-service.sh off electrs
  # close ports on firewall
  sudo ufw deny 50021
  sudo ufw deny 50022
  # to remove the database directory:
  # sudo rm -rf /mnt/hdd/app-storage/fulcrum
  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set fulcrum "off"
fi
