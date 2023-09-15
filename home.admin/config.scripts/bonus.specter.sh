#!/bin/bash
# https://github.com/cryptoadvance/specter-desktop

pinnedVersion="1.13.1"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to switch Specter Desktop on, off, configure or update"
  echo "bonus.specter.sh [status|on|config|update] <mainnet|testnet|signet>"
  echo "bonus.specter.sh off <--delete-data|--keep-data>"
  echo "installing the version $pinnedVersion by default"
  exit 1
fi

echo "# bonus.specter.sh $1 $2"

source /mnt/hdd/raspiblitz.conf
if [ $# -gt 1 ]; then
  CHAIN=$2
  chain=${CHAIN::-3}
fi

# get status key/values
if [ "$1" = "status" ]; then

  if [ "${specter}" = "on" ]; then

    echo "configured=1"

    installed=$(sudo ls /etc/systemd/system/specter.service 2>/dev/null | grep -c 'specter.service')
    echo "installed=${installed}"

    # get network info
    localip=$(hostname -I | awk '{print $1}')
    toraddress=$(sudo cat /mnt/hdd/tor/specter/hostname 2>/dev/null)
    fingerprint=$(openssl x509 -in /home/specter/.specter/cert.pem -fingerprint -noout | cut -d"=" -f2)
    echo "localIP='${localip}'"
    echo "httpPort=''"
    echo "httpsPort='25441'"
    echo "httpsForced='1'"
    echo "httpsSelfsigned='1'"
    echo "toraddress='${toraddress}'"
    echo "fingerprint='${fingerprint}'"

    # check for error
    serviceFailed=$(sudo systemctl status specter | grep -c 'inactive (dead)')
    if [ "${serviceFailed}" = "1" ]; then
      echo "error='Service Failed'"
      exit 1
    fi

  else
    echo "configured=0"
    echo "installed=0"
  fi

  exit 0
fi

# show info menu
if [ "$1" = "menu" ]; then

  # get status
  echo "# collecting status info ... (please wait)"
  source <(sudo /home/admin/config.scripts/bonus.specter.sh status)
  echo "# toraddress: ${toraddress}"

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then

    # Tor
    sudo /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
    whiptail --title " Specter Desktop " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localIP}:25441

SHA1 Thumb/Fingerprint:
${fingerprint}

Login with the Pin being Password B. If you have connected to a different Bitcoin RPC Endpoint, the Pin is the configured RPCPassword.

Hidden Service address for TOR Browser (QR see LCD):
https://${toraddress}
Unfortunately the camera is currently not usable via Tor, though.
" 18 74
    sudo /home/admin/config.scripts/blitz.display.sh hide
  else

    # IP + Domain
    whiptail --title " Specter Desktop " --msgbox "Open in your local web browser & accept self-signed cert:
https://${localIP}:25441

SHA1 Thumb/Fingerprint:
${fingerprint}

Login with the PIN being Password B. If you have connected to a different Bitcoin RPC Endpoint, the PIN is the configured RPCPassword.\n
Activate TOR to access the web block explorer from outside your local network.
" 15 74
  fi

  echo "# please wait ..."
  exit 0
fi

# blockfilterindex
# add blockfilterindex with default value (0) to bitcoin.conf if missing
if ! grep -Eq "^blockfilterindex=.*" /mnt/hdd/${network}/${network}.conf; then
  echo "blockfilterindex=0" | sudo tee -a /mnt/hdd/${network}/${network}.conf >/dev/null
fi
# set variable ${blockfilterindex}
source <(grep -E "^blockfilterindex=.*" /mnt/hdd/${network}/${network}.conf)

function configure_specter {
  echo "#    --> creating App-config"
  if [ "${runBehindTor}" = "on" ]; then
    proxy="socks5h://localhost:9050"
    torOnly="true"
    tor_control_port="9051"
  else
    proxy=""
    torOnly="false"
    tor_control_port=""
  fi
  cat >/home/admin/config.json <<EOF
{
    "auth": {
        "method": "rpcpasswordaspin",
        "password_min_chars": 6,
        "rate_limit": 10,
        "registration_link_timeout": 1
    },
    "active_node_alias": "raspiblitz_${chain}net",
    "proxy_url": "${proxy}",
    "only_tor": "${torOnly}",
    "tor_control_port": "${tor_control_port}",
    "tor_status": true,
    "hwi_bridge_url": "/hwi/api/"
}
EOF
  sudo mkdir -p /home/specter/.specter/nodes
  sudo mv /home/admin/config.json /home/specter/.specter/config.json
  sudo chown -RL specter:specter /home/specter/

  echo "# Adding the raspiblitz_${chain}net node to Specter"
  RPCUSER=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcuser | cut -c 9-)
  PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)

  echo "# Connect Specter to the default mainnet node"
  cat >/home/admin/default.json <<EOF
{
    "name": "raspiblitz_mainnet",
    "alias": "default",
    "autodetect": false,
    "datadir": "",
    "user": "${RPCUSER}",
    "password": "${PASSWORD_B}",
    "port": "8332",
    "host": "localhost",
    "protocol": "http",
    "external_node": true,
    "fullpath": "/home/specter/.specter/nodes/default.json"
}
EOF
  sudo mv /home/admin/default.json /home/specter/.specter/nodes/default.json
  sudo chown -RL specter:specter /home/specter/

  if [ "${chain}" != "main" ]; then
    if [ "${chain}" = "test" ]; then
      portprefix=1
    elif [ "${chain}" = "sig" ]; then
      portprefix=3
    fi
    PORT="${portprefix}8332"

    echo "# Connect Specter to the raspiblitz_${chain}net node"
    cat >/home/admin/raspiblitz_${chain}net.json <<EOF
{
    "name": "raspiblitz_${chain}net",
    "alias": "raspiblitz_${chain}net",
    "autodetect": false,
    "datadir": "",
    "user": "${RPCUSER}",
    "password": "${PASSWORD_B}",
    "port": "${PORT}",
    "host": "localhost",
    "protocol": "http",
    "external_node": true,
    "fullpath": "/home/specter/.specter/nodes/raspiblitz_${chain}net.json"
}
EOF
    sudo mv /home/admin/raspiblitz_${chain}net.json /home/specter/.specter/nodes/raspiblitz_${chain}net.json
    sudo chown -RL specter:specter /home/specter/
  fi
}

# config
if [ "$1" = "config" ]; then
  configure_specter
  echo "# Restarting Specter - reload it's page to log in with the new settings"
  sudo systemctl restart specter
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "#    --> INSTALL Specter Desktop"

  isInstalled=$(sudo ls /etc/systemd/system/specter.service 2>/dev/null | grep -c 'specter.service' || /bin/true)
  if [ ${isInstalled} -eq 0 ]; then

    echo "#    --> Enable wallets in Bitcoin Core"
    /home/admin/config.scripts/network.wallet.sh on

    echo "#    --> Installing prerequisites"
    sudo apt update
    sudo apt-get install -y virtualenv libffi-dev libusb-1.0.0-dev libudev-dev

    sudo adduser --system --group --home /home/specter specter
    if [ "$(ls /home | grep -c "specter")" == "0" ]; then
      echo "error='was not able to create user specter'"
      exit 1
    fi

    echo "# add the user to the debian-tor group"
    sudo usermod -a -G debian-tor specter

    echo "# add the user to the bitcoin group"
    sudo usermod -a -G bitcoin specter

    # store data on the disk
    sudo mkdir -p /mnt/hdd/app-data/.specter 2>/dev/null
    # move old Specter data to app-data (except .env)
    sudo mv -f /home/bitcoin/.specter/* /mnt/hdd/app-data/.specter/ 2>/dev/null
    sudo rm -rf /home/bitcoin/.specter 2>/dev/null
    # symlink to specter user
    sudo chown -R specter:specter /mnt/hdd/app-data/.specter
    sudo ln -s /mnt/hdd/app-data/.specter /home/specter/ 2>/dev/null
    sudo chown -R specter:specter /home/specter/.specter

    echo "#    --> creating a virtualenv"
    sudo -u specter virtualenv --python=python3 /home/specter/.env

    echo "#    --> pip-installing specter"
    sudo -u specter /home/specter/.env/bin/python3 -m pip install --upgrade cryptoadvance.specter==$pinnedVersion || exit 1

    # activating Authentication here ...
    configure_specter

    # Mandatory as the camera doesn't work without https
    echo "#    --> Creating self-signed certificate"
    openssl req -x509 -newkey rsa:4096 -nodes -out /tmp/cert.pem -keyout /tmp/key.pem -days 365 -subj "/C=US/ST=Nooneknows/L=Springfield/O=Dis/CN=www.fakeurl.com"
    sudo mv /tmp/cert.pem /home/specter/.specter
    sudo chown -R specter:specter /home/specter/.specter/cert.pem
    sudo mv /tmp/key.pem /home/specter/.specter
    sudo chown -R specter:specter /home/specter/.specter/key.pem

    # open firewall
    echo "#    --> Updating Firewall"
    sudo ufw allow 25441 comment 'specter'
    sudo ufw --force enable
    echo

    echo "#    --> Installing udev-rules for hardware-wallets"

    # Ledger
    cat >/home/admin/20-hw1.rules <<EOF
 HW.1 / Nano
SUBSYSTEMS=="usb", ATTRS{idVendor}=="2581", ATTRS{idProduct}=="1b7c|2b7c|3b7c|4b7c", TAG+="uaccess", TAG+="udev-acl", OWNER="specter"
# Blue
SUBSYSTEMS=="usb", ATTRS{idVendor}=="2c97", ATTRS{idProduct}=="0000|0000|0001|0002|0003|0004|0005|0006|0007|0008|0009|000a|000b|000c|000d|000e|000f|0010|0011|0012|0013|0014|0015|0016|0017|0018|0019|001a|001b|001c|001d|001e|001f", TAG+="uaccess", TAG+="udev-acl", OWNER="specter"
# Nano S
SUBSYSTEMS=="usb", ATTRS{idVendor}=="2c97", ATTRS{idProduct}=="0001|1000|1001|1002|1003|1004|1005|1006|1007|1008|1009|100a|100b|100c|100d|100e|100f|1010|1011|1012|1013|1014|1015|1016|1017|1018|1019|101a|101b|101c|101d|101e|101f", TAG+="uaccess", TAG+="udev-acl", OWNER="specter"
# Aramis
SUBSYSTEMS=="usb", ATTRS{idVendor}=="2c97", ATTRS{idProduct}=="0002|2000|2001|2002|2003|2004|2005|2006|2007|2008|2009|200a|200b|200c|200d|200e|200f|2010|2011|2012|2013|2014|2015|2016|2017|2018|2019|201a|201b|201c|201d|201e|201f", TAG+="uaccess", TAG+="udev-acl", OWNER="specter"
# HW2
SUBSYSTEMS=="usb", ATTRS{idVendor}=="2c97", ATTRS{idProduct}=="0003|3000|3001|3002|3003|3004|3005|3006|3007|3008|3009|300a|300b|300c|300d|300e|300f|3010|3011|3012|3013|3014|3015|3016|3017|3018|3019|301a|301b|301c|301d|301e|301f", TAG+="uaccess", TAG+="udev-acl", OWNER="specter"
# Nano X
SUBSYSTEMS=="usb", ATTRS{idVendor}=="2c97", ATTRS{idProduct}=="0004|4000|4001|4002|4003|4004|4005|4006|4007|4008|4009|400a|400b|400c|400d|400e|400f|4010|4011|4012|4013|4014|4015|4016|4017|4018|4019|401a|401b|401c|401d|401e|401f", TAG+="uaccess", TAG+="udev-acl", OWNER="specter"
EOF

    # ColdCard
    cat >/home/admin/51-coinkite.rules <<EOF
# Linux udev support file.
#
# This is a example udev file for HIDAPI devices which changes the permissions
# to 0666 (world readable/writable) for a specific device on Linux systems.
#
# - Copy this file into /etc/udev/rules.d and unplug and re-plug your Coldcard.
# - Udev does not have to be restarted.
#

# probably not needed:
SUBSYSTEMS=="usb", ATTRS{idVendor}=="d13e", ATTRS{idProduct}=="cc10", GROUP="plugdev", MODE="0666"

# required:
# from <https://github.com/signal11/hidapi/blob/master/udev/99-hid.rules>
KERNEL=="hidraw*", ATTRS{idVendor}=="d13e", ATTRS{idProduct}=="cc10", GROUP="plugdev", MODE="0666"
EOF

    # Trezor
    cat >/home/admin/51-trezor.rules <<EOF
# Trezor: The Original Hardware Wallet
# https://trezor.io/
#
# Put this file into /etc/udev/rules.d
#
# If you are creating a distribution package,
# put this into /usr/lib/udev/rules.d or /lib/udev/rules.d
# depending on your distribution

# Trezor
SUBSYSTEM=="usb", ATTR{idVendor}=="534c", ATTR{idProduct}=="0001", MODE="0660", GROUP="plugdev", TAG+="uaccess", TAG+="udev-acl", SYMLINK+="trezor%n"
KERNEL=="hidraw*", ATTRS{idVendor}=="534c", ATTRS{idProduct}=="0001", MODE="0660", GROUP="plugdev", TAG+="uaccess", TAG+="udev-acl"

# Trezor v2
SUBSYSTEM=="usb", ATTR{idVendor}=="1209", ATTR{idProduct}=="53c0", MODE="0660", GROUP="plugdev", TAG+="uaccess", TAG+="udev-acl", SYMLINK+="trezor%n"
SUBSYSTEM=="usb", ATTR{idVendor}=="1209", ATTR{idProduct}=="53c1", MODE="0660", GROUP="plugdev", TAG+="uaccess", TAG+="udev-acl", SYMLINK+="trezor%n"
KERNEL=="hidraw*", ATTRS{idVendor}=="1209", ATTRS{idProduct}=="53c1", MODE="0660", GROUP="plugdev", TAG+="uaccess", TAG+="udev-acl"
EOF

    # KeepKey
    cat >/home/admin/51-usb-keepkey.rules <<EOF
# KeepKey: Your Private Bitcoin Vault
# http://www.keepkey.com/
# Put this file into /usr/lib/udev/rules.d or /etc/udev/rules.d

# KeepKey HID Firmware/Bootloader
SUBSYSTEM=="usb", ATTR{idVendor}=="2b24", ATTR{idProduct}=="0001", MODE="0666", GROUP="plugdev", TAG+="uaccess", TAG+="udev-acl", SYMLINK+="keepkey%n"
KERNEL=="hidraw*", ATTRS{idVendor}=="2b24", ATTRS{idProduct}=="0001",  MODE="0666", GROUP="plugdev", TAG+="uaccess", TAG+="udev-acl"

# KeepKey WebUSB Firmware/Bootloader
SUBSYSTEM=="usb", ATTR{idVendor}=="2b24", ATTR{idProduct}=="0002", MODE="0666", GROUP="plugdev", TAG+="uaccess", TAG+="udev-acl", SYMLINK+="keepkey%n"
KERNEL=="hidraw*", ATTRS{idVendor}=="2b24", ATTRS{idProduct}=="0002",  MODE="0666", GROUP="plugdev", TAG+="uaccess", TAG+="udev-acl"
EOF

    sudo mv /home/admin/20-hw1.rules /home/admin/51-coinkite.rules /home/admin/51-trezor.rules /home/admin/51-usb-keepkey.rules /etc/udev/rules.d/
    sudo chown root:root /etc/udev/rules.d/*
    sudo udevadm trigger
    sudo udevadm control --reload-rules
    sudo groupadd plugdev || /bin/true
    sudo usermod -aG plugdev bitcoin
    sudo usermod -aG plugdev specter

    # install service
    echo "#    --> Install specter systemd service"
    cat >/home/admin/specter.service <<EOF
# systemd unit for Specter Desktop

[Unit]
Description=specter
Wants=${network}d.service
After=${network}d.service

[Service]
ExecStart=/home/specter/.env/bin/python3 -m cryptoadvance.specter server --host 0.0.0.0 --cert=/home/specter/.specter/cert.pem --key=/home/specter/.specter/key.pem
User=specter
Environment=PATH=/home/specter/.specter.env/bin:/home/specter/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/sbin:/bin
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
EOF

    sudo mv /home/admin/specter.service /etc/systemd/system/specter.service
    sudo systemctl enable specter
    echo "#    --> OK - the specter service is now enabled"

    source <(/home/admin/_cache.sh get state)
    if [ "${state}" == "ready" ]; then
      # start service
      echo "#    --> starting service ..."
      sudo systemctl start specter
      echo "#    --> OK - the specter service is now started"
    fi

  else
    echo "#    --> specter already installed."
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set specter "on"

  # Hidden Service for SERVICE if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    # make sure to keep in sync with tor.network.sh script
    # port 25441 is HTTPS with self-signed cert - specte only makes sense to be served over HTTPS
    /home/admin/config.scripts/tor.onion-service.sh specter 443 25441
  fi

  # blockfilterindex on
  # check txindex (parsed and sourced from bitcoin network config above)
  if [ "${blockfilterindex}" = "0" ]; then
    sudo sed -i "s/^blockfilterindex=.*/blockfilterindex=1/g" /mnt/hdd/${network}/${network}.conf
    echo "# switching blockfilterindex=1"
    isBitcoinRunning=$(systemctl is-active ${network}d | grep -c "^active")
    if [ ${isBitcoinRunning} -eq 1 ]; then
      echo "# ${network}d is running - so restarting"
      sudo systemctl restart ${network}d
    else
      echo "# ${network}d is not running - so NOT restarting"
    fi
    echo "# The indexing takes ~10h on an RPi4 with SSD"
    echo "# check with: sudo cat /mnt/hdd/bitcoin/debug.log | grep filter"
  else
    echo "# blockfilterindex is already active"
  fi

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set specter "off"

  # Hidden Service if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    echo "# Removing Tor hidden service for specter ..."
    /home/admin/config.scripts/tor.onion-service.sh off specter
  fi

  isInstalled=$(sudo ls /etc/systemd/system/specter.service 2>/dev/null | grep -c 'specter.service')
  if [ ${isInstalled} -gt 0 ]; then
    # removing base systemd service & code
    echo "#    --> REMOVING the specter.service"
    sudo systemctl stop specter
    sudo systemctl disable specter
    sudo rm /etc/systemd/system/specter.service
  else
    echo "#    --> The specter.service is not installed."
  fi

  # pip uninstall
  sudo -u specter /home/specter/.env/bin/python3 -m pip uninstall --yes cryptoadvance.specter 1>&2

  # get delete data status - either by parameter or if not set by user dialog
  deleteData=""
  if [ "$2" == "--delete-data" ]; then
    deleteData="1"
  fi
  if [ "$2" == "--keep-data" ]; then
    deleteData="0"
  fi
  if [ "${deleteData}" == "" ]; then
    if (whiptail --title "Delete Data?" --yes-button "Keep Data" --no-button "Delete Data" --yesno "Do you want to delete all data related to Specter? This includes the Bitcoin Core wallets managed by Specter." 0 0); then
      deleteData="0"
    else
      deleteData="1"
    fi
  fi

  # execute on delete data
  if [ "${deleteData}" == "1" ]; then
    echo "#    --> Removing wallets in core"
    bitcoin-cli listwallets | jq -r .[] | tail -n +2
    for i in $(bitcoin-cli listwallets | jq -r .[] | tail -n +2); do
      name=$(echo $i | cut -d"/" -f2)
      bitcoin-cli unloadwallet specter/$name
    done
    echo "#    --> Removing the /mnt/hdd/app-data/.specter"
    sudo rm -rf /mnt/hdd/app-data/.specter
  else
    echo "#    --> wallets in core are preserved on the disk (if exist)"
    echo "#    --> /mnt/hdd/app-data/.specter is preserved on the disk"
  fi

  echo "#    --> Removing the specter user and home directory"
  sudo userdel -rf specter 2>/dev/null
  echo "#    --> OK Specter Desktop removed."

  # needed for API/WebUI as signal that install ran thru
  echo "result='OK'"
  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "#    --> UPDATING Specter Desktop "
  sudo -u specter /home/specter/.env/bin/python3 -m pip install --upgrade pip
  sudo -u specter /home/specter/.env/bin/python3 -m pip install --upgrade cryptoadvance.specter
  echo "#    --> Updated to the latest in https://pypi.org/project/cryptoadvance.specter/#history ***"
  echo "#    --> Restarting the specter.service"
  sudo systemctl restart specter
  exit 0
fi

echo "error='unknown parameter'"
exit 1
