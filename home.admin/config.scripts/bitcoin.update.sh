#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Interim optional Bitcoin Core updates between RaspiBlitz releases."
  echo "bitcoin.update.sh [info|tested|reckless|custom]"
  echo "info -> get actual state and possible actions"
  echo "tested -> only do a tested update by the RaspiBlitz team"
  echo "reckless -> the update was not tested by the RaspiBlitz team"
  echo "custom -> update to a chosen version"
  echo " the binary will be checked by signature and checksum in all cases"
  echo
  exit 1
fi

# 1. parameter [info|tested|reckless]
mode="$1"

# RECOMMENDED UPDATE BY RASPIBLITZ TEAM (just possible once per sd card update)
# comment will be shown as "BEWARE Info" when option is choosen (can be multiple lines)
bitcoinVersion="" # example: 22.0 .. keep empty if no newer version as sd card build is available

# needed to check code signing
# https://github.com/emzy.gpg
fallbackSigner=Emzy

# GATHER DATA
# setting download directory to the current user
downloadDir="/home/$(whoami)/download/bitcoin.update"

# detect CPU architecture & fitting download link
if [ $(uname -m | grep -c 'arm') -eq 1 ]; then
  bitcoinOSversion="arm-linux-gnueabihf"
fi
if [ $(uname -m | grep -c 'aarch64') -eq 1 ]; then
  bitcoinOSversion="aarch64-linux-gnu"
fi
if [ $(uname -m | grep -c 'x86_64') -eq 1 ]; then
  bitcoinOSversion="x86_64-linux-gnu"
fi

# installed version
installedVersion=$(sudo -u bitcoin bitcoind --version | head -n1 | cut -d" " -f4 | cut -c 2-)

# test if the installed version already the tested/recommended update version
bitcoinUpdateInstalled=$(echo "${installedVersion}" | grep -c "${bitcoinVersion}")

# get latest release from GitHub releases
bitcoinLatestVersion=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s https://api.github.com/repos/bitcoin/bitcoin/releases | jq -r '.[].tag_name' | sort | tail -n1 | cut -c 2-)

# INFO
function displayInfo() {
  echo "# basic data"
  echo "installedVersion='${installedVersion}'"
  echo "bitcoinOSversion='${bitcoinOSversion}'"

  echo "# the tested/recommended update option"
  echo "bitcoinUpdateInstalled='${bitcoinUpdateInstalled}'"
  echo "bitcoinVersion='${bitcoinVersion}'"

  echo "# reckless update option (latest Bitcoin Core release from GitHub)"
  echo "bitcoinLatestVersion='${bitcoinLatestVersion}'"
}

if [ "${mode}" = "info" ]; then
  displayInfo
  exit 1
fi

# tested
if [ "${mode}" = "tested" ]; then

  echo "# bitcoin.update.sh tested"

  # check for optional second parameter: forced update version
  # --> only does the tested update if its the given version
  # this is needed for recovery/update.
  fixedBitcoinVersion="$2"
  if [ ${#fixedBitcoinVersion} -gt 0 ]; then
    echo "# checking for fixed version update: askedFor(${bitcoinVersion}) available(${bitcoinVersion})"
    if [ "${fixedBitcoinVersion}" != "${bitcoinVersion}" ]; then
      echo "# warn='required update version does not match'"
      echo "# this is normal when the recovery script of a new RaspiBlitz version checks for an old update - just ignore"
      exit 1
    else
      echo "# OK - update version is matching"
    fi
  fi
  pathVersion=${bitcoinVersion}

elif [ "${mode}" = "reckless" ]; then
  # RECKLESS
  # this mode is just for people running test and development nodes - its not recommended
  # for production nodes. In a update/recovery scenario it will not install a fixed version
  # it will always pick the latest release from the github
  echo "# bitcoin.update.sh reckless"
  bitcoinVersion=${bitcoinLatestVersion}
  pathVersion=${bitcoinVersion}

elif [ "${mode}" = "custom" ]; then
  clear
  echo
  echo "# Update Bitcoin Core to a chosen version."
  echo
  echo "# Input the version you would like to install and press ENTER."
  echo "# Examples (versions below 22 are not supported):"
  echo "22.0rc3"
  echo "24.0.1"
  echo
  read bitcoinVersion
  if [ $(echo ${bitcoinVersion} | grep -c "rc") -gt 0 ]; then
    cutVersion=$(echo ${bitcoinVersion} | awk -F"r" '{print $1}')
    rcVersion=$(echo ${bitcoinVersion} | awk -F"r" '{print $2}')
    # https://bitcoincore.org/bin/bitcoin-core-22.0/test.rc3/
    pathVersion=${cutVersion}/test.r${rcVersion}
  else
    pathVersion=${bitcoinVersion}
  fi

  if curl --output /dev/null --silent --head --fail \
    https://bitcoincore.org/bin/bitcoin-core-${pathVersion}/SHA256SUMS.asc; then
    echo "# OK version exists at https://bitcoincore.org/bin/bitcoin-core-${pathVersion}"
    echo "# Press ENTER to proceed to install Bitcoin Core $bitcoinVersion or CTRL+C to abort."
    read key
  else
    echo "# FAIL $bitcoinVersion does not exist"
    echo
    echo "# Press ENTER to return to the main menu"
    read key
    exit 0
  fi
fi

# JOINED INSTALL
if [ "${mode}" = "tested" ] || [ "${mode}" = "reckless" ] || [ "${mode}" = "custom" ]; then

  displayInfo

  if [ "$installedVersion" = "$bitcoinVersion" ]; then
    echo "# installedVersion = bitcoinVersion"
    echo "# exiting script"
    exit 0
  fi

  echo
  echo "# clean & change into download directory"
  sudo rm -rf "${downloadDir}"
  mkdir -p "${downloadDir}"
  cd "${downloadDir}" || exit 1

  # NOTE: this script is run by provision and cannot have user input at this point or it will lock up the provision process
  # echo "# Enter the github username of a signer. Find the list of signers at: "
  # echo "https://github.com/bitcoin-core/guix.sigs/tree/main/${pathVersion}"
  # echo "# Example for Peter Wuille (https://github.com/sipa):"
  # echo "sipa"
  # echo "# example for Emzy (https://github.com/Emzy):"
  # echo "Emzy"
  # read customSigner
  # if [ ${#customSigner} -eq 0 ]; then
  #   customSigner=$fallbackSigner
  # fi
  customSigner=$fallbackSigner

  echo "# Download the binary sha256 hash sum file"
  wget -O all.SHA256SUMS https://raw.githubusercontent.com/bitcoin-core/guix.sigs/main/${pathVersion}/${customSigner}/all.SHA256SUMS
  echo "# Download signature of the binary sha256 hash sum file"
  wget -O all.SHA256SUMS.asc https://raw.githubusercontent.com/bitcoin-core/guix.sigs/main/${pathVersion}/${customSigner}/all.SHA256SUMS.asc

  echo "# Download PGP pubkey of ${customSigner}"
  if ! wget -O pubkey.asc https://github.com/${customSigner}.gpg; then
    echo "# FAIL # Could not down
    load the PGP pubkey of ${customSigner}"
    rm pubkey.asc
    exit 1
  fi
  echo "# Import PGP pubkey of ${customSigner}"
  if ! gpg --import pubkey.asc; then
    echo "# FAIL # Couldn't import the PGP pubkey of ${customSigner}"
    rm pubkey.asc
    exit 1
  fi
  rm pubkey.asc

  echo "# Checking PGP signature of the binary sha256 hash sum file"
  if ! gpg --verify all.SHA256SUMS.asc; then
    echo
    echo "# BUILD FAILED --> the signature does not match"
    exit 1
  else
    echo
    echo "# OK --> BITCOIN MANIFEST IS CORRECT"
    echo
  fi

  echo "# Downloading Bitcoin Core v${bitcoinVersion} for ${bitcoinOSversion} ..."
  binaryName="bitcoin-${bitcoinVersion}-${bitcoinOSversion}.tar.gz"
  wget https://bitcoincore.org/bin/bitcoin-core-${pathVersion}/${binaryName}
  if [ ! -f "./${binaryName}" ]; then
    echo "# FAIL # Downloading BITCOIN BINARY did not succeed."
    exit 1
  fi

  echo "# Checking the binary checksum ..."
  if ! sha256sum -c --ignore-missing all.SHA256SUMS; then
    # get the sha256 value for the corresponding platform from signed hash sum file
    bitcoinSHA256=$(grep -i "${binaryName}}" all.SHA256SUMS | cut -d " " -f1)
    echo "# FAIL # Downloaded BITCOIN BINARY CHECKSUM:"
    echo "$(sha256sum ${binaryName})"
    echo "NOT matching SHA256 checksum:"
    echo "${bitcoinSHA256}"
    exit 1
  else
    echo
    echo "# OK --> VERIFIED BITCOIN CORE BINARY CHECKSUM IS CORRECT"
    echo
  fi
fi

if [ "${mode}" = "tested" ] || [ "${mode}" = "custom" ]; then
  bitcoinInterimsUpdateNew="${bitcoinVersion}"
elif [ "${mode}" = "reckless" ]; then
  bitcoinInterimsUpdateNew="reckless"
fi

# JOINED INSTALL
if [ "${mode}" = "tested" ] || [ "${mode}" = "reckless" ] || [ "${mode}" = "custom" ]; then

  # install
  echo "# Stopping bitcoind ..."
  sudo systemctl stop bitcoind 2>/dev/null
  sudo systemctl stop tbitcoind 2>/dev/null
  sudo systemctl stop sbitcoind 2>/dev/null
  echo
  echo "# Installing Bitcoin Core v${bitcoinVersion}"
  tar -xvf ${binaryName}
  sudo install -m 0755 -o root -g root -t /usr/local/bin/ bitcoin-${bitcoinVersion}/bin/*
  sleep 3
  if ! bitcoind --version | grep "${bitcoinVersion}"; then
    echo
    echo "# BUILD FAILED --> Was not able to install bitcoind version(${bitcoinVersion})"
    exit 1
  fi

  echo "# mark update in raspiblitz config"
  /home/admin/config.scripts/blitz.conf.sh set bitcoinInterimsUpdate "${bitcoinInterimsUpdateNew}"

  echo "# OK Bitcoin Core ${bitcoinVersion} is installed"
  exit 0

else
  echo "# error='parameter not known'"
  exit 1
fi
