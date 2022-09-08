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
    echo "toraddress='${toraddress}:${httpPort}'"
    exit
  fi

fi

# show info menu
if [ "$1" = "menu" ]; then

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    # Info with TOR
    sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}:${httpPort}"
    whiptail --title " LNDg " --msgbox "Open in your local web browser:
http://${localip}:${httpPort}\n
Use your Password B to login.\n
Hidden Service address for TOR Browser (see LCD for QR):\n${toraddress}:${httpPort}
" 16 67
    sudo /home/admin/config.scripts/blitz.display.sh hide
  else
    # Info without TOR
    whiptail --title " ThunderHub " --msgbox "Open in your local web browser:
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

    # download and install
    sudo -u lndg git clone https://github.com/cryptosharks131/lndg.git /home/lndg/lndg/
    cd /home/lndg/lndg/ || exit 1
    sudo -u lndg apt install virtualenv
    sudo -u lndg virtualenv -p python3 .venv
    sudo -u lndg .venv/bin/pip install -r requirements.txt
    PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
    sudo -u lndg .venv/bin/python initialize.py -pw $PASSWORD_B
    sudo -u lndg .venv/bin/python jobs.py

    ##################
    # NGINX
    ##################

    INSTALL_USER="lndg"
    NODE_IP=$(hostname -I | cut -d' ' -f1)
    RED='\033[0;31m'
    NC='\033[0m'
    HOME_DIR="/home/lndg"

    function install_deps() {
      #apt install -y python3-dev >/dev/null 2>&1
      #apt install -y build-essential python >/dev/null 2>&1
      apt install -y uwsgi >/dev/null 2>&1
      #apt install -y nginx >/dev/null 2>&1
      $HOME_DIR/lndg/.venv/bin/python -m pip install uwsgi >/dev/null 2>&1
    }

    function setup_uwsgi() {
      cat << EOF > $HOME_DIR/lndg/lndg.ini
    # lndg.ini file
    [uwsgi]

    # Django-related settings
    # the base directory (full path)
    chdir           = $HOME_DIR/lndg
    # Django's wsgi file
    module          = lndg.wsgi
    # the virtualenv (full path)
    home            = $HOME_DIR/lndg/.venv
    #location of log files
    logto           = /var/log/uwsgi/%n.log

    # process-related settings
    # master
    master          = true
    # maximum number of worker processes
    processes       = 1
    # the socket (use the full path to be safe
    socket          = $HOME_DIR/lndg/lndg.sock
    # ... with appropriate permissions - may be needed
    chmod-socket    = 660
    # clear environment on exit
    vacuum          = true
    EOF
      cat <<\EOF > $HOME_DIR/lndg/uwsgi_params

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
    EOF
      cat << EOF > /etc/systemd/system/uwsgi.service
    [Unit]
    Description=Lndg uWSGI app
    After=lnd.service

    [Service]
    ExecStart=$HOME_DIR/lndg/.venv/bin/uwsgi \
    --ini $HOME_DIR/lndg/lndg.ini
    User=$INSTALL_USER
    Group=www-data
    Restart=always
    KillSignal=SIGQUIT
    Type=notify
    StandardError=syslog
    NotifyAccess=all

    [Install]
    WantedBy=sockets.target
    EOF
      usermod -a -G www-data $INSTALL_USER
    }

    function setup_nginx() {
      cat << EOF > /etc/nginx/sites-available/lndg.conf
    user $INSTALL_USER

    upstream django {
      server unix://$HOME_DIR/lndg/lndg.sock; # for a file socket
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
        alias $HOME_DIR/lndg/gui/static; # your Django project's static files - amend as required
      }

      # Finally, send all non-media requests to the Django server.
      location / {
        uwsgi_pass  django;
        include     $HOME_DIR/lndg/uwsgi_params; # the uwsgi_params file
        }
      }
    EOF
    }

    function start_services() {
      touch /var/log/uwsgi/lndg.log
      touch $HOME_DIR/lndg/lndg.sock
      chgrp www-data /var/log/uwsgi/lndg.log
      chgrp www-data $HOME_DIR/lndg/lndg.sock
      chmod 660 /var/log/uwsgi/lndg.log
      sudo systemctl enable uwsgi.service
      systemctl start uwsgi.service
    }

    function report_information() {
      echo -e ""
      echo -e "================================================================================================================================"
      echo -e "Nginx service setup using user account $INSTALL_USER and an address of $NODE_IP:8889."
      echo -e "You can update the IP or port used by modifying this configuration file and restarting nginx: /etc/nginx/sites-enabled/lndg"
      echo -e ""
      echo -e "uWSGI Status: ${RED}sudo systemctl status uwsgi.service${NC}"
      echo -e "Nginx Status: ${RED}sudo systemctl status nginx.service${NC}"
      echo -e ""
      echo -e "To disable your webserver, use the following commands."
      echo -e "Disable uWSGI: ${RED}sudo systemctl disable uwsgi.service${NC}"
      echo -e "Disable Nginx: ${RED}sudo systemctl disable nginx.service${NC}"
      echo -e "Stop uWSGI: ${RED}sudo systemctl stop uwsgi.service${NC}"
      echo -e "Stop Nginx: ${RED}sudo systemctl stop nginx.service${NC}"
      echo -e ""
      echo -e "To re-enable these services, simply replace the disable/stop commands with enable/start."
      echo -e "================================================================================================================================"
    }

    ##### Main #####
    echo -e "Setting up, this may take a few minutes..."
    install_deps
    setup_uwsgi
    setup_nginx
    start_services
    report_information
    # setup nginx symlinks
    sudo ln -sf /etc/nginx/sites-available/lndg.conf /etc/nginx/sites-enabled/
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
  cd /home/lndg/lndg || exit 1
  sudo -u lndg git pull
  sudo -u lndg .venv/bin/pip install requests
  sudo -u lndg .venv/bin/python manage.py migrate
  sudo systemctl restart nginx
  sudo systemctl restart uwsgi.service

  echo "# Updated to the release in https://github.com/cryptosharks131/lndg"
  echo
  echo "# Starting the LNDg services ... *** "
  sudo systemctl start jobs-lndg.timer
  sudo systemctl start rebalancer-lndg.timer
  sudo systemctl start jobs-lndg.service
  sudo systemctl start rebalancer-lndg.service
  sudo systemctl start htlc-stream-lndg.service

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
