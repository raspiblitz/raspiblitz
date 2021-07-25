#!/bin/bash

## string   --> Defines the action and is necessary
## <string> --> Necesasry
## [string] --> Optional

# on SERVICE --> create an onion service
# TO_PORT is the port the Hidden Service forwards to (to be used in the Tor browser)
# FROM_PORT is the port to be forwarded with the Hidden Service

# auth --> client authorization for onion service. Will ask for a key when accessing it.
# vanguards --> use vanguards to protect from attacks to the service
# credentials --> see your service credentials

# TODO(nyxnor) <OPTIONAL> [REQUIRED]
# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Configure an Onion Service"
  echo
  echo "Usage: tor.onion-service.sh COMMAND <OPTION>"
  echo
  echo "Option:"
  echo
  echo "  on <SERVICE> <TO_PORT> <FROM_PORT> [TO_PORT_2] [FROM_PORT_2]"
  echo "  off <SERVICE>"
  echo
  echo "  renew <SERVICE>"
  echo "  renew <all>"
  echo
  echo "  credentials <SERVICE>"
  echo
  echo "  instance <on|off> <INSTANCE> <CONTROL_PORT>"
  echo
  echo "  auth <on|off> <SERVICE>"
  echo "  auth <purge>"
  echo
  echo "  vanguards <install|remove>"
  echo "  vanguards <on|off> <INSTANCE> <CONTROL_PORT>"
  exit 1
fi

# if ! [[ "$scale" =~ ^[0-9]+$ ]]
#     then
#         echo "Sorry integers only"
# fi


# include lib
. /home/admin/config.scripts/tor.functions.lib

if [ "${runBehindTor}" != "on" ]; then
  echo "ERROR: Tor is not configured"
  echo "Activate Tor --> Menu > Settings > run behind Tor"
  exit 0
fi

set_owner_permission(){
  sudo chown -R ${OWNER_TOR_DATA_DIR}:${OWNER_TOR_DATA_DIR} ${DATA_DIR}
  sudo chown -R ${OWNER_TOR_CONF_DIR}:${OWNER_TOR_CONF_DIR} ${CONF_DIR}
  sudo chmod 700 ${DATA_DIR}
  sudo chmod 644 ${TORRC}
}

if [ "${1}" == "off" ]||[ "${1}" == "on" ]&&[ "${#2}" -gt 0 ]; then
  # add default value to raspi config if needed
  SERVICE=${2}
  if ! grep -Eq "^${SERVICE}=" ${CONF}; then
    echo "${SERVICE}=off" >> ${CONF}
  fi
fi


# DELETE SERVICE
if [ "${1}" == "off" ]; then
  SERVICE="${2}"
  if [ ${#SERVICE} -eq 0 ]; then
    echo "ERROR: service name is missing"
    exit 0
  fi
  # remove service paragraph
  sudo sed -i "/# Hidden Service for ${SERVICE}/,/^\s*$/{d}" ${TORRC}
  # remove service data dir
  sudo rm -rf ${SERVICES_DATA_DIR}/${SERVICE}
  # remove double empty lines
  sudo cp ${TORRC} ${TORRC}.tmp
  sudo awk 'NF > 0 {blank=0} NF == 0 {blank++} blank < 2' ${TORRC} > ${TORRC}.tmp
  sudo mv ${TORRC}.tmp ${TORRC}
  # set owner and permissions for config and data files
  set_owner_permission
  echo "# OK service is removed - restarting Tor ..."
  restarting_tor
  sleep 10
  echo "# Done"
  exit 1
fi


## CREATE SERVICE
if [ "${1}" == "on" ]; then
  SERVICE="${2}"
  if [ ${#SERVICE} -eq 0 ]; then
    echo "ERROR: service name is missing"
    exit 0
  fi
  TO_PORT="${3}"
  if [ ${#TO_PORT} -eq 0 ]; then
    echo "ERROR: the port to forward to is missing"
    exit 0
  fi
  FROM_PORT="${4}"
  if [ ${#FROM_PORT} -eq 0 ]; then
    echo "ERROR: the port to forward from is missing"
    exit 0
  fi
  TO_PORT_2="${5}" # not mandatory
  FROM_PORT_2="${6}" # needed if $5 is given
  if [ ${#TO_PORT_2} -gt 0 ]; then
    if [ ${#FROM_PORT_2} -eq 0 ]; then
      echo "ERROR: the second port to forward from is missing"
      exit 0
    fi
  fi
  # delete any old entry for that servive
  sudo sed -i "/# Hidden Service for ${SERVICE}/,/^\s*$/{d}" ${TORRC}
  # delete any old data for that service
  sudo rm -rf ${SERVICES_DATA_DIR}/${SERVICE}
  # make new entry for that service
  echo "
# Hidden Service for ${SERVICE}
HiddenServiceDir ${SERVICES_DATA_DIR}/${SERVICE}
HiddenServiceVersion 3
HiddenServicePort ${TO_PORT} 127.0.0.1:${FROM_PORT}" | sudo tee -a ${TORRC}
  # remove double empty lines
  awk 'NF > 0 {blank=0} NF == 0 {blank++} blank < 2' ${TORRC} | sudo tee ${TORRC}.tmp >/dev/null && sudo mv ${TORRC}.tmp ${TORRC}
  # check and insert second port pair
  if [ ${#TO_PORT_2} -gt 0 ]; then
    alreadyThere=$(sudo cat ${TORRC} 2>/dev/null | grep -c "\b127.0.0.1:${FROM_PORT_2}\b")
    if [ ${alreadyThere} -gt 0 ]; then
      echo "The port ${FROM_PORT_2} is already forwarded. Check the ${TORRC} for the details."
    else
      echo "HiddenServicePort ${TO_PORT_2} 127.0.0.1:${FROM_PORT_2}" | sudo tee -a ${TORRC}
    fi
  fi
  echo
  # restart tor / sighup tor
  echo "Restarting Tor to activate the Hidden Service..."
  # set owner and permissions for config and data files
  set_owner_permission
  restarting_tor
  sleep 10
  # show the Hidden Service address
  TOR_ADDRESS=$(sudo cat ${SERVICES_DATA_DIR}/${SERVICE}/hostname)
  if [ -z "${TOR_ADDRESS}" ]; then
    echo "Waiting for the Hidden Service"
    sleep 10
    TOR_ADDRESS=$(sudo cat ${SERVICES_DATA_DIR}/${SERVICE}/hostname)
    if [ -z "${TOR_ADDRESS}" ]; then
      echo " FAIL - The Hidden Service address could not be found - Tor error?"
      exit 1
    fi
  fi
  echo
  echo "The Tor Hidden Service address for ${SERVICE} is:"
  echo "${TOR_ADDRESS}"
  echo "use with the port: ${TO_PORT}"
  if [ ${#TO_PORT_2} -gt 0 ]; then
    wasAdded=$(sudo cat ${TORRC} 2>/dev/null | grep -c "\b127.0.0.1:${FROM_PORT_2}\b")
    if [ ${wasAdded} -gt 0 ]; then
      echo "or the port: ${TO_PORT_2}"
    fi
  fi
fi


# Client Authorization not available for Tor Browser mobile - android
# source: https://gitlab.torproject.org/tpo/applications/tor-browser/-/issues/31672
if [ "${1}" == "auth" ]; then
  STATUS="${2}"
  if [ ${#STATUS} -eq 0 ]; then
    echo "ERROR: status is missing (on/off)"
    exit 0
  fi
  SERVICE="${3}"
  if [ ${#SERVICE} -eq 0 ]; then
    echo "ERROR: service name is missing"
    exit 0
  fi
  serviceExists=$(sudo -u ${OWNER_DATA_DIR} cat ${SERVICES_DATA_DIR}/${SERVICE}/hostname | grep -c ".onion")
  if [ ${serviceExists} -eq 0 ]; then
    echo "ERROR: Service does not exist"
    exit 0
  fi
  if ! grep -Eq "^${SERVICE}OnionAuth=" ${CONF}; then
    echo "${SERVICE}OnionAuth=off" >> ${CONF}
  fi
  if [ "${STATUS}" == "on" ]; then
    # Install basez if not installed
    echo "# Generating keys to access onion service (Client Authorization) ..."
    isInstalled(){
      dpkg -l basez | grep -q ^ii && return 1
      echo; echo "Installing necessary packages ..."
      sudo apt install -y basez; echo; return 0
    }
    isInstalled
    # set owner and permissions for config and data files
    set_owner_permission
    # Generate pem and derive pub and priv keys
    openssl genpkey -algorithm x25519 -out /tmp/k1.prv.pem
    cat /tmp/k1.prv.pem | grep -v " PRIVATE KEY" | base64pem -d | tail --bytes=32 | base32 | sed 's/=//g' > /tmp/k1.prv.key
    openssl pkey -in /tmp/k1.prv.pem -pubout | grep -v " PUBLIC KEY" | base64pem -d | tail --bytes=32 | base32 | sed 's/=//g' > /tmp/k1.pub.key
    # add backup of the priv key to display when requested
    sudo cp /tmp/k1.prv.key ${SERVICES_DATA_DIR}/${SERVICE}/authorized_clients/client_auth_priv_key
    # save variables
    PUB_KEY=$(cat /tmp/k1.pub.key)
    PRIV_KEY=$(cat /tmp/k1.prv.key)
    TOR_ADDRESS=$(sudo -u ${OWNER_DATA_DIR} cat ${SERVICES_DATA_DIR}/${SERVICE}/hostname)
    TOR_ADDRESS_WITHOUT_ONION=$(sudo -u ${OWNER_DATA_DIR} cat ${SERVICES_DATA_DIR}/${SERVICE}/hostname | cut -c1-56)
    TORRC_CLIENT_KEY=(${TOR_ADDRESS_WITHOUT_ONION}":descriptor:x25519:"${PRIV_KEY})
    TORRC_SERVER_KEY=("descriptor:x25519:"${PUB_KEY})
    # Server side configuration
    echo ${TORRC_SERVER_KEY} | sudo tee ${SERVICES_DATA_DIR}/${SERVICE}/authorized_clients/me.auth >/dev/null
    # Client side configuration
    echo "Client Private key for ${SERVICE}"
    echo
    echo "RAW:"
    echo
    echo "Address = "${TOR_ADDRESS}
    echo "Key     = "${PRIV_KEY}
    echo "Conf = "${TORRC_CLIENT_KEY}
    echo
    echo
    echo "EXPLAINED:"
    echo
    echo " BROWSER -> Typing the key in the GUI"
    echo " * In the browser, enter the service address       = "${TOR_ADDRESS}
    echo " * A small window will be prompted, enter the key  = "${PRIV_KEY}
    echo
    echo " BROWSER and DAEMON 2 -> Adding the key to torrc to be read automatically"
    echo " * Add the line containing ClientOnionAuthDir to the torrc file accordingly to your setup (remove identation):"
    echo "   - Browser = [Tor_Browser_folder]/Browser/TorBrowser/Data/Tor/torrc"
    echo "      ClientOnionAuthDir TorBrowser/Data/Tor/onion_auth"
    echo "   - Daemon  = /etc/tor/torrc"
    echo "      ClientOnionAuthDir /var/lib/tor/onion_auth/"
    echo
    echo " * Add the private key (note: same content for Browser and Daemon but different paths):"
    echo "   - Browser =  [Tor_Browser_folder]/Browser/TorBrowser/Data/Tor/onion_auth/bob.auth_private"
    echo "   - Daemon  = /var/lib/tor/onion_auth/bob.auth_private"
    echo "     "${TORRC_CLIENT_KEY}
    echo
    echo " * Restart the instance"
    echo "   - Browser = Close and open again the Tor Browser Bundle"
    echo "   - Daemon  = Reload the daemon = $ sudo pkill -sighup tor"
    echo
    echo " * Go to the service address = "${TOR_ADDRESS}
    echo
    # Finish
    sudo sed -i "s/^${SERVICE}OnionAuth=.*/${SERVICE}OnionAuth=on/g" ${CONF}
    rm -f /tmp/k1.pub.key /tmp/k1.prv.key /tmp/k1.prv.pem
    # set owner and permissions for config and data files
    set_owner_permission
    restarting_tor
    exit 1
  elif [ "${STATUS}" == "off" ]; then
    echo "Removing auth for ${SERVICE}"
    sudo rm -f ${SERVICES_DATA_DIR}/${SERVICE}/authorized_clients/*.auth
    sudo rm -f ${SERVICES_DATA_DIR}/${SERVICE}/authorized_clients/client_auth_priv_key
    sudo sed -i "s/^${SERVICE}OnionAuth=.*/${SERVICE}OnionAuth=off/g" ${CONF}
    # set owner and permissions for config and data files
    set_owner_permission
    restarting_tor
    echo "Client authorization deleted, you can access your service without being asked for a key now"
    exit 1
  elif [ "${STATUS}" == "purge" ]; then
    echo "Removing client authorization for all services"
    sudo sed -i "s/OnionAuth=.*/OnionAuth=off/g" ${CONF}
    for dir in ${SERVICES_DATA_DIR}/*/; do
      dir=${dir%*/}
      sudo rm -f ${dir}/authorized_clients/*
    done
    restarting_tor
    echo "Client authorization removed"
    echo "You can know access the services without being request for a key"
  else
    echo "ERROR: invalid status: ${STATUS}"
    echo "Options are on/off"
    exit 0
  fi
fi


# RENEW ADDRESS
if [ "${1}" == "renew" ]; then
  SERVICE="${2}"
  if [ "${SERVICE}" == "" ]; then
    echo "ERROR: SERVICE is missing (on/off)"
    exit 0
  fi
  if [ "${SERVICE}" == "all" ]; then
    sudo rm -rf ${SERVICES_DATA_DIR}/*
  fi
  echo "Restarting Tor to activate the Hidden Service..."
  # set owner and permissions for config and data files
  set_owner_permission
  # restart tor / sighup tor
  restarting_tor
fi


# USE VANGUARDS
if [ "${1}" == "vanguards" ]; then
  STATUS="${2}"
  if [ ${#STATUS} -eq 0 ]; then
    echo "ERROR: status is missing (install/on/off)"
    exit 0
  fi

  # This can be used for updates, as there is no official release tag since April of 2019. We are in 2021
  # https://github.com/mikeperry-tor/vanguards/releases
  if [ "${STATUS}" == "install" ]; then
    sudo rm -rf ${DATA_DIR}/vanguards
    echo "Installing necessary packages..."
    sudo -u ${OWNER_TOR_DATA_DIR} git clone https://github.com/mikeperry-tor/vanguards
    cd vanguards || exit 1
    COMMITHASH=10942de
    sudo -u ${OWNER_TOR_DATA_DIR} reset --hard ${COMMITHASH} || exit 1
    sudo mv vanguards ${DATA_DIR}/
    sudo cp ${DATA_DIR}/vanguards/vanguards-example.conf ${DATA_DIR}/vanguards/vanguards.conf
    set_owner_permission
    sudo apt install -y python3-stem #python-stem vanguards
    echo "Done"

  elif [ "${STATUS}" == "remove" ]; then
     echo "Removing Vanguards..."
    sudo systemctl stop vanguards@default.service
    sudo systemctl disable vanguards@default.service
    sudo rm -rf /etc/systemd/system/vanguards@default.service
    sudo rm -rf ${DATA_DIR}/vanguards
    sudo systemctl daemon-reload
    restarting_tor
    echo "Done"

  elif [ "${STATUS}" == "on" ]; then

    CONTROL_PORT="${3}"
    if [ ${#CONTROL_PORT} -eq 0 ]; then
      echo "ERROR: control port is missing"
      exit 0
    fi

    echo "Creating service for Vanguards..."
    sudo tee /etc/systemd/system/vanguards@default.service >/dev/null <<EOF
[Unit]
Description=Additional protections for Tor onion services
Wants=tor@default.service
After=network.target nss-lookup.target mnt-hdd.mount

[Service]
WorkingDirectory=${DATA_DIR}/vanguards
ExecStart=/usr/bin/python3 src/vanguards.py --control_port ${CONTROL_PORT}
Environment=VANGUARDS_CONFIG=${DATA_DIR}/vanguards/vanguards.conf
User=${OWNER_DATA_DIR}
Group=${OWNER_DATA_DIR}
Type=simple
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable vanguards@default.service
    sudo systemctl start vanguards@default.service

  elif [ "${STATUS}" == "off" ]; then

    CONTROL_PORT="${3}"
    if [ ${#CONTROL_PORT} -eq 0 ]; then
      echo "ERROR: control port is missing"
      exit 0
    fi

    if [ -f "/etc/systemd/system/vanguards@default.service" ]; then
      echo "Removing Vanguards..."
      sudo systemctl stop vanguards@default.service
      sudo systemctl disable vanguards@default.service
      sudo rm -f /etc/systemd/system/vanguards@default.service
      sudo rm -rf ${DATA_DIR}/vanguards-default
      sudo systemctl daemon-reload
      restarting_tor
      echo "Done"
    else
      echo "Error: Vanguards daemon service does not exist"
    fi
  fi
fi


# INSTANCE
if [ "${1}" == "instance" ]; then
  STATUS="${2}"
  if [ ${#STATUS} -eq 0 ]; then
    echo "ERROR: status is missing (on/off)"
    exit 0
  fi
  INSTANCE="${3}"
  if [ ${#INSTANCE} -eq 0 ]; then
    echo "ERROR: instance name is missing"
    exit 0
  fi

  if [ "${STATUS}" == "on" ]; then
    CONTROL_PORT="${4}"
    if [ ${#CONTROL_PORT} -eq 0 ]; then
      echo "ERROR: control port is missing"
      exit 0
    fi
    SOCKS_PORT=$((CONTROL_PORT-1))
    sudo tor-instance-create ${INSTANCE}
    if [ ! -d "${ROOT_DATA_DIR}/tor-${INSTANCE}" ]; then
      sudo mkdir -p ${ROOT_DATA_DIR}/tor-${INSTANCE}
    fi
    # make sure its the correct owner
    sudo chmod -R 700 ${ROOT_DATA_DIR}/tor-${INSTANCE}
    sudo chown -R _tor-${INSTANCE}:_tor-${INSTANCE} ${ROOT_DATA_DIR}/tor-${INSTANCE}

  echo "
### torrc for tor@${INSTANCE}
DataDirectory ${ROOT_DATA_DIR}/tor-${INSTANCE}/sys
PidFile ${ROOT_DATA_DIR}/tor-${INSTANCE}/sys/tor.pid
SocksPort ${SOCKS_PORT}
ControlPort ${CONTROL_PORT}
CookieAuthentication 1
CookieAuthFileGroupReadable 1
SafeLogging 1
#Log notice stdout
#Log notice file ${ROOT_DATA_DIR}/tor-${INSTANCE}/notice.log
#Log info file ${ROOT_DATA_DIR}/tor-${INSTANCE}/info.log
  " | sudo tee ${ROOT_TORRC}/instances/${INSTANCE}/torrc 2>/dev/null
    sudo chmod 644 ${ROOT_TORRC}/instances/${INSTANCE}/torrc

    sudo mkdir -p /etc/systemd/system/tor@${INSTANCE}.service.d
    sudo tee /etc/systemd/system/tor@${INSTANCE}.service.d/instance.conf >/dev/null <<EOF
# DO NOT EDIT! This file is generated by raspiblitz and will be overwritten
[Service]
ReadWriteDirectories=-${ROOT_DATA_DIR}/tor-${INSTANCE}
[Unit]
After=network.target nss-lookup.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable tor@${INSTANCE}
    sudo systemctl start tor@${INSTANCE}

  elif [ "${STATUS}" == "off" ]; then
    sudo systemctl mask tor@${INSTANCE}.service
    sudo rm -rf /etc/systemd/system/tor@${INSTANCE}.service.d
    sudo rm -rf ${ROOT_DATA_DIR}/tor-${INSTANCE}
    sudo rm -rf ${ROOT_TORRC}/instances/${INSTANCE}
    sudo systemctl daemon-reload

  fi
fi


# SEE INFO
if [ "${1}" == "credentials" ]; then
  STATUS="${2}"
  if [ ${#STATUS} -eq 0 ]; then
    echo "ERROR: status is missing (on/off)"
    exit 0
  fi
  SERVICE="${2}"
  if [ ${#SERVICE} -eq 0 ]; then
    echo "ERROR: service name is missing"
    exit 0
  fi
  serviceExists=$(sudo -u ${OWNER_DATA_DIR} cat ${SERVICES_DATA_DIR}/${SERVICE}/hostname | grep -c ".onion")
  if [ ${serviceExists} -eq 0 ]; then
    echo "Create the desired service first"
    echo "bash /home/admin/config.scripts/tor.onion-service.sh -h"
    exit 0
  fi
  # get credentials
  PUB_KEY=$(sudo -u ${OWNER_DATA_DIR} cat ${SERVICES_DATA_DIR}/${SERVICE}/authorized_clients/me.auth 2>/dev/null)
  PRIV_KEY=$(sudo -u ${OWNER_DATA_DIR} cat ${SERVICES_DATA_DIR}/${SERVICE}/authorized_clients/client_auth_priv_key 2>/dev/null)
  TOR_ADDRESS=$(sudo -u ${OWNER_DATA_DIR} cat ${SERVICES_DATA_DIR}/${SERVICE}/hostname 2>/dev/null)
  TOR_ADDRESS_WITHOUT_ONION=$(sudo -u ${OWNER_DATA_DIR} cat ${SERVICES_DATA_DIR}/${SERVICE}/hostname | cut -c1-56)
  if [ "${PRIV_KEY}" == "" ]; then
    TORRC_CLIENT_KEY=""
  else
    TORRC_CLIENT_KEY=(${TOR_ADDRESS_WITHOUT_ONION}":descriptor:x25519:"${PRIV_KEY})
  fi
  FINGERPRINT=$(openssl x509 -in /mnt/hdd/app-data/nginx/tls.cert -fingerprint -noout -sha256| cut -d"=" -f2)
  clear
  # QR code displaying in the SSH terminal and the LCD screen
  /home/admin/config.scripts/blitz.display.sh qr-console ${TOR_ADDRESS}
  /home/admin/config.scripts/blitz.display.sh qr ${TOR_ADDRESS}
  echo "-----------------------------------"
  echo "Address QR code:"
  qrencode -m 2 -t ANSIUTF8 ${TOR_ADDRESS}
  echo
  echo "Service            = "${SERVICE}
  echo "Fingerprint sha256 = "${FINGERPRINT}
  echo "Address            = "${TOR_ADDRESS}
  echo "Client priv key    = "${PRIV_KEY}
  echo "Client torrc       = "${TORRC_CLIENT_KEY}
  echo
  echo "See LCD or above for the QR code containing only the service address"
  echo "-----------------------------------"
  echo
  read key
  /home/admin/config.scripts/blitz.display.sh hide
  clear
  exit 0
fi