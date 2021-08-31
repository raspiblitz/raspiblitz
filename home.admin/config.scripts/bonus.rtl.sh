#!/bin/bash
RTLVERSION="v0.11.1"

# check and load raspiblitz config
# to know which network is running
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# config script for RideTheLightning $RTLVERSION WebInterface"
  echo "# able to run intances for lnd and cln parallel"
  echo "# lnd mainnet and testnet can run parallel"
  echo "# cln can only have one network active at a time"
  echo "# bonus.rtl.sh [on|off|menu] <lnd|cln> <mainnet|testnet|signet>"
  echo "# bonus.rtl.sh connect-services"
  echo "# bonus.rtl.sh prestart <mainnet|testnet|signet>"
  exit 1
fi

echo "# Running: 'bonus.rtl.sh $*'"

# LNTYPE is lnd | cln
LNTYPE=$2
if [ "${LNTYPE}" != "" ] && [ "${LNTYPE}" != "lnd" ] && [ "${LNTYPE}" != "cln" ]; then
  echo "# ${LNTYPE} is not a supported LNTYPE"
  echo "err='not supported parameter'"
  exit 1
fi
echo "# LNTYPE(${LNTYPE})"

# CHAIN is signet | testnet | mainnet
CHAIN=$3
if [ "${CHAIN}" != "" ] && [ "${CHAIN}" != "testnet" ] && [ "${CHAIN}" != "mainnet" ] && [ "${CHAIN}" != "signet" ]; then
  echo "# ${CHAIN} is not a supported CHAIN"
  echo "err='not supported parameter'"
  exit 1
fi
echo "# CHAIN(${CHAIN})"

# prefix for parallel networks
if [ "${CHAIN}" == "mainnet" ]; then
  netprefix=""
  portprefix=""
elif [ "${CHAIN}" == "testnet" ]; then
  netprefix="t"
  portprefix=1
elif [ "${CHAIN}" == "signet" ]; then
  netprefix="s"
  portprefix=3
fi
echo "# netprefix(${netprefix})"
echo "# portprefix(${portprefix})"

# prefix for parallel lightning impl
if [ "${LNTYPE}" == "cln" ]; then
  RTLHTTP=${portprefix}7000
  typeprefix="c"
elif [ "${LNTYPE}" == "lnd" ]; then
  RTLHTTP=${portprefix}3000
  typeprefix=""
fi
echo "# RTLHTTP(${RTLHTTP})"
echo "# typeprefix(${typeprefix})"

# construct needed varibale elements
configEntry="${netprefix}${typeprefix}rtlWebinterface"
systemdService="${netprefix}${typeprefix}RTL"
echo "# configEntry(${configEntry})"
echo "# systemdService(${systemdService})"

##########################
# MENU
#########################

# show info menu
if [ "$1" = "menu" ]; then

  # check that parameters are set
  if [ "${LNTYPE}" == "" ] || [ "${CHAIN}" == "" ]; then
    echo "# missing parameter"
    exit 1
  fi

  # get network info
  localip=$(hostname -I | awk '{print $1}')
  toraddress=$(sudo cat /mnt/hdd/tor/${netprefix}${typeprefix}RTL/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

  # Info with TOR
  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title "Ride The Lightning (RTL - $LNTYPE - $CHAIN)" --msgbox "Open in your local web browser:
http://${localip}:${RTLHTTP}\n
https://${localip}:$((RTLHTTP+1)) with Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Hidden Service address for TOR Browser (QRcode on LCD):\n${toraddress}
" 16 67
    /home/admin/config.scripts/blitz.display.sh hide

  # Info without TOR  
  else
    whiptail --title "Ride The Lightning (RTL - $LNTYPE - $CHAIN)" --msgbox "Open in your local web browser & accept self-signed cert:
http://${localip}:${RTLHTTP}\n
https://${localip}:$((RTLHTTP+1)) with Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Activate TOR to access the web interface from outside your local network.
" 15 67
  fi
  echo "please wait ..."
  exit 0
fi

# prepare raspiblitz.conf --> add default value
configEntryExists=$(sudo cat /mnt/hdd/raspiblitz.conf | grep -c "${configEntry}")
if [ "${configEntryExists}" == "0" ]; then
  echo "# adding default config entry for '${configEntry}'"
  sudo /bin/sh -c "echo '${configEntry}=off' >> /mnt/hdd/raspiblitz.conf"
else
  echo "# default config entry for '${configEntry}' exists"
fi

# stop services
echo "# making sure services are not running"
sudo systemctl stop ${systemdService} 2>/dev/null


##########################
# ON
#########################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # check that parameters are set
  if [ "${LNTYPE}" == "" ] || [ "${CHAIN}" == "" ]; then
    echo "# missing parameter"
    exit 1
  fi

  # check that is installed
  isInstalled=$(sudo ls /etc/systemd/system/${systemdService}.service 2>/dev/null | grep -c "${systemdService}.service")
  if [ ${isInstalled} -eq 1 ]; then
    echo "# OK, the ${netprefix}${typeprefix}RTL.service is already installed."
    exit 1
  fi

  echo "# Installing RTL for ${LNTYPE} ${CHAIN}"

  # check and install NodeJS
  /home/admin/config.scripts/bonus.nodejs.sh on

  # create rtl user (one for all instances)
  if [ $(compgen -u | grep -c rtl) -eq 0 ];then
    sudo adduser --disabled-password --gecos "" rtl || exit 1
  fi
  echo "# Make sure symlink to central app-data directory exists"
  if ! [[ -L "/home/rtl/.lnd" ]]; then
    sudo rm -rf "/home/rtl/.lnd" 2>/dev/null              # not a symlink.. delete it silently
    sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/rtl/.lnd"  # and create symlink
  fi
  if [ "${LNTYPE}" == "lnd" ]; then
    # for LND make sure user rtl is allowed to access admin macaroons
    echo "# adding user rtl to group lndadmin"
    sudo /usr/sbin/usermod --append --groups lndadmin rtl
  fi

  # source code (one place for all instances)
  if [ -f /home/rtl/RTL/rtl ];then
    echo "# OK - the RTL code is already present - just update"
    cd /home/rtl/RTL
    sudo -u rtl git pull
  else
    # download source code and set to tag release
    echo "# Get the RTL Source Code"
    sudo -u rtl rm -rf /home/rtl/RTL 2>/dev/null
    sudo -u rtl git clone https://github.com/ShahanaFarooqui/RTL.git /home/rtl/RTL
    cd /home/rtl/RTL
  fi
    
  # check https://github.com/Ride-The-Lightning/RTL/releases/
  sudo -u rtl git reset --hard $RTLVERSION
  # from https://github.com/Ride-The-Lightning/RTL/commits/master
  # git checkout 917feebfa4fb583360c140e817c266649307ef72
  if [ -d "/home/rtl/RTL" ]; then
    echo "# OK - RTL code copy looks good"
  else
    echo "# FAIL - RTL code not available"
    echo "err='code download falied'"
    exit 1
  fi
  echo
  
  # install
  echo "# Run: npm install"
  export NG_CLI_ANALYTICS=false
  sudo -u rtl npm install --only=prod
  if ! [ $? -eq 0 ]; then
    echo "# FAIL - npm install did not run correctly, aborting"
    exit 1
  else
    echo "# OK - RTL install looks good"
    echo
  fi
  
  echo "# Updating Firewall"
  sudo ufw allow ${RTLHTTP} comment "${systemdService} HTTP"
  sudo ufw allow $((RTLHTTP+1)) comment "${systemdService} HTTPS"
  echo

  echo "# Create Systemd Service: ${systemdService}.service (Template)"
  echo "
# Systemd unit for ${systemdService}

[Unit]
Description=${systemdService} Webinterface
Wants=
After=

[Service]
Environment=\"RTL_CONFIG_PATH=/home/rtl/${systemdService}/\"
ExecStartPre=-/home/admin/config.scripts/bonus.rtl.sh prestart ${LNTYPE} ${CHAIN}
ExecStart=/usr/bin/node /home/rtl/RTL/rtl
User=rtl
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
" | sudo tee /etc/systemd/system/${systemdService}.service
  sudo chown root:root /etc/systemd/system/${systemdService}.service

  # adapt systemd service template for LND
  if [ "${LNTYPE}" == "lnd" ]; then
    echo "# modifying ${systemdService}.service for LND"
    sudo sed -i "s/^Wants=.*/Wants=${netprefix}lnd.service/g" /etc/systemd/system/${systemdService}.service
    sudo sed -i "s/^After=.*/After=${netprefix}lnd.service/g" /etc/systemd/system/${systemdService}.service
  fi

  # adapt systemd service template for LND
  if [ "${LNTYPE}" == "cln" ]; then
    echo "# modifying ${systemdService}.service for CLN"
    sudo sed -i "s/^Wants=.*/Wants=${netprefix}lightningd.service/g" /etc/systemd/system/${systemdService}.service
    sudo sed -i "s/^After=.*/After=${netprefix}lightningd.service/g" /etc/systemd/system/${systemdService}.service
  fi

  # Note about RTL config file
  echo "# NOTE: the RTL config for this instance will be done on the fly as a prestart in systemd"

  # Hidden Service for RTL if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with internet.tor.sh script
    /home/admin/config.scripts/internet.hiddenservice.sh ${netprefix}${typeprefix}RTL 80 $((RTLHTTP+2)) 443 $((RTLHTTP+3))
  fi

  # nginx configuration
  echo "# Setup nginx confs"
  sudo cp /home/admin/assets/nginx/sites-available/rtl_ssl.conf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf
  sudo cp /home/admin/assets/nginx/sites-available/rtl_tor.conf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf
  sudo cp /home/admin/assets/nginx/sites-available/rtl_tor_ssl.conf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf
  sudo sed -i "s/3000/$RTLHTTP/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf
  sudo sed -i "s/3001/$((RTLHTTP+1))/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf
  sudo sed -i "s/3000/$RTLHTTP/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf
  sudo sed -i "s/3002/$((RTLHTTP+2))/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf
  sudo sed -i "s/3000/$RTLHTTP/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf
  sudo sed -i "s/3003/$((RTLHTTP+3))/g" /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf
  sudo ln -sf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf /etc/nginx/sites-enabled/
  sudo ln -sf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf /etc/nginx/sites-enabled/
  sudo nginx -t
  sudo systemctl reload nginx

  # run config as root to connect prepare services (lit, pool, ...)
  sudo /home/admin/config.scripts/bonus.rtl.sh connect-services

  # raspiblitz.config
  sudo sed -i "s/^${configEntry}=.*/${configEntry}=on/g" /mnt/hdd/raspiblitz.conf

  sudo systemctl enable ${systemdService}
  sudo systemctl start ${systemdService}
  echo "# OK - the ${systemdService}.service is now enabled & started"
  echo "# Monitor with: sudo journalctl -f -u ${systemdService}"
  exit 0
fi

##########################
# CONNECT SERVICES
# will be called by lit or loop services to make sure services 
# are connected or on RTL install/update
#########################

if [ "$1" = "connect-services" ]; then

  if [ "$USER" != "root" ] && [ "$USER" != "admin" ]; then
    echo "# FAIL: run as user root or admin"
    exit 1
  fi

  echo "## RTL CONNECT-SERVICES (when run as admin or root)" 

  # LIT & LOOP Swap Server
  echo "# checking of swap server ..."
  if [ "${lit}" = "on" ]; then
    echo "# LIT DETECTED"
    echo "# Add the rtl user to the lit group"
    sudo /usr/sbin/usermod --append --groups lit rtl
    echo "# Symlink the lit-loop.macaroon"
    sudo rm -rf "/home/rtl/.loop"                    #  delete symlink
    sudo ln -s "/home/lit/.loop/" "/home/rtl/.loop"  # create symlink
    echo "# Make the loop macaroon group readable"
    sudo chmod 640 /home/rtl/.loop/mainnet/macaroons.db
  elif [ "${loop}" = "on" ]; then
    echo "# LOOP DETECTED"
    echo "# Add the rtl user to the loop group"
    sudo /usr/sbin/usermod --append --groups loop rtl
    echo "# Symlink the loop.macaroon"
    sudo rm -rf "/home/rtl/.loop"                     # delete symlink
    sudo ln -s "/home/loop/.loop/" "/home/rtl/.loop"  # create symlink
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

  # determine C-Lightning config path based on chain
  if [ "${LNTYPE}" = "cln" ]; then
    if [ "${CHAIN}" = "mainnet" ]; then
      CLNCONF="/home/bitcoin/.lightning/config"
    else
      CLNCONF="/home/bitcoin/.lightning/${CHAIN}/config"
    fi
    echo "# CLNCONF(${CLNCONF})"
  fi

  # prepare RTL-Config.json file
  echo "# PREPARE /home/rtl/${systemdService}/RTL-Config.json"
  # make and clean directory
  mkdir -p /home/rtl/${systemdService}
  rm -f /home/rtl/${systemdService}/RTL-Config.json 2>/dev/null 
  # copy template
  cp /home/rtl/RTL/docs/Sample-RTL-Config.json /home/rtl/${systemdService}/RTL-Config.json
  chmod 600 /home/rtl/${systemdService}/RTL-Config.json

  # LND changes of config
  if [ "${LNType}" == "lnd" ]; then
    echo "# LND Config"
    cat /home/rtl/${systemdService}/RTL-Config.json | \
    jq ".port = \"${RTLHTTP}\"" | \
    jq ".multiPass = \"${RPCPASSWORD}\"" | \
    jq ".nodes[0].lnNode = \"${hostname}\"" | \
    jq ".nodes[0].lnImplementation = \"LND\"" | \
    jq ".nodes[0].Authentication.macaroonPath = \"/home/rtl/.lnd/data/chain/${network}/${CHAIN}/\"" | \
    jq ".nodes[0].Authentication.configPath = \"/home/rtl/.lnd/${netprefix}lnd.conf\"" | \
    jq ".nodes[0].Authentication.swapMacaroonPath = \"/home/rtl/.loop/${CHAIN}/\"" | \
    jq ".nodes[0].Authentication.boltzMacaroonPath = \"/home/rtl/.boltz-lnd/macaroons/\"" | \
    jq ".nodes[0].Settings.userPersona = \"OPERATOR\"" | \
    jq ".nodes[0].nodes[0].Settings.channelBackupPath = \"/home/rtl/${systemdService}-SCB-backup-$hostname\"" | \
    jq ".nodes[0].nodes[0].Settings.swapServerUrl = \"https://localhost:${SWAPSERVERPORT}\"" > /home/rtl/${systemdService}/RTL-Config.json.tmp
    mv /home/rtl/${systemdService}/RTL-Config.json.tmp /home/rtl/${systemdService}/RTL-Config.json
  fi

  # C-Lightning changes of config
  # https://github.com/Ride-The-Lightning/RTL/blob/master/docs/C-Lightning-setup.md
  if [ "${LNType}" == "cln" ]; then
    echo "# CLN Config"
    cat /home/rtl/${systemdService}/RTL-Config.json | \
    jq ".port = \"${RTLHTTP}\"" | \
    jq ".multiPass = \"${RPCPASSWORD}\"" | \
    jq ".nodes[0].lnNode = \"${hostname}\"" | \
    jq ".nodes[0].lnImplementation = \"CLT\"" | \
    jq ".nodes[0].Authentication.macaroonPath = \"/home/bitcoin/c-lightning-REST/certs\"" | \
    jq ".nodes[0].Authentication.configPath = \"${CLNCONF}\"" | \
    jq ".nodes[0].Authentication.swapMacaroonPath = \"/home/rtl/.loop/${CHAIN}/\"" | \
    jq ".nodes[0].Authentication.boltzMacaroonPath = \"/home/rtl/.boltz-lnd/macaroons/\"" | \
    jq ".nodes[0].Settings.userPersona = \"OPERATOR\"" | \
    jq ".nodes[0].Settings.lnServerUrl = \"https://localhost:${portprefix}6100\"" | \
    jq ".nodes[0].nodes[0].Settings.channelBackupPath = \"/home/rtl/${systemdService}-SCB-backup-$hostname\"" | \
    jq ".nodes[0].nodes[0].Settings.swapServerUrl = \"https://localhost:${SWAPSERVERPORT}\"" > /home/rtl/${systemdService}/RTL-Config.json.tmp
    mv /home/rtl/${systemdService}/RTL-Config.json.tmp /home/rtl/${systemdService}/RTL-Config.json
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
  if [ "${LNTYPE}" == "" ] || [ "${CHAIN}" == "" ]; then
    echo "# missing parameter"
    exit 1
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^${configEntry}=.*/${configEntry}=off/g" /mnt/hdd/raspiblitz.conf

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
    /home/admin/config.scripts/internet.hiddenservice.sh off ${systemdService}
  fi

  isInstalled=$(sudo ls /etc/systemd/system/${systemdService}.service 2>/dev/null | grep -c "${systemdService}.service")
  if [ ${isInstalled} -eq 1 ]; then

    echo "# Removing RTL for ${LNTYPE} ${CHAIN}"
    sudo systemctl disable ${systemdService}.service
    sudo rm /etc/systemd/system/${systemdService}.service

    # only if 'purge' is an additional parameter (might otherwise other instances/services might need this)
    if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
      echo "# Removing the binaries"
      echo "# Delete user and home directory"
      sudo userdel -rf rtl
      if [ $LNTYPE = cln ];then
        /home/admin/config.scripts/cln.rest.sh off ${CHAIN}
      fi
    fi

    echo "# OK ${systemdService} removed."
  else
    echo "# ${systemdService} is not installed."
  fi

  # close ports on firewall
  sudo ufw deny ${RTLHTTP}
  sudo ufw deny $((RTLHTTP+1))
  exit 0
fi

# DEAKTIVATED FOR NOW:
# - parameter scheme is conflicting with setting all perfixes etc
# - also just updating to latest has high change of breaking
#if [ "$1" = "update" ]; then
#  echo "# UPDATING RTL"
#  cd /home/rtl/RTL
#  updateOption="$2"
#  if [ ${#updateOption} -eq 0 ]; then
#    # from https://github.com/apotdevin/thunderhub/blob/master/scripts/updateToLatest.sh
#    # fetch latest master
#    sudo -u rtl git fetch
#    # unset $1
#    set --
#    UPSTREAM=${1:-'@{u}'}
#    LOCAL=$(git rev-parse @)
#    REMOTE=$(git rev-parse "$UPSTREAM")
#    if [ $LOCAL = $REMOTE ]; then
#      TAG=$(git tag | sort -V | tail -1)
#      echo "# You are up-to-date on version" $TAG
#    else
#      echo "# Pulling latest changes..."
#      sudo -u rtl git pull -p
#      echo "# Reset to the latest release tag"
#      TAG=$(git tag | sort -V | tail -1)
#      sudo -u rtl git reset --hard $TAG
#      echo "# updating to the latest"
#      # https://github.com/Ride-The-Lightning/RTL#or-update-existing-dependencies
#      sudo -u rtl npm install --only=prod
#      echo "# Updated to version" $TAG
#    fi
#  elif [ "$updateOption" = "commit" ]; then
#    echo "# updating to the latest commit in https://github.com/Ride-The-Lightning/RTL"
#    sudo -u rtl git pull -p
#    sudo -u rtl npm install --only=prod
#    currentRTLcommit=$(cd /home/rtl/RTL; git describe --tags)
#    echo "# Updated RTL to $currentRTLcommit"
#  else 
#    echo "# Unknown option: $updateOption"
#  fi
#
#  echo
#  echo "# Starting the RTL service ... "
#  sudo systemctl start RTL
#  exit 0
#fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run normal again"
exit 1
