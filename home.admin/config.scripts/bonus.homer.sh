#!/bin/bash

# https://github.com/bastienwirtz/homer

installVersion="v21.03.2"
remoteVersion=$(curl -s https://api.github.com/repos/bastienwirtz/homer/releases/latest|grep tag_name|head -1|cut -d '"' -f4)

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# small config script to switch Homer on or off"
  echo "# installs the $installVersion by default"
  echo "# bonus.homer.sh [status|on|off|update]"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then

  # get status
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.homer.sh status)


  # get network info
  localip=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0' | grep 'eth0\|wlan0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  toraddress=$(sudo cat /mnt/hdd/tor/homer/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then

    # TOR
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title " Homer " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:4091\n
SHA1 Thumb/Fingerprint:
${fingerprint}\n
Hidden Service address for TOR Browser (QR see LCD):
${toraddress}
" 16 67
    /home/admin/config.scripts/blitz.display.sh hide
  else

    # IP + Domain
    whiptail --title " Homer " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localip}:4091\n
SHA1 Thumb/Fingerprint:
${fingerprint}\n
Activate TOR to access the web block explorer from outside your local network.
" 16 54
  fi

  echo "please wait ..."
  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^homer=" /mnt/hdd/raspiblitz.conf; then
  echo "homer=off" >> /mnt/hdd/raspiblitz.conf
fi

# status
if [ "$1" = "status" ]; then

  if [ "${homer}" = "on" ]; then
    echo "configured=1"
  else
    echo "configured=0"
  fi
  exit 0
fi

# Update (quick hack)
# Stores configuration and assets found in /var/www/homer
if [ "$1" = "update" ]; then

  cd /home/homer/homer
  sudo -u homer git fetch
  # Comment out until official release that fixes issue #206 
  # sudo -u homer git reset --hard $remoteVersion

  # Save config file
  sudo cp /var/www/homer/assets/config.yml /mnt/hdd/app-data/homer/config.yml

  # Save any icons
  sudo rsync -av /var/www/homer/assets/icons/ /mnt/hdd/app-data/homer/icons

  # Install Homer
  sudo -u homer NG_CLI_ANALYTICS=false npm install
  if ! [ $? -eq 0 ]; then
      echo "FAIL - npm install did not run correctly, aborting"
      exit 1
  fi
  sudo -u homer NG_CLI_ANALYTICS=false npm run build
  if ! [ $? -eq 0 ]; then
      echo "FAIL - npm run build did not run correctly, aborting"
      exit 1
  fi    

  # remove conf link
  sudo rm /var/www/homer/assets/config.yml

  # copy new dist over to nginx
  sudo rsync -av --delete dist/ /var/www/homer/

  # link config again
  sudo -u www-data ln -s /mnt/hdd/app-data/homer/config.yml /var/www/homer/assets/config.yml

  #restore saved icons
  sudo rsync -av /mnt/hdd/app-data/homer/icons/ /var/www/homer/assets/icons/
  sudo chown -R www-data:www-data /var/www/homer/

  echo "# OK - Homer should now be serving latest code from Version $remoteVersion"
  exit 0

fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "# *** INSTALL Homer ***"

  isInstalled=$(sudo ls /var/www/homer/assets/config.yml.dist 2>/dev/null | grep -c 'config.yml.dist')
  if [ ${isInstalled} -eq 0 ]; then

    # add homer user
    sudo adduser --disabled-password --gecos "" homer

    # install homer
    cd /home/homer
    sudo -u homer git clone https://github.com/bastienwirtz/homer.git
    cd homer
    # sudo -u homer git reset --hard $installVersion

    sudo -u homer NG_CLI_ANALYTICS=false npm install
    if ! [ $? -eq 0 ]; then
        echo "FAIL - npm install did not run correctly, aborting"
        exit 1
    fi
    sudo -u homer NG_CLI_ANALYTICS=false npm run build
    if ! [ $? -eq 0 ]; then
        echo "FAIL - npm run build did not run correctly, aborting"
        exit 1
    fi    

    sudo mkdir -p /var/www/homer
    sudo rsync -av --delete dist/ /var/www/homer/
    sudo chown -R www-data:www-data /var/www/homer

    # if no persistent data exists - create data dir & use standard config
    oldConfigExists=$(ls /mnt/hdd/app-data/homer/config.yml 2>/dev/null | grep -c 'config.yml')
    if [ "${oldConfigExists}" == "0" ]; then
      sudo -u homer cp /home/homer/homer/dist/assets/config.yml.dist /home/homer/homer/dist/assets/config.yml
      sudo mkdir -p /mnt/hdd/app-data/homer
      sudo cp /home/homer/homer/dist/assets/config.yml.dist /mnt/hdd/app-data/homer/config.yml
    fi

    # link config into nginx directory
    sudo chown www-data:www-data /mnt/hdd/app-data/homer/config.yml
    sudo -u www-data ln -s /mnt/hdd/app-data/homer/config.yml /var/www/homer/assets/config.yml

    ##################
    # NGINX
    ##################

    if ! [ -f /etc/nginx/sites-available/homer_ssl.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/homer_ssl.conf /etc/nginx/sites-available/homer_ssl.conf
    fi
    if ! [ -f /etc/nginx/sites-available/homer_tor.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/homer_tor.conf /etc/nginx/sites-available/homer_tor.conf
    fi
    if ! [ -f /etc/nginx/sites-available/homer_tor_ssl.conf ]; then
       sudo cp /home/admin/assets/nginx/sites-available/homer_tor_ssl.conf /etc/nginx/sites-available/homer_tor_ssl.conf
    fi
    sudo ln -sf /etc/nginx/sites-available/homer_ssl.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/homer_tor.conf /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/homer_tor_ssl.conf /etc/nginx/sites-enabled/

    sudo nginx -t
    sudo systemctl restart nginx

    # open the firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow from any to any port 4090 comment 'allow homer HTTP'
    sudo ufw allow from any to any port 4091 comment 'allow homer HTTPS'
    echo ""

  else 
    echo "# homer is already installed."
  fi

  # start the service if ready
  source /home/admin/raspiblitz.info

  # setting value in raspi blitz config
  sudo sed -i "s/^homer=.*/homer=on/g" /mnt/hdd/raspiblitz.conf
  
  # Hidden Service for Mempool if Tor is active
  source /mnt/hdd/raspiblitz.conf
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with internet.tor.sh script
    /home/admin/config.scripts/internet.hiddenservice.sh homer 80 4092 443 4093
  fi
  exit 0
fi


# switch off
# Stores configuration on persistent disk for quick restore
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^homer=.*/homer=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /var/www/homer/assets/config.yml.dist 2>/dev/null | grep -c 'config.yml.dist')
  if [ ${isInstalled} -eq 1 ]; then

    echo "Saving assets to external drive. If you no longer require these files, it is safe delete from persistent disk at /mnt/hdd/app-data/homer."
    sudo cp /var/www/homer/assets/config.yml /mnt/hdd/app-data/homer/config.yml
    sudo rsync -av --delete /var/www/homer/assets/icons/ /mnt/hdd/app-data/homer/icons/


    echo "# *** REMOVING homer ***"
    # delete user and home directory
    sudo userdel -rf homer
    sudo rm -rf /var/www/homer

    # remove nginx symlinks
    sudo rm -f /etc/nginx/sites-enabled/homer_ssl.conf
    sudo rm -f /etc/nginx/sites-enabled/homer_tor.conf
    sudo rm -f /etc/nginx/sites-enabled/homer_tor_ssl.conf
    sudo rm -f /etc/nginx/sites-available/homer_ssl.conf
    sudo rm -f /etc/nginx/sites-available/homer_tor.conf
    sudo rm -f /etc/nginx/sites-available/homer_tor_ssl.conf
    sudo nginx -t
    sudo systemctl reload nginx

    # Hidden Service if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      # make sure to keep in sync with internet.tor.sh script
      /home/admin/config.scripts/internet.hiddenservice.sh off homer
    fi

    echo "# OK Homer removed."
  
  else 
    echo "# Homer is not installed."
  fi

  exit 0
fi

echo "error='unknown parameter'"
exit 1

