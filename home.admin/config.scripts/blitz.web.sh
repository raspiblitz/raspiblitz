#!/usr/bin/env bash

source /mnt/hdd/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  printf "Manage RaspiBlitz Web Interface(s)\n\n"
  printf "blitz.web.sh check \t\tprint operational nginx listen status (lsof)\n"
  printf "blitz.web.sh on \t\tturn on\n"
  printf "blitz.web.sh off \t\tturn off\n"
  printf "blitz.web.sh listen localhost \tset port 443 to localhost only\n"
  printf "blitz.web.sh listen any \tset port 443 to any\n"
  exit 1
fi

# using ${APOST} is a workaround to be able to use sed with '
APOST=\'  # close tag for linters: '


###################
# FUNCTIONS
###################
function set_nginx_blitzweb_listen() {
   # first parameter to function should be either "localhost" or "any"
   listen_to=${1}

   if [ -f "/etc/nginx/sites-available/blitzweb.conf" ]; then
       if ! grep -Eq '^\s*#?\s*listen 127.0.0.1:443 ssl default_server;$' /etc/nginx/sites-available/blitzweb.conf; then
           echo "Error: missing expected line for: lo:v4 https"
           exit 1
       else
           if grep -Eq '^\s*#\s*listen 127.0.0.1:443 ssl default_server;$' /etc/nginx/sites-available/blitzweb.conf; then
           #echo "found: lo:v4 https (disabled line)"
               if [ ${listen_to} = "localhost" ]; then
                   sudo sed -i -E 's/#\s*(listen 127.0.0.1:443 ssl default_server;)/\1/g' /etc/nginx/sites-available/blitzweb.conf
               fi
           else
               #echo "found: lo:v4 https (enabled line)"
               if [ ${listen_to} = "any" ]; then
                   sudo sed -i -E 's/(listen 127.0.0.1:443 ssl default_server;)/#\1/g' /etc/nginx/sites-available/blitzweb.conf
               fi
          fi

       fi

       if ! grep -Eq '^\s*#?\s*listen \[::1\]:443 ssl default_server;$' /etc/nginx/sites-available/blitzweb.conf; then
           echo "Error: missing expected line for: lo:v6 https"
           exit 1
       else
           if grep -Eq '^\s*#\s*listen \[::1\]:443 ssl default_server;$' /etc/nginx/sites-available/blitzweb.conf; then
               #echo "found: lo:v6 https (disabled line)"
               if [ ${listen_to} = "localhost" ]; then
                   sudo sed -i -E 's/#\s*(listen \[::1\]:443 ssl default_server;)/\1/g' /etc/nginx/sites-available/blitzweb.conf
               fi
           else
               #echo "found: lo:v6 https (enabled line)"
               if [ ${listen_to} = "any" ]; then
                   sudo sed -i -E 's/(listen \[::1\]:443 ssl default_server;)/#\1/g' /etc/nginx/sites-available/blitzweb.conf
               fi
           fi

       fi

       if ! grep -Eq '^\s*#?\s*listen 443 ssl default_server;$' /etc/nginx/sites-available/blitzweb.conf; then
           echo "Error: missing expected line for: any:v4 https"
           exit 1
       else
           if grep -Eq '^\s*#\s*listen 443 ssl default_server;$' /etc/nginx/sites-available/blitzweb.conf; then
               #echo "found: any:v4 https (disabled line)"
               if [ ${listen_to} = "any" ]; then
                   sudo sed -i -E 's/#\s*(listen 443 ssl default_server;)/\1/g' /etc/nginx/sites-available/blitzweb.conf
               fi
           else
               #echo "found: any:v4 https (enabled line)"
               if [ ${listen_to} = "localhost" ]; then
                   sudo sed -i -E 's/(listen 443 ssl default_server;)/#\1/g' /etc/nginx/sites-available/blitzweb.conf
               fi
           fi

       fi

       if ! grep -Eq '^\s*#?\s*listen \[::\]:443 ssl default_server;$' /etc/nginx/sites-available/blitzweb.conf; then
           echo "Error: missing expected line for: any:v6 https"
           exit 1
       else
           if grep -Eq '^\s*#\s*listen \[::\]:443 ssl default_server;$' /etc/nginx/sites-available/blitzweb.conf; then
               #echo "found: any:v6 https (disabled line)"
               if [ ${listen_to} = "any" ]; then
                   sudo sed -i -E 's/#\s*(listen \[::\]:443 ssl default_server;)/\1/g' /etc/nginx/sites-available/blitzweb.conf
               fi
           else
               #echo "found: any:v6 https (enabled line)"
               if [ ${listen_to} = "localhost" ]; then
                   sudo sed -i -E 's/(listen \[::\]:443 ssl default_server;)/#\1/g' /etc/nginx/sites-available/blitzweb.conf
               fi
           fi
       fi
   fi
}



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
# SWITCH ON
###################
elif [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "Turning ON: Web"

  # install
  sudo apt-get update
  sudo apt-get install -y nginx apache2-utils

  # additional config
  sudo mkdir -p /etc/systemd/system/nginx.service.d
  sudo tee /etc/systemd/system/nginx.service.d/raspiblitz.conf >/dev/null <<EOF
    # DO NOT EDIT! This file is generate by raspiblitz and will be overwritten
[Unit]
After=network.target nss-lookup.target mnt-hdd.mount
EOF

  # make sure that it is enabled and started
  sudo systemctl enable nginx 
  sudo systemctl start nginx

  # create nginx app-data dir
  sudo mkdir /mnt/hdd/app-data/nginx/ 2>/dev/null

  # general nginx settings
  if ! grep -Eq '^\s*server_names_hash_bucket_size.*$' /etc/nginx/nginx.conf; then
    # ToDo(frennkie) verify this
    sudo sed -i -E '/^.*server_names_hash_bucket_size [0-9]*;$/a \\tserver_names_hash_bucket_size 128;' /etc/nginx/nginx.conf
  fi

  if [ ! -f /etc/ssl/certs/dhparam.pem ]; then

    # check if there is a user generated dhparam.pem on the HDD to use
    userFileExists=$(sudo ls /mnt/hdd/app-data/nginx/dhparam.pem 2>/dev/null | grep -c dhparam.pem)
    if [ ${userFileExists} -eq 0 ]; then
      # generate dhparam.pem - can take +10 minutes on a Raspberry Pi
      echo "Generating a complete new dhparam.pem"
      echo "Running \"sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048\" next."
      echo "This can take 5-10 minutes on a Raspberry Pi 3 - please be patient!"
      sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048
      sudo cp /etc/ssl/certs/dhparam.pem /mnt/hdd/app-data/nginx/dhparam.pem
    else
      # just copy the already user generated dhparam.pem into nginx
      echo "Copying the user generetad /mnt/hdd/app-data/nginx/dhparam.pem"
      sudo cp /mnt/hdd/app-data/nginx/dhparam.pem /etc/ssl/certs/dhparam.pem
    fi

  fi

  sudo cp /home/admin/assets/nginx/snippets/* /etc/nginx/snippets/

  ### Welcome Server on HTTP Port 80
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo rm -f /var/www/html/index.nginx-debian.html

  if ! [ -f /etc/nginx/sites-available/public.conf ]; then
    sudo cp /home/admin/assets/nginx/sites-available/public.conf /etc/nginx/sites-available/public.conf
  fi

  if ! [ -d /var/www/letsencrypt/.well-known/acme-challenge ]; then
    sudo mkdir -p /var/www/letsencrypt/.well-known/acme-challenge
  fi

  # make sure admin can write here even without sudo
  sudo chown -R admin:www-data /var/www/letsencrypt

  # copy webroot
  if ! [ -d /var/www/public ]; then
    sudo cp -a /home/admin/assets/nginx/www_public/ /var/www/public
    sudo chown www-data:www-data /var/www/public
  fi

  sudo ln -sf /etc/nginx/sites-available/public.conf /etc/nginx/sites-enabled/public.conf

  ### RaspiBlitz Webserver on HTTPS 443

  # copy webroot
  if ! [ -d /var/www/blitzweb ]; then
      sudo cp -a /home/admin/assets/nginx/www_blitzweb/ /var/www/blitzweb
      sudo chown www-data:www-data /var/www/blitzweb
  fi

  # make sure jinja2 is installed and install j2cli
  sudo apt-get install -y python3-jinja2
  sudo -H python3 -m pip install j2cli

  if [ -f /mnt/hdd/app-data/nginx/tls.cert ];then
    if [ -f /mnt/hdd/lnd/tls.cert ]; then
      # use LND cert by default
      sudo ln -sf /mnt/hdd/lnd/tls.cert /mnt/hdd/app-data/nginx/tls.cert
      sudo ln -sf /mnt/hdd/lnd/tls.key /mnt/hdd/app-data/nginx/tls.key
      sudo ln -sf /mnt/hdd/lnd/tls.cert /mnt/hdd/app-data/nginx/tor_tls.cert
      sudo ln -sf /mnt/hdd/lnd/tls.key /mnt/hdd/app-data/nginx/tor_tls.key
    else 
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
  fi

  # config
  sudo cp /home/admin/assets/blitzweb.conf /etc/nginx/sites-available/blitzweb.conf
  sudo ln -sf /etc/nginx/sites-available/blitzweb.conf /etc/nginx/sites-enabled/

  if ! [ -f /etc/nginx/.htpasswd ]; then
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
    echo "${PASSWORD_B}" | sudo htpasswd -c -i /etc/nginx/.htpasswd admin
    sudo chown www-data:www-data /etc/nginx/.htpasswd
    sudo chmod 640 /etc/nginx/.htpasswd

  else
    sudo chown www-data:www-data /etc/nginx/.htpasswd
    sudo chmod 640 /etc/nginx/.htpasswd
  fi

  # restart NGINX
  sudo systemctl restart nginx


###################
# SWITCH OFF
###################
elif [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "Turning OFF: Web"

  sudo systemctl stop nginx
  sudo systemctl disable nginx >/dev/null


###################
# LISTEN
###################
elif [ "$1" = "listen" ]; then

  if [ "$2" = "localhost" ] || [ "$2" = "any" ]; then
    echo "Setting NGINX to listen on: ${2}"
    set_nginx_blitzweb_listen "${2}"
  else
    echo "# FAIL: parameter not known - run with -h for help"
  fi

else
  echo "# FAIL: parameter not known - run with -h for help"
fi
