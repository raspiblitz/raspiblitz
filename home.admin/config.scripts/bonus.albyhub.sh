#!/bin/bash

# This script installs Alby Hub on RaspiBlitz.
# Rename it as `bonus.albyhub.sh` and place it in `/home/admin/config.scripts`.

# id string of your app (short single string unique in raspiblitz)
APPID="albyhub" # one-word lower-case no-specials

# https://github.com/getAlby/hub/releases
VERSION="1.10.4"

# port numbers the app should run on
# delete if not an web app
PORT_CLEAR="8029"
PORT_SSL="8030"
PORT_TOR_CLEAR="80"
PORT_TOR_SSL="443"

# BASIC COMMANDLINE OPTIONS
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# bonus.${APPID}.sh status    -> status information (key=value)"
  echo "# bonus.${APPID}.sh on        -> install the app"
  echo "# bonus.${APPID}.sh off       -> uninstall the app"
  echo "# bonus.${APPID}.sh menu      -> SSH menu dialog"
  echo "# bonus.${APPID}.sh prestart  -> will be called by systemd before start"
  exit 1
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
  echo "isInstalled=${isInstalled}"
  echo "isRunning=${isRunning}"
  if [ "${isInstalled}" == "1" ]; then
    echo "localIP='${localIP}'"
    echo "portCLEAR=${PORT_CLEAR}"
    echo "portSSL=${PORT_SSL}"
    echo "localIP='${localIP}'"
    echo "toraddress='${toraddress}'"
    echo "fingerprint='${fingerprint}'"
  fi
  exit
fi

##########################
# MENU
#########################

# show info menu
if [ "$1" = "menu" ]; then

  if [ ${isInstalled} -lt 1 ]; then
    echo "error='App not installed'"
    exit 1
  fi

  # set the title for the dialog
  dialogTitle=" ${APPID} "

  # basic info text - for a web app how to call with http
  dialogText="Open in your local web browser:
http://${localIP}:${PORT_CLEAR}\n
https://${localIP}:${PORT_SSL} with Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
"

  # use whiptail to show SSH dialog & exit
  whiptail --title "${dialogTitle}" --msgbox "${dialogText}" 18 67
  echo "please wait ..."
  exit 0
fi

##########################
# ON / INSTALL
##########################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # dont run install if already installed
  if [ ${isInstalled} -eq 1 ]; then
    echo "# ${APPID}.service is already installed."
    exit 1
  fi

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

  echo "debug exit"
  exit 0

  # cleanup
  rm albyhub-server.tar.bz2

  # make libs available
  echo "/opt/albyhub/lib" | sudo tee /etc/ld.so.conf.d/albyhub.conf
  sudo ldconfig

  # create systemd service
  echo "# create systemd service: ${APPID}.service"
  echo "
[Unit]
Description=Alby Hub
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=1
User=$USER
ExecStart=/opt/albyhub/bin/albyhub
# Hack to ensure Alby Hub never uses more than 90% CPU
CPUQuota=90%

Environment=\"PORT=80\"
Environment=\"WORK_DIR=/opt/albyhub/data\"
Environment=\"LDK_ESPLORA_SERVER=https://electrs.getalbypro.com\"
Environment=\"LOG_EVENTS=true\"
Environment=\"LDK_GOSSIP_SOURCE=\"

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${APPID}.service
  sudo chown root:root /etc/systemd/system/${APPID}.service

  # enable and start the service
  sudo systemctl enable ${APPID}
  sudo systemctl start ${APPID}

  echo "\n\n✅ Installation finished! Please visit http://${localIP} to configure your new Alby Hub."
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

  echo "# delete user and directories"
  sudo userdel -rf ${APPID}

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
  exit 0
fi

# just a basic error message when unknown action parameter was given
echo "# FAIL - Unknown Parameter $1"
exit 1
