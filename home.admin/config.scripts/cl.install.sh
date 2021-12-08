#!/bin/bash
# https://lightning.readthedocs.io/

# https://github.com/ElementsProject/lightning/releases
CLVERSION=v0.10.2

# install the latest master by using the last commit id
# https://github.com/ElementsProject/lightning/commit/master
# CLVERSION="063366ed7e3b7cc12a8d1681acc2b639cf07fa23"

# help
if [ $# -eq 0 ]||[ "$1" = "-h" ]||[ "$1" = "--help" ];then
  echo
  echo "C-lightning install script"
  echo "The default version is: $CLVERSION"
  echo "mainnet / testnet / signet instances can run parallel"
  echo
  echo "Usage:"
  echo "cl.install.sh install - called by build_sdcard.sh"
  echo "cl.install.sh on <mainnet|testnet|signet>"
  echo "cl.install.sh off <mainnet|testnet|signet> <purge>"
  echo "cl.install.sh [update <version>|testPR <PRnumber>]"
  echo "cl.install.sh display-seed <mainnet|testnet|signet>"
  echo
  exit 1
fi

if [ "$1" = "install" ]; then
  echo "*** PREPARING C-LIGHTNING ***"
  
  # https://github.com/ElementsProject/lightning/tree/master/contrib/keys
  # PGPsigner="rustyrussel"
  # PGPpkeys="https://raw.githubusercontent.com/ElementsProject/lightning/master/contrib/keys/rustyrussell.txt"
  # PGPcheck="D9200E6CD1ADB8F1"

  PGPsigner="cdecker"
  PGPpkeys="https://raw.githubusercontent.com/ElementsProject/lightning/master/contrib/keys/cdecker.txt"
  PGPcheck="A26D6D9FE088ED58"

  # prepare download dir
  sudo rm -rf /home/admin/download/cl
  sudo -u admin mkdir -p /home/admin/download/cl
  cd /home/admin/download/cl || exit 1

  sudo -u admin wget -O "pgp_keys.asc" ${PGPpkeys}
  sudo -u admin gpg --import --import-options show-only ./pgp_keys.asc
  fingerprint=$(gpg "pgp_keys.asc" 2>/dev/null | grep "${PGPcheck}" -c)
  if [ ${fingerprint} -lt 1 ]; then
    echo
    echo "!!! WARNING --> the PGP fingerprint is not as expected for ${PGPsigner}"
    echo "Should contain PGP: ${PGPcheck}"
    echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
    read key
  fi
  sudo -u admin gpg --import ./pgp_keys.asc

  sudo -u admin wget https://github.com/ElementsProject/lightning/releases/download/${CLVERSION}/SHA256SUMS
  sudo -u admin wget https://github.com/ElementsProject/lightning/releases/download/${CLVERSION}/SHA256SUMS.asc
  
  verifyResult=$(sudo -u admin gpg --verify SHA256SUMS.asc 2>&1)

  goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
  echo "goodSignature(${goodSignature})"
  correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${PGPcheck}" -c)
  echo "correctKey(${correctKey})"
  if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
    echo
    echo "!!! BUILD FAILED --> PGP verification not OK / signature(${goodSignature}) verify(${correctKey})"
    exit 1
  else
    echo 
    echo "****************************************************************"
    echo "OK --> the PGP signature of the C-lightning SHA256SUMS is correct"
    echo "****************************************************************"
    echo 
  fi
  
  sudo -u admin wget https://github.com/ElementsProject/lightning/releases/download/${CLVERSION}/clightning-${CLVERSION}.zip
  
  hashCheckResult=$(sha256sum -c SHA256SUMS 2>&1)
  goodHash=$(echo ${hashCheckResult} | grep 'OK' -c)
  echo "goodHash(${goodHash})"
  if [ ${goodHash} -lt 1 ]; then
    echo
    echo "!!! BUILD FAILED --> Hash check not OK"
    exit 1
  else
    echo
    echo "********************************************************************"
    echo "OK --> the hash of the downloaded C-lightning source code is correct"
    echo "********************************************************************"
    echo
  fi
  
  echo "- Install build dependencies"
  sudo apt-get install -y \
    autoconf automake build-essential git libtool libgmp-dev \
    libsqlite3-dev python3 python3-mako net-tools zlib1g-dev libsodium-dev \
    gettext unzip
  sudo pip3 install mrkd==0.2.0
  sudo pip3 install mistune==0.8.4
  
  sudo -u admin unzip clightning-${CLVERSION}.zip
  cd clightning-${CLVERSION} || exit 1
  
  echo "- Configuring EXPERIMENTAL_FEATURES enabled"
  sudo -u admin ./configure --enable-experimental-features
  
  echo "- Building C-lightning from source"
  sudo -u admin make

  echo "- Install to /usr/local/bin/"
  sudo make install || exit 1
  
  installed=$(sudo -u admin lightning-cli --version)
  if [ ${#installed} -eq 0 ]; then
    echo
    echo "!!! BUILD FAILED --> Was not able to install C-lightning"
    exit 1
  fi
  
  correctVersion=$(echo "${installed}" | grep -c "${CLVERSION:1}")
  if [ ${correctVersion} -eq 0 ]; then
    echo
    echo "!!! BUILD FAILED --> installed C-lightning is not version ${CLVERSION}"
    sudo -u admin lightning-cli --version
    exit 1
  fi
  echo
  echo "- OK the installation of C-lightning v${installed} is successful"
  exit 0
fi

# vars
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
TORGROUP="debian-tor"

if [ "$1" = update ]||[ "$1" = testPR ];then
  source <(/home/admin/config.scripts/network.aliases.sh getvars cl mainnet)
else
  source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)
fi

echo "# Running: 'cl.install.sh $*'"
echo "# Using the settings for: ${network} ${CHAIN}"

# add default value to raspi config if needed
if ! grep -Eq "^lightning=" /mnt/hdd/raspiblitz.conf; then
  echo "lightning=cl" | sudo tee -a /mnt/hdd/raspiblitz.conf
fi
# add default value to raspi config if needed
if ! grep -Eq "^${netprefix}cl=" /mnt/hdd/raspiblitz.conf; then
  echo "${netprefix}cl=off" | sudo tee -a /mnt/hdd/raspiblitz.conf
fi
source /mnt/hdd/raspiblitz.conf

if [ "$1" = on ]||[ "$1" = update ]||[ "$1" = testPR ];then

  if [ "${CHAIN}" == "testnet" ] && [ "${testnet}" != "on" ]; then
    echo "# before activating testnet on cl, first activate testnet on bitcoind"
    echo "err='missing bitcoin testnet'"
    exit 1
  fi

  if [ "${CHAIN}" == "signet" ] && [ "${signet}" != "on" ]; then
    echo "# before activating signet on cl, first activate signet on bitcoind"
    echo "err='missing bitcoin signet'"
    exit 1
  fi

  if [ ! -f /usr/local/bin/lightningd ]||[ "$1" = "update" ]||[ "$1" = "testPR" ];then

    ########################
    # Install dependencies # 
    ########################
    
    # https://lightning.readthedocs.io/INSTALL.html#to-build-on-ubuntu
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
    sudo pip3 install mrkd==0.2.0
    sudo pip3 install mistune==0.8.4

    ####################################
    # Download and compile from source #
    ####################################

    cd /home/bitcoin || exit 1
    if [ "$1" = "update" ]||[ "$1" = "testPR" ]||[ "$1" = "experimental" ];then
      echo
      echo "# Deleting the old source code"
      sudo rm -rf lightning
    fi
    echo
    echo "# Cloning https://github.com/ElementsProject/lightning.git"
    echo
    sudo -u bitcoin git clone https://github.com/ElementsProject/lightning.git
    cd lightning || exit 1
    echo
    
    if [ "$1" = "update" ]; then
      if [ $# -gt 1 ];then
        CLVERSION=$2
        echo "# Installing the version $CLVERSION"
        sudo -u bitcoin git reset --hard $CLVERSION
      else
        echo "# Updating to the latest commit in:"
        echo "# https://github.com/ElementsProject/lightning"
        echo "# Make sure this is intended, there might be no way to downgrade your database"
        echo "# Press ENTER to continue or CTRL+C to abort the update"
        read -r key
      fi
    
    elif [ "$1" = "testPR" ]; then
      PRnumber=$2 || exit 1
      echo "# Using the PR:"
      echo "# https://github.com/ElementsProject/lightning/pull/$PRnumber"
      sudo -u bitcoin git fetch origin pull/$PRnumber/head:pr$PRnumber || exit 1
      sudo -u bitcoin git checkout pr$PRnumber || exit 1

    else
      echo "# Installing the version $CLVERSION"
      sudo -u bitcoin git reset --hard $CLVERSION
    fi

    echo "# Building with EXPERIMENTAL_FEATURES enabled"
    echo
    sudo -u bitcoin ./configure --enable-experimental-features
    echo
    currentCLversion=$(cd /home/bitcoin/lightning 2>/dev/null; \
    git describe --tags 2>/dev/null)
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

  echo "# Add plugin-dir: /home/bitcoin/${netprefix}cl-plugins-enabled"
  echo "# Add plugin-dir: /home/bitcoin/cl-plugins-available"
  # note that the disk is mounted with noexec
  sudo -u bitcoin mkdir /home/bitcoin/${netprefix}cl-plugins-enabled 2>/dev/null
  sudo -u bitcoin mkdir /home/bitcoin/cl-plugins-available 2>/dev/null

  echo "# Store the lightning data in /mnt/hdd/app-data/.lightning"
  echo "# Symlink to /home/bitcoin/"
  sudo rm -rf /home/bitcoin/.lightning # not a symlink, delete
  sudo mkdir -p /mnt/hdd/app-data/.lightning
  sudo ln -s /mnt/hdd/app-data/.lightning /home/bitcoin/

  if [ ${CLNETWORK} != "bitcoin" ] && [ ! -d /home/bitcoin/.lightning/${CLNETWORK} ] ;then
    sudo -u bitcoin mkdir /home/bitcoin/.lightning/${CLNETWORK}
  fi
  
  if ! sudo ls ${CLCONF};then
    echo "# Create ${CLCONF}"
    echo "# lightningd configuration for ${network} ${CHAIN}

network=${CLNETWORK}
log-file=cl.log
log-level=info
plugin-dir=/home/bitcoin/${netprefix}cl-plugins-enabled

# Tor settings
proxy=127.0.0.1:9050
bind-addr=127.0.0.1:${portprefix}9736
addr=statictor:127.0.0.1:9051/torport=${portprefix}9736
always-use-proxy=true
" | sudo tee ${CLCONF}
  else
    echo "# The file ${CLCONF} is already present"
  fi
  sudo chown -R bitcoin:bitcoin /mnt/hdd/app-data/.lightning
  sudo chown -R bitcoin:bitcoin /home/bitcoin/  

  #################
  # Backup plugin #
  #################
  /home/admin/config.scripts/cl-plugin.backup.sh on $CHAIN

  ###################
  # Systemd service #
  ###################
  /home/admin/config.scripts/cl.install-service.sh $CHAIN

  #############
  # logrotate #
  #############
  echo
  echo "# Set logrotate for ${netprefix}lightningd"
  echo "\
/home/bitcoin/.lightning/${CLNETWORK}/cl.log
{
        rotate 5
        daily
        copytruncate
        missingok
        olddir /home/bitcoin/.lightning/${CLNETWORK}/cl.log_old
        notifempty
        nocompress
        sharedscripts
        # We don't need to kill as we use copytruncate
        #postrotate
        #        kill -HUP \`cat /run/lightningd/lightningd.pid\'
        #endscript
        su bitcoin bitcoin
}" | sudo tee /etc/logrotate.d/${netprefix}lightningd
  # debug: 
  # sudo logrotate --debug /etc/logrotate.d/lightningd 

  echo
  if ! grep -Eq "${netprefix}lightning-cli" /home/admin/_aliases; then
    echo "# Adding aliases"
    echo "\
alias ${netprefix}lightning-cli=\"sudo -u bitcoin /usr/local/bin/lightning-cli\
 --conf=${CLCONF}\"
alias ${netprefix}cl=\"sudo -u bitcoin /usr/local/bin/lightning-cli\
 --conf=${CLCONF}\"
alias ${netprefix}cllog=\"sudo\
 tail -n 30 -f /home/bitcoin/.lightning/${CLNETWORK}/cl.log\"
alias ${netprefix}clconf=\"sudo\
 nano ${CLCONF}\"
" | sudo tee -a /home/admin/_aliases
    sudo chown admin:admin /home/admin/_aliases
  fi

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

  # setting value in the raspiblitz.conf
  sudo sed -i "s/^${netprefix}cl=.*/${netprefix}cl=on/g" /mnt/hdd/raspiblitz.conf

  # if this is the first lightning mainnet turned on - make default
  if [ "${CHAIN}" == "mainnet" ] && [ "${lightning}" == "" ]; then
    echo "# CL is now the default lightning implementation"
    sudo sed -i "s/^lightning=.*/lightning=cl/g" /mnt/hdd/raspiblitz.conf
  fi

  exit 0
fi

if [ "$1" = "display-seed" ]; then
  
  # check if sudo
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (with sudo)"
    exit 1
  fi

  # get network and aliases from second parameter (default mainnet)
  displayNetwork=$2
  if [ "${displayNetwork}" == "" ]; then
    displayNetwork="mainnet"
  fi
  source <(/home/admin/config.scripts/network.aliases.sh getvars cl $displayNetwork)

  # check if seedword file exists
  seedwordFile="/home/bitcoin/.lightning/${CLNETWORK}/seedwords.info"
  echo "# seedwordFile(${seedwordFile})"
  seedwordFileExists=$(ls ${seedwordFile} 2>/dev/null | grep -c "seedwords.info")
  echo "# seedwordFileExists(${seewordFileExists})"
  if [ "${seedwordFileExists}" == "1" ]; then
    source ${seedwordFile}
    #echo "# seedwords(${seedwords})"
    #echo "# seedwords6x4(${seedwords6x4})"
    ack=0
    while [ ${ack} -eq 0 ]
    do
      whiptail --title "C-Lightning ${displayNetwork} Wallet" \
        --msgbox "This is your C-Lightning ${displayNetwork} wallet seed. Store these numbered words in a safe location:\n\n${seedwords6x4}" 13 76
      whiptail --title "Please Confirm" --yes-button "Show Again" --no-button "CONTINUE" --yesno "  Are you sure that you wrote down the word list?" 8 55
      if [ $? -eq 1 ]; then
        ack=1
      fi
    done
  else
    # hsmFile="/home/bitcoin/.lightning/${CLNETWORK}/hsm_secret"
    whiptail --title "C-Lightning ${displayNetwork} Wallet Info" --msgbox "Your C-Lightning ${displayNetwork} wallet was already created before - there are no seed words available.\n\nTo secure your wallet secret you can manually backup the file: /home/bitcoin/.lightning/${CLNETWORK}/hsm_secret" 11 76
  fi

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
  # setting value in the raspiblitz.conf
  sudo sed -i "s/^${netprefix}cl=.*/${netprefix}cl=off/g" /mnt/hdd/raspiblitz.conf

  # if cl mainnet was default - remove 
  if [ "${CHAIN}" == "mainnet" ] && [ "${lightning}" == "cl" ]; then
    echo "# CL is REMOVED as the default lightning implementation"
    sudo sed -i "s/^lightning=.*/lightning=/g" /mnt/hdd/raspiblitz.conf
    if [ "${lnd}" == "on" ]; then
      echo "# LND is now the new default lightning implementation"
      sudo sed -i "s/^lightning=.*/lightning=lnd/g" /mnt/hdd/raspiblitz.conf
    fi
  fi
fi
