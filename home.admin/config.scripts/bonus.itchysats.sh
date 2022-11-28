#!/bin/bash

# id string of your app (short single string unique in raspiblitz)
# should be same as used in name if script
APPID="itchysats" # one-word lower-case no-specials

# the git repo to get the source code from for install
GITHUB_REPO="https://github.com/itchysats/itchysats"

# the github tag of the version of the source code to install
# can also be a commit hash 
# if empty it will use the latest source version
# GITHUB_VERSION=$( curl -s https://api.github.com/repos/itchysats/itchysats/releases | jq -r '.[].tag_name' | grep -v "rc" | head -n1)
GITHUB_VERSION="0.7.0"

# the github signature to verify the author
# leave GITHUB_SIGN_AUTHOR empty to skip verifying 
GITHUB_SIGN_AUTHOR=""
GITHUB_SIGN_PUBKEYLINK=""
GITHUB_SIGN_FINGERPRINT=""

# port numbers the app should run on
# delete if not an web app
PORT_CLEAR="8888"
PORT_SSL="8889"
PORT_TOR_CLEAR="8890"
PORT_TOR_SSL="8891"

# BASIC COMMANDLINE OPTIONS
# you can add more actions or parameters if needed - for example see the bonus.rtl.sh
# to see how you can deal with an app that installs multiple instances depending on
# lightning implementation or testnets - but this should be OK for a start:
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# bonus.${APPID}.sh status   -> status information (key=value)"
  echo "# bonus.${APPID}.sh on       -> install the app. Takes as argument '--build VERSION' to build from source or '--download VERSION' to download the binary from Github with the provided VERSION"
  echo "# bonus.${APPID}.sh off      -> uninstall the app"
  echo "# bonus.${APPID}.sh menu     -> SSH menu dialog"
  echo "# bonus.${APPID}.sh update   -> update the app to latest version"
  echo "# bonus.${APPID}.sh prestart -> will be called by systemd before start"
  exit 1
fi

# echoing comments is useful for logs - but start output with # when not a key=value 
echo "# Running: 'bonus.${APPID}.sh $*'"

# check & load raspiblitz config
source /mnt/hdd/raspiblitz.conf

# get password B to allow user to sign in with their know password
PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
# set network for ITchySats
ITCHYSATS_NETWORK="mainnet"
if [ "${chain}" = "test" ]; then
  ITCHYSATS_NETWORK="testnet"
fi
if [ "${chain}" = "sig" ]; then
  echo "* Warn: We do not support signet. Falling back to testnet"
  ITCHYSATS_NETWORK="testnet"
fi
ITCHYSATS_BIN_DIR=/home/${APPID}/bin/taker

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

# if the action parameter `info` was called - just stop here and output all
# status information as a key=value list
if [ "$1" = "info" ]; then
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
# Helper funcitons
#########################


buildFromSource() {
    VERSION=$1
    echo "# Building Binary $VERSION"

    # make sure needed debian packages are installed
    # 'fbi' is here just an example - change to what you need or delete
    echo "# Install from source code"

    # install Rust dependencies:
    echo "# Installing rustup for the ${APPID} user"
    cd /home/${APPID} || exit 1
    curl --proto '=https' --tlsv1.2 -sSs https://sh.rustup.rs | sudo -u ${APPID} sh -s -- -y

    # download source code and verify
    # BACKGROUND is that now you download the code from github, reset to a given version tag/commit,
    # verify the author. If you app provides its source/binaries in another way, may check
    # other install scripts to see how that implement code download & verify.
    echo "# download from source code & verify"
    sudo -u ${APPID} git clone ${GITHUB_REPO} /home/${APPID}/${APPID}
    cd /home/${APPID}/${APPID} || exit 1

    sudo -u ${APPID} git reset --hard "$VERSION"
    if [ "${GITHUB_SIGN_AUTHOR}" != "" ]; then
      sudo -u ${APPID} /home/admin/config.scripts/blitz.git-verify.sh \
       "${GITHUB_SIGN_AUTHOR}" "${GITHUB_SIGN_PUBKEYLINK}" "${GITHUB_SIGN_FINGERPRINT}" "${VERSION}" || exit 1
    fi

    # compile/install the app
    # BACKGROUND on this example is a web app that compiles with NodeJS. But of course
    # your app could have a complete other way to install - check other instal screipts as examples.
    echo "# compile/install the app. This will take a long time"
    sudo -u ${APPID} /home/${APPID}/.cargo/bin/cargo install --path taker --locked --target-dir /home/${APPID}/bin/
    exitCode=$?
    sudo rm -R /home/${APPID}/.rustup
    if ! [ ${exitCode} -eq 0 ]; then
        echo "# FAIL - cargo install did not run correctly - deleting code & exit"
        sudo rm -r /home/${APPID}/${APPID}
        exit 1
    fi
}

downloadBinary() {
    VERSION=${1}
    echo "# Downloading Binary $VERSION"

    echo "# Detect CPU architecture ..."
    architecture=$(uname -m)
    isAARCH64=$(uname -m | grep -c 'aarch64')
    isX86_64=$(uname -m | grep -c 'x86_64')
    if [ ${isAARCH64} -eq 0 ] && [ ${isX86_64} -eq 0 ] ; then
        echo "# FAIL #"
        echo "# Can only build on aarch64 or x86_64 not on:"
        uname -m
        exit 1
    else
        echo "# OK running on $architecture architecture."
    fi

    # create directories
    sudo -u ${APPID} mkdir -p /home/${APPID}/downloads
    sudo rm -fR /home/${APPID}/downloads/*
    cd /home/${APPID}/downloads/ || exit 1

    archiveName="taker_${VERSION}_Linux_${architecture}.tar"
    sudo -u ${APPID} wget -N ${GITHUB_REPO}/releases/download/"${VERSION}"/"${archiveName}"
    checkDownload=$(ls "${archiveName}" 2>/dev/null | grep -c "${archiveName}")
    if [ "${checkDownload}" -eq 0 ]; then
        echo "# FAIL #"
        echo "# Downloading the binary failed"
        exit 1
    fi

    # install
    echo "# unzip binary: ${archiveName}"
    sudo -u ${APPID} tar -xvf "${archiveName}"
    echo "# install binary"
    sudo -u ${APPID} mkdir -p /home/${APPID}/bin
    sudo install -m 0755 -o ${APPID} -g ${APPID} -t /home/${APPID}/bin taker
    sleep 3

    sudo -u ${APPID} "${ITCHYSATS_BIN_DIR}" --help 1> /dev/null
    exitstatus=$?
    if [ "${exitstatus}" -ne 0 ]; then
        echo "# FAIL #"
        echo "# install failed"
        exit 1
    fi

    echo
    echo "# Cleaning up download artifacts"
    echo

    sudo -u ${APPID} rm -f "${archiveName}"
    sudo -u ${APPID} rm -f taker
}

##########################
# MENU
#########################

# The `menu` action should give at least a SSH info dialog - when an webapp show
# URL to call (http & https+fingerprint) otherwise some instruction how to start it.

# This SSH dialog will be later called by the MAIN MENU to be available to the user
# when app is istalled.

# This menu can also have some more complex structure if you want to make it easy
# to the user to set configurations or maintance options - example bonus.lnbits.sh

# show info menu
if [ "$1" = "menu" ]; then

  # set the title for the dialog
  dialogTitle=" ${APPID} "

  # basic info text - for an web app how to call with http & self-signed https
  dialogText="Open in your local web browser:
http://${localIP}:${PORT_CLEAR}\n
https://${localIP}:${PORT_SSL} with Fingerprint:
${fingerprint}\n
Use 'itchysats' as username and your Password B to login.\n
"

  # add tor info (if available)
  if [ "${toraddress}" != "" ]; then
    dialogText="${dialogText}Hidden Service address for Tor Browser (QRcode on LCD):\n${toraddress}"
  fi

  # use whiptail to show SSH dialog & exit
  whiptail --title "${dialogTitle}" --msgbox "${dialogText}" 18 67
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
  if [ "${isInstalled}" -eq 1 ]; then
    echo "# ${APPID}.service is already installed."
    exit 1
  fi

  echo "# Installing ${APPID} ..."

  # create a dedicated user for the app 
  # BACKGROUND is here to seperate running apps by unix users
  # and only give file write access to the rest of the system where needed.
  echo "# Create user"
  sudo adduser --disabled-password --gecos "" ${APPID}

  # create a data directory on /mnt/hdd/app-data/ for the app
  # BACKGROUND is that any critical data that needs to survive an update should
  # be stored in that app-data directory. All data there will also be part of
  # any raspiblitz data migration. Also on install handle the case that there
  # is already data from a pervious install available the user wants to 
  # continue to use and even may come from an older version from your app.

  if ! [ -d /mnt/hdd/app-data/${APPID} ]; then

    echo "# Create app-data directory"
    sudo mkdir /mnt/hdd/app-data/${APPID} 2>/dev/null
    sudo chown ${APPID}:${APPID} -R /mnt/hdd/app-data/${APPID}

  else

    echo "# Reuse existing app-directory"
    sudo chown ${APPID}:${APPID} -R /mnt/hdd/app-data/${APPID}

  fi

  # Build from source or download binary from Github?
  build=0
  if [ "$2" = "--build" ]; then
    build=1
  elif [ "$2" = "--download" ]; then
    build=0
  else
    if (whiptail --title "Build or Download" --yesno "Do you want to build from source (yes) or download the binary from Github (no)?" 8 80); then
      build=1
    else
      build=0
    fi
  fi

  echo "# Build var set to (${build})"

  VERSION="$GITHUB_VERSION"
  if [ -n "$3" ]; then
    VERSION=$3
  fi
  if [ ${build} -eq 1 ]; then
    buildFromSource "$VERSION"
  else
    downloadBinary "$VERSION"
  fi
  exitstatus=$?
  if [ "${exitstatus}" -ne 0 ]; then
    echo "# Setting up ItchySats failed :("
    exit 1
  fi

  # open the ports in the firewall
  echo "# updating Firewall"
  sudo ufw allow ${PORT_CLEAR} comment "${APPID} HTTP"
  sudo ufw allow ${PORT_SSL} comment "${APPID} HTTPS"


  # every app should have their own systemd service that cares about starting & 
  # running the app in the background - see the PRESTART section for adhoc config
  # please config this systemd template to your needs
  echo "# create systemd service: ${APPID}.service"
  echo "
[Unit]
Description=${APPID}
Wants=bitcoind.service
After=bitcoind.service

[Service]
Environment=\"HOME_PATH=/mnt/hdd/app-data/${APPID}\"
Environment=\"ITCHYSATS_ENV=raspiblitz\"
ExecStartPre=-/home/admin/config.scripts/bonus.${APPID}.sh prestart
ExecStart=$ITCHYSATS_BIN_DIR --http-address=0.0.0.0:$PORT_CLEAR --data-dir=/mnt/hdd/app-data/${APPID} --password=$PASSWORD_B ${ITCHYSATS_NETWORK}
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
  # BACKGROUND is that the plain HTTP is served by your web app, but thru the nginx proxy it will be avaibale
  # with (self-signed) HTTPS and with sepereate configs for Tor & Tor+HTTPS.
  
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

        # to support SSE
        proxy_set_header Connection '';
        proxy_http_version 1.1;
        chunked_transfer_encoding off;
        proxy_buffering off;
        proxy_cache off;
    }
}
" | sudo tee /etc/nginx/sites-available/${APPID}_ssl.conf
  sudo ln -sf /etc/nginx/sites-available/${APPID}_ssl.conf /etc/nginx/sites-enabled/

  # write the TOR config
  echo "
server {
    listen ${PORT_TOR_CLEAR};
    server_name _;
    access_log /var/log/nginx/access_${APPID}.log;
    error_log /var/log/nginx/error_${APPID}.log;
    location / {
        proxy_pass http://127.0.0.1:${PORT_CLEAR};
        include /etc/nginx/snippets/ssl-proxy-params.conf;

        # to support SSE
        proxy_set_header Connection '';
        proxy_http_version 1.1;
        chunked_transfer_encoding off;
        proxy_buffering off;
        proxy_cache off;
    }
}
" | sudo tee /etc/nginx/sites-available/${APPID}_tor.conf
  sudo ln -sf /etc/nginx/sites-available/${APPID}_tor.conf /etc/nginx/sites-enabled/

  # write the TOR+HTTPS config
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

        # to support SSE
        proxy_set_header Connection '';
        proxy_http_version 1.1;
        chunked_transfer_encoding off;
        proxy_buffering off;
        proxy_cache off;
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
  # they are installed that then is calling this script with the `menu` parameter. Add your app accordantly.

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

###############
#  UPDATE
###############
if [ "$1" = "update" ]; then
    LATEST_VERSION=$( curl -s https://api.github.com/repos/itchysats/itchysats/releases | jq -r '.[].tag_name' | grep -v "rc" | head -n1)
    echo "# Updating ItchySats to $LATEST_VERSION"

    echo "# Making sure service is not running"
    sudo systemctl stop itchysats

    # Remove ItchySats, keeping data
    /home/admin/config.scripts/bonus.itchysats.sh off --keep-data

    # Reinstall ItchySats with existing data
    if /home/admin/config.scripts/bonus.itchysats.sh on --download "$LATEST_VERSION"; then
        echo "# Updating successful"
    else
        echo "# Updating ItchySats failed :("
        exit 1
    fi

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
# while the app is running with the next restart they will then autmatically update their config
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

  echo "## PRESTART CONFIG DONE for ${APPID}"
  exit 0
fi

###########################################
# OFF / DEINSTALL
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

  echo "# delete user"
  sudo userdel -rf itchysats 2>/dev/null

  # only if 'delete-data' is an additional parameter then also the data directory gets deleted
  if [ "$(echo "$@" | grep -c delete-data)" -gt 0 ]; then
    echo "# found 'delete-data' parameter --> also deleting the app-data"
    sudo rm -r /mnt/hdd/app-data/${APPID}
  fi

  echo "# OK - app should be deinstalled now"
  exit 0

fi

# just a basic error message when unknow action parameter was given  
echo "# FAIL - Unknown Parameter $1"
exit 1

# LAST NOTES:
# Best is to contribute a new app install script as a PR to the raspiblitz GitHub repo. 
# Please base your PR on the `dev` branch - not on the default branch displayed.
