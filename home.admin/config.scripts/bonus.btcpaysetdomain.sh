#!/bin/bash

# script to set up nginx and the SSL certificate for BTCPay Server
# calls the config.scripts/internet.hiddenservice.sh for the Tor connection

HEIGHT=20
WIDTH=73
CHOICE_HEIGHT=2
BACKTITLE="RaspiBlitz"
TITLE=""
MENU="Choose 'DOMAIN' if you want to use a Domain Name or dynamicDNS 
pointing to your public IP.\n
You will need the ports 80, 443 and 9735 forwarded to your RaspiBlitz
and an email address to be used for communication about the SSL certificate.\n\n
Choose 'TOR' if you want to set up BTCPayServer
as a Tor Hidden service and use a self signed SSL certificate.\n\n
Find more information about using the BTCPayServer on the RaspiBlitz here:
https://github.com/openoms/bitcoin-tutorials/tree/master/BTCPayServer"
OPTIONS=(DOMAIN "use a Domain Name or dynamicDNS" \
          TOR "Tor access and a self-signed certificate")

CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

dialogcancel=$?
echo "done dialog"
clear

# check if user canceled dialog
echo "dialogcancel(${dialogcancel})"
if [ ${dialogcancel} -eq 1 ]; then
  echo "user canceled"
  exit 1
fi

clear
case $CHOICE in

        DOMAIN)
            echo "setting up with own domain"
            ownDomain=1
            exit 0
            ;;
        TOR) 
            echo "setting up for Tor only"
            ownDomain=0
            exit 0
            ;;
esac

if [ $? -eq 0 ]; then
  echo "setting up with own domain"
  ownDomain=1
else
  echo "setting up for Tor only"
  ownDomain=0
fi

echo ""
echo "***"
echo "Setting up Nginx and Certbot"
echo "***"
echo ""

if [ $ownDomain -eq 1 ]; then
  echo ""
  echo "***"
  echo "Confirm that the port 80, 443 and 9735 are forwarded to the IP of the RaspiBlitz by pressing [ENTER]"
  echo "Use CTRL + C to EXIT" 
  read key
  
  echo ""
  echo "***"
  echo "Type the domain/ddns you want to use for BTCPayServer and press [ENTER]"
  echo "Use CTRL + C to EXIT" 
  read YOUR_DOMAIN
  
  echo ""
  echo "***"
  echo "Type an email address that will be used to register the SSL certificate and press [ENTER]"
  echo "Use CTRL + C to EXIT" 
  read YOUR_EMAIL
  
  echo ""
  echo "***"
  echo "Creating the btcpay user"
  echo "***"
  echo ""

  # install nginx and certbot
  sudo apt-get install nginx-full certbot -y
  
  sudo ufw allow 80 comment 'btcpayserver TCP'
  sudo ufw allow 443 comment 'btcpayserver SSL'
  
  # get SSL cert
  sudo systemctl stop certbot 2>/dev/null
  sudo certbot certonly -a standalone -m $YOUR_EMAIL --agree-tos -d $YOUR_DOMAIN --pre-hook "service nginx stop" --post-hook "service nginx start"

  # set nginx
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo rm -f /etc/nginx/sites-enabled/btcpayserver
  sudo rm -f /etc/nginx/sites-available/btcpayserver
  
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
    
elif [ $ownDomain -eq 0 ]; then

  YOUR_DOMAIN=localhost
  # create a self-signed ssl certificate
  /home/admin/config.scripts/internet.selfsignedcert.sh
  # set nginx
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo rm -f /etc/nginx/sites-enabled/btcpayserver
  sudo rm -f /etc/nginx/sites-available/btcpayserver
  
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

  ssl_certificate /etc/ssl/certs/localhost.crt;
  ssl_certificate_key /etc/ssl/private/localhost.key;
  ssl_session_timeout 1d;
  ssl_session_cache shared:SSL:50m;
  ssl_session_tickets off;
  ssl_protocols TLSv1.1 TLSv1.2;
  ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!3DES:!MD5:!PSK';
  ssl_prefer_server_ciphers on;
  ssl_stapling off;
  ssl_stapling_verify on;

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
fi

if [ $ownDomain -eq 1 ]; then
  echo ""
  echo "Visit your BTCpayServer instance on https://$YOUR_DOMAIN"
  echo ""
elif [ $ownDomain -eq 0 ]; then
  # Hidden Service for BTCPay if Tor active
  source /mnt/hdd/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
      /home/admin/config.scripts/internet.hiddenservice.sh btcpay 80 23000
  
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
      echo "Open the Hidden Service address in the Tor Browser to connect to your BTCPayServer instance."
      echo "$TOR_ADDRESS"
      echo "***"
      echo "" 
  fi
  localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  echo ""
  echo "Open https://$localip in a browser to visit your BTCPayServer on your Local Network." 
  echo "Will need to accept the self-signed certificate in the browser to be able to connect outside of the Tor Browser"
  echo ""
fi
