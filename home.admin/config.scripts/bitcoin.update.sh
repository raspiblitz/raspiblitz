#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "Interim optional Bitcoin Core updates between RaspiBlitz releases."
  echo "bitcoin.update.sh [info|tested|reckless|custom]"
  echo "info -> get actual state and possible actions"
  echo "tested -> only do a tested update by the RaspiBlitz team"
  echo "reckless -> the update was not tested by the RaspiBlitz team"
  echo "custom <version> <skipverify> -> update to a chosen version"
  echo " the binary checksum and signatures will be checked in all cases"
  echo " except when 'skipverify' is used"
  echo
  exit 1
fi

echo "# Running: bitcoin.update.sh $*"

# 1. parameter [info|tested|reckless]
mode="$1"

#4792 QUICK FIX --> downgrade reckless to tested
# TODO: Remove with RaspiBlitz v1.12.0
if [ "${mode}" = "reckless" ]; then
  echo "# WARN: reckless mode is temp deactivated - switching to tested"
  mode="tested"
fi

# RECOMMENDED UPDATE BY RASPIBLITZ TEAM (latest tested version available)
bitcoinVersion="27.1" # example: 22.0 .. keep empty if no newer version as sd card build is available

# GATHER DATA
# setting download directory to the current user
downloadDir="/home/$(whoami)/download/bitcoin.update"

# bitcoinOSversion
if [ "$(uname -m | grep -c 'arm')" -gt 0 ]; then
  bitcoinOSversion="arm-linux-gnueabihf"
elif [ "$(uname -m | grep -c 'aarch64')" -gt 0 ]; then
  bitcoinOSversion="aarch64-linux-gnu"
elif [ "$(uname -m | grep -c 'x86_64')" -gt 0 ]; then
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

# COMAPRE TWO VERSION STRINGS
# 0 = first version string is equal
# 1 = first version string is older
# 2 = first version string is newer
function version_compare() {
    if [[ $1 == $2 ]]
    then
        echo "equal"
        return 0
    fi
    IFS='.' read -r -a ver1 <<< "$1"
    IFS='.' read -r -a ver2 <<< "$2"
    len1=${#ver1[@]}
    len2=${#ver2[@]}
    max_len=$((len1>len2?len1:len2))
    for ((i=0; i<max_len; i++))
    do
        part1=${ver1[i]:-0}
        part2=${ver2[i]:-0}
        if ((part1 < part2))
        then
            # older
            return 1
        elif ((part1 > part2))
        then
            # newer
            return 2
        fi
    done
    # equal
    return 0
}

if [ "${mode}" = "info" ]; then
  displayInfo
  exit 1
fi

# tested
if [ "${mode}" = "tested" ]; then

  echo "# bitcoin.update.sh tested"

  # check if a tested update is available
  if [ ${#bitcoinVersion} -eq 0 ]; then
    echo "# warn='no tested update available'"
    echo "# thats OK on update from older versions"
    /home/admin/config.scripts/blitz.conf.sh delete bitcoinInterimsUpdate 2>/dev/null
    exit 1
  fi

  # check for optional second parameter: forced update version
  fixedBitcoinVersion="$2"
  if [ ${#fixedBitcoinVersion} -gt 0 ]; then
    echo "# checking for fixed version update: installed(${installedVersion}) requested(${fixedBitcoinVersion}) available(${bitcoinVersion})"
    version_compare "${fixedBitcoinVersion}" "${bitcoinVersion}"
    result=$?
    if [ "${result}" -eq 2 ]; then
      echo "# WARNING: requested version is newer then available tested --> ABORT (already up2date)"
      exit 1
    else
      echo "# requested version is older or equal --> OK install available tested version"
    fi
  fi

  # check against installed version
  version_compare "${installedVersion}" "${bitcoinVersion}"
  result=$?
  if [ "${result}" -eq 2 ]; then
    # this can happen if bitcoin install script already has a higher version then the tested version set by this script (see above)
    echo "# installed version is newer then to be updated version --> ABORT"
    echo 
    exit 1
  fi
  if [ "${result}" -eq 0 ]; then
    echo "# version is already installed --> ABORT"
    echo 
    exit 1
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
  if [ $# -gt 1 ]; then
    bitcoinVersion="$2"
  else
    clear
    echo
    echo "# Update Bitcoin Core to a chosen version."
    echo
    echo "# Input the version you would like to install and press ENTER."
    echo "# Examples (versions below 22.1 are not supported):"
    echo "24.0.1"
    echo "26.0"
    echo
    read bitcoinVersion
  fi

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
    if [ "${mode}" = "custom" ] && [ "$3" = "skipverify" ]; then
      echo "# skipping signature verification"
    fi
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

  echo "# Receive signer keys"
  curl -s "https://api.github.com/repos/bitcoin-core/guix.sigs/contents/builder-keys" |
    jq -r '.[].download_url' | while read url; do curl -s "$url" | gpg --import; done

  # download signed binary sha256 hash sum file
  wget --prefer-family=ipv4 --progress=bar:force -O SHA256SUMS https://bitcoincore.org/bin/bitcoin-core-${bitcoinVersion}/SHA256SUMS
  # download the signed binary sha256 hash sum file and check
  wget --prefer-family=ipv4 --progress=bar:force -O SHA256SUMS.asc https://bitcoincore.org/bin/bitcoin-core-${bitcoinVersion}/SHA256SUMS.asc

  if [ "${mode}" = "custom" ] && [ "$3" = "skipverify" ]; then
    echo "# skipping signature verification"
    echo "# display the output of 'gpg --verify SHA256SUMS.asc'"
    gpg --verify SHA256SUMS.asc
  else
    if gpg --verify SHA256SUMS.asc; then
      echo
      echo "****************************************"
      echo "OK --> BITCOIN MANIFEST IS CORRECT"
      echo "****************************************"
      echo
    else
      echo
      echo "# BUILD FAILED --> the PGP verification failed"
      echo "# try again or with a different version"
      echo "# if you want to skip verifying all signatures (and just show them) use the command:"
      echo "# /home/admin/config.scripts/bonus.bitcoin.sh custom ${bitcoinVersion:-<version>} skipverify"
      exit 1
    fi
  fi

  echo "# Downloading Bitcoin Core v${bitcoinVersion} for ${bitcoinOSversion} ..."
  binaryName="bitcoin-${bitcoinVersion}-${bitcoinOSversion}.tar.gz"
  wget https://bitcoincore.org/bin/bitcoin-core-${pathVersion}/${binaryName}
  if [ ! -f "./${binaryName}" ]; then
    echo "# FAIL # Downloading BITCOIN BINARY did not succeed."
    exit 1
  fi

  echo "# Checking the binary checksum ..."
  if ! sha256sum -c --ignore-missing SHA256SUMS; then
    # get the sha256 value for the corresponding platform from signed hash sum file
    bitcoinSHA256=$(grep -i "${binaryName}}" SHA256SUMS | cut -d " " -f1)
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
  if ! sudo /usr/local/bin/bitcoind --version | grep "${bitcoinVersion}"; then
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
