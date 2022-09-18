#!/bin/bash

APPID="boltcard" # one-word lower-case no-specials

# the git repo to get the source code from for install
GITHUB_REPO="https://github.com/boltcard/boltcard"

# the github tag of the version of the source code to install
# can also be a commit hash
# if empty it will use the latest source version
GITHUB_VERSION="d6724d416e977b835f9058ca86298000316d863e"

# the github signature to verify the author
# leave GITHUB_SIGN_AUTHOR empty to skip verifying
# GITHUB_SIGN_AUTHOR="web-flow"
# GITHUB_SIGN_PUBKEYLINK="https://github.com/web-flow.gpg"
# GITHUB_SIGN_FINGERPRINT="4AEE18F83AFDEB23"

# port numbers the app should run on
PORT_CLEAR="59000"
PORT_SSL="59001"
PORT_TOR_CLEAR="59002"
PORT_TOR_SSL="59003"

# db variables
DB_NAME="card_db"
DB_USER="cardapp"

# BASIC COMMANDLINE OPTIONS
# you can add more actions or parameters if needed - for example see the bonus.rtl.sh
# to see how you can deal with an app that installs multiple instances depending on
# lightning implementation or testnets - but this should be OK for a start:
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# bonus.${APPID}.sh status   -> status information (key=value)"
  echo "# bonus.${APPID}.sh on       -> install the app"
  echo "# bonus.${APPID}.sh off      -> uninstall the app"
  echo "# bonus.${APPID}.sh menu     -> SSH menu dialog"
  echo "# bonus.${APPID}.sh prestart -> will be called by systemd before start"
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
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

fi

# if the action parameter `status` was called - just stop here and output all
# status information as a key=value list
if [ "$1" = "status" ]; then
  echo "appID='${APPID}'"
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

  # get status
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.boltcard.sh status)

  if [ ${isInstalled} -eq 0 ]; then
    echo "# FAIL not installed"
    exit 1
  fi

  if [ ${isRunning} -eq 0 ]; then
    dialog --title "Boltcard Not Running" --msgbox "
The boltcard service is not running.
Please check the following debug info.
      " 8 48
    /home/admin/config.scripts/blitz.debug.sh
    echo "Press ENTER to get back to main menu."
    read key
    exit 0
  fi

  # Options (available without TOR)
  OPTIONS=( \
    CONFIGURE "Edit config file" \
    NEWCARD "Setup new card" \
    STATUS "Status Info" \
	)

  CHOICE=$(whiptail --clear --title "Electrum Rust Server" --menu "menu" 10 50 4 "${OPTIONS[@]}" 2>&1 >/dev/tty)
  clear

  case $CHOICE in
    CONFIGURE)
      if /home/admin/config.scripts/blitz.setconf.sh "/home/${APPID}/.env" "${APPID}"
      then
        whiptail \
          --title "Restart" --yes-button "Restart" --no-button "Not now" \
          --yesno "To apply the new settings ${APPID} may need to restart.
          Do you want to restart the ${APPID} service now?" 10 55
        if [ $? -eq 0 ]; then
          echo "# Restarting ${APPID}"
          sudo systemctl restart ${APPID}
        else
          echo "# Continue without restarting."
        fi
      else
        echo "# No change made"
      fi
    ;;
    NEWCARD)
      OPTIONS=()
      if [ "${toraddress}" != "" ]; then
        OPTIONS+=(TOR "${toraddress}")
      fi
      OPTIONS+=(HTTPS "https://${localIP}:${PORT_SSL}")
      
      CHOICE=$(dialog --clear --title "Setup new boltcard" --menu "\nChoose a server:" 11 50 7 "${OPTIONS[@]}" 2>&1 >/dev/tty)

      HOST_DOMAIN=""
      case $CHOICE in
        TOR)
          HOST_DOMAIN="${toraddress}"
        ;;
        HTTPS)
          HOST_DOMAIN="${localIP}:${PORT_SSL}"
        ;;
      esac

      NAME=$(whiptail --clear --title "Setup new boltcard" --inputbox "\nChoose a name for your card" 11 50 2>&1 >/dev/tty)
      TX_MAX=$(whiptail --clear --title "Setup new boltcard" --inputbox "\nEnter the maximum allowed per transaction in satoshis" 11 50 2>&1 >/dev/tty)
      DAY_MAX=$(whiptail --clear --title "Setup new boltcard" --inputbox "\nEnter the maximum allowed per day in satoshis" 11 50 2>&1 >/dev/tty)

      pushd /home/${APPID}/${APPID}/createboltcard
      (
        export $(grep -v '^#' /home/boltcard/.env | xargs)
        export HOST_DOMAIN="$HOST_DOMAIN"
        go build
        ./createboltcard -enable -tx_max=$TX_MAX -day_max=$DAY_MAX -name=$NAME
      )
      popd

    ;;
    STATUS)
      # set the title for the dialog
      dialogTitle=" ${APPID} "

      # basic info text - for an web app how to call with http & self-signed https
      dialogText="To see logs of the Boltcard service, run:
sudo journalctl -fu boltcard

Boltcard API is hosted at:
http://${localIP}:${PORT_CLEAR} [avoid if possible] \n
https://${localIP}:${PORT_SSL} with Fingerprint:
${fingerprint}\n
"

      # add tor info (if available)
      if [ "${toraddress}" != "" ]; then
        dialogText="${dialogText}Hidden Service address for Tor Browser (QRcode on LCD):\n${toraddress}"
      fi

      whiptail --title "${dialogTitle}" --msgbox "${dialogText}" 18 67
      echo "please wait ..."
      exit 0
    ;;
  esac

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

  # check and install Go - if already installed it will skip
  /home/admin/config.scripts/bonus.go.sh on
  # check and install PostgreSQL - if already installed it will skip
  /home/admin/config.scripts/bonus.postgres.sh on

  # create a dedicated user for the app
  echo "# create user"
  sudo adduser --disabled-password --gecos "" ${APPID} || exit 1

  echo "# Make sure symlink to central app-data .lnd directory exists"
  if ! [[ -L "/home/${APPID}/.lnd" ]]; then
    sudo rm -rf "/home/${APPID}/.lnd" 2>/dev/null              # not a symlink.. delete it silently
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/${APPID}/.lnd"  # and create symlink
  fi

  # add user to special groups with special access rights
  echo "# add use to special groups"
  sudo /usr/sbin/usermod --append --groups lndsigner ${APPID}

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
  echo "# download the source code & verify"
  sudo -u ${APPID} git clone ${GITHUB_REPO} /home/${APPID}/${APPID}
  cd /home/${APPID}/${APPID}
  sudo -u ${APPID} git reset --hard $GITHUB_VERSION
  if [ "${GITHUB_SIGN_AUTHOR}" != "" ]; then
    sudo -u ${APPID} /home/admin/config.scripts/blitz.git-verify.sh \
     "${GITHUB_SIGN_AUTHOR}" "${GITHUB_SIGN_PUBKEYLINK}" "${GITHUB_SIGN_FINGERPRINT}" "${GITHUB_VERSION}" || exit 1
  fi

  # compile/install the app
  echo "# compile/install the app"
  cd /home/${APPID}/${APPID}
  
  dbExists = $(sudo -u postgres psql -l | awk '{print $1}' | grep "${DB_NAME}" | wc -l)
  if [ "$dbExists" -gt "0" ]; then
    sudo -u postgres createuser -s ${APPID}
    sudo -u ${APPID} psql postgres -f create_db.sql
  fi

  sudo -u ${APPID} go build

  # open the ports in the firewall
  echo "# updating Firewall"
  sudo ufw allow ${PORT_CLEAR} comment "${APPID} HTTP"
  sudo ufw allow ${PORT_SSL} comment "${APPID} HTTPS"


  # create .env file
  echo "# create .env file"

  # remove symlink or old file
  sudo rm -f /home/${APPID}/.env
  # make app-data dir if missing
  sudo mkdir -p /mnt/hdd/app-data/${APPID}

  if [ -f /mnt/hdd/app-data/${APPID}/.env ]; then
    echo "# skipping: .env file already exists"
  else
    cat > /tmp/${APPID}.env <<EOF
# -----------
# DB Config
# -----------
DB_HOST=localhost
DB_PORT=5432
DB_USER=${DB_USER}
DB_PASSWORD=database_password
DB_NAME=${DB_NAME}

# -----------
# LND Config
# -----------
LN_HOST=localhost
LN_PORT=10009
LN_TLS_FILE=/home/${APPID}/.lnd/tls.cert
LN_MACAROON_FILE=/home/${APPID}/.lnd/data/chain/bitcoin/mainnet/signer.macaroon
FEE_LIMIT_SAT=10

# -----------
# API Config
# -----------
HOST_DOMAIN=localhost
HOST_PORT=59000
LOG_LEVEL=PRODUCTION
AES_DECRYPT_KEY=00000000000000000000000000000000
MIN_WITHDRAW_SATS=1
MAX_WITHDRAW_SATS=1000000
EOF

    sudo mv /tmp/${APPID}.env /mnt/hdd/app-data/${APPID}/.env
    sudo chown ${APPID}:${APPID} /mnt/hdd/app-data/${APPID}/.env
    sudo ln -s /mnt/hdd/app-data/${APPID}/.env /home/${APPID}/
  fi

  echo "# create systemd service: ${APPID}.service"
  echo "
[Unit]
Description=${APPID}
After=network.target network-online.target lnd
Requires=network-online.target
StartLimitIntervalSec=0

[Service]
Environment=\"HOME_PATH=/mnt/hdd/app-data/${APPID}\"
EnvironmentFile=/home/${APPID}/.env
WorkingDirectory=/home/${APPID}/${APPID}
ExecStartPre=!/home/admin/config.scripts/bonus.${APPID}.sh prestart
ExecStart=/home/${APPID}/${APPID}/${APPID}
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

  # mark app as installed in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ${APPID} "on"

  # start app up thru systemd
  sudo systemctl enable ${APPID}
  sudo systemctl start ${APPID}
  echo "# OK - the ${APPID}.service is now enabled & started"
  echo "# Monitor with: sudo journalctl -f -u ${APPID}"
  exit 0

  # OK so your app is now installed, but there please also check the following parts to ensure a propper integration
  # into the raspiblitz system:

  # PROVISION - reinstall on updates & recovery
  # Take a look at `_provision_.sh` script - you can see that there all bonus apps install scripts get called if
  # they have an active entry in the raspiblitz config. This is needed so that on sd card image update or recovery
  # all apps get installed again. So add your app there accordantly so its install will survive an sd card update.

  # MAINMENU - show users that app is installed
  # Take a look at the `00mainmenu.sh` script - you can see there almost all bonus apps add a menu entry there if
  # they are installed that then is calling this script with the `menu` parameter. Add your app accordingly.

  # SERVICES MENU - add your app for onclick install
  # Take a look at the `00settingsMenuServices.sh` script - you can there almost all bonus apps added themselves
  # as an option in to be easily installed & deinstalled. Add your app there accordantly.

  # DEBUGLOGS - add some status information
  # Take a look at the `blitz.debug.sh` script - you can see there that apps if they are installed give some
  # information on their latest logs and where to find them in the case that the user is searching for an  error.
  # So its best practice to also add your app there with some small info to help on debug & finding error logs.

  # PRESTART & DEINSTALL
  # see the following sections of the template

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

  # so if you have anything to configure before service starts, do it here
  PASSWORD_B=$(cat /mnt/hdd/bitcoin/bitcoin.conf | grep "^rpcpassword=" | cut -d "=" -f2)
  echo "# updating database password to PASSWORD_B"
  sudo -u postgres psql -c "ALTER ROLE ${DB_USER} WITH PASSWORD '${PASSWORD_B}';"
  echo "# updating .env conf to use PASSWORD_B for db connection"
  sed -i "s/DB_PASSWORD=*/DB_PASSWORD=${PASSWORD_B}/g" /home/${APPID}/.env

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
    echo "# found 'delete-data' parameter"

    echo "# deleting the db data"
    sudo -u postgres dropdb -e --if-exists "${DB_NAME}"

    echo "# deleting the app-data files"
    sudo rm -r /mnt/hdd/app-data/${APPID}
  fi

  echo "# OK - app should be uninstalled now"
  exit 0

fi

# just a basic error message when unknown action parameter was given
echo "# FAIL - Unknown Parameter $1"
exit 1

# LAST NOTES:
# Best is to contribute a new app install script as a PR to the raspiblitz GitHub repo.
# Please base your PR on the `dev` branch - not on the default branch displayed.