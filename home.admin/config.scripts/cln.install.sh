#!/bin/bash
# https://lightning.readthedocs.io/

# https://github.com/ElementsProject/lightning/releases
#CLVERSION=v0.10.0

# install the latest master by using the last commit id
# https://github.com/ElementsProject/lightning/commit/063366ed7e3b7cc12a8d1681acc2b639cf07fa23
CLVERSION="063366ed7e3b7cc12a8d1681acc2b639cf07fa23"

# vars
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# help
if [ $# -eq 0 ]||[ "$1" = "-h" ]||[ "$1" = "--help" ];then
  echo
  echo "C-lightning install script"
  echo "the default version is: $CLVERSION"
  echo "setting up on ${chain}net unless otherwise specified"
  echo "mainnet / testnet / signet instances can run parallel"
  echo
  echo "usage:"
  echo "cln.install.sh on <mainnet|testnet|signet>"
  echo "cln.install.sh off <mainnet|testnet|signet> <purge>"
  echo "cln.install.sh [update <version>|experimental|testPR <PRnumber>]"
  echo
  exit 1
fi

# Tor
TORGROUP="debian-tor"

source <(/home/admin/config.scripts/network.aliases.sh getvars cln $2)

echo "# Running: 'cln.install.sh $*'"
echo "# Using the settings for: ${network} ${CHAIN}"

# add default value to raspi config if needed
if ! grep -Eq "^${netprefix}cln=" /mnt/hdd/raspiblitz.conf; then
  echo "${netprefix}cln=off" >> /mnt/hdd/raspiblitz.conf
fi
source /mnt/hdd/raspiblitz.conf

if [ "$1" = on ]||[ "$1" = update ]||[ "$1" = experimental ]||[ "$1" = testPR ];then
  if [ ! -f /usr/local/bin/lightningd ]||[ "$1" = update ]||[ "$1" = experimental ]||[ "$1" = testPR ];then

    ########################
    # Install dependencies # 
    ########################
  
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

    ####################################
    # Download and compile from source #
    ####################################

    cd /home/bitcoin || exit 1
    if [ "$1" = "update" ] || [ "$1" = "testPR" ] || [ "$1" = "experimental" ]; then
      echo
      echo "# Deleting the old source code"
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
      sudo -u bitcoin git fetch origin pull/$PRnumber/head:pr$PRnumber || exit 1
      sudo -u bitcoin git checkout pr$PRnumber || exit 1
      echo "# Building with EXPERIMENTAL_FEATURES enabled"
      echo
      sudo -u bitcoin ./configure --enable-experimental-features
    elif [ "$1" = "experimental" ]; then
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
  
  ##########
  # Config #
  ##########

  echo "# Make sure bitcoin is in the ${TORGROUP} group"
  sudo usermod -a -G ${TORGROUP} bitcoin

  echo "# Add plugin-dir: /home/bitcoin/${netprefix}cln-plugins-enabled"
  echo "# Add plugin-dir: /home/bitcoin/cln-plugins-available"
  # note that the disk is mounted with noexec
  sudo -u bitcoin mkdir /home/bitcoin/${netprefix}cln-plugins-enabled
  sudo -u bitcoin mkdir /home/bitcoin/cln-plugins-available

  echo "# Store the lightning data in /mnt/hdd/app-data/.lightning"
  echo "# Symlink to /home/bitcoin/"
  sudo rm -rf /home/bitcoin/.lightning # not a symlink, delete
  sudo mkdir -p /mnt/hdd/app-data/.lightning
  sudo ln -s /mnt/hdd/app-data/.lightning /home/bitcoin/
  
 
  echo "# Create ${CLNCONF}"
  if [ ! -f ${CLNCONF} ];then
    echo "
# lightningd configuration for ${network} ${CHAIN}

network=${CLNETWORK}
announce-addr=127.0.0.1:${portprefix}9736
log-file=cl.log
log-level=debug
plugin-dir=/home/bitcoin/${netprefix}cln-plugins-enabled

# Tor settings
proxy=127.0.0.1:9050
bind-addr=127.0.0.1:${portprefix}9736
addr=statictor:127.0.0.1:9051/torport=${portprefix}9736
always-use-proxy=true
" | sudo tee ${CLNCONF}
  else
    echo "# The file ${CLNCONF} is already present"
  fi
  sudo chown -R bitcoin:bitcoin /mnt/hdd/app-data/.lightning
  sudo chown -R bitcoin:bitcoin /home/bitcoin/  

  #################
  # Backup plugin #
  #################
  /home/admin/config.scripts/cln-plugin.backup.sh on $CHAIN

  ###################
  # Systemd service #
  ###################
  /home/admin/config.scripts/cln.install-service.sh $CHAIN

  echo
  echo "# Adding aliases"
  echo "\
alias ${netprefix}lightning-cli=\"sudo -u bitcoin /usr/local/bin/lightning-cli\
 --conf=${CLNCONF}\"
alias ${netprefix}cln=\"sudo -u bitcoin /usr/local/bin/lightning-cli\
 --conf=${CLNCONF}\"
alias ${netprefix}clnlog=\"sudo\
 tail -n 30 -f /home/bitcoin/.lightning/${CLNETWORK}/cl.log\"
alias ${netprefix}clnconf=\"sudo\
 nano ${CLNCONF}\"
" | sudo tee -a /home/admin/_aliases

  echo "# The installed C-lightning version is: $(sudo -u bitcoin /usr/local/bin/lightningd --version)"
  echo   
  echo "# To activate the aliases reopen the terminal or use:"
  echo "source ~/_aliases"
  echo "# Monitor the ${netprefix}lightningd with:"
  echo "sudo journalctl -fu ${netprefix}lightningd"
  echo "sudo systemctl status ${netprefix}lightningd"
  echo "# logs:"
  echo "sudo tail -f /home/bitcoin/.lightning/${CLNETWORK}/cl.log"
  echo "# for the command line options use"
  echo "${netprefix}lightning-cli help"
  echo

  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}cln=.*/${netprefix}cln=on/g" /mnt/hdd/raspiblitz.conf

  exit 0
fi

if [ "$1" = "off" ];then
  echo "# Removing the ${netprefix}lightningd.service"
  sudo systemctl disable ${netprefix}lightningd
  sudo systemctl stop ${netprefix}lightningd
  echo "# Removing the aliases"
  sudo sed -i "/${netprefix}lightning-cli/d" /home/admin/_aliases
  sudo sed -i "/${netprefix}cl/d" /home/admin/_aliases
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
    echo "# Removing the binaries"
    sudo rm -f /usr/local/bin/lightningd
    sudo rm -f /usr/local/bin/lightning-cli
  fi
  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}cln=.*/${netprefix}cln=off/g" /mnt/hdd/raspiblitz.conf
fi
