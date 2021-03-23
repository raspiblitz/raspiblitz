#!/bin/bash

# !! NOTICE: Faraday is now prt of the 'bonus.lit.sh' bundle
# this single install script will still be available for now
# but main focus for the future development should be on LIT

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "Bonus App: faraday -> https://github.com/lightninglabs/faraday"
 echo "lnd.faraday.sh [status|on|off]"
 echo "!! DEPRECATED use instead: bonus.lit.sh"
 exit 1
fi

version="0.2.3-alpha"
echo "## bonus.faraday.sh ${version}"

# version and trusted release signer
PGPkeys="https://keybase.io/carlakirkcohen/pgp_keys.asc"
PGPcheck="15E7ECF257098A4EF91655EB4CA7FE54A6213C91"

# 1. parameter [info|verified|reckless]
mode="$1" 

# GATHER DATA
source /home/admin/raspiblitz.info
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
installedVersion=$(sudo -u faraday /home/faraday/bin/frcli --version 2>/dev/null)
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

# MENU INFO
if [ "${mode}" = "menu" ]; then
  if [ ${installed} -q 0 ]; then
    whiptail --title " ERROR " --msgbox "Faraday is not installed" 7 30
    exit 1
  fi
  whiptail --title " Faraday " --msgbox "
Faraday is a command line tool. Details see:
https://github.com/lightninglabs/faraday

Terminal-Shortcut: 'faraday' to switch to the dedicated user.
Or use like: sudo -u faraday /home/faraday/bin/frcli -help
" 13 70
  exit 1
fi

# INSTALL
if [ "${mode}" = "on" ] || [ "${mode}" = "1" ]; then

  if [ -f /etc/systemd/system/faraday.service ]; then
    echo "# FAIL - already installed"
    sleep 3
    exit 1
  fi

  echo "# INSTALL bonus.faraday.sh version: ${version}"

  echo 
  echo "# clean & change into download directory"
  sudo rm -r ${downloadDir}/*
  cd "${downloadDir}"

  echo "# extract the SHA256 hash from the manifest file for the corresponding platform"
  downloadLink="https://github.com/lightninglabs/faraday/releases/download/v${version}/manifest-v${version}.txt"
  sudo -u admin wget -N ${downloadLink}
  checkDownload=$(ls manifest-v${version}.txt 2>/dev/null | grep -c manifest-v${version}.txt)
  if [ ${checkDownload} -eq 0 ]; then
    echo "downloadLink='${downloadLink}'"
    echo "error='download manifest failed'"
    exit 1
  fi
  SHA256=$(grep -i "linux-${cpuArchitecture}" manifest-v$version.txt | cut -d " " -f1)
  echo "# SHA256 hash: $SHA256"
  if [ ${#SHA256} -eq 0 ]; then
    echo "error='getting checksum failed'"
    exit 1
  fi

  echo
  echo "# get Binary"
  binaryName="faraday-linux-${cpuArchitecture}-v${version}.tar.gz"
  sudo -u admin wget -N https://github.com/lightninglabs/faraday/releases/download/v${version}/${binaryName}
  checkDownload=$(ls ${binaryName} 2>/dev/null | grep -c ${binaryName})
  if [ ${checkDownload} -eq 0 ]; then
    echo "error='download binary failed'"
    exit 1
  fi

  echo
  echo "# check binary was not manipulated (checksum test)"
  sudo -u admin wget -N https://github.com/lightninglabs/faraday/releases/download/v${version}/manifest-v${version}.txt.sig
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
  verifyResult=$(gpg --verify manifest-v${version}.txt.sig 2>&1)
  goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
  echo "goodSignature='${goodSignature}'"
  correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${PGPcheck}" -c)
  echo "correctKey='${correctKey}'"
  if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
    echo "error='PGP verify fail'"
    exit 1
  fi

  # create dedicated user
  echo "# Add the 'faraday' user"
  sudo adduser --disabled-password --gecos "" faraday

  # set PATH for the user
  sudo bash -c "echo 'PATH=\$PATH:/home/faraday/bin/' >> /home/faraday/.profile"

  # install
  echo
  echo "# unzip binary: ${binaryName}"
  sudo -u admin tar -xzf ${binaryName}
  # removing the tar.gz ending from the binary
  directoryName="${binaryName%.*.*}"
  echo "# install binary directory '${directoryName}'"
  sudo -u faraday mkdir -p /home/faraday/bin
  sudo install -m 0755 -o faraday -g faraday -t /home/faraday/bin ${directoryName}/*
  sleep 3

  installed=$(sudo -u faraday /home/faraday/bin/frcli --version)
  if [ ${#installed} -eq 0 ]; then
    echo "error='install failed'"
    exit 1
  fi

  # make sure symlink to central app-data directory exists ***"
  sudo rm -rf /home/faraday/.lnd  # not a symlink.. delete it silently
  # create symlink
  sudo ln -s /mnt/hdd/app-data/lnd/ /home/faraday/.lnd
  # sync all macaroons and unix groups for access
  /home/admin/config.scripts/lnd.credentials.sh sync
  # macaroons will be checked after install
  # add user to group with admin access to lnd
  sudo /usr/sbin/usermod --append --groups lndadmin faraday
  # add user to group with readonly access on lnd
  sudo /usr/sbin/usermod --append --groups lndreadonly faraday
  # add user to group with invoice access on lnd
  sudo /usr/sbin/usermod --append --groups lndinvoice faraday
  # add user to groups with all macaroons
  sudo /usr/sbin/usermod --append --groups lndinvoices faraday
  sudo /usr/sbin/usermod --append --groups lndchainnotifier faraday
  sudo /usr/sbin/usermod --append --groups lndsigner faraday
  sudo /usr/sbin/usermod --append --groups lndwalletkit faraday
  sudo /usr/sbin/usermod --append --groups lndrouter faraday
 
  # install service
  echo "*** Install systemd ***"
  echo "
[Unit]
Description=faraday
Wants=lnd.service
After=lnd.service

[Service]
User=faraday
WorkingDirectory=/home/faraday/
ExecStart=/home/faraday/bin/faraday \
#--network=${chain}net
#--connect_bitcoin \
#--bitcoin.host=127.0.0.1:8332 \
#--bitcoin.user=raspibolt \
#--bitcoin.password=PASSWORD_B
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
" | sudo tee -a /etc/systemd/system/faraday.service
    sudo systemctl enable faraday
    echo "# OK - the Faraday service is now enabled"
  if [ "${state}" == "ready" ]; then
    sudo systemctl start faraday
  fi

  echo "# default config path"
  sudo mkdir /home/faraday/.faraday
  sudo mkdir /home/faraday/.faraday/${chain}net
  sudo chown -R faraday:faraday /home/faraday/.faraday

  echo "# flag in raspiblitz config"
  if [ ${#faraday} -eq 0 ]; then
    echo "faraday='on'" >> /mnt/hdd/raspiblitz.conf
  fi
  sudo sed -i "s/^faraday=.*/faraday=on/g" /mnt/hdd/raspiblitz.conf

  echo "# OK Faraday is installed"
  echo "# please 'restart' for clean creation of faraday tls/macaroons"
  exit 1

fi

# DEINSTALL
if [ "${mode}" = "off" ] || [ "${mode}" = "0" ]; then

  echo "# DEINSTALL"

  echo "# remove systemd service"
  sudo systemctl stop faraday
  sudo systemctl disable faraday
  sudo rm /etc/systemd/system/faraday.service

  echo "# remove faraday user & binary"
  sudo userdel -r -f faraday

  echo "# modify config file"
  sudo sed -i "s/^faraday=.*/faraday=off/g" /mnt/hdd/raspiblitz.conf

  exit 1
 
fi

echo "error='parameter not known'"
exit 1
