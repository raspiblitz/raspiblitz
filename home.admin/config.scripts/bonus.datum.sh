#!/bin/bash

APPID="datum"

# clean human readable version - will be displayed in UI
# just numbers only separated by dots (2 or 0.1 or 1.3.4 or 3.4.5.2)
VERSION="0.4.1"

# the git repo to get the source code from for install
GITHUB_REPO="https://github.com/OCEAN-xyz/datum_gateway.git"

# the github tag of the version of the source code to install
# can also be a commit hash
# if empty it will use the latest source version
GITHUB_TAG="v0.4.1beta"

# the github signature to verify the author
# leave GITHUB_SIGN_AUTHOR empty to skip verifying
GITHUB_SIGN_AUTHOR="luke-jr"
GITHUB_SIGN_PUBKEYLINK="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x1a3e761f19d2cc7785c5502ea291a2c45d0c504a"
GITHUB_SIGN_FINGERPRINT="A291A2C45D0C504A"

# port numbers the app should run on
# delete if not an web app
PORT_CLEAR="21000"

# BASIC COMMANDLINE OPTIONS
# you can add more actions or parameters if needed - for example see the bonus.rtl.sh
# to see how you can deal with an app that installs multiple instances depending on
# lightning implementation or testnets - but this should be OK for a start:
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# bonus.${APPID}.sh status    -> status information (key=value)"
  echo "# bonus.${APPID}.sh on        -> install the app"
  echo "# bonus.${APPID}.sh off       -> uninstall the app"
  echo "# bonus.${APPID}.sh menu      -> SSH menu dialog"
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

  localIP=$(hostname -I | awk '{print $1}')

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
    echo "localIP='${localIP}'"
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

  password=$(jq -r '.api.admin_password' /mnt/hdd/app-data/datum/datum_config.json)

  # basic info text - for an web app how to call with http & self-signed https
  dialogText="Open in your local web browser:
http://${localIP}:${PORT_CLEAR}\n

Datum user=admin
Datum admin password=$password
"

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

  # create a dedicated user for the app
  # BACKGROUND is here to separate running apps by unix users
  # and only give file write access to the rest of the system where needed.
  echo "# create user"
  # If the user is intended to be logged in to add '--shell /bin/bash'
  # and copy the skeleton files
  sudo adduser --system --group --shell /bin/bash --home /home/${APPID} ${APPID} || exit 1
  # copy the skeleton files for login
  sudo -u ${APPID} cp -r /etc/skel/. /home/${APPID}/

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
  sudo apt install -y cmake pkgconf libcurl4-openssl-dev libjansson-dev libmicrohttpd-dev libsodium-dev psmisc pwgen

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
  sudo -u ${APPID} cmake . && sudo -u ${APPID} make
  if ! [ $? -eq 0 ]; then
      echo "# FAIL - make did not run correctly - deleting code & exit"
      sudo rm -r /home/${APPID}/${APPID}
      exit 1
  fi

  #creating the config file
  if [ -e "/mnt/hdd/app-data/${APPID}/datum_config.json" ]; then
    echo "There is already a datum config file"
  else
    sudo -u ${APPID} touch /mnt/hdd/app-data/${APPID}/datum_config.json
  fi

  PASS=$(pwgen -N 1 -n 20)

  sudo -u ${APPID} bash -c 'echo "{
  \"bitcoind\": {
    \"rpcuser\": \"auto-config\",
    \"rpcpassword\": \"auto-config\",
    \"rpcurl\": \"127.0.0.1:8332\"
  },
  \"api\": {
    \"listen_port\": 21000,
    \"modify_conf\": true,
    \"admin_password\": \"$1\"
  },
  \"mining\": {
    \"pool_address\": \"\",
    \"coinbase_tag_primary\": \"DATUM on raspiblitz\",
    \"coinbase_tag_secondary\": \"DATUM on raspiblitz\"
  },
  \"stratum\": {
    \"listen_port\": 23334
  },
  \"logger\": {
    \"log_level_console\": 2
  },
  \"datum\": {
    \"pool_pass_workers\": true,
    \"pool_pass_full_users\": true,
    \"pooled_mining_only\": true
  }
}
" > /mnt/hdd/app-data/datum/datum_config.json' _ "$PASS"

  # Configure bitcoind

  sudo -u bitcoin bash -c 'echo "blockmaxsize=3985000" >> /mnt/hdd/app-data/bitcoin/bitcoin.conf'
  sudo -u bitcoin bash -c 'echo "blockmaxweight=3985000" >> /mnt/hdd/app-data/bitcoin/bitcoin.conf'
  sudo -u bitcoin bash -c 'echo "maxmempool=1000" >> /mnt/hdd/app-data/bitcoin/bitcoin.conf'
  sudo -u bitcoin bash -c 'echo "blockreconstructionextratxn=1000000" >> /mnt/hdd/app-data/bitcoin/bitcoin.conf'
  sudo -u bitcoin bash -c 'echo "blocknotify=curl -s -m 5 127.0.0.1:21000/NOTIFY" >> /mnt/hdd/app-data/bitcoin/bitcoin.conf'
  sudo -u bitcoin sed -i "s/^dnsseed=.*/dnsseed=1/" "/mnt/hdd/app-data/bitcoin/bitcoin.conf"
  sudo -u bitcoin sed -i "/^onlynet=/d" "/mnt/hdd/app-data/bitcoin/bitcoin.conf"

  echo "# restart bitcoind"
  sudo systemctl restart --no-block bitcoind.service

  # open the ports in the firewall
  echo "# updating Firewall"
  sudo ufw allow ${PORT_CLEAR} comment "${APPID} HTTP"
  sudo ufw allow 23334 comment "stratum port"


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
WorkingDirectory=/home/${APPID}
Environment=\"HOME_PATH=/mnt/hdd/app-data/${APPID}\"
ExecStartPre=-/home/admin/config.scripts/bonus.${APPID}.sh prestart
ExecStart=/home/${APPID}/${APPID}/datum_gateway -c /mnt/hdd/app-data/${APPID}/datum_config.json
User=${APPID}
Restart=always
TimeoutSec=120
RestartSec=30
ProtectSystem=full
NoNewPrivileges=true

# Hardening measures
PrivateTmp=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${APPID}.service
  sudo chown root:root /etc/systemd/system/${APPID}.service


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

  # OK so your app is now installed, but there please also check the following parts to ensure a proper integration
  # into the raspiblitz system:

  # PROVISION - reinstall on updates & recovery
  # Take a look at `_provision_.sh` script - you can see that there all bonus apps install scripts get called if
  # they have an active entry in the raspiblitz config. This is needed so that on sd card image update or recovery
  # all apps get installed again. So add your app there accordantly so its install will survive an sd card update.

  # MAINMENU - show users that app is installed
  # Take a look at the `00mainmenu.sh` script - you can see there almost all bonus apps add a menu entry there if
  # they are installed that then is calling this script with the `menu` parameter. Add your app accordingly.

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
  RPCPASS=$(cat /mnt/hdd/app-data/bitcoin/bitcoin.conf | grep "^rpcpassword=" | cut -d "=" -f2)
  RPCUSER=$(cat /mnt/hdd/app-data/bitcoin/bitcoin.conf | grep "^rpcuser=" | cut -d "=" -f2)

  jq --arg RPCPASS "$RPCPASS" '.bitcoind.rpcpassword = $RPCPASS' /mnt/hdd/app-data/${APPID}/datum_config.json > /mnt/hdd/app-data/${APPID}/datum_config.json.tmp && mv /mnt/hdd/app-data/${APPID}/datum_config.json.tmp /mnt/hdd/app-data/${APPID}/datum_config.json
  jq --arg RPCUSER "$RPCUSER" '.bitcoind.rpcuser = $RPCUSER' /mnt/hdd/app-data/${APPID}/datum_config.json > /mnt/hdd/app-data/${APPID}/datum_config.json.tmp && mv /mnt/hdd/app-data/${APPID}/datum_config.json.tmp /mnt/hdd/app-data/${APPID}/datum_config.json
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

  echo "# close ports on firewall"
  sudo ufw deny "${PORT_CLEAR}"
  sudo ufw deny "23334"

  echo "# delete user"
  sudo userdel -rf ${APPID}


  echo "# mark app as uninstalled in raspiblitz config"
  /home/admin/config.scripts/blitz.conf.sh set ${APPID} "off"

  echo "# deleting unnecessary bitcoin.conf entry"
  sudo -u bitcoin sed -i "/^blockmaxsize=/d" "/mnt/hdd/app-data/bitcoin/bitcoin.conf"
  sudo -u bitcoin sed -i "/^blockmaxweight=/d" "/mnt/hdd/app-data/bitcoin/bitcoin.conf"
  sudo -u bitcoin sed -i "/^maxmempool=/d" "/mnt/hdd/app-data/bitcoin/bitcoin.conf"
  sudo -u bitcoin sed -i "/^blocknotify=/d" "/mnt/hdd/app-data/bitcoin/bitcoin.conf"
  sudo -u bitcoin sed -i "s/^dnsseed=.*/dnsseed=0/" "/mnt/hdd/app-data/bitcoin/bitcoin.conf"

  echo "# enabling additional network method"
  sudo -u bitcoin bash -c 'echo "onlynet=onion" >> /mnt/hdd/app-data/bitcoin/bitcoin.conf'
  sudo -u bitcoin bash -c 'echo "onlynet=i2p" >> /mnt/hdd/app-data/bitcoin/bitcoin.conf'

  echo "# restart bitcoind"
  sudo systemctl restart --no-block bitcoind.service

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