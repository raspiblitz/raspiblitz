#!/bin/bash

# https://github.com/cculianu/Fulcrum/releases
fulcrumVersion="1.6.0"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch the Fulcrum electrum server on or off"
  # echo "bonus.fulcrum.sh status [?showAddress]"
  echo "bonus.fulcrum.sh [on|off]"
  echo "installs the version $fulcrumVersion"
  exit 1
fi

# will use blitz.conf.sh in v1.7.2
function setConf {
  keystr=$1
  valuestr=$2
  configFile=$3
  # check if key needs to be added (prepare new entry)
  entryExists=$(grep -c "^${keystr}=" ${configFile})
  if [ ${entryExists} -eq 0 ]; then
    echo "${keystr}=" | sudo tee -a ${configFile}  # set value (sed needs sudo to operate when user is not root)  1>/dev/null
  fi
  # set value (sed needs sudo to operate when user is not root)
  sudo sed -i "s/^${keystr}=.*/${keystr}=${valuestr}/g" ${configFile}
}

if [ "$1" = on ]; then
  # ?wait until txindex finishes?
  /home/admin/config.scripts/network.txindex.sh on

  # ?activate zram?
  # https://github.com/rootzoll/raspiblitz/issues/2905

  # rpcworkqueue=512
  # rpcthreads=128
  # zmqpubhashblock=tcp://0.0.0.0:8433
  #/home/admin/config.scripts/blitz.conf.sh set rpcworkqueue 512 /mnt/hdd/bitcoin/bitcoin.conf noquotes
  #/home/admin/config.scripts/blitz.conf.sh set rpcthreads 128 /mnt/hdd/bitcoin/bitcoin.conf noquotes
  #/home/admin/config.scripts/blitz.conf.sh set zmqpubhashblock 'tcp:\/\/0.0.0.0:8433' /mnt/hdd/bitcoin/bitcoin.conf noquotes
  setConf rpcworkqueue 512 /mnt/hdd/bitcoin/bitcoin.conf
  setConf rpcthreads 128 /mnt/hdd/bitcoin/bitcoin.conf
  setConf zmqpubhashblock 'tcp:\/\/0.0.0.0:8433' /mnt/hdd/bitcoin/bitcoin.conf
  # enable for provision
  #source <(/home/admin/_cache.sh get state)
  #if [ "${state}" == "ready" ]; then
    sudo systemctl restart bitcoind
  #fi

  # create a dedicated user
  sudo adduser --disabled-password --gecos "" fulcrum
  cd /home/fulcrum

  # sudo -u fulcrum git clone https://github.com/cculianu/Fulcrum
  # cd fulcrum

  # dependencies
  # sudo apt install -y libzmq3-dev
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
  sudo -u fulcrum gpg --verify Fulcrum-${fulcrumVersion}-${build}.tar.gz.asc || exit 1

  # look for 'OK'
  sudo -u fulcrum sha256sum -c Fulcrum-${fulcrumVersion}-${build}.tar.gz.sha256sum || exit 1

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
bitcoind_timeout = 300
# reduce load (4 cores only)
bitcoind_clients = 1
worker_threads = 1
db_mem=1024

# for 4GB RAM
db_max_open_files=200
fast-sync = 1024

# for 8GB RAM
#db_max_open_files=500
#fast-sync = 2048

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

[Service]
ExecStart=/home/fulcrum/Fulcrum-${fulcrumVersion}-${build}/Fulcrum /home/fulcrum/.fulcrum/fulcrum.conf
User=fulcrum
LimitNOFILE=8192
TimeoutStopSec=30min
Restart=on-failure

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/fulcrum.service

  sudo systemctl enable fulcrum
  sudo systemctl start fulcrum

  # sudo journalctl -fu fulcrum
  # sudo systemctl status fulcrum

  sudo ufw allow 50021 comment 'Fulcrum TCP'
  sudo ufw allow 50022 comment 'Fulcrum SSL'

  # Set up SSL
  cd /home/fulcrum/.fulcrum

  # Create a self signed SSL certificate
  sudo -u fulcrum openssl genrsa -out selfsigned.key 2048

  echo "\
[req]
prompt             = no
default_bits       = 2048
default_keyfile    = selfsigned.key
distinguished_name = req_distinguished_name
req_extensions     = req_ext
x509_extensions    = v3_ca

[req_distinguished_name]
C = US
ST = Texas
L = Fulcrum
O = RaspiBlitz
CN = RaspiBlitz

[req_ext]
subjectAltName = @alt_names

[v3_ca]
subjectAltName = @alt_names

[alt_names]
DNS.1   = localhost
DNS.2   = 127.0.0.1
" | sudo -u fulcrum tee localhost.conf

  sudo -u fulcrum openssl req -new -x509 -sha256 -key selfsigned.key \
    -out selfsigned.cert -days 3650 -config localhost.conf

  # Setting up the nginx.conf
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
                ssl_certificate /home/fulcrum/.fulcrum/selfsigned.cert;
                ssl_certificate_key /home/fulcrum/.fulcrum/selfsigned.key;
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
                ssl_certificate /home/fulcrum/.fulcrum/selfsigned.cert;
                ssl_certificate_key /home/fulcrum/.fulcrum/selfsigned.key;
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
fi