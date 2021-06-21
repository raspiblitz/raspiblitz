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

source /home/admin/raspiblitz.info

# 1. parameter [info|tested|reckless]
mode="$1"

# RECOMMENDED UPDATE BY RASPIBLITZ TEAM
# comment will be shown as "BEWARE Info" when option is chosen (can be multiple lines) 
bitcoinVersion="0.21.0"

# needed to check code signing
laanwjPGP="01EA5486DE18A882D4C2684590C8019E36C2E964"

# GATHER DATA
# setting download directory
downloadDir="/home/admin/download"

# detect CPU architecture & fitting download link
if [ $(uname -m | grep -c 'arm') -eq 1 ] ; then
  bitcoinOSversion="arm-linux-gnueabihf"
fi
if [ $(uname -m | grep -c 'aarch64') -eq 1 ] ; then
  bitcoinOSversion="aarch64-linux-gnu"
fi
if [ $(uname -m | grep -c 'x86_64') -eq 1 ] ; then
  bitcoinOSversion="x86_64-linux-gnu"
fi

# installed version
installedVersion=$(sudo -u bitcoin bitcoind --version | head -n1| cut -d" " -f4|cut -c 2-)

# test if the installed version already the tested/recommended update version
bitcoinUpdateInstalled=$(echo "${installedVersion}" | grep -c "${bitcoinVersion}")

# get latest release from GitHub releases
gitHubLatestReleaseJSON="$(curl -s https://api.github.com/repos/bitcoin/bitcoin/releases | jq '.[0]')"
bitcoinLatestVersion=$(echo "${gitHubLatestReleaseJSON}"|jq -r '.tag_name'|cut -c 2-)

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
  echo "# Examples:"
  echo "0.21.1rc1"
  echo "0.21.0"
  echo
  read bitcoinVersion
  if [ $(echo ${bitcoinVersion} | grep -c "rc") -gt 0 ];then
    cutVersion=$(echo ${bitcoinVersion} | awk -F"r" '{print $1}')
    rcVersion=$(echo ${bitcoinVersion} | awk -F"r" '{print $2}')
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
if [ "${mode}" = "tested" ]||[ "${mode}" = "reckless" ]||[ "${mode}" = "custom" ]; then
  
  displayInfo

  if [ $installedVersion = $bitcoinVersion ];then
    echo "# installedVersion = bitcoinVersion"
    echo "# exiting script"
    exit 0
  fi

  echo 
  echo "# clean & change into download directory"
  sudo rm -r ${downloadDir}/*
  cd "${downloadDir}" || exit 1

  echo
  # download, check and import signer key
  sudo -u admin wget https://bitcoin.org/laanwj-releases.asc
  if [ ! -f "./laanwj-releases.asc" ]
  then
    echo "# !!! FAIL !!! Download laanwj-releases.asc not success."
    exit 1
  fi
  gpg --import-options show-only --import ./laanwj-releases.asc
  fingerprint=$(gpg ./laanwj-releases.asc 2>/dev/null | grep -c "${laanwjPGP}")
  if [ ${fingerprint} -eq 0 ]; then
    echo
    echo "# !!! BUILD WARNING --> Bitcoin PGP author not as expected"
    echo "# Should contain laanwjPGP: ${laanwjPGP}"
    echo "# PRESS ENTER to TAKE THE RISK if you think all is OK"
    read key
  fi
  gpg --import ./laanwj-releases.asc

  # download signed binary sha256 hash sum file and check
  sudo -u admin wget https://bitcoincore.org/bin/bitcoin-core-${pathVersion}/SHA256SUMS.asc
  verifyResult=$(gpg --verify SHA256SUMS.asc 2>&1)
  goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
  echo "goodSignature(${goodSignature})"
  correctKey=$(echo ${verifyResult} |  grep "using RSA key ${laanwjPGP: -16}" -c)
  echo "correctKey(${correctKey})"
  if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
    echo
    echo "# !!! BUILD FAILED --> PGP Verify not OK / signature(${goodSignature}) verify(${correctKey})"
    exit 1
  else
    echo
    echo "# OK --> BITCOIN MANIFEST IS CORRECT"
    echo
  fi

  echo "# Downloading Bitcoin Core v${bitcoinVersion} for ${bitcoinOSversion} ..."
  binaryName="bitcoin-${bitcoinVersion}-${bitcoinOSversion}.tar.gz"
  sudo -u admin wget https://bitcoincore.org/bin/bitcoin-core-${pathVersion}/${binaryName}
  if [ ! -f "./${binaryName}" ]
  then
    echo "# !!! FAIL !!! Downloading BITCOIN BINARY did not succeed."
    exit 1
  fi

  echo "# Checking binary checksum ..."
  checksumTest=$(sha256sum -c --ignore-missing SHA256SUMS.asc ${binaryName} 2>/dev/null \
                | grep -c "${binaryName}: OK")
  if [ "${checksumTest}" -eq 0 ]; then
    # get the sha256 value for the corresponding platform from signed hash sum file
    bitcoinSHA256=$(grep -i "$bitcoinOSversion" SHA256SUMS.asc | cut -d " " -f1)
    echo "!!! FAIL !!! Downloaded BITCOIN BINARY CHECKSUM:"
    echo "$(sha256sum ${binaryName})"
    echo "NOT matching SHA256 checksum:"
    echo "${bitcoinSHA256}"
    exit 1
  else
    echo
    echo "# OK --> VERIFIED BITCOIN CHECKSUM IS CORRECT"
    echo
  fi

fi 

if [ "${mode}" = "tested" ]||[ "${mode}" = "custom" ]; then
  bitcoinInterimsUpdateNew="${bitcoinVersion}"
elif [ "${mode}" = "reckless" ]; then
  bitcoinInterimsUpdateNew="reckless"
fi

# JOINED INSTALL
if [ "${mode}" = "tested" ]||[ "${mode}" = "reckless" ]||[ "${mode}" = "custom" ];then

  # install
  echo "# Stopping bitcoind and lnd ..."
  sudo systemctl stop lnd
  sudo systemctl stop bitcoind
  echo
  echo "# Installing Bitcoin Core v${bitcoinVersion}"
  sudo -u admin tar -xvf ${binaryName}
  sudo install -m 0755 -o root -g root -t /usr/local/bin/ bitcoin-${bitcoinVersion}/bin/*
  sleep 3
  installed=$(sudo -u admin bitcoind --version | grep "${bitcoinVersion}" -c)
  if [ ${installed} -lt 1 ]; then
    echo
    echo "# !!! BUILD FAILED --> Was not able to install bitcoind version(${bitcoinVersion})"
    exit 1
  fi
  echo "# flag update in raspiblitz config"
  source /mnt/hdd/raspiblitz.conf
  if [ ${#bitcoinInterimsUpdate} -eq 0 ]; then
    echo "bitcoinInterimsUpdate='${bitcoinInterimsUpdateNew}'" >> /mnt/hdd/raspiblitz.conf
  else
    sudo sed -i "s/^bitcoinInterimsUpdate=.*/bitcoinInterimsUpdate='${bitcoinInterimsUpdateNew}'/g" /mnt/hdd/raspiblitz.conf
  fi

  echo "# OK Bitcoin Core ${bitcoinVersion} is installed"
  if [ "${state}" == "ready" ]; then
    echo
    echo "# Starting ..."
    sudo systemctl start bitcoind
    sleep 10
    echo
    sudo systemctl start lnd
    echo "# Starting LND ..."
    sleep 10
    echo
    echo "# Press ENTER to proceed to unlock the LND wallet ..."
    read key
    sudo /home/admin/config.scripts/lnd.unlock.sh
  fi
  exit 0

else
  echo "# error='parameter not known'"
  exit 1
fi
