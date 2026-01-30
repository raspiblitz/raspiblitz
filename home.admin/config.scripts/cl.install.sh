#!/bin/bash
# https://lightning.readthedocs.io/

# https://github.com/ElementsProject/lightning/releases
CLVERSION="v25.12.1"

# https://github.com/ElementsProject/lightning/tree/master/contrib/keys
# rustyrussell D9200E6CD1ADB8F1
# cdecker A26D6D9FE088ED58
# niftynei BFF0F67810C1EED1
# pneuroth (nepet) C3F21EE387FF4CD2
# sfarooqui (ShahanaFarooqui) B56B4453DA8C6DF7FC9BCFCBDCA40B7128DA62A8
# amyers (endothermicdev) F3BF63F2747436AB
# madel (Madeline Paech) A57AFC231B580804
# cln (cln@blockstream.com) 616C52F99D0612B2A151B1074129A994AA7E9852
PGPsigner="cln"
PGPpubkeyLink="https://raw.githubusercontent.com/ElementsProject/lightning/master/contrib/keys/${PGPsigner}.txt"
PGPpubkeyFingerprint="616C52F99D0612B2A151B1074129A994AA7E9852"

# help
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo
  echo "Core Lightning install script"
  echo "The default version is: ${CLVERSION}"
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

function installDependencies() {
  echo "- installDependencies()"
  # from https://docs.corelightning.org/docs/installation#to-build-on-ubuntu
  # apt packages
  sudo apt-get install -y \
    autoconf automake build-essential git libtool libsqlite3-dev libffi-dev \
    python3 python3-pip python3-mako net-tools zlib1g-dev libsodium-dev gettext lowdown
  # additional requirements (postgres support)
  sudo apt-get install -y libpq-dev

  # rust deps for cln-grpc and clnrest plugins
  echo "# Install Rust to /opt/rust/"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sudo RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/rust sh -s -- --no-modify-path -y
  echo "# Set /opt/rust write access for rust group"
  if ! getent group rust >/dev/null 2>&1; then
    sudo groupadd rust
  fi
  sudo chown -R root:rust /opt/rust
  sudo chmod -R g+w /opt/rust
  sudo usermod -a -G rust bitcoin
  echo "# Set the default Rust toolchain"
  sudo RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/rust /opt/rust/bin/rustup default stable
  # Ensure permissions are correct after rustup operations
  sudo chown -R root:rust /opt/rust
  sudo chmod -R g+w /opt/rust
  echo "# Make Rust binaries available system-wide"
  sudo ln -sf /opt/rust/bin/* /usr/local/bin/
  echo "# Set up system-wide environment variables for Rust"
  if ! grep -q "RUSTUP_HOME=/opt/rust" /etc/environment; then
    echo 'RUSTUP_HOME=/opt/rust' | sudo tee -a /etc/environment
  fi
  if ! grep -q "CARGO_HOME=/opt/rust" /etc/environment; then
    echo 'CARGO_HOME=/opt/rust' | sudo tee -a /etc/environment
  fi

  # Install uv for Python dependency management (replaces poetry in CLN 25.x+)
  echo "# Installing uv for Python dependency management"
  if ! command -v uv &>/dev/null; then
    sudo RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/rust cargo install --locked uv || exit 1
    # Ensure uv is symlinked into /usr/local/bin
    sudo ln -sf /opt/rust/bin/uv /usr/local/bin/uv
  fi

  # Sync Python dependencies with uv
  cd /home/bitcoin/lightning || exit 1
  sudo -u bitcoin RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/rust uv sync --all-extras --all-groups --frozen

  sudo apt-get install -y protobuf-compiler

  # remove old clnrest dir if exists
  if [ -d /usr/local/libexec/c-lightning/plugins/clnrest ]; then
    sudo rm -rf /usr/local/libexec/c-lightning/plugins/clnrest
  fi
}

function buildAndInstallCLbinaries() {
  # Optional parameter: version to pass to make (for zip builds without git)
  local buildVersion="$1"

  cd /home/bitcoin/lightning || exit 1

  # Ensure /opt/rust has correct permissions before building
  echo "# Ensuring /opt/rust permissions for rust group"
  sudo chown -R root:rust /opt/rust
  sudo chmod -R g+w /opt/rust

  echo
  echo "########## configure"
  sudo -u bitcoin RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/rust ./configure || exit 1
  echo
  echo "########## make (using uv run)"
  # Pass VERSION to make if provided (needed for zip builds without git history)
  if [ -n "${buildVersion}" ]; then
    sudo -u bitcoin RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/rust VERSION="${buildVersion}" uv run make -j"$(nproc)" || exit 1
  else
    sudo -u bitcoin RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/rust uv run make -j"$(nproc)" || exit 1
  fi
  echo
  echo "########## install"
  sudo RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/rust make install || exit 1
}

function downloadAndVerifySourceZip() {
  # Downloads, verifies, and extracts the CLN source zip
  # Uses CLVERSION variable for the version to download
  cd /home/bitcoin || exit 1
  echo
  echo "- Downloading Core Lightning ${CLVERSION} source release"
  echo

  # Download the source zip and SHA256SUMS signature file
  sudo -u bitcoin wget -O "clightning-${CLVERSION}.zip" \
    "https://github.com/ElementsProject/lightning/releases/download/${CLVERSION}/clightning-${CLVERSION}.zip" || exit 1
  sudo -u bitcoin wget -O "SHA256SUMS-${CLVERSION}" \
    "https://github.com/ElementsProject/lightning/releases/download/${CLVERSION}/SHA256SUMS-${CLVERSION}" || exit 1
  sudo -u bitcoin wget -O "SHA256SUMS-${CLVERSION}.asc" \
    "https://github.com/ElementsProject/lightning/releases/download/${CLVERSION}/SHA256SUMS-${CLVERSION}.asc" || exit 1

  echo
  echo "- Importing PGP key of ${PGPsigner} for verification"
  echo

  # Import PGP key
  sudo -u bitcoin wget -O "/var/cache/raspiblitz/pgp_keys_${PGPsigner}.asc" "${PGPpubkeyLink}" || exit 1
  echo "# Verifying ${PGPsigner} key fingerprint"
  fingerprint=$(gpg --show-keys --keyid-format LONG "/var/cache/raspiblitz/pgp_keys_${PGPsigner}.asc" 2>/dev/null | grep -c "${PGPpubkeyFingerprint}")
  if [ "${fingerprint}" -lt 1 ]; then
    echo "# ERROR --> ${PGPsigner} PGP fingerprint mismatch"
    exit 1
  fi
  sudo -u bitcoin gpg --import "/var/cache/raspiblitz/pgp_keys_${PGPsigner}.asc" || exit 1

  echo
  echo "- Verifying SHA256SUMS signature"
  echo

  # Verify the signature on SHA256SUMS
  sudo -u bitcoin gpg --verify "SHA256SUMS-${CLVERSION}.asc" "SHA256SUMS-${CLVERSION}" 2>&1 | tee /tmp/cl_gpg_verify.txt
  goodSignature=$(grep -c "Good signature" /tmp/cl_gpg_verify.txt)
  if [ "${goodSignature}" -lt 1 ]; then
    echo "# ERROR --> SHA256SUMS signature verification failed"
    exit 1
  fi
  echo "# OK - SHA256SUMS signature verified"

  echo
  echo "- Verifying source zip checksum"
  echo

  # Verify the zip file checksum
  expectedChecksum=$(grep "clightning-${CLVERSION}.zip" "SHA256SUMS-${CLVERSION}" | awk '{print $1}')
  actualChecksum=$(sha256sum "clightning-${CLVERSION}.zip" | awk '{print $1}')
  if [ "${expectedChecksum}" != "${actualChecksum}" ]; then
    echo "# ERROR --> Checksum mismatch for clightning-${CLVERSION}.zip"
    echo "# Expected: ${expectedChecksum}"
    echo "# Actual: ${actualChecksum}"
    exit 1
  fi
  echo "# OK - Checksum verified for clightning-${CLVERSION}.zip"

  echo
  echo "- Extracting source"
  echo

  # Extract and set up directory
  sudo -u bitcoin unzip -q "clightning-${CLVERSION}.zip" || exit 1
  sudo -u bitcoin rm -rf lightning
  sudo -u bitcoin mv "clightning-${CLVERSION}" lightning
  sudo -u bitcoin rm -f "clightning-${CLVERSION}.zip" "SHA256SUMS-${CLVERSION}" "SHA256SUMS-${CLVERSION}.asc"
}

function runTests() {
  # Test dependencies are managed by uv sync in installDependencies()
  cd /home/bitcoin/lightning || exit 1
  echo "- run tests (using uv run)"
  echo
  sudo -u bitcoin RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/rust uv run make check VALGRIND=0 || exit 1
}

echo "# Running: 'cl.install.sh $*'"

# check for version if specified
if [ "$1" = "update" ] && [ $# -gt 1 ]; then
  CLVERSION=$2
  if curl --output /dev/null --silent --head --fail \
    https://github.com/ElementsProject/lightning/releases/tag/${CLVERSION}; then
    echo "# OK version exists at https://github.com/ElementsProject/lightning/releases/tag/${CLVERSION}"
  else
    echo "# ${CLVERSION} does not exist"
    echo
    echo "# Exiting 'cl.install.sh $*' script"
    exit 1
  fi
fi

# check for PR if testPR
if [ "$1" = "testPR" ]; then
  if [ $# -gt 1 ]; then
    PRnumber=$2
  else
    echo "# Need PRnumber as the second paramater"
  fi
  echo "# Using the PR:"
  echo "# https://github.com/ElementsProject/lightning/pull/${PRnumber}"
  if curl --output /dev/null --silent --head --fail \
    https://github.com/ElementsProject/lightning/pull/${PRnumber}; then
    echo "# OK the PR exists at https://github.com/ElementsProject/lightning/pull/${PRnumber}"
    echo "# Press ENTER to proceed to install Core Lightning with the PR ${PRnumber} or CTRL+C to abort."
    read key
  else
    echo "# ${PRnumber} does not exist"
    echo
    echo "# Press ENTER to return to the main menu"
    read key
    exit 1
  fi
fi

if [ "$1" = "install" ]; then

  echo "# *** INSTALL CORE LIGHTNING ${CLVERSION} BINARY ***"
  echo "# only binary install to system"
  echo "# no configuration, no systemd service"

  # check if the binary is already installed
  if [ -f /usr/local/bin/lightningd ]; then
    echo "Core Lightning binary already installed - done"
    exit 0
  fi

  # download and verify the source from github
  downloadAndVerifySourceZip

  installDependencies

  # Pass version since zip has no git history
  buildAndInstallCLbinaries "${CLVERSION}" || exit 1

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
  echo "- OK the installation of Core Lightning ${installed} is successful"
  exit 0
fi

# vars
source /home/admin/raspiblitz.info
source /mnt/hdd/app-data/raspiblitz.conf
TORGROUP="debian-tor"

if [ "$1" = update ] || [ "$1" = testPR ]; then
  source <(/home/admin/config.scripts/network.aliases.sh getvars cl mainnet)
else
  source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)
fi

echo "# Using the settings for: ${network} ${CHAIN}"

if [ "$1" = on ] || [ "$1" = update ] || [ "$1" = testPR ]; then

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

  if [ "$1" = "update" ] || [ "$1" = "testPR" ]; then

    echo "# apt update"
    echo
    sudo apt-get update

    cd /home/bitcoin || exit 1
    echo
    echo "# Deleting the old source code"
    sudo rm -rf lightning

    # Track if we're building from zip (no git history) or git clone
    buildFromZip=0

    if [ "$1" = "update" ] && [ $# -gt 1 ]; then
      # Update to a specific version - use zip download with signature verification
      CLVERSION=$2
      downloadAndVerifySourceZip
      buildFromZip=1

    elif [ "$1" = "update" ]; then
      # Update to latest commit - use git clone (no verification)
      echo
      echo "# Cloning https://github.com/ElementsProject/lightning.git"
      echo
      sudo -u bitcoin git clone https://github.com/ElementsProject/lightning.git
      cd lightning || exit 1
      echo
      echo "# Updating to the latest commit in:"
      echo "# https://github.com/ElementsProject/lightning"
      echo "# Make sure this is intended, there might be no way to downgrade your database"
      echo "# Press ENTER to continue or CTRL+C to abort the update"
      read -r key

    elif [ "$1" = "testPR" ]; then
      # Test a PR - use git clone
      echo
      echo "# Cloning https://github.com/ElementsProject/lightning.git"
      echo
      sudo -u bitcoin git clone https://github.com/ElementsProject/lightning.git
      cd lightning || exit 1
      echo
      PRnumber=$2 || exit 1
      echo "# Using the PR:"
      echo "# https://github.com/ElementsProject/lightning/pull/${PRnumber}"
      sudo -u bitcoin git fetch origin pull/${PRnumber}/head:pr${PRnumber} || exit 1
      sudo -u bitcoin git checkout pr${PRnumber} || exit 1
    fi

    installDependencies

    if [ "${buildFromZip}" = "1" ]; then
      echo "# Building from source Core Lightning ${CLVERSION}"
      buildAndInstallCLbinaries "${CLVERSION}" || exit 1
    else
      currentCLversion=$(
        cd /home/bitcoin/lightning || exit 1
        git describe --tags 2>/dev/null || echo "unknown"
      )
      echo "# Building from source Core Lightning $currentCLversion"
      buildAndInstallCLbinaries || exit 1
    fi

  fi

  ##########
  # Config #
  ##########

  # make sure binary is installed (will skip if already done)
  /home/admin/config.scripts/cl.install.sh install || exit 1

  echo "# Make sure bitcoin is in the ${TORGROUP} group"
  sudo usermod -a -G ${TORGROUP} bitcoin

  echo "# Add plugin-dir: /home/bitcoin/${netprefix}cl-plugins-enabled"
  echo "# Add plugin-dir: /home/bitcoin/cl-plugins-available"
  # note that the disk is mounted with noexec
  sudo -u bitcoin mkdir /home/bitcoin/${netprefix}cl-plugins-enabled 2>/dev/null
  sudo -u bitcoin mkdir /home/bitcoin/cl-plugins-available 2>/dev/null

  echo "# Store the lightning data in /mnt/hdd/app-data/.lightning"
  # Create the main and network-specific lightning directories
  sudo mkdir -p "/mnt/hdd/app-data/.lightning/${CLNETWORK}"
  sudo chown -R bitcoin:bitcoin /mnt/hdd/app-data/.lightning
  echo "# Symlink to /home/bitcoin/"
  sudo rm -rf /home/bitcoin/.lightning # not a symlink, delete
  sudo ln -s /mnt/hdd/app-data/.lightning /home/bitcoin/
  echo "# Symlink to /home/admin/"
  sudo rm -rf /home/admin/.lightning # not a symlink, delete
  sudo ln -s /mnt/hdd/app-data/.lightning /home/admin/

  if ! sudo ls ${CLCONF} 2>/dev/null; then
    echo "# Create ${CLCONF}"
    echo "# lightningd configuration for ${network} ${CHAIN}

network=${CLNETWORK}
log-file=cl.log
log-level=info
plugin-dir=/home/bitcoin/${netprefix}cl-plugins-enabled
clnrest-port=${portprefix}7378
clnrest-host=0.0.0.0
grpc-port=${portprefix}4772

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
  /home/admin/config.scripts/cl-plugin.backup.sh on ${CHAIN}

  ###################
  # Systemd service #
  ###################
  /home/admin/config.scripts/cl.install-service.sh ${CHAIN}

  #############
  # logrotate #
  #############
  echo
  echo "# Set logrotate for ${netprefix}lightningd"
  if ! sudo ls /home/bitcoin/.lightning/${CLNETWORK}/cl.log_old 2>/dev/null; then
    sudo -u bitcoin mkdir /home/bitcoin/.lightning/${CLNETWORK}/cl.log_old
  fi
  echo "\
/home/bitcoin/.lightning/${CLNETWORK}/cl.log
{
        rotate 4
        size 100M
        copytruncate
        missingok
        olddir /home/bitcoin/.lightning/${CLNETWORK}/cl.log_old
        notifempty
        nocompress
        sharedscripts
        su bitcoin bitcoin
}" | sudo tee /etc/logrotate.d/${netprefix}lightningd
  # debug:
  # sudo logrotate --debug /etc/logrotate.d/lightningd
  echo
  sudo -u admin touch /home/admin/_aliases
  if ! grep -Eq "^alias ${netprefix}lightning-cli" /home/admin/_aliases; then
    echo "# Adding aliases: ${netprefix}cl, ${netprefix}cllog, ${netprefix}clconf"
    echo "\
alias ${netprefix}cl=\"sudo -u bitcoin /usr/local/bin/lightning-cli\
 --conf=${CLCONF}\"
alias ${netprefix}cllog=\"sudo\
 tail -n 30 -f /home/bitcoin/.lightning/${CLNETWORK}/cl.log\"
alias ${netprefix}clconf=\"sudo nano ${CLCONF}\"
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
  if [ ! -f /home/bitcoin/cl-plugins-enabled/c-lightning-http-plugin ]; then
    /home/admin/config.scripts/blitz.conf.sh set clHTTPplugin "off"
  fi
  if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/feeadjuster.py ]; then
    /home/admin/config.scripts/blitz.conf.sh set ${netprefix}feeadjuster "off"
  fi
  if [ ! -f /home/bitcoin/${netprefix}cl-plugins-enabled/cln-grpc ]; then
    /home/admin/config.scripts/blitz.conf.sh set "${netprefix}clnGRPCport" "off"
  fi

  # if this is the first lightning mainnet turned on - make default
  [ "${lightning}" == "none" ] && lightning=""
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
    if [ ${#seedwords6x4} -gt 0 ]; then
      ack=0
      while [ ${ack} -eq 0 ]; do
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

if [ "$1" = "off" ]; then
  echo "# Removing the ${netprefix}lightningd.service"
  sudo systemctl disable ${netprefix}lightningd
  sudo systemctl stop ${netprefix}lightningd
  echo "# Removing the aliases"
  sudo sed -i "/${netprefix}lightning-cli/d" /home/admin/_aliases
  sudo sed -i "/${netprefix}cl/d" /home/admin/_aliases
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ]; then
    echo "# Removing the binaries"
    sudo rm -f /usr/local/bin/lightningd
    sudo rm -f /usr/local/bin/lightning-cli
    echo "# Removing the source code"
    sudo rm -rf /home/bitcoin/lightning
  fi
  # setting value in the raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}cl "off"

  # if cl mainnet was default - remove
  if [ "${CHAIN}" == "mainnet" ] && [ "${lightning}" == "cl" ]; then
    echo "# Core Lightning is REMOVED as the default lightning implementation"
    /home/admin/config.scripts/blitz.conf.sh set lightning "none"
    if [ "${lnd}" == "on" ]; then
      echo "# LND is now the new default lightning implementation"
      /home/admin/config.scripts/blitz.conf.sh set lightning "lnd"
    fi
  fi
fi
