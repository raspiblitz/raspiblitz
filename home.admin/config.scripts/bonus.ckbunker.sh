#!/bin/bash

GITHUB_REPO="https://github.com/Coldcard/ckbunker"
VERSION="bf08623875b576c4bc4498dc68e749cdf6b5de31"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# Config script to switch the CKbunker on or off"
  echo "# Installs CKBunker ${GITHUB_REPO}/commit/${VERSION}"
  echo "# bonus.ckbunker.sh status   -> status information (key=value)"
  echo "# bonus.ckbunker.sh on       -> install the app"
  echo "# bonus.ckbunker.sh off      -> uninstall the app"
  echo "# bonus.ckbunker.sh menu     -> SSH menu dialog"
  echo "# bonus.ckbunker.sh prestart -> will be called by systemd before start"
  exit 1
fi

source /mnt/hdd/app-data/raspiblitz.conf

GITHUB_SIGN_AUTHOR="web-flow"
GITHUB_SIGN_PUBKEYLINK="https://github.com/web-flow.gpg"
GITHUB_SIGN_FINGERPRINT="(4AEE18F83AFDEB23|B5690EEEBB952194)"

PORT_CLEAR="9823"
PORT_SSL="9824"
PORT_TOR_CLEAR="9825"
PORT_TOR_SSL="9826"

localIP=$(hostname -I | awk '{print $1}')

# check if app is already installed
isInstalled=$(sudo ls /etc/systemd/system/ckbunker.service 2>/dev/null | grep -c "ckbunker.service")

# check if service is running
isRunning=$(systemctl status ckbunker 2>/dev/null | grep -c 'active (running)')

if [ "${isInstalled}" == "1" ]; then

  # gather address info (whats needed to call the app)
  toraddress=$(sudo cat /mnt/hdd/app-data/tor/ckbunker/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

fi

if [ "$1" = "status" ]; then
  echo "appID='ckbunker'"
  echo "githubRepo='${GITHUB_REPO}'"
  echo "githubVersion='${GITHUB_VERSION}'"
  echo "githubSignature='${GITHUB_SIGNATURE}'"
  echo "isInstalled=${isInstalled}"
  echo "isRunning=${isRunning}"
  if [ "${isInstalled}" == "1" ]; then
    echo "portCLEAR=${PORT_CLEAR}"
    echo "portSSL=${PORT_SSL}"
    echo "localIP='${localIP}'"
    echo "toraddress='${toraddress}'"
    echo "fingerprint='${fingerprint}'"
    echo "toraddress='${toraddress}'"
  fi
  exit
fi

# show info menu
if [ "$1" = "menu" ]; then
  dialogTitle="CKbunker setup"
  dialogText="# To set up first switch to the 'ckbunker' user:
sudo su - ckbunker
# run:
ckbunker setup
# open in your local web browser:
https://${localIP}:${PORT_SSL}/setup with Fingerprint:
${fingerprint}\n
# follow the guide at:
https://ckbunker.com/setup.html
(save your password)

# When the setup is done start the service in the background:
sudo systemctl enable ckbunker
sudo systemctl start ckbunker"

  # use whiptail to show SSH dialog & exit
  whiptail --title "${dialogTitle}" --msgbox "${dialogText}" 21 67
  echo "please wait ..."
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# Install CKBunker"

  if [ ${isInstalled} -eq 1 ]; then
    echo "# ckbunker.service is already installed."
    exit 1
  fi

  echo "# Installing ckbunker ..."

  # dependencies
  sudo apt install -y virtualenv python-dev libusb-1.0-0-dev libudev-dev

  # create dedicated user
  sudo adduser --system --group --home /home/ckbunker ckbunker

  # add the user to the Tor group
  sudo usermod -a -G debian-tor ckbunker

  if ! [ -d /mnt/hdd/app-data/ckbunker ]; then
    echo "# create app-data directory"
    sudo mkdir /mnt/hdd/app-data/ckbunker 2>/dev/null
    sudo chown ckbunker:ckbunker -R /mnt/hdd/app-data/ckbunker
  else
    echo "# reuse existing app-directory"
    sudo chown ckbunker:ckbunker -R /mnt/hdd/app-data/ckbunker
  fi

  echo "# download the source code & verify"
  sudo -u ckbunker git clone --recursive ${GITHUB_REPO} /home/ckbunker/ckbunker
  cd /home/ckbunker/ckbunker || exit 1
  sudo -u ckbunker git reset --hard ${VERSION}
  if [ "${GITHUB_SIGN_AUTHOR}" != "" ]; then
    sudo -u ckbunker /home/admin/config.scripts/blitz.git-verify.sh \
     "${GITHUB_SIGN_AUTHOR}" "${GITHUB_SIGN_PUBKEYLINK}" "${GITHUB_SIGN_FINGERPRINT}" || exit 1
  fi

  sudo -u ckbunker virtualenv -p python3 ENV
  sudo -u ckbunker sh -c '. /home/ckbunker/ckbunker/ENV/bin/activate && \
   pip install -r requirements.txt && pip install --editable .'

  echo "# add the udev rules"
  cd /etc/udev/rules.d/
  sudo wget https://raw.githubusercontent.com/Coldcard/ckcc-protocol/master/51-coinkite.rules
  sudo udevadm control --reload-rules && sudo udevadm trigger

  echo "source /home/ckbunker/ckbunker/ENV/bin/activate" | sudo -u ckbunker tee -a /home/ckbunker/.bashrc
  echo "PATH=\$PATH:~/ckbunker/ENV/bin/" | sudo -u ckbunker tee -a /home/ckbunker/.bashrc
  echo "cd /home/ckbunker/ckbunker" | sudo -u ckbunker tee -a /home/ckbunker/.bashrc

  echo "# updating Firewall"
  sudo ufw allow ${PORT_CLEAR} comment "ckbunker HTTP"
  sudo ufw allow ${PORT_SSL} comment "ckbunker HTTPS"

  echo "# create systemd service: ckbunker.service"
  echo "
[Unit]
Description=ckbunker
Wants=bitcoind
After=bitcoind

[Service]
WorkingDirectory=/home/ckbunker/ckbunker/
ExecStartPre=-/home/admin/config.scripts/bonus.ckbunker.sh prestart
ExecStart=sh -c '. ENV/bin/activate && ENV/bin/ckbunker run'
User=ckbunker
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/ckbunker.service
    sudo chown root:root /etc/systemd/system/ckbunker.service

  # when tor is set on also install the hidden service
  if [ "${runBehindTor}" = "on" ]; then
    # activating tor hidden service
    /home/admin/config.scripts/tor.onion-service.sh ckbunker 80 ${PORT_TOR_CLEAR} 443 ${PORT_TOR_SSL}
  fi

  echo "# setup nginx config"
  # write the HTTPS config
  echo "
server {
    listen ${PORT_SSL} ssl;
    listen [::]:${PORT_SSL} ssl;
    server_name _;
    include /etc/nginx/snippets/ssl-params.conf;
    include /etc/nginx/snippets/ssl-certificate-app-data.conf;
    access_log /var/log/nginx/access_ckbunker.log;
    error_log /var/log/nginx/error_ckbunker.log;
    location / {
        proxy_pass http://127.0.0.1:${PORT_CLEAR};
        include /etc/nginx/snippets/ssl-proxy-params.conf;
    }
}
" | sudo tee /etc/nginx/sites-available/ckbunker_ssl.conf
  sudo ln -sf /etc/nginx/sites-available/ckbunker_ssl.conf /etc/nginx/sites-enabled/

  # write the Tor config
  echo "
server {
    listen ${PORT_TOR_CLEAR};
    server_name _;
    access_log /var/log/nginx/access_ckbunker.log;
    error_log /var/log/nginx/error_ckbunker.log;
    location / {
        proxy_pass http://127.0.0.1:${PORT_CLEAR};
        include /etc/nginx/snippets/ssl-proxy-params.conf;
    }
}
" | sudo tee /etc/nginx/sites-available/ckbunker_tor.conf
  sudo ln -sf /etc/nginx/sites-available/ckbunker_tor.conf /etc/nginx/sites-enabled/

  # write the Tor+HTTPS config
  echo "
server {
    listen ${PORT_TOR_SSL} ssl;
    server_name _;
    include /etc/nginx/snippets/ssl-params.conf;
    include /etc/nginx/snippets/ssl-certificate-app-data-tor.conf;
    access_log /var/log/nginx/access_ckbunker.log;
    error_log /var/log/nginx/error_ckbunker.log;
    location / {
        proxy_pass http://127.0.0.1:${PORT_CLEAR};
        include /etc/nginx/snippets/ssl-proxy-params.conf;
    }
}
" | sudo tee /etc/nginx/sites-available/ckbunker_tor_ssl.conf
  sudo ln -sf /etc/nginx/sites-available/ckbunker_tor_ssl.conf /etc/nginx/sites-enabled/

  # test nginx config & activate thru reload
  sudo nginx -t
  sudo systemctl reload nginx

  # mark app as installed in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ckbunker "on"

  echo "# OK - CKbunker is now installed"
  echo "# To set up:
# switch to the user
sudo su - ckbunker
# run:
ckbunker setup
# open in your local web browser:
https://${localIP}:${PORT_SSL}/setup
# and follow the guide at:
https://ckbunker.com/setup.html

# When the setup is done run the service in the backgound with:
sudo systemctl enable ckbunker
sudo systemctl start ckbunker
"
  exit 0
fi


# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# stop & remove systemd service"
  sudo systemctl stop ckbunker 2>/dev/null
  sudo systemctl disable ckbunker.service
  sudo rm /etc/systemd/system/ckbunker.service

  echo "# remove nginx symlinks"
  sudo rm -f /etc/nginx/sites-enabled/ckbunker_ssl.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-enabled/ckbunker_tor.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-enabled/ckbunker_tor_ssl.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-available/ckbunker_ssl.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-available/ckbunker_tor.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-available/ckbunker_tor_ssl.conf 2>/dev/null
  sudo nginx -t
  sudo systemctl reload nginx

  echo "# close ports on firewall"
  sudo ufw deny "${PORT_CLEAR}"
  sudo ufw deny "${PORT_SSL}"

  echo "# removing Tor hidden service (if active)"
  /home/admin/config.scripts/tor.onion-service.sh off ckbunker

  echo "# remove user"
  sudo userdel -rf ckbunker

  echo "# mark app as uninstalled in raspiblitz config"
  /home/admin/config.scripts/blitz.conf.sh set ckbunker "off"

  # only if 'delete-data' is an additional parameter then also the data directory gets deleted
  if [ "$(echo "$@" | grep -c delete-data)" -gt 0 ]; then
    echo "# found 'delete-data' parameter --> also deleting the app-data"
    sudo rm -r /mnt/hdd/app-data/ckbunker
  fi

  echo "# OK - CKbunker is uninstalled now"
  exit 0
fi

# just a basic error message when unknow action parameter was given
echo "# FAIL - Unknown Parameter $1"
exit 1
