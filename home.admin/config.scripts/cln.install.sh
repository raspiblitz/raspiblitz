#!/bin/bash
# https://lightning.readthedocs.io/

# https://github.com/ElementsProject/lightning/releases
CLVERSION=v0.10.0

# vars
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# help
if [ $# -eq 0 ]||[ "$1" = "-h" ]||[ "$1" = "--help" ];then
  echo
  echo "C-lightning install script"
  echo "the default version is: $CLVERSION"
  echo "setting up on ${chain}net unless otherwise specified"
  echo "mainnet / signet / testnet instances can run parallel"
  echo
  echo "usage:"
  echo "cln.install.sh on  <signet|testnet>"
  echo "cln.install.sh off <signet|testnet> <purge>"
  echo "cln.install.sh [update<version>|commit|testPR<PRnumber>]"
  echo
  exit 1
fi

# Tor
TORGROUP="debian-tor"

# bitcoin mainnet / signet / testnet
if [ "$1" = on ] || [ "$1" = off ] && [ $# -gt 1 ];then
  NETWORK=$2
else 
  if [ $chain = main ];then
    NETWORK=${network}
  else
    NETWORK=${chain}net
  fi
fi

# prefix for parallel testnetwork services
if [ $NETWORK = testnet ];then
  prefix="t"
  portprefix=1
elif [ $NETWORK = signet ];then
  prefix="s"
  portprefix=3
else
  prefix=""
  portprefix=""
fi

echo "# Running: 'cln.install.sh $*'"
echo "# Using the settings for: ${NETWORK} "

# add default value to raspi config if needed
if ! grep -Eq "^${prefix}cln=" /mnt/hdd/raspiblitz.conf; then
  echo "${prefix}cln=off" >> /mnt/hdd/raspiblitz.conf
fi
source /mnt/hdd/raspiblitz.conf

if [ "$1" = on ]||[ "$1" = update ]||[ "$1" = commit ]||[ "$1" = testPR ];then
  if [ ! -f /usr/local/bin/lightningd ]||[ "$1" = update ]||[ "$1" = commit ]||[ "$1" = testPR ];then
    # dependencies
    echo "# apt update"
    echo
    sudo apt-get update
    echo
    echo "# Installing dependencies"
    echo
    sudo apt-get install -y \
    autoconf automake build-essential git libtool libgmp-dev \
    libsqlite3-dev python3 python3-mako net-tools zlib1g-dev libsodium-dev \
    gettext

    # download and compile from source
    cd /home/bitcoin || exit 1
    if [ "$1" = "update" ] || [ "$1" = "testPR" ] || [ "$1" = "commit" ]; then
      echo
      echo "# Deleting the old source code"
      echo
      sudo rm -rf lightning
    fi
    echo
    echo "# Cloning https://github.com/ElementsProject/lightning.git"
    echo
    sudo -u bitcoin git clone https://github.com/ElementsProject/lightning.git
    cd lightning || exit 1
    
    if [ "$1" = "testPR" ]; then
      PRnumber=$2 || exit 1
      echo
      echo "# Using the PR:"
      echo "# https://github.com/ElementsProject/lightning/pull/$PRnumber"
      echo
      sudo -u bitcoin git fetch origin pull/$PRnumber/head:pr$PRnumber || exit 1
      sudo -u bitcoin git checkout pr$PRnumber || exit 1
      echo "# Building with EXPERIMENTAL_FEATURES enabled"
      sudo -u bitcoin ./configure --enable-experimental-features
    elif [ "$1" = "commit" ]; then
      echo
      echo "# Updating to the latest commit in:"
      echo "# https://github.com/ElementsProject/lightning"
      echo
      echo "# Building with EXPERIMENTAL_FEATURES enabled"
      sudo -u bitcoin ./configure --enable-experimental-features
    else
      if [ "$1" = "update" ]; then
        CLVERSION=$2
        echo "# Updating to the version $CLVERSION"
      fi
      sudo -u bitcoin git reset --hard $CLVERSION
      sudo -u bitcoin ./configure
    fi

    currentCLversion=$(cd /home/bitcoin/lightning 2>/dev/null; \
    git describe --tags 2>/dev/null)
    sudo -u bitcoin ./configure
    echo
    echo "# Building from source C-lightning $currentCLversion"
    echo
    sudo -u bitcoin make
    echo
    echo "# Built C-lightning $currentCLversion"
    echo
    echo "# Install to /usr/local/bin/"
    echo
    sudo make install || exit 1
    # clean up
    # cd .. && rm -rf lightning
  else
    installedVersion=$(sudo -u bitcoin /usr/local/bin/lightningd --version)
    echo "# C-lightning ${installedVersion} is already installed"
  fi

  # config
  echo "# Make sure bitcoin is in the ${TORGROUP} group"
  sudo usermod -a -G ${TORGROUP} bitcoin

  echo "# Store the lightning data in /mnt/hdd/app-data/.lightning"
  echo "# Symlink to /home/bitcoin/"
  sudo rm -rf /home/bitcoin/.lightning # not a symlink, delete
  sudo mkdir -p /mnt/hdd/app-data/.lightning
  sudo ln -s /mnt/hdd/app-data/.lightning /home/bitcoin/
  echo "# Create /home/bitcoin/.lightning/${prefix}config"
  if [ ! -f /home/bitcoin/.lightning/${prefix}config ];then
    echo "
# lightningd configuration for $NETWORK

network=$NETWORK
announce-addr=127.0.0.1:${portprefix}9736
log-file=cl.log
log-level=debug

# Tor settings
proxy=127.0.0.1:9050
bind-addr=127.0.0.1:${portprefix}9736
addr=statictor:127.0.0.1:9051
always-use-proxy=true
" | sudo tee /home/bitcoin/.lightning/${prefix}config
  else
    echo "# The file /home/bitcoin/.lightning/${prefix}config is already present"
  fi
  sudo chown -R bitcoin:bitcoin /mnt/hdd/app-data/.lightning
  sudo chown -R bitcoin:bitcoin /home/bitcoin/  

  # systemd service
  sudo systemctl stop ${prefix}lightningd
  sudo systemctl disable ${prefix}lightningd
  echo "# Create /etc/systemd/system/${prefix}lightningd.service"
  echo "
[Unit]
Description=c-lightning daemon on $NETWORK

[Service]
User=bitcoin
Group=bitcoin
Type=simple
ExecStart=/usr/local/bin/lightningd\
 --conf=\"/home/bitcoin/.lightning/${prefix}config\"
KillMode=process
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
" | sudo tee /etc/systemd/system/${prefix}lightningd.service
  sudo systemctl daemon-reload
  sudo systemctl enable ${prefix}lightningd
  echo "# Enabled the ${prefix}lightningd.service"
  if [ "${state}" == "ready" ]; then
    sudo systemctl start ${prefix}lightningd
    echo "# Started the ${prefix}lightningd.service"
  fi
  echo
  echo "# Adding aliases"
  echo "\
alias ${prefix}lightning-cli=\"sudo -u bitcoin /usr/local/bin/lightning-cli\
 --conf=/home/bitcoin/.lightning/${prefix}config\"
alias ${prefix}cl=\"sudo -u bitcoin /usr/local/bin/lightning-cli\
 --conf=/home/bitcoin/.lightning/${prefix}config\"
" | sudo tee -a /home/admin/_aliases.sh

  echo
  echo "# The installed C-lightning version is: $(sudo -u bitcoin /usr/local/bin/lightningd --version)"
  echo   
  echo "# To activate the aliases reopen the terminal or use:"
  echo "source ~/_aliases.sh"
  echo "# Monitor the ${prefix}lightningd with:"
  echo "sudo journalctl -fu ${prefix}lightningd"
  echo "sudo systemctl status ${prefix}lightningd"
  echo "# logs:"
  echo "sudo tail -f /home/bitcoin/.lightning/${NETWORK}/cl.log"
  echo "# for the command line options use"
  echo "${prefix}lightning-cli help"
  echo

  # setting value in raspi blitz config
  sudo sed -i "s/^${prefix}cln=.*/${prefix}cln=on/g" /mnt/hdd/raspiblitz.conf

  exit 0
fi

if [ "$1" = "off" ];then
  echo "# Removing the ${prefix}lightningd.service"
  sudo systemctl disable ${prefix}lightningd
  sudo systemctl stop ${prefix}lightningd
  echo "# Removing the aliases"
  sudo sed -i "/${prefix}lightning-cli/d" /home/admin/_aliases.sh
  sudo sed -i "/${prefix}cl/d" /home/admin/_aliases.sh
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
    echo "# Removing the binaries"
    sudo rm -f /usr/local/bin/lightningd
    sudo rm -f /usr/local/bin/lightning-cli
  fi
  # setting value in raspi blitz config
  sudo sed -i "s/^${prefix}cln=.*/${prefix}cln=off/g" /mnt/hdd/raspiblitz.conf
fi
