#!/bin/bash

# https://i2pd.readthedocs.io

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "I2P Daemon install script"
  echo "More info at https://i2pd.readthedocs.io"
  echo "Usage:"
  echo "blitz.i2pd.sh install      -> Install i2pd"
  echo "blitz.i2pd.sh on           -> Switch on i2pd"
  echo "blitz.i2pd.sh off          -> Uninstall i2pd"
  echo "blitz.i2pd.sh addseednodes -> Add 21 randonly selected I2P seed nodes from: https://github.com/bitcoin/bitcoin/blob/master/contrib/seeds/nodes_main.txt"
  echo "blitz.i2pd.sh status       -> I2P related logs from bitcoind, bitcoin-cli -netinfo 4 and webconsole access"
  exit 1
fi

function confAdd {
  # get parameters
  keystr="$1"
  valuestr=$(echo "$2" | sed 's/\//\\\//g')
  configFile="$3"

  # check if key needs to be added (prepare new entry)
  entryExists=$(grep -c "^${keystr}=" ${configFile})
  if [ ${entryExists} -eq 0 ]; then
    echo "${keystr}=" | sudo tee -a ${configFile} 1>/dev/null
  fi

  # add an extra key=value line (needs sudo to operate when user is not root)
  echo "${keystr}=${valuestr}" | sudo tee -a ${configFile}
}

function add_repo {
  # Add repo for the latest version
  # i2pd — https://repo.i2pd.xyz/.help/readme.txt
  # https://repo.i2pd.xyz/.help/add_repo

  source /etc/os-release
  DIST=$ID
  case $ID in
  debian | ubuntu | raspbian)
    if [[ -n $DEBIAN_CODENAME ]]; then
      VERSION_CODENAME=$DEBIAN_CODENAME
    fi
    if [[ -n $UBUNTU_CODENAME ]]; then
      VERSION_CODENAME=$UBUNTU_CODENAME
    fi
    if [[ -z $VERSION_CODENAME ]]; then
      echo "Couldn't find VERSION_CODENAME in your /etc/os-release file. Did your system supported? Please report issue to me by writing to email: 'r4sas <at> i2pd.xyz'"
      exit 1
    fi
    RELEASE=$VERSION_CODENAME
    ;;
  *)
    if [[ -z $ID_LIKE || "$ID_LIKE" != "debian" && "$ID_LIKE" != "ubuntu" ]]; then
      echo "Your system is not supported by this script. Currently it supports debian-like and ubuntu-like systems."
      exit 1
    else
      DIST=$ID_LIKE
      case $ID_LIKE in
      debian)
        if [[ "$ID" == "kali" ]]; then
          if [[ "$VERSION" == "2019"* || "$VERSION" == "2020"* ]]; then
            RELEASE="buster"
          elif [[ "$VERSION" == "2021"* || "$VERSION" == "2022"* ]]; then
            RELEASE="bullseye"
          fi
        else
          RELEASE=$DEBIAN_CODENAME
        fi
        ;;
      ubuntu)
        RELEASE=$UBUNTU_CODENAME
        ;;
      esac
    fi
    ;;
  esac
  if [[ -z $RELEASE ]]; then
    echo "Couldn't detect your system release. Please report issue to me by writing to email: 'r4sas <at> i2pd.xyz'"
    exit 1
  fi
  echo "Importing signing key"
  wget -q -O - https://repo.i2pd.xyz/r4sas.gpg | sudo apt-key --keyring /etc/apt/trusted.gpg.d/i2pd.gpg add -
  echo "Adding APT repository"
  echo "deb https://repo.i2pd.xyz/$DIST $RELEASE main" | sudo tee /etc/apt/sources.list.d/i2pd.list
  echo "deb-src https://repo.i2pd.xyz/$DIST $RELEASE main" | sudo tee -a /etc/apt/sources.list.d/i2pd.list
}

function bitcoinI2Pstatus {
  echo "# I2P related logs from the bitcoin debug log"
  echo "# Follow live with the command:"
  echo "sudo tail -n 1000 -f /mnt/hdd/bitcoin/debug.log | grep i2p"
  echo
  sudo cat /mnt/hdd/bitcoin/debug.log | grep i2p
  echo
  echo "# Running the command:"
  echo "bitcoin-cli -netinfo 4"
  echo
  bitcoin-cli -netinfo 4
  echo
  echo "# i2pd webconsole:"
  localip=$(hostname -I | awk '{print $1}')
  echo "http://${localip}:7070"
  echo "# Username: i2pd"
  echo "# Password: your passwordB"
  echo
}

echo "# Running: 'blitz.i2pd.sh $*'"
source /mnt/hdd/raspiblitz.conf

# make sure to be present in PATH
if ! echo "$PATH" | grep "/usr/sbin" >/dev/null; then
  export PATH=$PATH:/usr/sbin
  echo "PATH=\$PATH:/usr/sbin" | sudo tee -a /etc/profile
fi

if [ "$1" = "install" ]; then

  isInstalled=$(sudo systemctl list-unit-files | grep -c i2pd)
  if [ "${isInstalled}" != "0" ]; then
    echo "# i2pd is already installed."
  else
    echo "# Installing i2pd ..."

    add_repo

    sudo apt-get update
    sudo apt-get install -y i2pd

  fi
  exit 0
fi

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  isInstalled=$(sudo systemctl list-unit-files | grep -c i2pd)
  if [ "${isInstalled}" != "0" ]; then
    echo "# i2pd is installed."
  else
    /home/admin/config.scripts/blitz.i2pd.sh install
  fi

  if systemctl is-active --quiet i2pd.service; then
    echo "# i2pd.service is already active."
  else
    echo "# sudo systemctl enable i2pd"
    sudo systemctl enable i2pd
  fi

  echo "# i2pd config"
  /home/admin/config.scripts/blitz.conf.sh set debug tor /mnt/hdd/bitcoin/bitcoin.conf noquotes
  confAdd debug i2p /mnt/hdd/bitcoin/bitcoin.conf
  /home/admin/config.scripts/blitz.conf.sh set i2psam 127.0.0.1:7656 /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh set i2pacceptincoming 1 /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh set onlynet onion /mnt/hdd/bitcoin/bitcoin.conf noquotes
  confAdd onlynet i2p /mnt/hdd/bitcoin/bitcoin.conf
  PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
  cat <<EOF | sudo tee /etc/i2pd/i2pd.conf
# i2pd settings for the RaspiBlitz
# for the defaults see:
# https://github.com/PurpleI2P/i2pd/blob/openssl/contrib/i2pd.conf
# Docs:
# https://i2pd.readthedocs.io/en/latest/user-guide/configuration/
loglevel = none
[http]
address=0.0.0.0
strictheaders = false
port = 7070
auth = true
user = i2pd
pass = ${PASSWORD_B}
[httpproxy]
enabled = false
[socksproxy]
enabled = false
[sam]
enabled = true
[bob]
enabled = false
[i2cp]
enabled = false
[i2pcontrol]
enabled = false
[upnp]
enabled = false
EOF

  sudo ufw allow 7070 comment "i2pd-webconsole"

  # Restart bitcoind and start i2p
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# Starting i2pd service ..."
    sudo systemctl start i2pd

    echo "# Restart bitcoind ..."
    sudo systemctl restart bitcoind 2>/dev/null
    sleep 10
  fi

  if i2pd --version; then
    echo "# Installed i2pd"
  else
    echo "# i2pd is not installed"
    exit 1
  fi

  # setting value in raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set i2pd "on"

  localip=$(hostname -I | awk '{print $1}')
  echo "# Config: /etc/i2pd/i2pd.conf"
  echo "# i2pd web console: ${localip}:7070"
  echo "# Monitor i2p in bitcoind:"
  echo "sudo tail -n 100 /mnt/hdd/bitcoin/debug.log | grep i2p"
  echo "bitcoin-cli -netinfo 4"

  exit 0
fi

if [ "$1" = "addseednodes" ]; then

  if ! sudo -u bitcoin bitcoin-cli -netinfo 4 | grep i2p; then
    /home/admin/config.scripts/blitz.i2pd.sh on
  fi
  echo "Add 21 randomly selected I2P seed nodes from: https://github.com/bitcoin/bitcoin/blob/master/contrib/seeds/nodes_main.txt"
  echo "Monitor in a new terminal with:"
  echo "watch sudo -u bitcoin bitcoin-cli -netinfo 4"
  echo "This will take some time ..."

  # Fetch and filter the list of seed nodes
  i2pSeedNodeList=$(curl -sS https://raw.githubusercontent.com/bitcoin/bitcoin/master/contrib/seeds/nodes_main.txt | grep .b32.i2p:0)

  # Shuffle the list and pick the first 21 nodes
  selectedNodes=$(echo "$i2pSeedNodeList" | shuf | head -n 21)

  # Add each selected node
  for i2pSeedNode in ${selectedNodes}; do
    echo "# Add i2p seed node: ${i2pSeedNode} by running:"
    echo "bitcoin-cli addnode $i2pSeedNode onetry"
    sudo -u bitcoin bitcoin-cli addnode "$i2pSeedNode" "onetry"
  done
  
  echo
  echo "# Display bitcoin-cli -netinfo 4"
  sudo -u bitcoin bitcoin-cli -netinfo 4

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# stop & remove systemd service"
  sudo systemctl stop i2pd 2>/dev/null
  sudo systemctl disable i2pd.service

  echo "# Uninstall with apt"
  sudo apt remove -y i2pd

  echo "# Remove settings from bitcoind"
  /home/admin/config.scripts/blitz.conf.sh delete debug /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh set debug tor /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh delete i2psam /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh delete i2pacceptincoming /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh delete onlynet /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh set onlynet onion /mnt/hdd/bitcoin/bitcoin.conf noquotes

  sudo rm /etc/systemd/system/i2pd.service

  sudo ufw delete allow 7070

  if ! i2pd --version 2>/dev/null; then
    echo "# OK - i2pd is not installed now"
  else
    echo "# i2pd is still installed"
    exit 1
  fi

  # setting value in raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set i2pd "off"

  exit 0
fi

if [ "$1" = "status" ]; then
  bitcoinI2Pstatus
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
exit 1
