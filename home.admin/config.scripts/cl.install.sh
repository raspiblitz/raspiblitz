#!/bin/bash
# https://lightning.readthedocs.io/

# https://github.com/ElementsProject/lightning/releases
CLVERSION=v0.12.0

# install the latest master by using the last commit id
# https://github.com/ElementsProject/lightning/commit/master
# CLVERSION="063366ed7e3b7cc12a8d1681acc2b639cf07fa23"

# https://github.com/ElementsProject/lightning/tree/master/contrib/keys
PGPsigner="niftynei" # rustyrussel D9200E6CD1ADB8F1 # cdecker A26D6D9FE088ED58
PGPpubkeyLink="https://raw.githubusercontent.com/ElementsProject/lightning/master/contrib/keys/${PGPsigner}.txt"
PGPpubkeyFingerprint="BFF0F67810C1EED1"

# help
if [ $# -eq 0 ]||[ "$1" = "-h" ]||[ "$1" = "--help" ];then
  echo
  echo "Core Lightning install script"
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

function installDependencies()
{
  echo "- installDependencies()"
  # from https://lightning.readthedocs.io/INSTALL.html#to-build-on-ubuntu
  sudo apt-get install -y \
   autoconf automake build-essential git libtool libgmp-dev \
   libsqlite3-dev python3 python3-mako net-tools zlib1g-dev libsodium-dev \
   gettext
  # additional requirements
  sudo apt-get install -y postgresql libpq-dev
  # mrkd and mistune needs to be globally available for the build
  sudo pip3 install mrkd==0.2.0
  sudo pip3 install mistune==0.8.4
  # poetry
  sudo -u bitcoin pip3 install --user poetry
  if ! grep -Eq '^PATH="$HOME/.local/bin:$PATH"' /mnt/hdd/raspiblitz.conf; then
    echo 'PATH="$HOME/.local/bin:$PATH"' | sudo tee -a /home/bitcoin/.profile
  fi
  export PATH="home/bitcoin/.local/bin:$PATH"
  sudo -u bitcoin /home/bitcoin/.local/bin/poetry install
}

function buildAndInstallCLbinaries()
{
  echo "- Configuring EXPERIMENTAL_FEATURES enabled"
  echo
  sudo -u bitcoin ./configure --enable-experimental-features
  echo
  echo "- Building Core lightning from source"
  echo
  sudo -u bitcoin make
  echo
  echo "- Install to /usr/local/bin/"
  sudo make install || exit 1
}

if [ "$1" = "install" ]; then

  echo "# *** INSTALL CORE LIGHTNING ${CLVERSION} BINARY ***"
  echo "# only binary install to system"
  echo "# no configuration, no systemd service"

  # check if the binary is already installed
  if [ -f /usr/local/bin/lightningd ]; then
    echo "Core Lightning binary already installed - done"
    exit 1
  fi

## Download and verify zip
#  # prepare download dir
#  sudo rm -rf /home/bitcoin/download
#  sudo -u bitcoin mkdir -p /home/bitcoin/download
#  cd /home/bitcoin/download || exit 1
#
#  sudo -u bitcoin wget -O "pgp_keys.asc" ${PGPpubkeyLink}
#  sudo -u bitcoin gpg --import --import-options show-only ./pgp_keys.asc
#  fingerprint=$(gpg "pgp_keys.asc" 2>/dev/null | grep "${PGPpubkeyFingerprint}" -c)
#  if [ ${fingerprint} -lt 1 ]; then
#    echo
#    echo "# WARNING --> the PGP fingerprint is not as expected for ${PGPsigner}"
#    echo "Should contain PGP: ${PGPpubkeyFingerprint}"
#    echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
#    read key
#  fi
#  sudo -u bitcoin gpg --import ./pgp_keys.asc
#
#  sudo -u bitcoin wget https://github.com/ElementsProject/lightning/releases/download/${CLVERSION}/SHA256SUMS
#  sudo -u bitcoin wget https://github.com/ElementsProject/lightning/releases/download/${CLVERSION}/SHA256SUMS.asc
#
#  verifyResult=$(LANG=en_US.utf8; sudo -u bitcoin gpg --verify SHA256SUMS.asc 2>&1)
#
#  goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
#  echo "goodSignature(${goodSignature})"
#  correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${PGPpubkeyFingerprint}" -c)
#  echo "correctKey(${correctKey})"
#  if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
#    echo
#    echo "# DOWNLOAD FAILED --> PGP verification not OK / signature(${goodSignature}) verify(${correctKey})"
#    exit 1
#  else
#    echo
#    echo "****************************************************************"
#    echo "OK --> the PGP signature of the Core Lightning SHA256SUMS is correct"
#    echo "****************************************************************"
#    echo
#  fi
#
#  sudo -u bitcoin wget https://github.com/ElementsProject/lightning/releases/download/${CLVERSION}/clightning-${CLVERSION}.zip
#
#  hashCheckResult=$(sha256sum -c SHA256SUMS 2>&1)
#  goodHash=$(echo ${hashCheckResult} | grep 'OK' -c)
#  echo "goodHash(${goodHash})"
#  if [ ${goodHash} -lt 1 ]; then
#    echo
#    echo "# BUILD FAILED --> Hash check not OK"
#    exit 1
#  else
#    echo
#    echo "********************************************************************"
#    echo "OK --> the hash of the downloaded Core Lightning source code is correct"
#    echo "********************************************************************"
#    echo
#  fi
#
#  sudo -u bitcoin unzip clightning-${CLVERSION}.zip
#  cd clightning-${CLVERSION} || exit 1

  # download and verify the source from github
  cd /home/bitcoin || exit 1
  echo
  echo "- Cloning https://github.com/ElementsProject/lightning.git"
  echo
  sudo -u bitcoin git clone https://github.com/ElementsProject/lightning.git
  cd lightning || exit 1
  echo
  echo "- Reset to version $CLVERSION"
  sudo -u bitcoin git reset --hard $CLVERSION

  sudo -u bitcoin /home/admin/config.scripts/blitz.git-verify.sh \
   "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" "${CLVERSION}" || exit 1

  installDependencies

  buildAndInstallCLbinaries

  installed=$(sudo -u bitcoin lightning-cli --version)
  if [ ${#installed} -eq 0 ]; then
    echo
    echo "# BUILD FAILED --> Was not able to install Core Lightning"
    exit 1
  fi

  correctVersion=$(echo "${installed}" | grep -c "${CLVERSION:1}")
  if [ "${correctVersion}" -eq 0 ]; then
    echo
    echo "# BUILD FAILED --> installed Core Lightning is not version ${CLVERSION}"
    sudo -u bitcoin lightning-cli --version
    exit 1
  fi
  echo
  echo "- OK the installation of Core Lightning v${installed} is successful"
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

  if [ "$1" = "update" ]||[ "$1" = "testPR" ];then

    echo "# apt update"
    echo
    sudo apt-get update

    cd /home/bitcoin || exit 1
    if [ "$1" = "update" ]||[ "$1" = "testPR" ];then
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
    fi

    installDependencies

    currentCLversion=$(cd /home/bitcoin/lightning 2>/dev/null; \
    git describe --tags 2>/dev/null)
    echo "# Building from source Core Lightning $currentCLversion"

    buildAndInstallCLbinaries
  fi

  ##########
  # Config #
  ##########

  # make sure binary is installed (will skip if already done)
  /home/admin/config.scripts/cl.install.sh install

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

  ## Create a wallet from seedwords for mainnet
  if [ ${CHAIN} = "mainnet" ]; then
    hsmSecretPath="/home/bitcoin/.lightning/${CLNETWORK}/hsm_secret"
    if sudo ls $hsmSecretPath; then
      echo "# $hsmSecretPath is already present"
    else
      echo "Create a wallet from seedwords for mainnet"
      /home/admin/config.scripts/cl.hsmtool.sh new-force mainnet 1>/dev/null 2>/dev/null
    fi
  fi

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
  sudo -u bitcoin mkdir /home/bitcoin/.lightning/${CLNETWORK}/cl.log_old
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
  sudo -u admin touch /home/admin/_aliases
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

  echo "# The installed Core Lightning version is: $(sudo -u bitcoin /usr/local/bin/lightningd --version)"
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

  # setting values in the raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}cl on
  # blitz.conf.sh needs sudo access - cannot be run in cl.check.sh
  if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/sparko ];then
    /home/admin/config.scripts/blitz.conf.sh set ${netprefix}sparko "off"
  fi
  if [ ! -f /home/bitcoin/cl-plugins-enabled/c-lightning-http-plugin ];then
    /home/admin/config.scripts/blitz.conf.sh set clHTTPplugin "off"
  fi
  if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/feeadjuster.py ]; then
    /home/admin/config.scripts/blitz.conf.sh set ${netprefix}feeadjuster "off"
  fi
  if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/cln-grpc ];then
    /home/admin/config.scripts/blitz.conf.sh set "${netprefix}clnGRPCport" "off"
  fi

  # if this is the first lightning mainnet turned on - make default
  if [ "${CHAIN}" == "mainnet" ] && [ "${lightning}" == "" ]; then
    echo "# CL is now the default lightning implementation"
    /home/admin/config.scripts/blitz.conf.sh set lightning cl
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
  echo "# seedwordFileExists(${seedwordFileExists})"
  if [ "${seedwordFileExists}" == "1" ]; then
    source ${seedwordFile}
    #echo "# seedwords(${seedwords})"
    #echo "# seedwords6x4(${seedwords6x4})"
    if [ ${#seedwords6x4} -gt 0 ];then
      ack=0
      while [ ${ack} -eq 0 ]
      do
        whiptail --title "Core Lightning ${displayNetwork} Wallet" \
          --msgbox "This is your Core Lightning ${displayNetwork} wallet seed. Store these numbered words in a safe location:\n\n${seedwords6x4}" 13 76
        whiptail --title "Please Confirm" --yes-button "Show Again" --no-button "CONTINUE" --yesno "  Are you sure that you wrote down the word list?" 8 55
        if [ $? -eq 1 ]; then
          ack=1
        fi
      done
    else
      dialog \
       --title "Core Lightning ${displayNetwork} Wallet" \
       --exit-label "exit" \
       --textbox "${seedwordFile}" 14 92
    fi
  else
    # hsmFile="/home/bitcoin/.lightning/${CLNETWORK}/hsm_secret"
    whiptail --title "Core Lightning ${displayNetwork} Wallet Info" --msgbox "Your Core Lightning ${displayNetwork} wallet was already created before - there are no seed words available.\n\nTo secure your wallet secret you can manually backup the file: /home/bitcoin/.lightning/${CLNETWORK}/hsm_secret" 11 76
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
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}cl "off"

  # if cl mainnet was default - remove
  if [ "${CHAIN}" == "mainnet" ] && [ "${lightning}" == "cl" ]; then
    echo "# Core Lightning is REMOVED as the default lightning implementation"
    /home/admin/config.scripts/blitz.conf.sh set lightning ""
    if [ "${lnd}" == "on" ]; then
      echo "# LND is now the new default lightning implementation"
      /home/admin/config.scripts/blitz.conf.sh set lightning "lnd"
    fi
  fi
fi
