#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "Bonus App: faraday -> https://github.com/lightninglabs/faraday"
 echo "lnd.faraday.sh [status|on|off]"
 exit 1
fi

# version and trusted release signer
version="v0.1.0-alpha"
PGPkeys="https://keybase.io/carlakirkcohen/pgp_keys.asc"
PGPcheck="15E7ECF257098A4EF91655EB4CA7FE54A6213C91"

# 1. parameter [info|verified|reckless]
mode="$1" 

# GATHER DATA
source /mnt/hdd/raspiblitz.conf

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

# check if already installed
installed=0
installedVersion=$(sudo -u admin faraday --version)
if [ ${#installedVersion} -gt 0 ]; then
  installed=1
fi

# STATUS
if [ "${mode}" = "status" ]; then

  echo "# status data"
  echo "cpuArchitecture='${cpuArchitecture}'"
  echo "version='${version}'"
  echo "installed=${installed}"
  exit 1

fi

# INSTALL
if [ "${mode}" = "on" ] || [ "${mode}" = "1" ]; then

  echo "# INSTALL bonus.faraday.sh"

  echo 
  echo "# clean & change into download directory"
  sudo rm -r ${downloadDir}/*
  cd "${downloadDir}"

  echo "# extract the SHA256 hash from the manifest file for the corresponding platform"
  downloadLink="https://github.com/lightninglabs/faraday/releases/download/${version}/manifest-${version}.txt"
  sudo -u admin wget -N ${downloadLink}
  checkDownload=$(ls manifest-${version}.txt 2>/dev/null | grep -c manifest-${version}.txt)
  if [ ${checkDownload} -eq 0 ]; then
    echo "downloadLink='${downloadLink}'"
    echo "error='download manifest failed'"
    exit 1
  fi
  SHA256=$(grep -i "linux-${cpuArchitecture}" manifest-$version.txt | cut -d " " -f1)
  echo "# SHA256 hash: $SHA256"
  if [ ${#SHA256} -eq 0 ]; then
    echo "error='getting checksum failed'"
    exit 1
  fi

  echo
  echo "# get Binary"
  binaryName="faraday-linux-${cpuArchitecture}-${version}.tar.gz"
  sudo -u admin wget -N https://github.com/lightninglabs/faraday/releases/download/${version}/${binaryName}
  checkDownload=$(ls ${binaryName} 2>/dev/null | grep -c ${binaryName})
  if [ ${checkDownload} -eq 0 ]; then
    echo "error='download binary failed'"
    exit 1
  fi

  echo
  echo "# check binary was not manipulated (checksum test)"
  sudo -u admin wget -N https://github.com/lightninglabs/faraday/releases/download/${version}/manifest-${version}.txt.sig
  sudo -u admin wget -N -O "${downloadDir}/pgp_keys.asc" ${PGPkeys}
  binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
  if [ "${binaryChecksum}" != "${SHA256}" ]; then
    echo "error='checksum not matching'"
    exit 1
  fi

  echo 
  echo "# getting gpg finger print"
  gpg ./pgp_keys.asc
  fingerprint=$(sudo gpg "${downloadDir}/pgp_keys.asc" 2>/dev/null | grep "${PGPcheck}" -c)
  if [ ${fingerprint} -lt 1 ]; then
    echo "error='PGP author check failed'"
    exit 1
  fi
  echo "fingerprint='${fingerprint}'"

  echo 
  echo "# checking PGP finger print"
  gpg --import ./pgp_keys.asc
  sleep 3
  verifyResult=$(gpg --verify manifest-${version}.txt.sig 2>&1)
  goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
  echo "goodSignature='${goodSignature}'"
  correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${PGPcheck}" -c)
  echo "correctKey='${correctKey}'"
  if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
    echo "error='PGP verify fail'"
    exit 1
  fi

  # install
  echo "# unzip binary"
  sudo -u admin tar -xzf ${binaryName}
  # removing the tar.gz ending from the binary
  directoryName="${binaryName%.*.*}"
  echo "# install binary directory '${directoryName}'"
  sudo install -m 0755 -o root -g root -t /usr/local/bin ${directoryName}/*
  sleep 3
  installed=$(sudo -u admin faraday --version)
  if [ ${#installed} -eq 0 ]; then
    echo "error='install failed'"
    exit 1
  fi
  echo "# flag in raspiblitz config"
  if [ ${#faraday} -eq 0 ]; then
    echo "faraday='${faraday}'" >> /mnt/hdd/raspiblitz.conf
  else
    sudo sed -i "s/^faraday=.*/faraday=on/g" /mnt/hdd/raspiblitz.conf
  fi

  echo "# OK LND Installed"
  exit 1

fi

# TODO: OFF - DEINSTALL
if [ "${mode}" = "reckless" ]; then

  echo "# DEINSTALL bonus.faraday.sh TODO"
  exit 1
 
fi

echo "error='parameter not known'"
exit 1
