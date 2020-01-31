#!/bin/bash

source /mnt/hdd/raspiblitz.conf

# script to set up nginx and the SSL certificate for BTCPay Server
# calls the config.scripts/internet.hiddenservice.sh for the Tor connection

HEIGHT=20
WIDTH=73
CHOICE_HEIGHT=2
BACKTITLE="RaspiBlitz"
TITLE="BTCPay Server Install"
MENU="Choose 'TOR' if you want to set up BTCPayServer
as a Tor Hidden service and use a self signed SSL certificate.\n\n
Choose 'DOMAIN' if you want to use a Domain Name or dynamicDNS
pointing to your public IP. You will need to forward ports from your
router to your RaspiBlitz and an email address to be used for
communication about the SSL certificate (very experimental).\n\n
For details or troubleshoot check for 'BTCPay'
in README of https://github.com/rootzoll/raspiblitz"
OPTIONS=(TOR "Tor access and a self-signed certificate"\
         DOMAIN "(Dynamic) Domain Name (experimental)")

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
  echo "user cancelled"
  exit 1
fi

clear
case $CHOICE in

        DOMAIN)
            echo "setting up with own domain"
            ownDomain=1
            ;;
        TOR) 
            echo "setting up for Tor only"
            if [ "${runBehindTor}" != "on" ]; then
            whiptail --title " TOR needs be installed first " --msgbox "\
Please activate TOR service first to use this option.
Use 'Run behind TOR' in the SERVICES submenu.
Once TOR is running, choose this option again. 
" 9 58
              exit 1
            fi
            ownDomain=0
            ;;
esac

if [ ${#ownDomain} -eq 0 ]; then
  echo "user cancelled"
  exit 1
fi

# add default value to raspi config if needed
if ! grep -Eq "^BTCPayDomain=" /mnt/hdd/raspiblitz.conf; then
  echo "BTCPayDomain=off" >> /mnt/hdd/raspiblitz.conf
fi

echo ""
echo "***"
echo "Setting up Nginx and Certbot"
echo "***"
echo ""

if [ $ownDomain -eq 1 ]; then
  localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  echo ""
  echo "***"
  echo "Confirm that the ports 80, 443 and 9735 are forwarded to your RaspiBlitz" 
  echo ""
  echo "Press [ENTER] to continue or use [CTRL + C] to exit"
  echo ""
  echo "Example settings for your router:"
  echo "forward the port 443 to port 443 on ${localip}"
  echo "forward the port 9735 to port 9735 on ${localip}"
  echo "forward the port 80 to port 80 on ${localip}"
  read key
  
  echo ""
  echo "***"
  echo "Type your domain or dynamicDNS pointing to your public IP and press [ENTER] or use [CTRL + C] to exit"
  echo ""
  echo "Example:"
  echo "btcpay.example.com"
  read YOUR_DOMAIN

  echo ""
  echo "***"
  echo "Type an email address that will be used to message about the expiration of the SSL certificate and press [ENTER] or use [CTRL + C] to exit"
  echo ""
  echo "Example:"
  echo "name@email.com"
  read YOUR_EMAIL
  
  echo ""
  echo "***"
  echo "Creating the btcpay user"
  echo "***"
  echo ""

  # install nginx and certbot
  sudo apt-get install nginx-full certbot -y
  
  sudo ufw allow 80 comment 'HTTP web server'
  sudo ufw allow 443 comment 'btcpayserver SSL'
  
  # get SSL cert
  sudo systemctl stop certbot 2>/dev/null
  sudo certbot certonly -a standalone -m $YOUR_EMAIL --agree-tos -d $YOUR_DOMAIN -n --pre-hook "service nginx stop" --post-hook "service nginx start"

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
  
  # disable certbot
  sudo systemctl stop certbot.timer 2>/dev/null
  sudo systemctl disable certbot.timer 2>/dev/null
  sudo systemctl stop certbot 2>/dev/null
  sudo systemctl disable certbot 2>/dev/null
  
  # create a self-signed ssl certificate
  /home/admin/config.scripts/internet.selfsignedcert.sh
  
  # allow the HTTPS connection through the firewall
  sudo ufw allow 443 comment 'Nginx'

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
    listen 23001 default_server;
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

# setting value in raspi blitz config
sudo sed -i "s/^BTCPayDomain=.*/BTCPayDomain=$YOUR_DOMAIN/g" /mnt/hdd/raspiblitz.conf

if [ $ownDomain -eq 0 ]; then
  # Hidden Service for BTCPay if Tor active
  /home/admin/config.scripts/internet.hiddenservice.sh btcpay 80 23000
fi

echo "OK done - check the new option 'BTCPAY' on main menu for more info." 
