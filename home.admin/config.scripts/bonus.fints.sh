#!/bin/bash

APPID="fints"
VERSION="2.23"

# the git repo to get the source code from for install
GITHUB_REPO="https://github.com/drmartinberger/FueliFinTS"

# the github tag of the version of the source code to install
# can also be a commit hash
# if empty it will use the latest source version
GITHUB_TAG=""

# the github signature to verify the author
# leave GITHUB_SIGN_AUTHOR empty to skip verifying
GITHUB_SIGN_AUTHOR="" #web-flow
GITHUB_SIGN_PUBKEYLINK="https://github.com/web-flow.gpg"
GITHUB_SIGN_FINGERPRINT="(4AEE18F83AFDEB23|B5690EEEBB952194)"

# port numbers the app should run on
# delete if not an web app
PORT_CLEAR="3110"
PORT_SSL="3111"

# BASIC COMMANDLINE OPTIONS
# you can add more actions or parameters if needed - for example see the bonus.rtl.sh
# to see how you can deal with an app that installs multiple instances depending on
# lightning implementation or testnets - but this should be OK for a start:
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# Github Repo: ${GITHUB_REPO}"
  echo "# Telegram Community Support: https://t.me/LN_FinTS"
  echo "# bonus.${APPID}.sh status    -> status information (key=value)"
  echo "# bonus.${APPID}.sh on        -> install the app"
  echo "# bonus.${APPID}.sh off       -> uninstall the app"
  echo "# bonus.${APPID}.sh menu      -> SSH menu dialog"
  echo "# bonus.${APPID}.sh prestart  -> will be called by systemd before start"
  exit 1
fi

# echoing comments is useful for logs - but start output with # when not a key=value
echo "# Running: 'bonus.${APPID}.sh $*'"

# check & load raspiblitz config
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
  #fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

fi

# if the action parameter `status` was called - just stop here and output all
# status information as a key=value list
if [ "$1" = "status" ]; then
  echo "appID='${APPID}'"
  echo "version='${VERSION}'"
  echo "githubRepo='${GITHUB_REPO}'"
  echo "githubVersion='${GITHUB_TAG}'"
  echo "githubSignature='${GITHUB_SIGNATURE}'"
  echo "isInstalled=${isInstalled}"
  echo "isRunning=${isRunning}"
  if [ "${isInstalled}" == "1" ]; then
    echo "portCLEAR=${PORT_CLEAR}"
    echo "portSSL=${PORT_SSL}"
    echo "localIP='${localIP}'"
    echo "toraddress='${toraddress}'"
    #echo "fingerprint='${fingerprint}'"
    echo "toraddress='${toraddress}'"
  fi
  exit
fi

##########################
# MENU
#########################

# The `menu` action should give at least a SSH info dialog - when an webapp show
# URL to call (http & https+fingerprint) otherwise some instruction how to start it.

# This SSH dialog will be later called by the MAIN MENU to be available to the user
# when app is installed.

# This menu can also have some more complex structure if you want to make it easy
# to the user to set configurations or maintenance options - example bonus.lnbits.sh

# show info menu
if [ "$1" = "menu" ]; then

  # get local ip
  localIP=$(hostname -I | awk '{print $1}')

  # set the title for the dialog
  dialogTitle=" FinTS / HBCI Interface "

  # basic info text - for an web app how to call with http & self-signed https
  dialogText="This is an very early experimental feature.\nServer-URL: ${localIP}:${PORT_SSL}\n\nSee GitHub Repo for more Details:\n${GITHUB_REPO}\n\nTelegram Community Chat & Support (say hi):\nhttps://t.me/LN_FinTS\n\nUse OPTIONS to config with LNbits & Debug.\n\n"

  # add tor info (if available)
  if [ "${toraddress}" != "" ]; then
    dialogText="${dialogText}Hidden Service address for Tor Connection:\n${toraddress}"
  fi

  # use whiptail to show SSH dialog & exit
  whiptail --title "${dialogTitle}" --yes-button "OK" --no-button "OPTIONS" --yesno "${dialogText}" 19 67
  result=$?
  if [ ${result} -eq 0 ]; then
    exit 0
  fi

  OPTIONS=()
  OPTIONS+=(LNBITS "Edit lnbits.properties")
  OPTIONS+=(DEBUG "Print Logs")

  WIDTH=66
  CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
  HEIGHT=$((CHOICE_HEIGHT+7))
  CHOICE=$(dialog --clear \
                --title " ${APPID} - Options" \
                --ok-label "Select" \
                --cancel-label "Back" \
                --menu "Choose one of the following options:" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)
  case $CHOICE in
    DEBUG)
      clear
      echo "# sudo tail -n 100 /home/fints/log/fuelifints.log"
      sudo tail -n 100 /home/fints/log/fuelifints.log
      echo "# PRESS ENTER to continue"
      read key
      ;;
    LNBITS)
      edittemp=$(mktemp -p /dev/shm/)
      sudo -u fints dialog --title "Editing /home/fints/config/lnbits.properties" --editbox "/home/fints/config/lnbits.properties" 200 200 2> "${edittemp}"
      result=$?
      clear
      if [ "${result}" == "0" ]; then
        echo "# saving changes to /home/fints/config/lnbits.properties"
        sudo rm /home/fints/config/lnbits.properties
        sudo mv ${edittemp} /home/fints/config/lnbits.properties
        sudo chown fints:fints /home/fints/config/lnbits.properties
      else
        echo "# (${result}) no changes - dont save"
      fi
      echo "# restarting fints service"
      sudo systemctl restart fints
      sleep 2
      ;;
  esac

  echo "please wait ..."
  exit 0
fi

##########################
# ON / INSTALL
##########################

# This section takes care of installing the app.
# The template contains some basic steps but also look at other install scripts
# to see how special cases are solved.

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # dont run install if already installed
  if [ ${isInstalled} -eq 1 ]; then
    echo "# ${APPID}.service is already installed."
    exit 1
  fi

  echo "# Installing ${APPID} ..."

  # install java & build tool
  sudo apt install -y default-jdk
  sudo apt install -y maven

  # make sure mysql/myria db is available & running
  sudo apt-get install -y mariadb-server mariadb-client
  sudo systemctl enable mariadb 2>/dev/null
  sudo systemctl start mariadb 2>/dev/null

  # create a dedicated user for the app
  echo "# create user"
  sudo adduser --system --group --home /home/${APPID} ${APPID} || exit 1

  # add user to special groups with special access rights
  # echo "# add use to special groups"
  # sudo /usr/sbin/usermod --append --groups lndadmin ${APPID}

  # create a data directory on /mnt/hdd/app-data/ for the app
  if ! [ -d /mnt/hdd/app-data/${APPID} ]; then
    echo "# create app-data directory"
    sudo mkdir /mnt/hdd/app-data/${APPID} 2>/dev/null
    sudo chown ${APPID}:${APPID} -R /mnt/hdd/app-data/${APPID}
  else
    echo "# reuse existing app-directory"
    sudo chown ${APPID}:${APPID} -R /mnt/hdd/app-data/${APPID}
  fi

  # download source code and verify
  # BACKGROUND is that now you download the code from github, reset to a given version tag/commit,
  # verify the author. If you app provides its source/binaries in another way, may check
  # other install scripts to see how that implement code download & verify.
  echo "# download the source code & verify"
  sudo -u ${APPID} git clone ${GITHUB_REPO} /home/${APPID}/${APPID}
  cd /home/${APPID}/${APPID}

  if [ "${GITHUB_TAG}" != "" ]; then
    sudo -u ${APPID} git reset --hard $GITHUB_TAG
  fi
  if [ "${GITHUB_SIGN_AUTHOR}" != "" ]; then
    sudo -u ${APPID} /home/admin/config.scripts/blitz.git-verify.sh \
     "${GITHUB_SIGN_AUTHOR}" "${GITHUB_SIGN_PUBKEYLINK}" "${GITHUB_SIGN_FINGERPRINT}" "${GITHUB_TAG}" || exit 1
  fi

  # compile/install the app
  echo "# compile/install the app"
  cd /home/${APPID}/${APPID}
  # install dependencies from pom.xml
  sudo -u fints mvn package
  if ! [ $? -eq 0 ]; then
      echo "# FAIL - mvn package did not run correctly - deleting code & exit"
      sudo rm -r /home/${APPID}/${APPID}
      exit 1
  fi
  sudo -u fints cp /home/fints/fints/target/LN-FinTS-jar-with-dependencies.jar /home/fints/fints-fat.jar
  if ! [ $? -eq 0 ]; then 
      echo "# FAIL - was not able to copy /home/fints/fints-fat.jar"
      sudo rm -r /home/${APPID}/${APPID}
      exit 1
  fi

  # init database
  sudo mariadb -e "DROP DATABASE IF EXISTS fints;"
  sudo mariadb -e "CREATE DATABASE fints;"
  sudo mariadb -e "GRANT ALL PRIVILEGES ON fints.* TO 'fintsuser' IDENTIFIED BY 'fints';"
  sudo mariadb -e "FLUSH PRIVILEGES;"
  if [ -f "dbsetup.sql" ]; then
    # set default encrypted PIN 123456789 within dbsetup.sql if not yet set
    sudo sed -i -e "s/REPLACE_ENCRYPTED_PIN/$(mvn compile exec:java -Dexec.mainClass="net.petafuel.fuelifints.cryptography.aesencryption.AESUtil" -Dexec.args=123456789 -q)/g" dbsetup.sql
    
    mariadb -ufintsuser -pfints fints < dbsetup.sql
  else
    echo "# FAIL - dbsetup.sql not found - deleting code & exit"
    sudo rm -r /home/${APPID}/${APPID}
    exit 1
  fi

  # open the ports in the firewall
  echo "# updating Firewall"
  sudo ufw allow ${PORT_CLEAR} comment "${APPID} HTTP"
  sudo ufw allow ${PORT_SSL} comment "${APPID} HTTPS"

  # every app has their own systemd service that cares about starting &
  # running the app in the background - see the PRESTART section for adhoc config
  echo "# create systemd service: ${APPID}.service"
  echo "
[Unit]
Description=${APPID}
Wants=bitcoind
After=bitcoind

[Service]
WorkingDirectory=/home/${APPID}
Environment=\"HOME_PATH=/mnt/hdd/app-data/${APPID}\"
ExecStartPre=-/home/admin/config.scripts/bonus.${APPID}.sh prestart
ExecStart=java -jar /home/${APPID}/fints-fat.jar
User=${APPID}
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
" | sudo tee /etc/systemd/system/${APPID}.service
  sudo chown root:root /etc/systemd/system/${APPID}.service

  # when tor is set on also install the hidden service
  if [ "${runBehindTor}" = "on" ]; then
    # activating tor hidden service
    /home/admin/config.scripts/tor.onion-service.sh ${APPID} 80 ${PORT_CLEAR} 443 ${PORT_SSL}
  fi

  # create keystore if needed
  keystoreExists=$(sudo ls /mnt/hdd/app-data/fints/keystore.jks 2>/dev/null | grep -c 'keystore.jks')
  if [ ${keystoreExists} -eq 0 ]; then
    echo "# creating keystore"
    sudo -u fints keytool -genkey -keyalg RSA -alias fints -keystore /mnt/hdd/app-data/fints/keystore.jks -storepass raspiblitz -noprompt -dname "CN=raspiblitz, OU=IT, O=raspiblitz, L=world, S=world, C=BZ"
  else
    echo "# keystore already exists"
  fi
  
  # create aeskey.properties if needed
  aeskeyExists=$(sudo ls /home/fints/aeskey.properties 2>/dev/null | grep -c 'aeskey.properties')
  if [ ${aeskeyExists} -eq 0 ]; then
    echo "# creating aeskey.properties"
    sudo -u fints openssl rand -hex 12 > /home/fints/aeskey.secret
    sudo -u fints openssl enc -aes-128-cbc -kfile /home/fints/aeskey.secret -P -md sha1 | grep "key=" > /home/fints/aeskey.tmp
    sudo sed -i "s/key/aes_key/g" /home/fints/aeskey.tmp
    sudo -u fints tr -d '\n' < /home/fints/aeskey.tmp > /home/fints/aeskey.properties
    sudo -u fints rm /home/fints/aeskey.tmp
  else
    echo "# aeskey.properties already exists"
  fi
  
  # config app basics: fuelifints.properties
  sudo -u fints mkdir /home/fints/config
  sudo -u fints cp /home/fints/fints/config/fuelifints.properties /home/fints/config/fuelifints.properties
  sudo sed -i "s/^productinfo.csv.check=.*/productinfo.csv.check=false/g" /home/fints/config/fuelifints.properties
  sudo sed -i "s/^rdh_port =.*/rdh_port = ${PORT_CLEAR}/g" /home/fints/config/fuelifints.properties
  sudo sed -i "s/^ssl_port =.*/ssl_port = ${PORT_SSL}/g" /home/fints/config/fuelifints.properties
  sudo sed -i "s/^keystore_location =.*/keystore_location = \/mnt\/hdd\/app-data\/fints\/keystore.jks/g" /home/fints/config/fuelifints.properties
  sudo sed -i "s/^keystore_password =.*/keystore_password = raspiblitz/g" /home/fints/config/fuelifints.properties

  # config app basics: blz.banking2.properties.example: blz needs to be replaced with bankcode of fuelifints.properties
  sudo -u fints cp /home/fints/fints/config/blz.banking2.properties.example /home/fints/config/12345678.banking2.properties
  
  # config app basics: connectionpool.properties
  sudo -u fints cp /home/fints/fints/connectionpool.properties.example /home/fints/connectionpool.properties
  sudo sed -i "s/yourdbserver/127.0.0.1/g" /home/fints/connectionpool.properties
  sudo sed -i "s/=dbserver/=127.0.0.1/g" /home/fints/connectionpool.properties
  sudo sed -i "s/=dbuser/=fintsuser/g" /home/fints/connectionpool.properties
  sudo sed -i "s/=dbpassword/=fints/g" /home/fints/connectionpool.properties
  
  # config app basics: lnbits.properties
  sudo -u fints cp /home/fints/fints/config/lnbits.properties.example /home/fints/config/lnbits.properties
  # in file lnbits.properties replace the line starting with lnbitsUrl with the following line 'lnbitsUrl = http://127.0.0.1:5000'
  sudo sed -i "s/lnbitsUrl =.*/lnbitsUrl = http:\/\/127.0.0.1:5000/g" /home/fints/config/lnbits.properties   

  # mark app as installed in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ${APPID} "on"

  # enable app up thru systemd
  sudo systemctl enable ${APPID}
  echo "# OK - the ${APPID}.service is now enabled"

  # start app (only when blitz is ready)
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    sudo systemctl start ${APPID}
    echo "# OK - the ${APPID}.service is now started"
  fi

  echo "# Monitor with: sudo journalctl -f -u ${APPID}"
  exit 0

fi

##########################
# PRESTART
##########################

# BACKGROUND is that this script will be called with `prestart` on every start & restart
# of this apps systemd service. This has the benefit that right before the app is started
# config parameters for this app can be updated so that it always starts with the most updated
# values. With such an "adhoc config" it is for example possible to check right before start
# what other apps are installed and configure connections. Even if those configs outdate later
# while the app is running with the next restart they will then automatically update their config
# again. If you dont need such "adhoc" config for your app - just leave it empty as it is, so
# you maybe later on have the option to use it.

if [ "$1" = "prestart" ]; then

  # needs to be run as the app user - stop if not run as the app user
  # keep in mind that in the prestart section you cannot use `sudo` command
  if [ "$USER" != "${APPID}" ]; then
    echo "# FAIL: run as user ${APPID}"
    exit 1
  fi

  echo "## PRESTART CONFIG START for ${APPID} (called by systemd prestart)"
  # at the moment no on the fly config is needed
  echo "## PRESTART CONFIG DONE for ${APPID}"
  exit 0
fi

###########################################
# OFF / UNINSTALL
# call with parameter `delete-data` to also
# delete the persistent data directory
###########################################

# BACKGROUND is that this section removes entries in systemd, nginx, etc and then
# deletes the user with its home directory to nuke all installed code

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# stop & remove systemd service"
  sudo systemctl stop ${APPID} 2>/dev/null
  sudo systemctl disable ${APPID}.service
  sudo rm /etc/systemd/system/${APPID}.service

  #echo "# remove nginx symlinks"
  #sudo rm -f /etc/nginx/sites-enabled/${APPID}_ssl.conf 2>/dev/null
  #sudo rm -f /etc/nginx/sites-enabled/${APPID}_tor.conf 2>/dev/null
  #sudo rm -f /etc/nginx/sites-enabled/${APPID}_tor_ssl.conf 2>/dev/null
  #sudo rm -f /etc/nginx/sites-available/${APPID}_ssl.conf 2>/dev/null
  #sudo rm -f /etc/nginx/sites-available/${APPID}_tor.conf 2>/dev/null
  #sudo rm -f /etc/nginx/sites-available/${APPID}_tor_ssl.conf 2>/dev/null
  #sudo nginx -t
  #sudo systemctl reload nginx

  echo "# close ports on firewall"
  sudo ufw deny "${PORT_CLEAR}"
  sudo ufw deny "${PORT_SSL}"

  echo "# delete user"
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
