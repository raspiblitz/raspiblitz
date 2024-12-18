#!/bin/bash

# This script installs Alby Hub on RaspiBlitz.
# Rename it as `bonus.albyhub.sh` and place it in `/home/admin/config.scripts`.

# id string of your app (short single string unique in raspiblitz)
APPID="albyhub" # one-word lower-case no-specials

# https://github.com/getAlby/hub/releases
VERSION="1.11.3"

# port numbers the app should run on
# delete if not an web app
PORT_CLEAR="8029"
PORT_SSL="8030"
PORT_TOR_CLEAR="8031"
PORT_TOR_SSL="8032"

# BASIC COMMANDLINE OPTIONS
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# bonus.${APPID}.sh status            -> status information (key=value)"
  echo "# bonus.${APPID}.sh install           -> install the app"
  echo "# bonus.${APPID}.sh uninstall         -> uninstall the app"
  echo "# bonus.${APPID}.sh on                -> activate the app"
  echo "# bonus.${APPID}.sh off [delete-data] -> deactivate the app"
  echo "# bonus.${APPID}.sh menu              -> SSH menu dialog"
  echo "# bonus.${APPID}.sh prestart          -> prestart used by systemd"
  exit 1
fi

ENVFILE="/home/${APPID}/config.env"

##########################
# PRESTART
##########################

# background is that this script will be called with `prestart` on every start & restart
if [ "$1" = "prestart" ]; then

  # needs to be run as the app user - stop if not run as the app user
  # keep in mind that in the prestart section you cannot use `sudo` command
  if [ "$USER" != "${APPID}" ]; then
    echo "# FAIL: run as user ${APPID}"
    exit 1
  fi

  # see: https://github.com/getAlby/hub/blob/master/.env.example

  echo "## PRESTART CONFIG START for ${APPID} (called by systemd prestart)"
  echo "# creating dynamic env file --> ${ENVFILE}"
  touch ${ENVFILE}
  chmod 770 ${ENVFILE}
  echo "PORT=${PORT_CLEAR}" > ${ENVFILE}
  echo "WORK_DIR=/mnt/hdd/app-data/${APPID}" >> ${ENVFILE}
  echo "LN_BACKEND_TYPE=LND" >> ${ENVFILE}
  echo "LND_ADDRESS=127.0.0.1:10009" >> ${ENVFILE}
  echo "LND_CERT_FILE=/mnt/hdd/app-data/lnd/tls.cert" >> ${ENVFILE}
  echo "LND_MACAROON_FILE=/mnt/hdd/app-data/lnd/data/chain/bitcoin/mainnet/admin.macaroon" >> ${ENVFILE}
  echo >> ${ENVFILE}

  echo "## PRESTART CONFIG DONE for ${APPID}"
  exit 0
fi

# echoing comments is useful for logs - but start output with # when not a key=value
echo "# Running: 'bonus.${APPID}.sh $*'"

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

#########################
# INFO
#########################

# this section is always executed to gather status information that
# all the following commands can use & execute on

# check if app is already installed
isInstalled=$(sudo ls /etc/systemd/system/${APPID}.service 2>/dev/null | grep -c "${APPID}.service")

# check if service is running
isRunning=$(systemctl status ${APPID} 2>/dev/null | grep -c 'active (running)')

if [ "${isInstalled}" == "1" ]; then
  # gather address info (whats needed to call the app)
  localIP=$(hostname -I | awk '{print $1}')
  toraddress=$(sudo cat /mnt/hdd/tor/${APPID}/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)
fi

# if the action parameter `status` was called - just stop here and output all
# status information as a key=value list
if [ "$1" = "status" ]; then
  echo "appID='${APPID}'"
  echo "version='${VERSION}'"
  echo "installed=${isRunning}" # installed means towards webui on or off
  if [ "${isInstalled}" == "1" ]; then
    echo "localIP='${localIP}'"
    echo "toraddress='${toraddress}'"
    echo "fingerprint='${fingerprint}'"
    echo "httpPort='${PORT_CLEAR}'"
    echo "httpsPort='${PORT_SSL}'"
    echo "httpsForced='1'"
    echo "httpsSelfsigned='1'"
    echo "authMethod='userdefined'"
  fi
  exit
fi

##########################
# MENU
#########################

# show info menu
if [ "$1" = "menu" ]; then

  if [ ${isInstalled} -eq 0 ] && [ "${albyhub}" == "on" ]; then
    clear
    echo "# AlbyHub needs re-install ..."
    /home/admin/config.scripts/bonus.albyhub.sh on
  elif [ ${isInstalled} -lt 1 ]; then
    echo "error='App not installed'"
    exit 1
  fi

  # set the title for the dialog
  dialogTitle=" ${APPID} "
  localIP=$(hostname -I | awk '{print $1}')
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

  # basic info text - for a web app how to call with http
  dialogText="Open in your local web browser:
http://${localIP}:${PORT_CLEAR}\n
https://${localIP}:${PORT_SSL} with Fingerprint:
${fingerprint}\n
The Alby Hub password is managed seperate from RaspiBlitz - make sure to manage it safely.\n
"

  # use whiptail to show SSH dialog & exit
  whiptail --title "${dialogTitle}" --msgbox "${dialogText}" 15 67
  echo "please wait ..."
  exit 0
fi

##########################
# INSTALL
##########################

if [ "$1" = "install" ]; then

  echo "# Installing ${APPID} ..."

  echo "# create user"
  sudo adduser --system --group --shell /bin/bash --home /home/${APPID} ${APPID} || exit 1
  sudo -u ${APPID} cp -r /etc/skel/. /home/${APPID}/

  echo "# add use to special groups"
  sudo /usr/sbin/usermod --append --groups lndadmin ${APPID}

  # use new app user home as install directory
  cd /home/${APPID}

  # download Alby Hub
  if [ ${cpu} == "aarch64" ]; then
    echo "# Downloading Alby Hub for aarch64"
    sudo wget -O albyhub-server.tar.bz2 https://github.com/getAlby/hub/releases/download/v$VERSION/albyhub-Server-Linux-aarch64.tar.bz2
  else
    echo "# Downloading Alby Hub for x86"
    sudo wget -O albyhub-server.tar.bz2 https://github.com/getAlby/hub/releases/download/v$VERSION/albyhub-Server-Linux-x86_64.tar.bz2 
  fi

  # extract archives
  sudo tar -xvf albyhub-server.tar.bz2
  if [[ $? -ne 0 ]]; then
    echo "# Failed to download & unpack Alby Hub"
    echo "error='download & unpack failed'"
    exit 1
  fi

  # cleanup
  sudo rm -f albyhub-server.tar.bz2

  # Setze die Berechtigungen für das Verzeichnis und die Dateien
  sudo chmod -R 755 /home/${APPID}/lib
  sudo chown -R root:root /home/${APPID}/lib

  # make libs available
  echo "/home/${APPID}/lib" | sudo tee /etc/ld.so.conf.d/${APPID}.conf
  sudo ldconfig
  
  echo "# Install ${APPID} done"
  exit 0

fi

##########################
# ON
##########################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # dont run install if already installed
  if [ ${isInstalled} -eq 1 ]; then
    echo "# ${APPID}.service is already installed."
    exit 1
  fi

  # check if lnd service is available (LND is needed as a base)
  if [ $(sudo ls /etc/systemd/system/lnd.service 2>/dev/null | grep -c 'lnd.service') -eq 0 ]; then
    echo "error='LND needs to be installed'"
    exit 1
  fi

  # check if code is already installed
  isInstalled=$(compgen -u | grep -c ${APPID})
  if [ "${isInstalled}" == "0" ]; then
    echo "# Installing code base & dependencies first .."
    /home/admin/config.scripts/bonus.albyhub.sh install || { echo "error='install failed'"; exit 1; }
  fi

  echo "# ACTIVATE Alby-Hub"

  # prepare data directory
  sudo mkdir -p /mnt/hdd/app-data/${APPID} 2>/dev/null
  sudo chown -R ${APPID}:${APPID} /mnt/hdd/app-data/${APPID}

  # open the ports in the firewall
  echo "# updating Firewall"
  sudo ufw allow ${PORT_CLEAR} comment "${APPID} HTTP"
  sudo ufw allow ${PORT_SSL} comment "${APPID} HTTPS"

  # prepare env file
  echo "# prepare env file --> ${ENVFILE}"
  sudo touch ${ENVFILE}
  sudo chown ${APPID}:${APPID} ${ENVFILE}
  sudo chmod 770 ${ENVFILE}

  # create systemd service
  echo "# create systemd service: ${APPID}.service"
  echo "
[Unit]
Description=AlbyHub
Wants=lnd.service
After=lnd.service

[Service]
Type=simple
Restart=always
RestartSec=1
User=${APPID}
ExecStartPre=-/home/admin/config.scripts/bonus.${APPID}.sh prestart
EnvironmentFile=${ENVFILE}
ExecStart=/home/${APPID}/bin/${APPID}
# Hack to ensure Alby Hub never uses more than 90% CPU
CPUQuota=90%sudo 

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${APPID}.service
  sudo chown root:root /etc/systemd/system/${APPID}.service

  # when tor is set on also install the hidden service
  if [ "${runBehindTor}" = "on" ]; then
    # activating tor hidden service
    /home/admin/config.scripts/tor.onion-service.sh ${APPID} 80 ${PORT_TOR_CLEAR} 443 ${PORT_TOR_SSL}
  fi

  # nginx configuration
  # BACKGROUND is that the plain HTTP is served by your web app, but thru the nginx proxy it will be available
  # with (self-signed) HTTPS and with separate configs for Tor & Tor+HTTPS.
  
  echo "# setup nginx confing"

  # write the HTTPS config
  echo "
server {
    listen ${PORT_SSL} ssl;
    listen [::]:${PORT_SSL} ssl;
    server_name _;
    include /etc/nginx/snippets/ssl-params.conf;
    include /etc/nginx/snippets/ssl-certificate-app-data.conf;
    access_log /var/log/nginx/access_${APPID}.log;
    error_log /var/log/nginx/error_${APPID}.log;
    location / {
        proxy_pass http://127.0.0.1:${PORT_CLEAR};
        include /etc/nginx/snippets/ssl-proxy-params.conf;
    }
}
" | sudo tee /etc/nginx/sites-available/${APPID}_ssl.conf
  sudo ln -sf /etc/nginx/sites-available/${APPID}_ssl.conf /etc/nginx/sites-enabled/

  # write the Tor config
  echo "
server {
    listen ${PORT_TOR_CLEAR};
    server_name _;
    access_log /var/log/nginx/access_${APPID}.log;
    error_log /var/log/nginx/error_${APPID}.log;
    location / {
        proxy_pass http://127.0.0.1:${PORT_CLEAR};
        include /etc/nginx/snippets/ssl-proxy-params.conf;
    }
}
" | sudo tee /etc/nginx/sites-available/${APPID}_tor.conf
  sudo ln -sf /etc/nginx/sites-available/${APPID}_tor.conf /etc/nginx/sites-enabled/

  # write the Tor+HTTPS config
  echo "
server {
    listen ${PORT_TOR_SSL} ssl;
    server_name _;
    include /etc/nginx/snippets/ssl-params.conf;
    include /etc/nginx/snippets/ssl-certificate-app-data-tor.conf;
    access_log /var/log/nginx/access_${APPID}.log;
    error_log /var/log/nginx/error_${APPID}.log;
    location / {
        proxy_pass http://127.0.0.1:${PORT_CLEAR};
        include /etc/nginx/snippets/ssl-proxy-params.conf;
    }
}
" | sudo tee /etc/nginx/sites-available/${APPID}_tor_ssl.conf
  sudo ln -sf /etc/nginx/sites-available/${APPID}_tor_ssl.conf /etc/nginx/sites-enabled/

  # test nginx config & activate thru reload
  sudo nginx -t
  sudo systemctl reload nginx

  # enable app up thru systemd
  sudo systemctl enable ${APPID}
  echo "# OK - the ${APPID}.service is now enabled"

  # start app (only when blitz is ready)
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    sudo systemctl start ${APPID}
    echo "# OK - the ${APPID}.service is now started"
  fi

  echo "# mark app as installed in raspiblitz config"
  /home/admin/config.scripts/blitz.conf.sh set ${APPID} "on"

  echo "# Monitor with: sudo journalctl -f -u ${APPID}"
  echo "# OK actvation done"

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

###########################################
# OFF / UNINSTALL
# call with parameter `delete-data` to also
# delete the persistent data directory
###########################################

if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# stop & remove systemd service"
  sudo systemctl stop ${APPID} 2>/dev/null
  sudo systemctl disable ${APPID}.service
  sudo rm /etc/systemd/system/${APPID}.service

  echo "# remove nginx symlinks"
  sudo rm -f /etc/nginx/sites-enabled/${APPID}_ssl.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-enabled/${APPID}_tor.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-enabled/${APPID}_tor_ssl.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-available/${APPID}_ssl.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-available/${APPID}_tor.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-available/${APPID}_tor_ssl.conf 2>/dev/null
  sudo nginx -t
  sudo systemctl reload nginx

  echo "# close ports on firewall"
  sudo ufw deny "${PORT_CLEAR}"
  sudo ufw deny "${PORT_SSL}"

  echo "# removing Tor hidden service (if active)"
  /home/admin/config.scripts/tor.onion-service.sh off ${APPID}

  echo "# mark app as uninstalled in raspiblitz config"
  /home/admin/config.scripts/blitz.conf.sh set ${APPID} "off"

  # only if 'delete-data' is an additional parameter then also the data directory gets deleted
  if [ "$(echo "$@" | grep -c delete-data)" -gt 0 ]; then
    echo "# found 'delete-data' parameter --> also deleting the app-data"
    sudo rm -r /mnt/hdd/app-data/${APPID}
  fi

  echo "# OK - app should be uninstalled now"
  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

########################################
# UNINSTALL (remove from system)
########################################

if [ "$1" = "uninstall" ]; then

  isActive=$(sudo ls /etc/systemd/system/${APPID}.service 2>/dev/null | grep -c '${APPID}.service')
  if [ "${isActive}" != "0" ]; then
    echo "# cannot uninstall if still 'on'"
    exit 1
  fi

  # remove libraries again
  sudo rm /etc/ld.so.conf.d/albyhub.conf
  sudo ldconfig

  # nuke user
  sudo userdel -rf ${APPID} 2>/dev/null

  echo "# uninstall ${APPID} done"

  exit 0
fi

# just a basic error message when unknown action parameter was given
echo "# FAIL - Unknown Parameter $1"
exit 1
