#!/usr/bin/env bash

# TODO: later on this script will be run on build sdcard - make sure that the self-signed tls cert get created fresh on every new RaspiBlitz

source /mnt/hdd/raspiblitz.conf 2>/dev/null

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  printf "Manage RaspiBlitz Web Interface(s)\n\n"
  printf "blitz.web.sh check \t\tprint operational nginx listen status (lsof)\n"
  printf "blitz.web.sh http-on \t\tturn on basic http & api\n"
  printf "blitz.web.sh https-on \t\tturn on https (needs hdd)\n"
  printf "blitz.web.sh off \t\tturn off\n"
  exit 1
fi

###################
# CHECK
###################
if [ "$1" = "check" ]; then

  active_v4=$(sudo -u www-data lsof -i4 -sTCP:LISTEN -P | awk '{if(NR>1)print}' | awk '{ print $9 }' | awk -F":" '{ print $2, $1 " IPv4" }' | sort -nu)
  active_v6=$(sudo -u www-data lsof -i6 -sTCP:LISTEN -P | awk '{if(NR>1)print}' | awk '{ print $9 }' | awk -F":" '{ print $2, $1 " IPv6" }' | sort -nu)

  active=$(printf "${active_v4}\n${active_v6}" | sort -n)
  printf "Proto\tInterface\tPort\n"
  printf "=====\t=========\t====\n"
  echo "${active}" | awk '{ if($2 == "*") print $3 "\tany\t\t" $1; else print $3 "\t" $2 "\t" $1 }'

###################
# SWITCH ON-BASICS
###################
elif [ "$1" = "http-on" ]; then

  echo "Turning ON: Web HTTP"

  # install
  sudo apt-get update
  sudo apt-get install -y nginx apache2-utils

  # additional config
  sudo mkdir -p /etc/systemd/system/nginx.service.d
  sudo tee /etc/systemd/system/nginx.service.d/raspiblitz.conf >/dev/null <<EOF
    # DO NOT EDIT! This file is generate by raspiblitz and will be overwritten
[Unit]
After=network.target nss-lookup.target

[Service]
Restart=on-failure
TimeoutSec=120
RestartSec=60
EOF

  # general nginx settings
  if ! grep -Eq '^\s*server_names_hash_bucket_size.*$' /etc/nginx/nginx.conf; then
    # ToDo(frennkie) verify this
    sudo sed -i -E '/^.*server_names_hash_bucket_size [0-9]*;$/a \\tserver_names_hash_bucket_size 128;' /etc/nginx/nginx.conf
  fi
  if [ $(sudo cat /etc/nginx/nginx.conf | grep -c "# server_tokens off") -gt 0 ]; then
    sudo sed -i "s/# server_tokens off;/server_tokens off;/g" /etc/nginx/nginx.conf
  fi

  ### Welcome Server on HTTP Port 80
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo rm -f /var/www/html/index.nginx-debian.html
  sudo mkdir -p /var/www/letsencrypt/.well-known/acme-challenge
  sudo chown -R admin:www-data /var/www/letsencrypt
  sudo cp -a /home/admin/assets/nginx/www_public/ /var/www/public
  sudo chown www-data:www-data /var/www/public

  # enable public site & API redirect
  sudo cp /home/admin/assets/nginx/sites-available/public.conf /etc/nginx/sites-available/public.conf
  sudo ln -sf /etc/nginx/sites-available/public.conf /etc/nginx/sites-enabled/public.conf

  # make sure that it is enabled and started
  sudo systemctl enable nginx 
  sudo systemctl start nginx

###################
# SWITCH ON
###################
elif [ "$1" = "https-on" ]; then

  echo "Turning ON: Web HTTPS"

  # create nginx app-data dir
  sudo mkdir /mnt/hdd/app-data/nginx/ 2>/dev/null

  echo "# Checking dhparam.pem ..."
  if [ ! -f /etc/ssl/certs/dhparam.pem ]; then

    # check if there is a user generated dhparam.pem on the HDD to use
    userFileExists=$(sudo ls /mnt/hdd/app-data/nginx/dhparam.pem 2>/dev/null | grep -c dhparam.pem)
    if [ ${userFileExists} -eq 0 ]; then
      # generate dhparam.pem - can take +10 minutes on a Raspberry Pi
      echo "Generating a complete new dhparam.pem"
      echo "Running \"sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048\" next."
      sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048
      sudo cp /etc/ssl/certs/dhparam.pem /mnt/hdd/app-data/nginx/dhparam.pem
    else
      # just copy the already user generated dhparam.pem into nginx
      echo "Copying the user generetad /mnt/hdd/app-data/nginx/dhparam.pem"
      sudo cp /mnt/hdd/app-data/nginx/dhparam.pem /etc/ssl/certs/dhparam.pem
    fi

  else
    echo "# skip - dhparam.pem exists"
  fi

  # copy snippets
  sudo cp /home/admin/assets/nginx/snippets/* /etc/nginx/snippets/

  ### RaspiBlitz Webserver on HTTPS 443

  if ! [ -f /mnt/hdd/app-data/nginx/tls.cert ];then

    if [ -f /mnt/hdd/lnd/tls.cert ]; then
      # use LND cert by default
      echo "# use LND cert for: /mnt/hdd/app-data/nginx/tls.cert"
      sudo ln -sf /mnt/hdd/lnd/tls.cert /mnt/hdd/app-data/nginx/tls.cert
      sudo ln -sf /mnt/hdd/lnd/tls.key /mnt/hdd/app-data/nginx/tls.key
      sudo ln -sf /mnt/hdd/lnd/tls.cert /mnt/hdd/app-data/nginx/tor_tls.cert
      sudo ln -sf /mnt/hdd/lnd/tls.key /mnt/hdd/app-data/nginx/tor_tls.key
    else 
      echo "# exists /mnt/hdd/app-data/nginx/tls.cert"

      # create a self-signed cert if the LND cert is not present
      /home/admin/config.scripts/internet.selfsignedcert.sh   
  
      sudo ln -sf /mnt/hdd/app-data/selfsignedcert/selfsigned.cert \
                  /mnt/hdd/app-data/nginx/tls.cert
      sudo ln -sf /mnt/hdd/app-data/selfsignedcert/selfsigned.key \
                  /mnt/hdd/app-data/nginx/tls.key
      sudo ln -sf /mnt/hdd/app-data/selfsignedcert/selfsigned.cert \
                  /mnt/hdd/app-data/nginx/tor_tls.cert
      sudo ln -sf /mnt/hdd/app-data/selfsignedcert/selfsigned.key \
                  /mnt/hdd/app-data/nginx/tor_tls.key
    fi
  else
    echo "# exists /mnt/hdd/app-data/nginx/tls.cert"
  fi

  # make sure nginx process has permissions
  sudo chmod 744 /mnt/hdd/lnd/tls.key

  # restart NGINX
  sudo systemctl restart nginx


###################
# SWITCH OFF
###################
elif [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "Turning OFF: Web"

  sudo systemctl stop nginx
  sudo systemctl disable nginx >/dev/null

else
  echo "# FAIL: parameter not known - run with -h for help"
fi
