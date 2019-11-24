#!/bin/bash

# Based on: https://gist.github.com/normandmickey/3f10fc077d15345fb469034e3697d0d0 

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch BTCPay Server on or off"
 echo "bonus.btcpayserver.sh [on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if [ ${#BTCPayServer} -eq 0 ]; then
  echo "BTCPayServer=off" >> /mnt/hdd/raspiblitz.conf
fi
    
  # stop service
  echo "making sure services are not running"
  sudo systemctl stop btcpayserver 2>/dev/null
  sudo systemctl disable btcpayserver 2>/dev/null
  
# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL BTCPAYSERVER ***"
  
  isInstalled=$(sudo ls /etc/systemd/system/btcpayserver.service 2>/dev/null | grep -c 'btcpayserver.service')
  if [ ${isInstalled} -eq 0 ]; then
    echo ""
    echo "***"
    echo "Confirm that the port 80, 443 and 9735 are forwarded to the IP of the RaspiBlitz by pressing [ENTER]" 
    read key
    
    echo ""
    echo "***"
    echo "Type the domain/ddns you want to use for BTCPayServer and press [ENTER]"
    read YOUR_DOMAIN
    
    echo ""
    echo "***"
    echo "Type an email address that will be used to register the SSL certificate and press [ENTER]"
    read YOUR_EMAIL
    
    echo ""
    echo "***"
    echo "Creating the btcpay user"
    echo "***"
    echo ""
    sudo adduser --disabled-password --gecos "" btcpay 2>/dev/null
    cd /home/btcpay
    
    # store BTCpay data on HDD
    sudo mkdir /mnt/hdd/.btcpayserver 2>/dev/null
    
    sudo mv -f /home/admin/.btcpayserver /mnt/hdd/ 2>/dev/null
    sudo rm -rf /home/admin/.btcpayserver
    sudo mv -f /home/btcpay/.btcpayserver /mnt/hdd/ 2>/dev/null
    
    sudo chown -R btcpay:btcpay /mnt/hdd/.btcpayserver
    sudo ln -s /mnt/hdd/.btcpayserver /home/btcpay/ 2>/dev/null
    
    # clean when installed as admin
    sudo rm -f /home/admin/dotnet-sdk*
    sudo rm -f /home/admin/dotnet-sdk*
    sudo rm -f /home/admin/.nbxplorer/Main/settings.config
  
    # cleanup previous installs
    sudo rm -f /home/btcpay/dotnet-sdk*
    sudo rm -f /home/btcpay/aspnetcore*
    sudo rm -rf /home/btcpay/dotnet
    sudo rm -f /usr/local/bin/dotnet
    
    sudo systemctl stop nbxplorer 2>/dev/null
    sudo systemctl disable nbxplorer 2>/dev/null
    sudo rm -f /home/btcpay/.nbxplorer/Main/settings.config
    sudo rm -f /etc/systemd/system/nbxplorer.service
    
    sudo rm -f /home/btcpay/.btcpayserver/Main/settings.config
    sudo rm -f /etc/systemd/system/btcpayserver.service
    sudo rm -f /etc/nginx/sites-available/btcpayserver
    
    echo ""
    echo "***"
    echo "Installing .NET"
    echo "***"
    echo ""
    
    # download dotnet-sdk
    sudo apt-get -y install libunwind8 gettext libssl1.0
    sudo -u btcpay wget https://download.visualstudio.microsoft.com/download/pr/94409a9a-41e3-4df9-83bc-9e23ed96abaf/2b75460d9a8eef8361c01bafc1783fab/dotnet-sdk-2.1.607-linux-arm.tar.gz
    # check binary is was not manipulated (checksum test)
    dotnetName="dotnet-sdk-2.1.607-linux-arm.tar.gz"
    binaryChecksum="2cd8fa250e6a0e81faf409e7dc4f6d581117f565d58cff48b31f457e7cafc7f3cfe0de0df2b1c5d035733879750eb2af22fcc950720a7a7192e4221318052838"
    actualChecksum=$(sha512sum /home/btcpay/${dotnetName} | cut -d " " -f1)
    if [ "${actualChecksum}" != "${binaryChecksum}" ]; then
      echo "!!! FAIL !!! Downloaded ${dotnetName} not matching SHA512 checksum: ${binaryChecksum}"
      exit 1
    fi
  
    # download aspnetcore-runtime
    sudo -u btcpay wget https://download.visualstudio.microsoft.com/download/pr/9c563df7-736b-49ce-bd17-e739f3765541/e93dd1eff909e59a7ba72784a64dc031/aspnetcore-runtime-2.1.14-linux-arm.tar.gz
    # check binary is was not manipulated (checksum test)
    aspnetcoreName="aspnetcore-runtime-2.1.14-linux-arm.tar.gz"
    binaryChecksum="f4500187bf135254a03b5eb4105b8ce20f71d71e0f08c2c2ec914920f80435b7b36351c3f9c15504d0b1c2187b904c8283db67a2b60ebff374b058641153aaac"
    actualChecksum=$(sha512sum /home/btcpay/${aspnetcoreName} | cut -d " " -f1)
    if [ "${actualChecksum}" != "${binaryChecksum}" ]; then
      echo "!!! FAIL !!! Downloaded ${aspnetcoreName} not matching SHA512 checksum: ${binaryChecksum}"
      exit 1
    fi
  
    sudo -u btcpay mkdir /home/btcpay/dotnet
    sudo -u btcpay tar -xvf ${dotnetName} -C /home/btcpay/dotnet
    sudo -u btcpay tar -xvf ${aspnetcoreName} -C /home/btcpay/dotnet
    
    # opt out of telemetry
    echo "DOTNET_CLI_TELEMETRY_OPTOUT=1" | sudo tee -a /etc/environment
    
    sudo ln -s /home/btcpay/dotnet/dotnet /usr/local/bin
    sudo -u btcpay /home/btcpay/dotnet/dotnet --info
    
    echo ""
    echo "***"
    echo "Installing NBXplorer"
    echo "***"
    echo ""
    
    cd /home/btcpay
    sudo -u btcpay git clone https://github.com/dgarage/NBXplorer.git
    cd NBXplorer
    # checkout from last known to work commit:
    # https://github.com/dgarage/NBXplorer/commit/6069d0a06aae467cab41ea509450222d45fb9c04
    # check https://github.com/dgarage/NBXplorer/commits/master
    sudo -u btcpay git checkout 6069d0a06aae467cab41ea509450222d45fb9c04
    sudo -u btcpay ./build.sh
    
    echo "
[Unit]
Description=NBXplorer daemon
Requires=bitcoind.service
After=bitcoind.service

[Service]
ExecStart=/usr/local/bin/dotnet \"/home/btcpay/NBXplorer/NBXplorer/bin/Release/netcoreapp2.1/NBXplorer.dll\" -c /home/btcpay/.nbxplorer/Main/settings.config
User=btcpay
Group=btcpay
pe=simple
PIDFile=/run/nbxplorer/nbxplorer.pid
Restart=on-failure

PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee -a /etc/systemd/system/nbxplorer.service
  
    sudo systemctl daemon-reload
    # restart to create settings.config if was running already
    sudo systemctl restart nbxplorer
    sudo systemctl enable nbxplorer
    sudo systemctl start nbxplorer
    
    echo "Checking for nbxplorer config"
    while [ ! -f "/home/btcpay/.nbxplorer/Main/settings.config" ]
      do
        echo "Waiting for nbxplorer to start - CTRL+C to abort"
        sleep 10
    done
    
    echo ""
    echo "***"
    echo "getting RPC credentials from the bitcoin.conf"
    RPC_USER=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
    PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
    #sudo mv /home/btcpay/.nbxplorer/Main/settings.config /home/admin/settings.config
    #sudo chown admin:admin /home/admin/settings.config
    sudo mv /home/btcpay/.nbxplorer/Main/settings.config /home/btcpay/.nbxplorer/Main/settings.config.backup
    touch /home/admin/settings.config
    sudo chmod 600 /home/admin/settings.config || exit 1
    cat >> /home/admin/settings.config <<EOF
btc.rpc.user=raspibolt
btc.rpc.password=$PASSWORD_B
EOF

    sudo mv /home/admin/settings.config /home/btcpay/.nbxplorer/Main/settings.config
    sudo chown btcpay:btcpay /home/btcpay/.nbxplorer/Main/settings.config
    sudo systemctl restart nbxplorer
    
    echo ""
    echo "***"
    echo "Installing BTCPayServer"
    echo "***"
    echo ""
    
    cd /home/btcpay
    sudo -u btcpay git clone https://github.com/btcpayserver/btcpayserver.git
    cd btcpayserver
    # https://github.com/btcpayserver/btcpayserver/releases 
    sudo -u btcpay git reset --hard v1.0.3.144 
    sudo -u btcpay ./build.sh
    
    echo "
[Unit]
Description=BtcPayServer daemon
Requires=btcpayserver.service
After=nbxplorer.service

[Service]
ExecStart=/usr/local/bin/dotnet run --no-launch-profile --no-build -c Release -p \"/home/btcpay/btcpayserver/BTCPayServer/BTCPayServer.csproj\" -- \$@
User=btcpay
Group=btcpay
Type=simple
PIDFile=/run/btcpayserver/btcpayserver.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
" | sudo tee -a /etc/systemd/system/btcpayserver.service
  
    sudo systemctl daemon-reload
    sudo systemctl enable btcpayserver
    sudo systemctl start btcpayserver
    
    # set thumbprint
    FINGERPRINT=$(openssl x509 -noout -fingerprint -sha256 -inform pem -in /home/admin/.lnd/tls.cert | cut -c 20-)
    sudo cp /mnt/hdd/lnd/data/chain/bitcoin/mainnet/admin.macaroon /home/btcpay/admin.macaroon
    sudo chown btcpay:btcpay /home/btcpay/admin.macaroon
    sudo chmod 600 /home/btcpay/admin.macaroon
    echo "
### Global settings ###
network=mainnet

### Server settings ###
port=23000
bind=127.0.0.1
externalurl=https://$YOUR_DOMAIN

### NBXplorer settings ###
BTC.explorer.url=http://127.0.0.1:24444/
BTC.lightning=type=lnd-rest;server=https://127.0.0.1:8080/;macaroonfilepath=/home/btcpay/admin.macaroon;certthumbprint=$FINGERPRINT
" | sudo -u btcpay tee -a /home/btcpay/.btcpayserver/Main/settings.config

    sudo systemctl restart btcpayserver
    
    echo ""
    echo "***"
    echo "Setting up Nginx and Certbot"
    echo "***"
    echo ""
    
    # install nginx and certbot
    sudo apt-get install nginx-full certbot -y
    
    sudo ufw allow 80
    sudo ufw allow 443
    
    # get SSL cert
    sudo systemctl stop certbot 2>/dev/null
    sudo certbot certonly -a standalone -m $YOUR_EMAIL --agree-tos -d $YOUR_DOMAIN --pre-hook "service nginx stop" --post-hook "service nginx start"
  
    # set nginx
    sudo rm -f /etc/nginx/sites-enabled/default
    
    echo "
# If we receive X-Forwarded-Proto, pass it through; otherwise, pass along the
# scheme used to connect to this server
map \$http_x_forwarded_proto \$proxy_x_forwarded_proto {
  default \$http_x_forwarded_proto;
  ''      \$scheme;
}
# If we receive X-Forwarded-Port, pass it through; otherwise, pass along the
# server port the client connected to
map \$http_x_forwarded_port \$proxy_x_forwarded_port {
  default \$http_x_forwarded_port;
  ''      \$server_port;
}
# If we receive Upgrade, set Connection to \"upgrade\"; otherwise, delete any
# Connection header that may have been passed to this server
map \$http_upgrade \$proxy_connection {
  default upgrade;
  '' close;
}
# Apply fix for very long server names
#server_names_hash_bucket_size 128;
# Prevent Nginx Information Disclosure
server_tokens off;
# Default dhparam
# Set appropriate X-Forwarded-Ssl header
map \$scheme \$proxy_x_forwarded_ssl {
  default off;
  https on;
}

gzip_types text/plain text/css application/javascript application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;
log_format vhost '\$host \$remote_addr - \$remote_user [\$time_local] '
                 '\"\$request\" \$status \$body_bytes_sent '
                 '\"\$http_referer\" \"\$http_user_agent\"';
access_log off;
# HTTP 1.1 support
proxy_http_version 1.1;
proxy_buffering off;
proxy_set_header Host \$http_host;
proxy_set_header Upgrade \$http_upgrade;
proxy_set_header Connection \$proxy_connection;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$proxy_x_forwarded_proto;
proxy_set_header X-Forwarded-Ssl \$proxy_x_forwarded_ssl;
proxy_set_header X-Forwarded-Port \$proxy_x_forwarded_port;
# Mitigate httpoxy attack (see README for details)
proxy_set_header Proxy \"\";


server {
    listen 80 default_server;
    server_name _;
    return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl;
  server_name $YOUR_DOMAIN;
  ssl on;

  ssl_certificate /etc/letsencrypt/live/$YOUR_DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$YOUR_DOMAIN/privkey.pem;
  ssl_session_timeout 1d;
  ssl_session_cache shared:SSL:50m;
  ssl_session_tickets off;
  ssl_protocols TLSv1.1 TLSv1.2;
  ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!3DES:!MD5:!PSK';
  ssl_prefer_server_ciphers on;
  ssl_stapling on;
  ssl_stapling_verify on;
  ssl_trusted_certificate /etc/letsencrypt/live/$YOUR_DOMAIN/chain.pem;

  location / {
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_pass http://localhost:23000;
  }
}
" | sudo tee -a /etc/nginx/sites-available/btcpayserver

    sudo ln -s /etc/nginx/sites-available/btcpayserver /etc/nginx/sites-enabled/ 2>/dev/null
    
    sudo systemctl restart nginx
    
    echo ""
    echo "***"
    echo "Setting up certbot-auto renewal service"
    echo "***"
    echo ""
    
    sudo rm -f /etc/systemd/system/certbot.timer
    echo "
[Unit]
Description=Certbot-auto renewal service

[Timer]
OnBootSec=20min
OnCalendar=*-*-* 4:00:00

[Install]
WantedBy=timers.target
" | sudo tee -a /etc/systemd/system/certbot.timer

    sudo rm -f /etc/systemd/system/certbot.service
    echo "
[Unit]
Description=Certbot-auto renewal service
After=bitcoind.service

[Service]
WorkingDirectory=/home/admin/
ExecStart=sudo certbot renew --pre-hook \"service nginx stop\" --post-hook \"service nginx start\"

User=admin
Group=admin
Type=simple
KillMode=process
TimeoutSec=60
Restart=always
RestartSec=60
" | sudo tee -a /etc/systemd/system/certbot.service

    sudo systemctl enable certbot.timer
  
  else 
    echo "BTCPayServer is already installed."
    # start service
    echo "start service"
    sudo systemctl start btcpayserver 2>/dev/null
  fi

  # setting value in raspiblitz config
  sudo sed -i "s/^BTCPayServer=.*/BTCPayServer=on/g" /mnt/hdd/raspiblitz.conf

  # Hidden Service for BTCPay if Tor active
  source /mnt/hdd/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
    isTor=$(sudo cat /etc/tor/torrc 2>/dev/null | grep -c 'btcpay')
    if [ ${isTor} -eq 0 ]; then
        echo "
# Hidden Service for BTCPayServer
HiddenServiceDir /mnt/hdd/tor/btcpay
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:23000
" | sudo tee -a /etc/tor/torrc

      sudo systemctl restart tor
      sleep 2
    else
      echo "The Hidden Service is already installed"
    fi
    
    TOR_ADDRESS=$(sudo cat /mnt/hdd/tor/btcpay/hostname)
    if [ -z "$TOR_ADDRESS" ]; then
      echo "Waiting for the Hidden Service"
      sleep 10
      TOR_ADDRESS=$(sudo cat /mnt/hdd/tor/btcpay/hostname)
      if [ -z "$TOR_ADDRESS" ]; then
        echo " FAIL - The Hidden Service address could not be found - Tor error?"
        exit 1
      fi
    fi   
    echo ""
    echo "***"
    echo "The Tor Hidden Service address for BTCPayServer is:"
    echo "$TOR_ADDRESS"
    echo "***"
    echo "" 
  fi

  echo ""
  echo "Visit your BTCpayServer instance on https://$YOUR_DOMAIN"
  echo ""

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^BTCPayServer=.*/BTCPayServer=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/btcpayserver.service 2>/dev/null | grep -c 'btcpayserver.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** REMOVING BTCPAYSERVER ***"
    sudo systemctl stop btcpayserver
    sudo systemctl disable btcpayserver
    sudo rm /etc/systemd/system/btcpayserver.service
   
    sudo rm -f /home/btcpay/dotnet-sdk*
    sudo rm -f /home/btcpay/aspnetcore*
    sudo rm -rf /home/btcpay/dotnet
    sudo rm -f /usr/local/bin/dotnet
    
    sudo systemctl stop nbxplorer 2>/dev/null
    sudo systemctl disable nbxplorer 2>/dev/null
    sudo rm -f /home/btcpay/.nbxplorer/Main/settings.config
    sudo rm -f /etc/systemd/system/nbxplorer.service
    
    sudo rm -f /home/btcpay/.btcpayserver/Main/settings.config
    sudo rm -f /etc/systemd/system/btcpayserver.service
    sudo rm -f /etc/nginx/sites-available/btcpayserver    
    echo "OK BTCPayServer removed."
  else 
    echo "BTCPayServer is not installed."
  fi
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1