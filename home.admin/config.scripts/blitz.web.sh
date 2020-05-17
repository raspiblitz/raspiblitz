#!/usr/bin/env bash

source /mnt/hdd/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "the RaspiBlitz Web Interface(s)"
  echo "blitz.web.sh [on|off]"
  exit 1
fi

# using ${APOST} is a workaround to be able to use sed with '
APOST=\'


###################
# SWITCH ON
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "Turn ON: Web"

  # install
  sudo apt-get update >/dev/null
  sudo apt-get install -y nginx >/dev/null

  # make sure that it's enabled and started
  sudo systemctl enable nginx >/dev/null
  sudo systemctl start nginx

  ### Welcome Server on HTTP Port 80
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo rm -f /var/www/html/index.nginx-debian.html

  sudo mv /etc/nginx/sites-available/default /etc/nginx/sites-available/public.conf

  sudo sed -i 's|root /var/www/html;|root /var/www/public;|g' /etc/nginx/sites-available/public.conf
  sudo sed -i 's|index index.html index.htm index.nginx-debian.html;|index index.html;|g' /etc/nginx/sites-available/public.conf

  if ! grep -Eq '^\s*sub_filter.*$' /etc/nginx/sites-available/public.conf; then
    # search for "location /" entry and add three lines below
    sed -i -E '/^\s*location \/ \{$/a \
                # make sure to have https link to exact same host that was called\n             sub_filter '$APOST'<a href="https:\/\/HOST_SET_BY_NGINX\/'$APOST' '$APOST'<a href="https:\/\/$host\/'$APOST';\n' /etc/nginx/sites-available/public.conf
  fi

  # copy webroot
  sudo cp -a /home/admin/assets/www_public/ /var/www/public
  sudo chown www-data:www-data /var/www/public

  sudo ln -sf /etc/nginx/sites-available/public.conf /etc/nginx/sites-enabled/public.conf

  # open firewall
  sudo ufw allow 80 comment 'nginx http_80'

  ### RaspiBlitz Webserver on HTTPS 443

  # copy webroot
  sudo cp -a /home/admin/assets/www_blitzweb/ /var/www/blitzweb
  sudo chown www-data:www-data /var/www/blitzweb

  # create nginx app-data dir and use LND cert by default
  sudo mkdir /mnt/hdd/app-data/nginx/
  sudo ln -sf /mnt/hdd/lnd/tls.cert /mnt/hdd/app-data/nginx/tls.cert
  sudo ln -sf /mnt/hdd/lnd/tls.key /mnt/hdd/app-data/nginx/tls.key

  # config
  sudo cp /home/admin/assets/blitzweb.conf /etc/nginx/sites-available/blitzweb.conf
  sudo ln -sf /etc/nginx/sites-available/blitzweb.conf /etc/nginx/sites-enabled/

  # open firewall
  sudo ufw allow 443 comment 'nginx https_443'

  # restart NGINX
  sudo systemctl restart nginx


###################
# SWITCH OFF
###################
elif [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "Turn OFF: Web"

  sudo systemctl stop nginx
  sudo systemctl disable nginx >/dev/null

else
  echo "# FAIL: parameter not known - run with -h for help"
fi
