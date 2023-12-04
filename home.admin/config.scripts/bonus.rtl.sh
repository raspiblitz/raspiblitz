#!/bin/bash

# https://github.com/Ride-The-Lightning/RTL/releases
RTLVERSION="v0.14.1"

# check and load raspiblitz config
# to know which network is running
source /mnt/hdd/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# config script for RideTheLightning $RTLVERSION WebInterface"
  echo "# able to run intances for lnd and cl parallel"
  echo "# mainnet and testnet instances can run parallel"
  echo "# bonus.rtl.sh [install|uninstall]"
  echo "# bonus.rtl.sh [on|off|menu] <lnd|cl> <mainnet|testnet|signet> <purge>"
  echo "# bonus.rtl.sh connect-services"
  echo "# bonus.rtl.sh prestart <lnd|cl> <mainnet|testnet|signet>"
  echo "# bonus.rtl.sh update <commit>"
  exit 1
fi

PGPsigner="saubyk"
PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
PGPpubkeyFingerprint="00C9E2BC2E45666F"

echo "# Running: 'bonus.rtl.sh $*'"

source <(/home/admin/config.scripts/network.aliases.sh getvars $2 $3)

# LNTYPE is lnd | cl
echo "# LNTYPE(${LNTYPE})"
# CHAIN is signet | testnet | mainnet
echo "# CHAIN(${CHAIN})"
# prefix for parallel networks
echo "# netprefix(${netprefix})"
echo "# portprefix(${portprefix})"
echo "# typeprefix(${typeprefix})"

# prefix for parallel lightning impl
if [ "${LNTYPE}" == "cl" ]; then
  RTLHTTP=${portprefix}7000
elif [ "${LNTYPE}" == "lnd" ]; then
  RTLHTTP=${portprefix}3000
fi
echo "# RTLHTTP(${RTLHTTP})"

# construct needed varibale elements
configEntry="${netprefix}${typeprefix}rtlWebinterface"
systemdService="${netprefix}${typeprefix}RTL"
echo "# configEntry(${configEntry})"
echo "# systemdService(${systemdService})"

##########################
# MENU
#########################

# show info menu
if [ "$1" = "status" ] || [ "$1" = "menu" ]; then

  # get network info
  isInstalled=$(sudo ls /etc/systemd/system/${netprefix}${typeprefix}RTL.service 2>/dev/null | grep -c 'RTL.service')
  localip=$(hostname -I | awk '{print $1}')
  toraddress=$(sudo cat /mnt/hdd/tor/${netprefix}${typeprefix}RTL/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)
  RTLHTTPS=$((RTLHTTP + 1))

  if [ "$1" = "status" ]; then

    echo "version='${RTLVERSION}'"
    echo "installed='${isInstalled}'"
    echo "localIP='${localip}'"
    echo "httpPort='${RTLHTTP}'"
    echo "httpsPort='${RTLHTTPS}'"
    echo "httpsForced='0'"
    echo "httpsSelfsigned='1'"
    echo "authMethod='password_b'"
    echo "toraddress='${toraddress}'"
    exit
  fi
fi

# show info menu
if [ "$1" = "menu" ]; then

  # check that parameters are set
  if [ "${LNTYPE}" == "" ] || [ "${CHAIN}" == "" ]; then
    clear
    echo "# FAIL missing parameter"
    sleep 2
    exit 1
  fi

  # info with Tor
  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title "Ride The Lightning (RTL - $LNTYPE - $CHAIN)" --msgbox "Open in your local web browser:
http://${localip}:${RTLHTTP}\n
https://${localip}:$((RTLHTTP + 1)) with Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Hidden Service address for Tor Browser (QRcode on LCD):\n${toraddress}
" 16 67
    sudo /home/admin/config.scripts/blitz.display.sh hide

  # info without Tor
  else
    whiptail --title "Ride The Lightning (RTL - $LNTYPE - $CHAIN)" --msgbox "Open in your local web browser & accept self-signed cert:
http://${localip}:${RTLHTTP}\n
https://${localip}:$((RTLHTTP + 1)) with Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Activate Tor to access the web interface from outside your local network.
" 15 67
  fi
  echo "please wait ..."
  exit 0
fi

########################################
# INSTALL (just user, code & compile)
########################################

if [ "$1" = "install" ]; then

  # check if already installed
  if [ -f /home/rtl/RTL/LICENSE ]; then
    echo "# RTL already installed - skipping"
    exit 0
  fi

  echo "# Installing RTL codebase"

  # check and install NodeJS
  /home/admin/config.scripts/bonus.nodejs.sh on

  # create rtl user (one for all instances)
  if [ $(compgen -u | grep -c rtl) -eq 0 ]; then
    sudo adduser --system --group --home /home/rtl rtl || exit 1
  fi

  # download source code and set to tag release
  echo "# Get the RTL Source Code"
  sudo -u rtl rm -rf /home/rtl/RTL 2>/dev/null
  sudo -u rtl git clone https://github.com/ShahanaFarooqui/RTL.git /home/rtl/RTL
  cd /home/rtl/RTL
  # check https://github.com/Ride-The-Lightning/RTL/releases/
  sudo -u rtl git reset --hard $RTLVERSION

  sudo -u rtl /home/admin/config.scripts/blitz.git-verify.sh "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" "${RTLVERSION}" || exit 1

  # from https://github.com/Ride-The-Lightning/RTL/commits/master
  # git checkout 917feebfa4fb583360c140e817c266649307ef72
  if [ -f /home/rtl/RTL/LICENSE ]; then
    echo "# OK - RTL code copy looks good"
  else
    echo "# FAIL - RTL code not available"
    echo "err='code download falied'"
    exit 1
  fi

  # install
  echo "# Running npm install ..."
  export NG_CLI_ANALYTICS=false
  sudo -u rtl npm install --omit=dev --legacy-peer-deps
  if ! [ $? -eq 0 ]; then
    echo "# FAIL - npm install did not run correctly - deleting code and exit"
    sudo rm -r /home/rtl/RTL
    exit 1
  else
    echo "# OK - RTL install looks good"
    echo
  fi

  exit 0
fi

########################################
# UNINSTALL (remove from system)
########################################

if [ "$1" = "uninstall" ]; then

  echo "# Uninstalling RTL codebase"

  # check LND RTL services
  isActiveMain=$(sudo ls /etc/systemd/system/RTL.service 2>/dev/null | grep -c 'RTL.service')
  isActiveTest=$(sudo ls /etc/systemd/system/tRTL.service 2>/dev/null | grep -c 'RTL.service')
  isActiveSig=$(sudo ls /etc/systemd/system/sRTL.service 2>/dev/null | grep -c 'RTL.service')
  if [ "${isActiveMain}" != "0" ] || [ "${isActiveTest}" != "0" ] || [ "${isActiveSig}" != "0" ]; then
    echo "# cannot uninstall RTL still used by LND"
    exit 1
  fi

  # check LND RTL services
  isActiveMain=$(sudo ls /etc/systemd/system/cRTL.service 2>/dev/null | grep -c 'RTL.service')
  isActiveTest=$(sudo ls /etc/systemd/system/tcRTL.service 2>/dev/null | grep -c 'RTL.service')
  isActiveSig=$(sudo ls /etc/systemd/system/scRTL.service 2>/dev/null | grep -c 'RTL.service')
  if [ "${isActiveMain}" != "0" ] || [ "${isActiveTest}" != "0" ] || [ "${isActiveSig}" != "0" ]; then
    echo "# cannot uninstall RTL still used by CLN"
    exit 1
  fi

  echo "# Delete user and home directory"
  sudo userdel -rf rtl

  exit 0
fi

##########################
# ON
#########################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check that parameters are set
  if [ "${LNTYPE}" == "" ] || [ "${CHAIN}" == "" ]; then
    echo "# missing parameter"
    exit 1
  fi

  # check that is already active
  isActive=$(sudo ls /etc/systemd/system/${systemdService}.service 2>/dev/null | grep -c "${systemdService}.service")
  if [ ${isActive} -eq 1 ]; then
    echo "# OK, the ${netprefix}${typeprefix}RTL.service is already active."
    echo "result='already active'"
    exit 1
  fi

  # make sure softwarte is installed
  if [ -f /home/rtl/RTL/LICENSE ]; then
    echo "# OK - the RTL code is already present"
  else
    echo "# install of codebase is needed first"
    /home/admin/config.scripts/bonus.rtl.sh install || exit 1
  fi
  cd /home/rtl/RTL

  echo "# Activating RTL for ${LNTYPE} ${CHAIN}"

  echo "# Make sure symlink to central app-data directory exists"
  if ! [[ -L "/home/rtl/.lnd" ]]; then
    sudo rm -rf "/home/rtl/.lnd" 2>/dev/null             # not a symlink.. delete it silently
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/rtl/.lnd" # and create symlink
  fi

  if [ "${LNTYPE}" == "lnd" ]; then
    # for LND make sure user rtl is allowed to access admin macaroons
    echo "# adding user rtl to group lndadmin"
    sudo /usr/sbin/usermod --append --groups lndadmin rtl
  fi

  echo "# Updating Firewall"
  sudo ufw allow "${RTLHTTP}" comment "${systemdService} HTTP"
  sudo ufw allow $((RTLHTTP + 1)) comment "${systemdService} HTTPS"
  echo

  # make sure config directory exists
  sudo mkdir -p /mnt/hdd/app-data/rtl 2>/dev/null
  sudo chown -R rtl:rtl /mnt/hdd/app-data/rtl

  echo "# Create Systemd Service: ${systemdService}.service (Template)"
  echo "\
# Systemd unit for ${systemdService}

[Unit]
Description=${systemdService} Webinterface
Wants=
After=

[Service]
Environment=\"RTL_CONFIG_PATH=/mnt/hdd/app-data/rtl/${systemdService}/\"
ExecStartPre=-/home/admin/config.scripts/bonus.rtl.sh prestart ${LNTYPE} ${CHAIN}
ExecStart=/usr/bin/node /home/rtl/RTL/rtl
User=rtl
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal
LogLevelMax=4

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/${systemdService}.service
  sudo chown root:root /etc/systemd/system/${systemdService}.service

  # adapt systemd service template for LND
  if [ "${LNTYPE}" == "lnd" ]; then
    echo "# modifying ${systemdService}.service for LND"
    sudo sed -i "s/^Wants=.*/Wants=${netprefix}lnd.service/g" /etc/systemd/system/${systemdService}.service
    sudo sed -i "s/^After=.*/After=${netprefix}lnd.service/g" /etc/systemd/system/${systemdService}.service
  fi
  # adapt systemd service template for
  if [ "${LNTYPE}" == "cl" ]; then
    echo "# modifying ${systemdService}.service for CL"
    sudo sed -i "s/^Wants=.*/Wants=${netprefix}lightningd.service/g" /etc/systemd/system/${systemdService}.service
    sudo sed -i "s/^After=.*/After=${netprefix}lightningd.service/g" /etc/systemd/system/${systemdService}.service

    # set up Core LightningREST
    /home/admin/config.scripts/cl.rest.sh on ${CHAIN}
  fi

  # Note about RTL config file
  echo "# NOTE: the RTL config for this instance will be done on the fly as a prestart in systemd"

  # Hidden Service for RTL if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with tor.network.sh script
    /home/admin/config.scripts/tor.onion-service.sh ${netprefix}${typeprefix}RTL 80 $((RTLHTTP + 2)) 443 $((RTLHTTP + 3))
  fi

  # nginx configuration
  echo "# Setup nginx confs"
  sudo cp /home/admin/assets/nginx/sites-available/rtl_ssl.conf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf
  sudo cp /home/admin/assets/nginx/sites-available/rtl_tor.conf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf
  sudo cp /home/admin/assets/nginx/sites-available/rtl_tor_ssl.conf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf
  sudo sed -i "s/3000/$RTLHTTP/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf
  sudo sed -i "s/3001/$((RTLHTTP + 1))/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf
  sudo sed -i "s/3000/$RTLHTTP/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf
  sudo sed -i "s/3002/$((RTLHTTP + 2))/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf
  sudo sed -i "s/3000/$RTLHTTP/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf
  sudo sed -i "s/3003/$((RTLHTTP + 3))/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf
  sudo ln -sf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf /etc/nginx/sites-enabled/
  sudo nginx -t
  sudo systemctl reload nginx

  # run config as root to connect prepare services (lit, pool, ...)
  sudo /home/admin/config.scripts/bonus.rtl.sh connect-services

  # ig
  /home/admin/config.scripts/blitz.conf.sh set ${configEntry} "on"

  sudo systemctl enable ${systemdService}
  sudo systemctl start ${systemdService}
  echo "# OK - the ${systemdService}.service is now enabled & started"
  echo "# Monitor with: sudo journalctl -f -u ${systemdService}"

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

##########################
# CONNECT SERVICES
# will be called by lit or loop services to make sure services
# are connected or on RTL install/update
#########################

if [ "$1" = "connect-services" ]; then

  # has to run as use root or sudo
  if [ "$USER" != "root" ] && [ "$USER" != "admin" ]; then
    echo "# FAIL: run as user root or admin"
    exit 1
  fi

  # only run when RTL is installed
  if [ -d /home/rtl ]; then
    echo "## RTL CONNECT-SERVICES"
  else
    echo "# no RTL installed - no need to connect any services"
    exit
  fi

  # LIT & LOOP Swap Server
  echo "# checking of swap server ..."
  if [ "${lit}" = "on" ]; then
    echo "# LIT DETECTED"
    echo "# Add the rtl user to the lit group"
    sudo /usr/sbin/usermod --append --groups lit rtl
    echo "# Symlink the lit-loop.macaroon"
    sudo rm -rf "/home/rtl/.loop"                   #  delete symlink
    sudo ln -s "/home/lit/.loop/" "/home/rtl/.loop" # create symlink
    echo "# Make the loop macaroon group readable"
    sudo chmod 640 /home/rtl/.loop/mainnet/macaroons.db
  elif [ "${loop}" = "on" ]; then
    echo "# LOOP DETECTED"
    echo "# Add the rtl user to the loop group"
    sudo /usr/sbin/usermod --append --groups loop rtl
    echo "# Symlink the loop.macaroon"
    sudo rm -rf "/home/rtl/.loop"                    # delete symlink
    sudo ln -s "/home/loop/.loop/" "/home/rtl/.loop" # create symlink
    echo "# Make the loop macaroon group readable"
    sudo chmod 640 /home/rtl/.loop/mainnet/macaroons.db
  else
    echo "# No lit or loop single detected"
  fi

  echo "# RTL CONNECT-SERVICES done"
  exit 0

fi

##########################
# PRESTART
# - will be called as prestart by systemd service (as user rtl)
#########################

if [ "$1" = "prestart" ]; then

  # check that parameters are set
  if [ "${LNTYPE}" == "" ] || [ "${CHAIN}" == "" ]; then
    echo "# missing parameter"
    exit 1
  fi

  # users need to be `rtl` so that it can be run by systemd as prestart (no SUDO available)
  if [ "$USER" != "rtl" ]; then
    echo "# FAIL: run as user rtl"
    exit 1
  fi

  echo "## RTL PRESTART CONFIG (called by systemd prestart)"

  # getting the up-to-date RPC password
  RPCPASSWORD=$(cat /mnt/hdd/${network}/${network}.conf | grep "^rpcpassword=" | cut -d "=" -f2)
  echo "# Using RPCPASSWORD(${RPCPASSWORD})"

  # determine correct loop swap server port (lit over loop single)
  if [ "${lit}" = "on" ]; then
    echo "# use lit loop port"
    SWAPSERVERPORT=8443
  elif [ "${loop}" = "on" ]; then
    echo "# use loop single instance port"
    SWAPSERVERPORT=8081
  else
    echo "# No lit or loop single detected"
    SWAPSERVERPORT=""
  fi

  # prepare RTL-Config.json file
  echo "# PREPARE /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json"

  # make sure directory exists
  mkdir -p /mnt/hdd/app-data/rtl/${systemdService} 2>/dev/null

  # check if RTL-Config.json exists
  configExists=$(ls /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json 2>/dev/null | grep -c "RTL-Config.json")
  if [ "${configExists}" == "0" ]; then
    # copy template
    cp /home/rtl/RTL/Sample-RTL-Config.json /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json
    chmod 600 /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json
  fi

  # LND changes of config
  if [ "${LNTYPE}" == "lnd" ]; then
    echo "# LND Config"
    cat /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json |
      jq ".port = \"${RTLHTTP}\"" |
      jq ".multiPass = \"${RPCPASSWORD}\"" |
      jq ".multiPassHashed = \"\"" |
      jq ".nodes[0].lnNode = \"${hostname}\"" |
      jq ".nodes[0].lnImplementation = \"LND\"" |
      jq ".nodes[0].Authentication.macaroonPath = \"/home/rtl/.lnd/data/chain/${network}/${CHAIN}/\"" |
      jq ".nodes[0].Authentication.configPath = \"/home/rtl/.lnd/${netprefix}lnd.conf\"" |
      jq ".nodes[0].Authentication.swapMacaroonPath = \"/home/rtl/.loop/${CHAIN}/\"" |
      jq ".nodes[0].Authentication.boltzMacaroonPath = \"/home/rtl/.boltz-lnd/macaroons/\"" |
      jq ".nodes[0].Settings.userPersona = \"OPERATOR\"" |
      jq ".nodes[0].Settings.lnServerUrl = \"https://127.0.0.1:${portprefix}8080\"" |
      jq ".nodes[0].Settings.channelBackupPath = \"/mnt/hdd/app-data/rtl/${systemdService}-SCB-backup-$hostname\"" |
      jq ".nodes[0].Settings.swapServerUrl = \"https://127.0.0.1:${SWAPSERVERPORT}\"" >/mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json.tmp
    mv /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json.tmp /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json
  fi

  # Core Lightning changes of config
  # https://github.com/Ride-The-Lightning/RTL/blob/master/docs/C-Lightning-setup.md
  if [ "${LNTYPE}" == "cl" ]; then
    echo "# CL Config"
    cat /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json |
      jq ".port = \"${RTLHTTP}\"" |
      jq ".multiPass = \"${RPCPASSWORD}\"" |
      jq ".multiPassHashed = \"\"" |
      jq ".nodes[0].lnNode = \"${hostname}\"" |
      jq ".nodes[0].lnImplementation = \"CLT\"" |
      jq ".nodes[0].Authentication.macaroonPath = \"/home/bitcoin/c-lightning-REST/${CLNETWORK}/certs\"" |
      jq ".nodes[0].Authentication.configPath = \"${CLCONF}\"" |
      jq ".nodes[0].Authentication.swapMacaroonPath = \"/home/rtl/.loop/${CHAIN}/\"" |
      jq ".nodes[0].Authentication.boltzMacaroonPath = \"/home/rtl/.boltz-lnd/macaroons/\"" |
      jq ".nodes[0].Settings.userPersona = \"OPERATOR\"" |
      jq ".nodes[0].Settings.lnServerUrl = \"https://127.0.0.1:${portprefix}6100\"" |
      jq ".nodes[0].Settings.channelBackupPath = \"/mnt/hdd/app-data/rtl/${systemdService}-SCB-backup-$hostname\"" |
      jq ".nodes[0].Settings.swapServerUrl = \"https://127.0.0.1:${SWAPSERVERPORT}\"" >/mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json.tmp
    mv /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json.tmp /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json
  fi

  echo "# RTL prestart config done"
  exit 0
fi

##########################
# OFF
#########################

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # check that parameters are set
  if [ "${LNTYPE}" == "" ] || [ "${CHAIN}" == "" ]; then
    echo "# missing parameter"
    exit 1
  fi

  # stop services
  echo "# making sure services are not running"
  sudo systemctl stop ${systemdService} 2>/dev/null

  # remove config
  sudo rm -f /mnt/hdd/app-data/rtl/${systemdService}/RTL-Config.json

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${configEntry} "off"

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/${netprefix}${typeprefix}rtl_ssl.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-enabled/${netprefix}${typeprefix}rtl_tor.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-enabled/${netprefix}${typeprefix}rtl_tor_ssl.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf 2>/dev/null
  sudo rm -f /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf 2>/dev/null
  sudo nginx -t
  sudo systemctl reload nginx

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/tor.onion-service.sh off ${systemdService}
  fi

  isInstalled=$(sudo ls /etc/systemd/system/${systemdService}.service 2>/dev/null | grep -c "${systemdService}.service")
  if [ ${isInstalled} -eq 1 ]; then
    echo "# Removing RTL for ${LNTYPE} ${CHAIN}"
    sudo systemctl disable ${systemdService}.service
    sudo rm /etc/systemd/system/${systemdService}.service
    echo "# OK ${systemdService} removed."
  else
    echo "# ${systemdService} is not installed."
  fi

  # only if 'purge' is an additional parameter (other instances/services might need this)
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ]; then
    /home/admin/config.scripts/bonus.rtl.sh uninstall
    if [ $LNTYPE = cl ]; then
      /home/admin/config.scripts/cl.rest.sh off ${CHAIN} purge
    fi
    echo "# Delete all configs"
    sudo rm -rf /mnt/hdd/app-data/rtl
  fi

  # close ports on firewall
  sudo ufw delete allow "${RTLHTTP}"
  sudo ufw delete allow $((RTLHTTP + 1))

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

if [ "$1" = "update" ]; then
  echo "# UPDATING RTL"
  cd /home/rtl/RTL || exit 1
  updateOption="$2"
  if [ ${#updateOption} -eq 0 ]; then
    # from https://github.com/apotdevin/thunderhub/blob/master/scripts/updateToLatest.sh
    # fetch latest master
    sudo -u rtl git fetch
    # unset $1
    set --
    UPSTREAM=${1:-'@{u}'}
    LOCAL=$(sudo -u rtl git rev-parse @)
    REMOTE=$(sudo -u rtl git rev-parse "$UPSTREAM")
    if [ $LOCAL = $REMOTE ]; then
      TAG=$(sudo -u rtl git tag | sort -V | grep -v rc | tail -1)
      echo "# You are up-to-date on version" $TAG
    else
      echo "# Pulling latest changes..."
      sudo -u rtl git pull -p
      echo "# Reset to the latest release tag"
      TAG=$(sudo -u rtl git tag | sort -V | grep -v rc | tail -1)
      sudo -u rtl git reset --hard $TAG
      echo "# updating to the latest"
      # https://github.com/Ride-The-Lightning/RTL#or-update-existing-dependencies
      echo "# Running npm install ..."
      export NG_CLI_ANALYTICS=false
      sudo -u rtl npm install --omit=dev --legacy-peer-deps
      if ! [ $? -eq 0 ]; then
        echo "# FAIL - npm install did not run correctly - deleting code and exit"
        sudo rm -r /home/rtl/RTL
        exit 1
      else
        echo "# OK - RTL install looks good"
        echo
      fi
      echo "# Updated to version" $TAG
    fi
  elif [ "$updateOption" = "commit" ]; then
    echo "# updating to the latest commit in https://github.com/Ride-The-Lightning/RTL"
    sudo -u rtl git pull -p
    echo "# Running npm install ..."
    export NG_CLI_ANALYTICS=false
    sudo -u rtl npm install --omit=dev --legacy-peer-deps
    if ! [ $? -eq 0 ]; then
      echo "# FAIL - npm install did not run correctly - deleting code and exit"
      sudo rm -r /home/rtl/RTL
      exit 1
    else
      echo "# OK - RTL install looks good"
      echo
    fi
    currentRTLcommit=$(
      cd /home/rtl/RTL || exit 1
      git describe --tags
    )
    echo "# Updated RTL to $currentRTLcommit"
  else
    echo "# Unknown option: $updateOption"
  fi

  echo
  echo "# Starting the ${systemdService} service ... "
  sudo systemctl restart ${systemdService}
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run normal again"
exit 1
