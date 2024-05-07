#!/bin/bash
 
# github users to ping on issues:
# allyourbankarebelongtous 

# https://github.com/cryptosharks131/lndg
VERSION="1.8.0"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to install, update or uninstall LNDG"
  echo "bonus.lndg.sh [on|off|menu|update|setpassword|status]"
  exit 1
fi

# check and load raspiblitz config
# to know which network is running
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

if [ "$1" = "status" ] || [ "$1" = "menu" ]; then

  # get network info
  isInstalled=$(sudo ls /etc/systemd/system/jobs-lndg.service 2>/dev/null | grep -c 'jobs-lndg.service')
  localip=$(hostname -I | awk '{print $1}')
  toraddress=$(sudo cat /mnt/hdd/tor/lndg/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)
  httpPort="8889"
  httpsPort="8888"

  if [ "$1" = "status" ]; then
    echo "installed='${isInstalled}'"
    echo "localIP='${localip}'"
    echo "httpPort='${httpPort}'"
    echo "httpsForced='0'"
    echo "httpsSelfsigned='1'"
    echo "authMethod='password_b'"
    echo "toraddress='${toraddress}'"
    exit
  fi

fi

# show info menu
if [ "$1" = "menu" ]; then

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    # Info with TOR
    sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title " LNDg " --msgbox "Open in your local web browser:
http://${localip}:${httpPort}\n
https://${localip}:${httpsPort} with Fingerprint:
${fingerprint}\n
Username is lndg-admin. Use your Password B to login.\n
Hidden Service address for TOR Browser (see LCD for QR):\n${toraddress}
" 18 67
    sudo /home/admin/config.scripts/blitz.display.sh hide
  else
    # Info without TOR
    whiptail --title " LNDg " --msgbox "Open in your local web browser:
http://${localip}:${httpPort}\n
Or https://${localip}:${httpsPort} with Fingerprint:
${fingerprint}\n
Username is lndg-admin. Use your Password B to login.\n
Activate TOR to access the web interface from outside your local network.
" 17 67
  fi
  echo "please wait ..."
  exit 0
fi

if [ "$1" = "setpassword" ]; then
  if [ "$2" = "" ]; then
    echo "to change lndg password, enter the new password as the second variable and try again"
    echo "example: bonus.lndg.sh setpassword mynewpassword"
    echo "will change the password to: mynewpassword"
    exit 1
  fi
  isChangepassword=$(sudo ls /home/lndg/lndg/changepassword.py 2>/dev/null | grep -c 'changepassword.py')
  if ! [ ${isChangepassword} -eq 0 ]; then
    sudo -u lndg /home/lndg/lndg/.venv/bin/python /home/lndg/lndg/changepassword.py "$2"
  else
    # create python file for command line password change
    echo "# create python file for command line password change"
    echo "
#!/usr/bin/env python

import django
import sys
from os import environ
from lndg import settings
from time import sleep
environ['DJANGO_SETTINGS_MODULE'] = 'lndg.settings'
django.setup()
from django.contrib.auth.models import User

def newpassword():
    users = User.objects.all()
    user = users[0]
    user.set_password(sys.argv[1])
    user.save()

def main():
    try:
        newpassword()
    except Exception as e:
        print('Error while attempting to change password: ' + str(e))
        sleep(5)

if __name__ == '__main__':
    main()
" | sudo tee "/home/lndg/lndg/changepassword.py"

    sudo chmod 644 /home/lndg/lndg/changepassword.py
    sudo chown lndg:lndg /home/lndg/lndg/changepassword.py
    sudo -u lndg /home/lndg/lndg/.venv/bin/python /home/lndg/lndg/changepassword.py "$2"
  fi
  echo "ok, password changed to $2"
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL LNDg ***"

  isInstalled=$(sudo ls /etc/systemd/system/jobs-lndg.service 2>/dev/null | grep -c 'jobs-lndg.service')
  if ! [ ${isInstalled} -eq 0 ]; then
    echo "LNDg already installed."
  else
    ###############
    # INSTALL
    ###############

    echo "# LNDg user ..."

    # create lndg user
    sudo adduser --system --group --home /home/lndg lndg
    # add user to group with admin access to lnd
    sudo /usr/sbin/usermod --append --groups lndadmin lndg
    # make sure symlink to central app-data directory exists
    sudo rm -rf /home/lndg/.lnd  # not a symlink.. delete it silently
    # create symlink
    sudo ln -s /mnt/hdd/app-data/lnd/ /home/lndg/.lnd

    echo "# LNDg download and install ..."

    # download and install
    sudo -u lndg git clone https://github.com/cryptosharks131/lndg.git /home/lndg/lndg/
    cd /home/lndg/lndg/ || exit 1
    sudo -u lndg git reset --hard v${VERSION}
    sudo apt install -y virtualenv
    sudo -u lndg virtualenv -p python3 .venv
    sudo -u lndg .venv/bin/pip install -r requirements.txt
    PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
    echo "# LNDg initialize.py ..."
    sudo -u lndg .venv/bin/python initialize.py -pw $PASSWORD_B

    echo "# LNDg database ..."

    # set database path to HDD data so that its survives updates and migrations
    # first check and see if a database exists
    isDatabase=$(sudo ls /mnt/hdd/app-data/lndg/data/db.sqlite3 2>/dev/null | grep -c 'db.sqlite3')
    if ! [ ${isDatabase} -eq 0 ]; then
      if [ "$2" == "deletedatabase" ]; then
    
      # deleting old database and moving new database
        echo "Deleting existing database and creating new one"
        sudo rm -rf /mnt/hdd/app-data/lndg/data
        sudo cp -p -r /home/lndg/lndg/data /mnt/hdd/app-data/lndg/data
        sudo rm /home/lndg/lndg/data/db.sqlite3
        sudo ln -sf /mnt/hdd/app-data/lndg/data/db.sqlite3 /home/lndg/lndg/data/db.sqlite3
        sudo chown lndg:lndg -R /mnt/hdd/app-data/lndg/
      else    
    
        # using existing database, so remove newly created database and link to existing one
        echo "Database already exists, using existing database"
        sudo rm /home/lndg/lndg/data/db.sqlite3
        sudo chown -R lndg:lndg /mnt/hdd/app-data/lndg
        sudo chmod -R 755 /mnt/hdd/app-data/lndg
        sudo chmod 644 /mnt/hdd/app-data/lndg/data/db.sqlite3
        sudo -u lndg ln -sf /mnt/hdd/app-data/lndg/data/db.sqlite3 /home/lndg/lndg/data/db.sqlite3
        sudo -u lndg /home/lndg/lndg/.venv/bin/python manage.py migrate
      fi
    else
  
      # database doesn't exist, so move to HDD and simlink
      sudo mkdir -p /mnt/hdd/app-data/lndg
      sudo cp -p -r /home/lndg/lndg/data /mnt/hdd/app-data/lndg/data
      sudo rm /home/lndg/lndg/data/db.sqlite3
      sudo ln -sf /mnt/hdd/app-data/lndg/data/db.sqlite3 /home/lndg/lndg/data/db.sqlite3
      sudo chown lndg:lndg -R /mnt/hdd/app-data/lndg/
    fi
    sudo chown lndg:lndg /home/lndg/lndg/data/db.sqlite3

    # create python file for command line password change
    echo "# create python file for command line password change"
    echo "
#!/usr/bin/env python

import django
import sys
from os import environ
from lndg import settings
from time import sleep
environ['DJANGO_SETTINGS_MODULE'] = 'lndg.settings'
django.setup()
from django.contrib.auth.models import User

def newpassword():
    users = User.objects.all()
    user = users[0]
    user.set_password(sys.argv[1])
    user.save()

def main():
    try:
        newpassword()
    except Exception as e:
        print('Error while attempting to change password: ' + str(e))
        sleep(5)

if __name__ == '__main__':
    main()
" | sudo tee "/home/lndg/lndg/changepassword.py"

    sudo chmod 644 /home/lndg/lndg/changepassword.py
    sudo chown lndg:lndg /home/lndg/lndg/changepassword.py

    ##################
    # gunicorn install
    ##################

    echo "# LNDg gunicorn ..."

    # first install and configure whitenoise
    sudo /home/lndg/lndg/.venv/bin/pip install whitenoise
    sudo rm /home/lndg/lndg/lndg/settings.py
    sudo /home/lndg/lndg/.venv/bin/python initialize.py -wn

    # install gunicorn application server
    sudo /home/lndg/lndg/.venv/bin/python -m pip install 'gunicorn==20.1.*'

    # switch back to home directory
    cd /home/admin/

    echo "# Install gunicorn.service file for gunicorn lndg.wsgi application server"
    echo "
[Unit]
Description=Lndg guincorn app
After=lnd.service

[Service]
User=lndg
Group=lndg
WorkingDirectory=/home/lndg/lndg
ExecStart=/home/lndg/lndg/.venv/bin/gunicorn lndg.wsgi -w 4 -b 0.0.0.0:8889
Restart=always
KillSignal=SIGQUIT
Type=notify
StandardError=append:/var/log/gunicorn_error.log
NotifyAccess=all
RestartSec=60s

[Install]
WantedBy=multi-user.target
" | sudo tee "/etc/systemd/system/gunicorn.service"

    sudo usermod -a -G www-data lndg

    # setup nginx .conf files
    if ! [ -f /etc/nginx/sites-available/lndg_ssl.conf ]; then
      sudo cp -f /home/admin/assets/nginx/sites-available/lndg_ssl.conf /etc/nginx/sites-available/lndg_ssl.conf
    fi
    if ! [ -f /etc/nginx/sites-available/lndg_tor.conf ]; then
      sudo cp -f /home/admin/assets/nginx/sites-available/lndg_tor.conf /etc/nginx/sites-available/lndg_tor.conf
    fi
    if ! [ -f /etc/nginx/sites-available/lndg_tor_ssl.conf ]; then
      sudo cp -f /home/admin/assets/nginx/sites-available/lndg_tor_ssl.conf /etc/nginx/sites-available/lndg_tor_ssl.conf
    fi

    # setup nginx symlinks
    sudo ln -sf /etc/nginx/sites-available/lndg_ssl.conf /etc/nginx/sites-enabled/lndg_ssl.conf
    sudo ln -sf /etc/nginx/sites-available/lndg_tor.conf /etc/nginx/sites-enabled/lndg_tor.conf
    sudo ln -sf /etc/nginx/sites-available/lndg_tor_ssl.conf /etc/nginx/sites-enabled/lndg_tor_ssl.conf
    sudo nginx -t
    sudo systemctl reload nginx

    # start nginx and uwsgi services
    sudo touch /var/log/uwsgi/lndg.log
    sudo touch /home/lndg/lndg/lndg.sock
    sudo chgrp www-data /var/log/uwsgi/lndg.log
    sudo chgrp www-data /home/lndg/lndg/lndg.sock
    sudo chmod 771 /home/lndg/lndg/lndg.sock
    sudo chmod 660 /var/log/uwsgi/lndg.log
    sudo systemctl enable gunicorn.service
    sudo systemctl start gunicorn.service

    # open the firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow from any to any port 8889 comment 'allow LNDg HTTP'
    sudo ufw allow from any to any port 8888 comment 'allow LNDg HTTPS'
    echo ""

    ############################
    # SYSTEMD CONTROLLER SERVICE
    ############################

    echo "# Install LNDg systemd for ${network} on ${chain}"
    echo "
[Unit]
Description=Backend Controller For Lndg
[Service]
Environment=PYTHONUNBUFFERED=1
User=lndg
Group=lndg
ExecStart=/home/lndg/lndg/.venv/bin/python /home/lndg/lndg/controller.py
StandardOutput=append:/var/log/lndg-controller.log
StandardError=append:/var/log/lndg-controller.log
Restart=always
RestartSec=60s
[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/lndg-controller.service

    sudo systemctl enable lndg-controller
    sudo systemctl start lndg-controller

    # setting value in raspiblitz config
    /home/admin/config.scripts/blitz.conf.sh set lndg "on"

    # Hidden Service for LNDg if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      # make sure to keep in sync with tor.network.sh script
      /home/admin/config.scripts/tor.onion-service.sh lndg 80 8886 443 8887
    fi
  fi

  echo "# LNDg install OK!"
  sleep 5

  # needed for API/WebUI as signal that install ran thru 
  echo "result='OK'"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "*** REMOVING LNDG ***"
  # remove systemd services
  sudo systemctl disable lndg-controller
  sudo systemctl disable gunicorn.service
  sudo rm -f /etc/systemd/system/jobs-lndg.timer
  sudo rm -f /etc/systemd/system/rebalancer-lndg.timer
  sudo rm -f /etc/systemd/system/jobs-lndg.service
  sudo rm -f /etc/systemd/system/rebalancer-lndg.service
  sudo rm -f /etc/systemd/system/htlc-stream-lndg.service
  sudo rm -f /etc/systemd/system/gunicorn.service
  # delete user and home directory
  sudo userdel -rf lndg
  # close ports on firewall
  sudo ufw deny 8889
  sudo ufw deny 8888

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/lndg_ssl.conf
  sudo rm -f /etc/nginx/sites-enabled/lndg_tor.conf
  sudo rm -f /etc/nginx/sites-enabled/lndg_tor_ssl.conf
  sudo rm -f /etc/nginx/sites-available/lndg_ssl.conf
  sudo rm -f /etc/nginx/sites-available/lndg_tor.conf
  sudo rm -f /etc/nginx/sites-available/lndg_tor_ssl.conf
  sudo nginx -t
  sudo systemctl reload nginx

  # hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off lndg
  fi
  
  # database removal (if selected)
  if [ "$2" == "deletedatabase" ]; then
    echo "Deleting database"
    sudo rm -rf /mnt/hdd/app-data/lndg
  fi
  
  echo "OK LNDg removed."

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set lndg "off"

  # needed for API/WebUI as signal that install ran thru 
  echo "result='OK'"
  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "# UPDATING LNDG"
  echo "# Updated to the release in https://github.com/cryptosharks131/lndg"
  cd /home/lndg/lndg || exit 1
  sudo -u lndg git pull
  sudo -u lndg .venv/bin/pip install requests
  sudo -u lndg .venv/bin/pip install -r requirements.txt
  sudo -u lndg .venv/bin/python manage.py migrate
  
  # reinitialize settings.py in case update requires it
  sudo rm /home/lndg/lndg/lndg/settings.py 
  sudo /home/lndg/lndg/.venv/bin/python initialize.py -wn
  cd /home/admin
  
  # restart services
  sudo systemctl restart nginx
  sudo systemctl restart gunicorn.service

  echo ""
  echo "# Starting the LNDg services ... *** "
  sudo systemctl start jobs-lndg.timer
  sudo systemctl start rebalancer-lndg.timer
  sudo systemctl start htlc-stream-lndg.service

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
