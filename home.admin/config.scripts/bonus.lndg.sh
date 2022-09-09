#!/bin/bash

# https://github.com/cryptosharks131/lndg

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install, update or uninstall LNDG"
 echo "bonus.lndg.sh [on|off|menu|update|status]"
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
  httpPort="8889"

  if [ "$1" = "status" ]; then
    echo "installed='${isInstalled}'"
    echo "localIP='${localip}'"
    echo "httpPort='${httpPort}'"
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
Use your Password B to login.\n
Hidden Service address for TOR Browser (see LCD for QR):\n${toraddress}
" 16 67
    sudo /home/admin/config.scripts/blitz.display.sh hide
  else
    # Info without TOR
    whiptail --title " LNDg " --msgbox "Open in your local web browser:
http://${localip}:${httpPort}\n
Use your Password B to login.\n
Activate TOR to access the web interface from outside your local network.
" 15 57
  fi
  echo "please wait ..."
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

    # create lndg user
    sudo adduser --disabled-password --gecos "" lndg
    # add user to group with admin access to lnd
    sudo /usr/sbin/usermod --append --groups lndadmin lndg
    # make sure symlink to central app-data directory exists
    sudo rm -rf /home/lndg/.lnd  # not a symlink.. delete it silently
    # create symlink
    sudo ln -s /mnt/hdd/app-data/lnd/ /home/lndg/.lnd

    # download and install
    sudo -u lndg git clone https://github.com/cryptosharks131/lndg.git /home/lndg/lndg/
    cd /home/lndg/lndg/ || exit 1
    sudo apt install virtualenv
    sudo -u lndg virtualenv -p python3 .venv
    sudo -u lndg .venv/bin/pip install -r requirements.txt
    PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
    sudo -u lndg .venv/bin/python initialize.py -pw $PASSWORD_B
    sudo -u lndg .venv/bin/python jobs.py

    # set database path to HDD data so that its survives updates and migrations
    # first check and see if a database exists
    isDatabase=$(sudo ls /mnt/hdd/app-data/lndg/data/db.sqlite3 2>/dev/null | grep -c 'db.sqlite3')
    if ! [ ${isDatabase} -eq 0 ]; then
      #database exists, so remove newly created database and link to existing one
      echo "Database already exists, using existing database"
      sudo rm /home/lndg/lndg/data/db.sqlite3
      sudo -u lndg ln -sf /mnt/hdd/app-data/lndg/data/db.sqlite3 /home/lndg/lndg/data/db.sqlite3
      sudo chown lndg:lndg /home/lndg/lndg/data/db.sqlite3
    else
      #database doesn't exist, so move to HDD and simlink
      sudo mkdir /mnt/hdd/app-data/lndg
      sudo mkdir /mnt/hdd/app-data/lndg/data
      sudo cp -p /home/lndg/lndg/data/db.sqlite3 /mnt/hdd/app-data/lndg/data/db.sqlite3
      sudo rm /home/lndg/lndg/data/db.sqlite3
      sudo ln -sf /mnt/hdd/app-data/lndg/data/db.sqlite3 /home/lndg/lndg/data/db.sqlite3
      sudo chown lndg:lndg -R /mnt/hdd/app-data/lndg/
      sudo chown lndg:lndg /home/lndg/lndg/data/db.sqlite3
    fi
    cd /home/admin/

    ##################
    # NGINX
    ##################

    sudo apt install -y python3-dev >/dev/null 2>&1
    sudo apt install -y build-essential python >/dev/null 2>&1
    sudo apt install -y uwsgi >/dev/null 2>&1
    sudo apt install -y nginx >/dev/null 2>&1
    sudo /home/lndg/lndg/.venv/bin/python -m pip install uwsgi >/dev/null 2>&1

    echo "# Install lndg.ini and uwsgi.service for uwsgi"
    echo "
# lndg.ini file
[uwsgi]

# Django-related settings
# the base directory (full path)
chdir           = /home/lndg/lndg
# Django's wsgi file
module          = lndg.wsgi
# the virtualenv (full path)
home            = /home/lndg/lndg/.venv
#location of log files
logto           = /var/log/uwsgi/%n.log

# process-related settings
# master
master          = true
# maximum number of worker processes
processes       = 1
# the socket (use the full path to be safe
socket          = /home/lndg/lndg/lndg.sock
# ... with appropriate permissions - may be needed
chmod-socket    = 660
# clear environment on exit
vacuum          = true
" | sudo tee "/home/lndg/lndg/lndg.ini"

    echo '
uwsgi_param  QUERY_STRING       $query_string;
uwsgi_param  REQUEST_METHOD     $request_method;
uwsgi_param  CONTENT_TYPE       $content_type;
uwsgi_param  CONTENT_LENGTH     $content_length;

uwsgi_param  REQUEST_URI        "$request_uri";
uwsgi_param  PATH_INFO          "$document_uri";
uwsgi_param  DOCUMENT_ROOT      "$document_root";
uwsgi_param  SERVER_PROTOCOL    "$server_protocol";
uwsgi_param  REQUEST_SCHEME     "$scheme";
uwsgi_param  HTTPS              "$https if_not_empty";

uwsgi_param  REMOTE_ADDR        "$remote_addr";
uwsgi_param  REMOTE_PORT        "$remote_port";
uwsgi_param  SERVER_PORT        "$server_port";
uwsgi_param  SERVER_NAME        "$server_name";
' | sudo tee "/home/lndg/lndg/uwsgi_params"

    echo "
[Unit]
Description=Lndg uWSGI app
After=lnd.service

[Service]
ExecStart=/home/lndg/lndg/.venv/bin/uwsgi \
--ini /home/lndg/lndg/lndg.ini
User=lndg
Group=www-data
Restart=always
KillSignal=SIGQUIT
Type=notify
StandardError=syslog
NotifyAccess=all

[Install]
WantedBy=sockets.target
" | sudo tee "/etc/systemd/system/uwsgi.service"

    sudo usermod -a -G www-data lndg

    echo "
#user lndg

upstream django {
  server unix:///home/lndg/lndg/lndg.sock; # for a file socket
}

server {
  # the port your site will be served on, use port 80 unless setting up ssl certs, then 443
  listen      8889;
  # optional settings for ssl setup
  #ssl on;
  #ssl_certificate /<path_to_certs>/fullchain.pem;
  #ssl_certificate_key /<path_to_certs>/privkey.pem;
  # the domain name it will serve for
  server_name _; # you can substitute your node IP address or a custom domain like lndg.local (just make sure to update your local hosts file)
  charset     utf-8;

  # max upload size
  client_max_body_size 75M;   # adjust to taste

  # max wait for django time
  proxy_read_timeout 180;

  # Django media
  location /static {
    alias /home/lndg/lndg/gui/static; # your Django project's static files - amend as required
  }

  # Finally, send all non-media requests to the Django server.
  location / {
    uwsgi_pass  django;
    include     /home/lndg/lndg/uwsgi_params; # the uwsgi_params file
  }
}
" | sudo tee "/etc/nginx/sites-available/lndg.conf"

    sudo touch /var/log/uwsgi/lndg.log
    sudo touch /home/lndg/lndg/lndg.sock
    sudo chgrp www-data /var/log/uwsgi/lndg.log
    sudo chgrp www-data /home/lndg/lndg/lndg.sock
    sudo chmod 771 /home/lndg/lndg/lndg.sock
    sudo chmod 660 /var/log/uwsgi/lndg.log
    sudo systemctl enable uwsgi.service
    sudo systemctl start uwsgi.service

    # setup nginx symlinks
    sudo ln -sf /etc/nginx/sites-available/lndg.conf /etc/nginx/sites-enabled/lndg.conf
    sudo nginx -t
    sudo systemctl reload nginx

    # open the firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow from any to any port 8889 comment 'allow LNDg HTTP'
    echo ""

    ##################
    # SYSTEMD SERVICE
    ##################

    echo "# Install LNDg systemd for ${network} on ${chain}"
    echo "
#!/bin/bash

/home/lndg/lndg/.venv/bin/python /home/lndg/lndg/jobs.py
" | sudo tee /home/lndg/lndg/jobs.sh
    echo "
#!/bin/bash

/home/lndg/lndg/.venv/bin/python /home/lndg/lndg/rebalancer.py
" | sudo tee /home/lndg/lndg/rebalancer.sh
    echo "
#!/bin/bash

/home/lndg/lndg/.venv/bin/python /home/lndg/lndg/htlc_stream.py
" | sudo tee /home/lndg/lndg/htlc_stream.sh
    echo "
[Unit]
Description=Run Jobs For Lndg
[Service]
User=lndg
Group=lndg
ExecStart=/bin/bash /home/lndg/lndg/jobs.sh
StandardError=append:/var/log/lnd_jobs_error.log
" | sudo tee /etc/systemd/system/jobs-lndg.service
    echo "
[Unit]
Description=Run Rebalancer For Lndg
[Service]
User=lndg
Group=lndg
ExecStart=/bin/bash /home/lndg/lndg/rebalancer.sh
StandardError=append:/var/log/lnd_rebalancer_error.log
RuntimeMaxSec=3600
" | sudo tee /etc/systemd/system/rebalancer-lndg.service
    echo "
[Unit]
Description=Run HTLC Stream For Lndg
Requires=lnd.service
After=lnd.service
[Service]
User=lndg
Group=lndg
ExecStart=/bin/bash /home/lndg/lndg/htlc_stream.sh
StandardError=append:/var/log/lnd_htlc_stream_error.log
Restart=always
RestartSec=60s
[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/htlc-stream-lndg.service
    echo "
[Unit]
Description=Run Lndg Jobs Every 20 Seconds
[Timer]
OnBootSec=300
OnUnitActiveSec=20
AccuracySec=1
[Install]
WantedBy=timers.target
" | sudo tee /etc/systemd/system/jobs-lndg.timer
    echo "
[Unit]
Description=Run Lndg Rebalancer Every 20 Seconds
[Timer]
OnBootSec=315
OnUnitActiveSec=20
AccuracySec=1
[Install]
WantedBy=timers.target
" | sudo tee /etc/systemd/system/rebalancer-lndg.timer
    sudo systemctl enable jobs-lndg.timer
    sudo systemctl enable rebalancer-lndg.timer
    sudo systemctl enable htlc-stream-lndg.service
    sudo systemctl start jobs-lndg.timer
    sudo systemctl start rebalancer-lndg.timer
    sudo systemctl start htlc-stream-lndg.service


    # setting value in raspiblitz config
    /home/admin/config.scripts/blitz.conf.sh set lndg "on"

    # Hidden Service for LNDg if Tor is active
    if [ "${runBehindTor}" = "on" ]; then
      # make sure to keep in sync with tor.network.sh script
      /home/admin/config.scripts/tor.onion-service.sh lndg 80 8889
    fi
  fi

  # needed for API/WebUI as signal that install ran thru 
  echo "result='OK'"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "*** REMOVING LNDG ***"
  # remove systemd service
  sudo systemctl disable jobs-lndg.timer
  sudo systemctl disable rebalancer-lndg.timer
  sudo systemctl disable htlc-stream-lndg.service
  sudo rm -f /etc/systemd/system/jobs-lndg.timer
  sudo rm -f /etc/systemd/system/rebalancer-lndg.timer
  sudo rm -f /etc/systemd/system/jobs-lndg.service
  sudo rm -f /etc/systemd/system/rebalancer-lndg.service
  sudo rm -f /etc/systemd/system/htlc-stream-lndg.service
  # delete user and home directory
  sudo userdel -rf lndg
  # close ports on firewall
  sudo ufw deny 8889

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/lndg.conf
  sudo rm -f /etc/nginx/sites-available/lndg.conf
  sudo nginx -t
  sudo systemctl reload nginx

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off lndg
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
  sudo -u lndg .venv/bin/python manage.py migrate
  sudo systemctl restart nginx
  sudo systemctl restart uwsgi.service

  echo ""
  echo "# Starting the LNDg services ... *** "
  sudo systemctl start jobs-lndg.timer
  sudo systemctl start rebalancer-lndg.timer
  sudo systemctl start htlc-stream-lndg.service

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
