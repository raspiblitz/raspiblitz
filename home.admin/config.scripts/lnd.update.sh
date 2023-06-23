#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "Interim optional LND updates between RaspiBlitz releases."
 echo "lnd.update.sh [info|verified|reckless]"
 echo "info -> get actual state and possible actions"
 echo "verified -> only do recommended updates by RaspiBlitz team"
 echo "  binary will be checked by signature and checksum"
 echo "reckless -> if you just want to update to the latest release"
 echo "  published on LND GitHub releases (RC or final) without any"
 echo "  testing or security checks."
 exit 1
fi

# 1. parameter [info|verified|reckless]
mode="$1"

# RECOMMENDED UPDATE BY RASPIBLITZ TEAM
# comment will be shown as "BEWARE Info" when option is choosen (can be multiple lines)
lndUpdateVersion="" # example: 0.13.2-beta .. keep empty if no newer version as sd card build is available
lndUpdateComment="Please keep in mind that downgrading afterwards is not tested. Also not all additional apps are fully tested with the this update - but it looked good on first tests."

# check who signed the release in https://github.com/lightningnetwork/lnd/releases
# olaoluwa
PGPauthor="roasbeef"
lndUpdatePGPpkeys="https://keybase.io/roasbeef/pgp_keys.asc"
lndUpdatePGPcheck="4AB7F8DA6FAEBB3B70B1F903BC13F65E2DC84465"

# bitconner
# PGPauthor="bitconner"
# lndUpdatePGPpkeys="https://keybase.io/bitconner/pgp_keys.asc"
# lndUpdatePGPcheck="9C8D61868A7C492003B2744EE7D737B67FA592C7"

# wpaulino
# PGPauthor="wpaulino"
# lndUpdatePGPpkeys="https://keybase.io/wpaulino/pgp_keys.asc"
# lndUpdatePGPcheck="729E9D9D92C75A5FBFEEE057B5DD717BEF7CA5B1"

# GATHER DATA

# setting download directory
downloadDir="/home/admin/download"

# detect CPU architecture & fitting download link
cpuArchitecture=""
if [ $(uname -m | grep -c 'arm') -eq 1 ] ; then
  cpuArchitecture="armv7"
fi
if [ $(uname -m | grep -c 'aarch64') -eq 1 ] ; then
  cpuArchitecture="arm64"
fi
if [ $(uname -m | grep -c 'x86_64') -eq 1 ] ; then
  cpuArchitecture="amd64"
fi
if [ $(uname -m | grep -c 'i386\|i486\|i586\|i686\|i786') -eq 1 ] ; then
  cpuArchitecture="386"
fi

# installed LND version
lndInstalledVersion=$(sudo -u bitcoin lncli --version | cut -d " " -f3)
# example: '0.14.1-beta'
lndInstalledVersionMajor=$(echo "${lndInstalledVersion}" | cut -d "-" -f1 | cut -d "." -f1)
lndInstalledVersionMain=$(echo "${lndInstalledVersion}" | cut -d "-" -f1 | cut -d "." -f2)
lndInstalledVersionMinor=$(echo "${lndInstalledVersion}" | cut -d "-" -f1 | cut -d "." -f3)

# test if the installed version already the verified/recommended update version
lndUpdateInstalled=$(echo "${lndInstalledVersion}" | grep -c "${lndUpdateVersion}")

# get latest release from LND GitHub releases (without release candidates)
lndLatestVersion=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s https://api.github.com/repos/lightningnetwork/lnd/releases | jq -r '.[].tag_name' | grep -v "rc" | head -n1)
# example: v0.13.3-beta
binaryName="lnd-linux-${cpuArchitecture}-${lndLatestVersion}.tar.gz"
# example: lnd-linux-arm64-v0.13.3-beta.tar.gz
lndLatestDownload="https://github.com/lightningnetwork/lnd/releases/download/${lndLatestVersion}/${binaryName}"
# example: https://github.com/lightningnetwork/lnd/releases/download/v0.13.3-beta/lnd-linux-arm64-v0.13.3-beta.tar.gz

# INFO
if [ "${mode}" = "info" ]; then

  echo "# basic data"
  echo "cpuArchitecture='${cpuArchitecture}'"
  echo "lndInstalledVersion='${lndInstalledVersion}'"
  echo "lndInstalledVersionMajor='${lndInstalledVersionMajor}'"
  echo "lndInstalledVersionMain='${lndInstalledVersionMain}'"
  echo "lndInstalledVersionMinor='${lndInstalledVersionMinor}'"

  echo "# the verified/recommended update option"
  echo "lndUpdateInstalled='${lndUpdateInstalled}'"
  echo "lndUpdateVersion='${lndUpdateVersion}'"
  echo "lndUpdateComment='${lndUpdateComment}'"

  echo "# reckless update option (latest LND release from GitHub)"
  echo "lndLatestVersion='${lndLatestVersion}'"
  echo "lndLatestDownload='${lndLatestDownload}'"

  exit 1
fi

function installLND() {
  # install
  echo "# stopping LND"
  sudo systemctl stop lnd
  echo "# unzip LND binary"
  sudo -u admin tar -xzf ${binaryName}
  # removing the tar.gz ending from the binary
  directoryName="${binaryName%.*.*}"
  echo "# install binary directory '${directoryName}'"
  sudo install -m 0755 -o root -g root -t /usr/local/bin ${directoryName}/*
  sleep 3
  installed=$(sudo -u admin lnd --version)
  if [ ${#installed} -eq 0 ]; then
    echo "error='install failed'"
    exit 1
  fi
}

# verified
if [ "${mode}" = "verified" ]; then

  echo "# lnd.update.sh verified"

  # check for optional second parameter: forced update version
  # --> only does the verified update if its the given version
  # this is needed for recovery/update.
  fixedUpdateVersion="$2"
  if [ ${#fixedUpdateVersion} -gt 0 ]; then
    echo "# checking for fixed version update: askedFor(${fixedUpdateVersion}) available(${lndUpdateVersion})"
    if [ "${fixedUpdateVersion}" != "${lndUpdateVersion}" ]; then
      echo "warn='required update version does not match'"
      echo "# this is normal when the recovery script of a new RaspiBlitz version checks for an old update - just ignore"
      /home/admin/config.scripts/blitz.conf.sh delete lndInterimsUpdate
      exit 1
    else
      echo "# OK - update version is matching"
    fi
  fi

  echo
  echo "# clean & change into download directory"
  sudo rm -r ${downloadDir}/*
  cd "${downloadDir}" || exit 1

  echo
  echo "# extract the SHA256 hash from the manifest file for the corresponding platform"
  sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndUpdateVersion}/manifest-v${lndUpdateVersion}.txt
  checkDownload=$(ls manifest-v${lndUpdateVersion}.txt 2>/dev/null | grep -c manifest-v${lndUpdateVersion}.txt)
  if [ ${checkDownload} -eq 0 ]; then
    echo "error='download manifest failed'"
    exit 1
  fi
  lndSHA256=$(grep -i "linux-${cpuArchitecture}" manifest-v$lndUpdateVersion.txt | cut -d " " -f1)
  echo "# SHA256 hash: $lndSHA256"

  echo
  echo "# get LND binary"
  binaryName="lnd-linux-${cpuArchitecture}-v${lndUpdateVersion}.tar.gz"
  sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndUpdateVersion}/${binaryName}
  checkDownload=$(ls ${binaryName} 2>/dev/null | grep -c ${binaryName})
  if [ ${checkDownload} -eq 0 ]; then
    echo "error='download binary failed'"
    exit 1
  fi

  echo
  echo "# check binary was not manipulated (checksum test)"
  sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndUpdateVersion}/manifest-${PGPauthor}-v${lndUpdateVersion}.sig
  sudo -u admin wget --no-check-certificate -N -O "${downloadDir}/pgp_keys.asc" ${lndUpdatePGPpkeys}
  binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
  echo "# binary chdecksum: ${binaryChecksum}"
  echo "# lndSHA256: ${lndSHA256}"
  validSignature=$(echo "${lndSHA256}" | grep -c "${binaryChecksum}")
  if [ ${validSignature} -eq 0 ]; then
    echo "error='checksum not matching'"
    exit 1
  fi

  echo
  echo "# getting gpg finger print"
  gpg --show-keys ./pgp_keys.asc
  fingerprint=$(sudo gpg --show-keys "${downloadDir}/pgp_keys.asc" 2>/dev/null | grep "${lndUpdatePGPcheck}" -c)
  if [ ${fingerprint} -lt 1 ]; then
    echo "error='PGP author check failed'"
    exit 1
  fi
  echo "fingerprint='${fingerprint}'"

  echo
  echo "# checking PGP finger print"
  gpg --import ./pgp_keys.asc
  sleep 3
  verifyResult=$(LANG=en_US.utf8; gpg --verify manifest-${PGPauthor}-v${lndUpdateVersion}.sig manifest-v${lndUpdateVersion}.txt 2>&1)
  goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
  echo "goodSignature='${goodSignature}'"
  correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${lndUpdatePGPcheck}" -c)
  echo "correctKey='${correctKey}'"
  if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
    echo "error='PGP verify fail'"
    exit 1
  fi

  # note: install will be done the same as reckless further down
  lndInterimsUpdateNew="${lndUpdateVersion}"

  installLND

fi

# RECKLESS
# this mode is just for people running test and development nodes - its not recommended
# for production nodes. In a update/recovery scenario it will not install a fixed version
# it will always pick the latest release from the github
if [ "${mode}" = "reckless" ]; then

  echo "# lnd.update.sh reckless"
  # only update if the latest release is different from the installed
  if [ "v${lndInstalledVersion}" = "${lndLatestVersion}" ]; then
    # attention to leading 'v'
    echo "# lndInstalledVersion = lndLatestVersion (${lndLatestVersion:1})"
    echo "# There is no need to update again."
    lndInterimsUpdateNew="${lndLatestVersion:1}"
  else
    # check that download link has a value
    if [ ${#lndLatestDownload} -eq 0 ]; then
      echo "error='no download link'"
      exit 1
    fi

    # clean & change into download directory
    sudo rm -r ${downloadDir}/*
    cd "${downloadDir}" || exit 1

    # download binary
    echo "# downloading binary"
    binaryName=$(basename "${lndLatestDownload}")
    sudo -u admin wget -N ${lndLatestDownload}
    checkDownload=$(ls ${binaryName} 2>/dev/null | grep -c ${binaryName})
    if [ ${checkDownload} -eq 0 ]; then
      echo "error='download binary failed'"
      exit 1
    fi

    # prepare install
    lndInterimsUpdateNew="reckless"

    installLND

  fi
fi

# JOINED INSTALL (verified & RECKLESS)
if [ "${mode}" = "verified" ] || [ "${mode}" = "reckless" ]; then

  echo "# mark update in raspiblitz config"
  /home/admin/config.scripts/blitz.conf.sh set lndInterimsUpdate "${lndInterimsUpdateNew}"

  echo "# OK LND Installed"
  echo "# NOTE: RaspiBlitz may need to reboot now"
  exit 1

else

  echo "error='parameter not known'"
  exit 1

fi
