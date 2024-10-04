#!/bin/bash

# This is a template bonus script you can use to add your own app to RaspiBlitz.
# So just copy it within the `/home.admin/config.scripts` directory and
# rename it for your app - example: `bonus.myapp.sh`.
# Then go thru this script and delete parts/comments you dont need or add
# needed configurations.

# id string of your app (short single string unique in raspiblitz)
# should be same as used in name if script
APPID="template" # one-word lower-case no-specials

# clean human readable version - will be displayed in UI
# just numbers only separated by dots (2 or 0.1 or 1.3.4 or 3.4.5.2)
VERSION="0.1"

# the git repo to get the source code from for install
GITHUB_REPO="https://github.com/rootzoll/webapp-template"

# the github tag of the version of the source code to install
# can also be a commit hash
# if empty it will use the latest source version
GITHUB_TAG="v0.1"

# the github signature to verify the author
# leave GITHUB_SIGN_AUTHOR empty to skip verifying
GITHUB_SIGN_AUTHOR="web-flow"
GITHUB_SIGN_PUBKEYLINK="https://github.com/web-flow.gpg"
GITHUB_SIGN_FINGERPRINT="(4AEE18F83AFDEB23|B5690EEEBB952194)"

# port numbers the app should run on
# delete if not an web app
PORT_CLEAR="12345"
PORT_SSL="12346"
PORT_TOR_CLEAR="12347"
PORT_TOR_SSL="12348"

# BASIC COMMANDLINE OPTIONS
# you can add more actions or parameters if needed - for example see the bonus.rtl.sh
# to see how you can deal with an app that installs multiple instances depending on
# lightning implementation or testnets - but this should be OK for a start:
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


  # set the title for the dialog
  dialogTitle=" ${APPID} "

  # basic info text - for an web app how to call with http & self-signed https
  dialogText="Open in your local web browser:
http://${localIP}:${PORT_CLEAR}\n
https://${localIP}:${PORT_SSL} with Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
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
  if [ ${isInstalled} -eq 1 ]; then
    echo "# ${APPID}.service is already installed."
    exit 1
  fi

  echo "# Installing ${APPID} ..."

  # check and install NodeJS - if already installed it will skip
  /home/admin/config.scripts/bonus.nodejs.sh on

  # create a dedicated user for the app
  # BACKGROUND is here to separate running apps by unix users
  # and only give file write access to the rest of the system where needed.
  echo "# create user"
  # If the user is intended to be loeed in to add '--shell /bin/bash'
  # and copy the skeleton files
  sudo adduser --system --group --shell /bin/bash --home /home/${APPID} ${APPID} || exit 1
  # copy the skeleton files for login
  sudo -u ${APPID} cp -r /etc/skel/. /home/${APPID}/

  # add user to special groups with special access rights
  # BACKGROUND there are some unix groups available that will give the access to
  # like for example to the lnd admin macaroons - to check all groups available use:
  # `cut -d: -f1 /etc/group | sort` command on raspiblitz commandline
  echo "# add use to special groups"
  sudo /usr/sbin/usermod --append --groups lndadmin ${APPID}

  # create a data directory on /mnt/hdd/app-data/ for the app
  # BACKGROUND is that any critical data that needs to survive an update should
  # be stored in that app-data directory. All data there will also be part of
  # any raspiblitz data migration. Also on install handle the case that there
  # is already data from a pervious install available the user wants to
  # continue to use and even may come from an older version from your app.

  if ! [ -d /mnt/hdd/app-data/${APPID} ]; then

    echo "# create app-data directory"
    sudo mkdir /mnt/hdd/app-data/${APPID} 2>/dev/null
    sudo chown ${APPID}:${APPID} -R /mnt/hdd/app-data/${APPID}

  else

    echo "# reuse existing app-directory"
    sudo chown ${APPID}:${APPID} -R /mnt/hdd/app-data/${APPID}

  fi

  # make sure needed debian packages are installed
  # 'fbi' is here just an example - change to what you need or delete
  echo "# install from source code"
  sudo apt install -y fbi

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
  # BACKGROUND on this example is a web app that compiles with NodeJS. But of course
  # your app could have a complete other way to install - check other install scripts as examples.
  echo "# compile/install the app"
  cd /home/${APPID}/${APPID}
  sudo -u ${APPID} npm install --only=prod --logLevel warn
  if ! [ $? -eq 0 ]; then
      echo "# FAIL - npm install did not run correctly - deleting code & exit"
      sudo rm -r /home/${APPID}/${APPID}
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
Wants=bitcoind
After=bitcoind

[Service]
WorkingDirectory=/home/${APPID}
Environment=\"HOME_PATH=/mnt/hdd/app-data/${APPID}\"
ExecStartPre=-/home/admin/config.scripts/bonus.${APPID}.sh prestart
ExecStart=/usr/bin/node /home/${APPID}/${APPID}/${APPID}
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
  echo "# no need for adhoc config needed so far"

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

# LAST NOTES:
# Best is to contribute a new app install script as a PR to the raspiblitz GitHub repo.
# Please base your PR on the `dev` branch - not on the default branch displayed.