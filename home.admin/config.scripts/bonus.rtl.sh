#!/bin/bash
RTLVERSION="v0.10.1"

# check and load raspiblitz config
# to know which network is running
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# config script to switch the RideTheLightning WebGUI on, off or update"
  echo
  echo "# bonus.rtl.sh [on|off|menu] <lnd|cln> <testnet|signet>"
  echo "# sets up lnd on ${chain}net by default"
  echo "# able to run intances for lnd and cln parallel"
  echo "# lnd mainnet and testnet can run parallel"
  echo "# cln can only have one network active at a time"
  echo
  echo "# bonus.rtl.sh [update<commit>|config]"
  echo "# installs the version $RTLVERSION by default"
  exit 1
fi

echo "# Running: 'bonus.rtl.sh $*'"

if [ ${#network} -eq 0 ]; then
 echo "FAIL - missing /mnt/hdd/raspiblitz.conf"
 exit 1
fi

# LNTYPE is lnd | cln
if [ $# -gt 1 ]; then
  LNTYPE=$2
else
  LNTYPE=lnd
fi
if [ ${LNTYPE} != lnd ]&&[ ${LNTYPE} != cln ];then
  echo "# ${LNTYPE} is not a supported LNTYPE"
  exit 1
fi

# CHAIN is signet | testnet | mainnet
if [ $# -gt 2 ]; then
  CHAIN=$3
else
  CHAIN=${chain}net
fi
if [ ${CHAIN} != testnet ]&&[ ${CHAIN} != mainnet ]&&[ ${CHAIN} != signet ];then
  echo "# ${CHAIN} is not a supported CHAIN"
  exit 1
fi

# prefix for parallel networks
if [ "${CHAIN}" == "testnet" ]; then
  netprefix="t"
  portprefix=1
elif [ "${CHAIN}" == "signet" ]; then
  netprefix="s"
  portprefix=3
elif [ "${CHAIN}" == "mainnet" ]; then
  netprefix=""
  portprefix=""
fi

# prefix for parallel lightning impl
if [ "${LNTYPE}" == "cln" ]; then
  RTLHTTP=${portprefix}7000
  typeprefix="c"
elif [ "${LNTYPE}" == "lnd" ]; then
  RTLHTTP=${portprefix}3000
  typeprefix=""
fi

# show info menu
if [ "$1" = "menu" ]; then

  # get network info
  localip=$(hostname -I | awk '{print $1}')
  toraddress=$(sudo cat /mnt/hdd/tor/RTL/hostname 2>/dev/null)
  fingerprint=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout | cut -d"=" -f2)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    # Info with TOR
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title "Ride The Lightning (RTL - $LNTYPE - $CHAIN)" --msgbox "Open in your local web browser:
http://${localip}:${RTLHTTP}\n
https://${localip}:$((RTLHTTP+1)) with Fingerprint:
${fingerprint}\n
Use your Password B to login.\n
Hidden Service address for TOR Browser (QRcode on LCD):\n${toraddress}
" 16 67
    /home/admin/config.scripts/blitz.display.sh hide
  else
    # Info without TOR
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

# add default value to raspi config if needed
configEntryExists=$(sudo cat /mnt/hdd/raspiblitz.conf | grep -c "${netprefix}${typeprefix}rtlWebinterface=")
if [ "${configEntryExists}" == "0" ]; then
  echo "# adding default config entry for '${netprefix}${typeprefix}rtlWebinterface'"
  echo "${netprefix}${typeprefix}rtlWebinterface=off" >> /mnt/hdd/raspiblitz.conf
else
  echo "# default config entry for '${netprefix}${typeprefix}rtlWebinterface' exists"
fi

# stop services
echo "# making sure services are not running"
sudo systemctl stop ${netprefix}${typeprefix}RTL 2>/dev/null

function configRTL() {

  if [ $LNTYPE = lnd ];then
    echo "# Make sure rtl is member of lndadmin"
    sudo /usr/sbin/usermod --append --groups lndadmin rtl
    SWAPSERVERPORT=8443
    if [ "$(grep -Ec "(loop=|lit=)" < /mnt/hdd/raspiblitz.conf)" -gt 0 ];then 
      if [ $lit = on ];then
        echo "# Add the rtl user to the lit group"
        sudo /usr/sbin/usermod --append --groups lit rtl
        echo "# Symlink the lit-loop.macaroon"
        sudo rm -rf "/home/rtl/.loop"                    #  delete symlink
        sudo ln -s "/home/lit/.loop/" "/home/rtl/.loop"  # create symlink
        SWAPSERVERPORT=8443
      elif [ $loop = on ];then
        echo "# Add the rtl user to the loop group"
        sudo /usr/sbin/usermod --append --groups loop rtl
        echo "# Symlink the loop.macaroon"
        sudo rm -rf "/home/rtl/.loop"                     # delete symlink
        sudo ln -s "/home/loop/.loop/" "/home/rtl/.loop"  # create symlink
        SWAPSERVERPORT=8081
      fi
      echo "# Make the loop macaroon group readable"
      sudo chmod 640 /home/rtl/.loop/mainnet/macaroons.db
    else
      echo "# No Loop or LiT is installed"
    fi
  fi

  # prepare RTL-Config.json file
  echo "# ${netprefix}RTL/RTL.conf"
  # change of config: https://github.com/Ride-The-Lightning/RTL/tree/v0.6.4
  sudo cp /home/rtl/RTL/sample-RTL-Config.json /home/admin/RTL-Config.json
  sudo chown admin:admin /home/admin/RTL-Config.json
  sudo chmod 600 /home/admin/RTL-Config.json || exit 1
  PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
  # modify sample-RTL-Config.json and save in RTL-Config.json
  node > /home/admin/RTL-Config.json <<EOF
//Read data
var data = require('/home/rtl/RTL/sample-RTL-Config.json');
//Manipulate data
data.port = '$RTLHTTP'
data.nodes[0].lnNode = '$hostname'
data.nodes[0].Authentication.macaroonPath = '/home/rtl/.lnd/data/chain/${network}/${chain}net/'
data.nodes[0].Authentication.configPath = '/home/rtl/.lnd/${netprefix}lnd.conf';
data.nodes[0].Authentication.swapMacaroonPath = '/home/rtl/.loop/${chain}net/'
data.nodes[0].Authentication.boltzMacaroonPath = '/home/rtl/.boltz-lnd/macaroons/'
data.multiPass = '$PASSWORD_B';
data.nodes[0].Settings.userPersona = 'OPERATOR'
data.nodes[0].Settings.channelBackupPath = '/home/rtl/${netprefix}RTL-SCB-backup-$hostname'
data.nodes[0].Settings.swapServerUrl = 'https://localhost:$SWAPSERVERPORT'
//Output data
console.log(JSON.stringify(data, null, 2));
EOF
  sudo -u rtl mkdir -p /home/rtl/${netprefix}RTL
  sudo rm -f /home/rtl/${netprefix}RTL/RTL-Config.json
  sudo mv /home/admin/RTL-Config.json /home/rtl/${netprefix}RTL/
  sudo chown rtl:rtl /home/rtl/${netprefix}RTL/RTL-Config.json
}

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# Installing the RTL for ${LNTYPE} ${CHAIN}"

  isInstalled=$(sudo ls /etc/systemd/system/${netprefix}${typeprefix}RTL.service 2>/dev/null | grep -c "${netprefix}${typeprefix}RTL.service")
  if ! [ ${isInstalled} -eq 0 ]; then
    echo "# OK, the ${netprefix}${typeprefix}RTL.service is already installed."
  else
    # check and install NodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on

    # create rtl user
    if [ $(compgen -u | grep -c rtl) -eq 0 ];then
      sudo adduser --disabled-password --gecos "" rtl || exit 1
    fi

    if [ -f /home/rtl/RTL/rtl.js ];then
      echo "# OK - the RTL code is already present"
    else
      
      echo "# Make sure symlink to central app-data directory exists"
      if ! [[ -L "/home/rtl/.lnd" ]]; then
        sudo rm -rf "/home/rtl/.lnd"                          # not a symlink.. delete it silently
        sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/rtl/.lnd"  # and create symlink
      fi
  
      # download source code and set to tag release
      echo "# Get the RTL Source Code"
      rm -rf /home/admin/RTL 2>/dev/null
      sudo -u rtl rm -rf /home/rtl/RTL 2>/dev/null
      sudo -u rtl git clone https://github.com/ShahanaFarooqui/RTL.git /home/rtl/RTL
      cd /home/rtl/RTL
      # check https://github.com/Ride-The-Lightning/RTL/releases/
      sudo -u rtl git reset --hard $RTLVERSION
      # from https://github.com/Ride-The-Lightning/RTL/commits/master
      # git checkout 917feebfa4fb583360c140e817c266649307ef72
      if [ -d "/home/rtl/RTL" ]; then
        echo "# OK - RTL code copy looks good"
      else
        echo "# FAIL - code copy did not run correctly"
        echo "# ABORT - RTL install"
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
    fi

    echo "# Updating Firewall"
    sudo ufw allow ${RTLHTTP} comment "${netprefix}${typeprefix}RTL HTTP"
    sudo ufw allow $((RTLHTTP+1)) comment "${netprefix}${typeprefix}RTL HTTPS"
    echo

  if [ $LNTYPE = lnd ];then
    echo "# Install service"
    echo "# Install RTL systemd for ${network} on ${chain}"
    echo "
# Systemd unit for ${netprefix}${typeprefix}RTL
# /etc/systemd/system/${netprefix}${typeprefix}RTL.service

[Unit]
Description=${netprefix}${typeprefix}RTL daemon
Wants=lnd.service
After=lnd.service

[Service]
Environment=\"RTL_CONFIG_PATH=/home/rtl/${netprefix}RTL/\"
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
" | sudo tee /home/admin/${netprefix}${typeprefix}RTL.service

      sudo mv /home/admin/${netprefix}${typeprefix}RTL.service /etc/systemd/system/${netprefix}${typeprefix}RTL.service
      sudo sed -i "s|chain/bitcoin/mainnet|chain/${network}/${CHAIN}|" /etc/systemd/system/${netprefix}${typeprefix}RTL.service
      sudo chown root:root /etc/systemd/system/${netprefix}${typeprefix}RTL.service

  elif [ $LNTYPE = cln ];then

    # clnrest
    /home/admin/config.scripts/cln.rest.sh on ${CHAIN}

    echo "
# Systemd unit for ${netprefix}${typeprefix}RTL
# /etc/systemd/system/${netprefix}${typeprefix}RTL.service

[Unit]
Description=${netprefix}${typeprefix}RTL daemon
Wants=${netprefix}lightningd.service
After=${netprefix}lightningd.service

[Service]
Environment=\"RTL_CONFIG_PATH=/home/rtl/${netprefix}RTL/\"
Environment=\"PORT=$RTLHTTP\"
Environment=\"LN_IMPLEMENTATION=CLT\"
Environment=\"LN_SERVER_URL=https://localhost:${portprefix}6100\"
Environment=\"CONFIG_PATH=/home/bitcoin/.lightning/${netprefix}config\"
Environment=\"MACAROON_PATH=/home/bitcoin/c-lightning-REST/certs\"
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
" | sudo tee /etc/systemd/system/${netprefix}${typeprefix}RTL.service

    fi
  fi

  echo "# Setup nginx symlinks"
  if ! [ -f /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf ]; then
     sudo cp /home/admin/assets/nginx/sites-available/rtl_ssl.conf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf
  fi
  if ! [ -f /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf ]; then
     sudo cp /home/admin/assets/nginx/sites-available/rtl_tor.conf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf
  fi
  if ! [ -f /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf ]; then
     sudo cp /home/admin/assets/nginx/sites-available/rtl_tor_ssl.conf /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf
  fi

  echo "# Set ports for Nginx"
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

  configRTL

  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}${typeprefix}rtlWebinterface=.*/${netprefix}${typeprefix}rtlWebinterface=on/g" /mnt/hdd/raspiblitz.conf

  # Hidden Service for RTL if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with internet.tor.sh script
    /home/admin/config.scripts/internet.hiddenservice.sh ${netprefix}${typeprefix}RTL 80 $((RTLHTTP+2)) 443 $((RTLHTTP+3))
  fi

  sudo systemctl enable ${netprefix}${typeprefix}RTL
  echo "# OK - the ${netprefix}${typeprefix}RTL.service is now enabled"

  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    echo "# OK - system is ready so starting service"
    sudo systemctl start ${netprefix}${typeprefix}RTL
    echo "# Monitor with:"
    echo "sudo journalctl -f -u ${netprefix}${typeprefix}RTL"
  else
    echo "# OK - To start manually use: 'sudo systemctl start RTL'"
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}${typeprefix}rtlWebinterface=.*/${netprefix}${typeprefix}rtlWebinterface=off/g" /mnt/hdd/raspiblitz.conf

  # remove nginx symlinks
  sudo rm -f /etc/nginx/sites-enabled/${netprefix}${typeprefix}rtl_ssl.conf
  sudo rm -f /etc/nginx/sites-enabled/${netprefix}${typeprefix}rtl_tor.conf
  sudo rm -f /etc/nginx/sites-enabled/${netprefix}${typeprefix}rtl_tor_ssl.conf
  sudo rm -f /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_ssl.conf
  sudo rm -f /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor.conf
  sudo rm -f /etc/nginx/sites-available/${netprefix}${typeprefix}rtl_tor_ssl.conf
  sudo nginx -t
  sudo systemctl reload nginx

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    /home/admin/config.scripts/internet.hiddenservice.sh off ${netprefix}${typeprefix}RTL
  fi

  isInstalled=$(sudo ls /etc/systemd/system/${netprefix}${typeprefix}RTL.service 2>/dev/null | grep -c "${netprefix}${typeprefix}RTL.service")
  if [ ${isInstalled} -eq 1 ]; then
  echo "# Removing RTL for ${LNTYPE} ${CHAIN}"
    sudo systemctl disable ${netprefix}${typeprefix}RTL
    sudo rm /etc/systemd/system/${netprefix}${typeprefix}RTL.service
    if [ $LNTYPE = cln ];then
      /home/admin/config.scripts/cln.rest.sh off ${CHAIN}
    fi
    if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
      echo "# Removing the binaries"
      echo "# Delete user and home directory"
      sudo userdel -rf rtl
    fi

    echo "# OK ${netprefix}${typeprefix}RTL removed."
  else
    echo "# ${netprefix}${typeprefix}RTL is not installed."
  fi

  # close ports on firewall
  sudo ufw deny ${RTLHTTP}
  sudo ufw deny $((RTLHTTP+1))
  exit 0
fi

# config
if [ "$1" = "config" ]; then
  echo "# CONFIG RTL"
  configRTL
  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "# UPDATING RTL"
  cd /home/rtl/RTL
  updateOption="$2"
  if [ ${#updateOption} -eq 0 ]; then
    # from https://github.com/apotdevin/thunderhub/blob/master/scripts/updateToLatest.sh
    # fetch latest master
    sudo -u rtl git fetch
    # unset $1
    set --
    UPSTREAM=${1:-'@{u}'}
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse "$UPSTREAM")
    if [ $LOCAL = $REMOTE ]; then
      TAG=$(git tag | sort -V | tail -1)
      echo "# You are up-to-date on version" $TAG
    else
      echo "# Pulling latest changes..."
      sudo -u rtl git pull -p
      echo "# Reset to the latest release tag"
      TAG=$(git tag | sort -V | tail -1)
      sudo -u rtl git reset --hard $TAG
      echo "# updating to the latest"
      # https://github.com/Ride-The-Lightning/RTL#or-update-existing-dependencies
      sudo -u rtl npm install --only=prod
      echo "# Updated to version" $TAG
    fi
  elif [ "$updateOption" = "commit" ]; then
    echo "# updating to the latest commit in https://github.com/Ride-The-Lightning/RTL"
    sudo -u rtl git pull -p
    sudo -u rtl npm install --only=prod
    currentRTLcommit=$(cd /home/rtl/RTL; git describe --tags)
    echo "# Updated RTL to $currentRTLcommit"
  else 
    echo "# Unknown option: $updateOption"
  fi

  configRTL
  
  echo
  echo "# Starting the RTL service ... "
  sudo systemctl start RTL
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run normal again"
exit 1
