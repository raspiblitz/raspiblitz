#!/bin/bash

# !! NOTICE: Pool is now part of the 'bonus.lit.sh' bundle
# this single install script will still be available for now
# but main focus for the future development should be on LIT

# https://github.com/lightninglabs/pool/releases/
poolVersion="v0.5.1-alpha"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# config script to switch the Lightning Pool CLI on or off"
 echo "# bonus.pool.sh [on|off|menu]"
 echo "# this Pool instance is CLI only."
 echo "# for a GUI use 'bonus.lit.sh' instead"
 exit 1
fi

# show info menu
if [ "$1" = "menu" ]; then
  whiptail --title " Info Pool Service " --msgbox "\
Usage and examples: https://github.com/lightninglabs/pool\n
Use the shortcut 'pool' in the terminal to switch to the dedicated user and type 'pool' again to see the options.
" 12 56
  exit 0
fi

# stop services
echo "# making sure the service is not running"
sudo systemctl stop poold 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# installing pool"
  
  echo "# remove LiT to avoid interference with accounts (data is preserved)"
  /home/admin/config.scripts/bonus.lit.sh off

  isInstalled=$(sudo ls /etc/systemd/system/poold.service 2>/dev/null | grep -c 'poold.service')
  if [ ${isInstalled} -eq 0 ]; then

    # create dedicated user
    sudo adduser --disabled-password --gecos "" pool
    
    echo "# persist settings in app-data"
    echo "# make sure the data directory exists"
    sudo mkdir -p /mnt/hdd/app-data/.pool
    echo "# symlink"
    sudo rm -rf /home/pool/.pool # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/.pool/ /home/pool/.pool
    sudo chown pool:pool -R /mnt/hdd/app-data/.pool
    
    # set PATH for the user
    sudo bash -c "echo 'PATH=$PATH:/home/pool/go/bin/' >> /home/pool/.profile"

    # make sure symlink to central app-data directory exists
    sudo rm -rf /home/pool/.lnd  # not a symlink.. delete it silently
    # create symlink
    sudo ln -s /mnt/hdd/app-data/lnd/ /home/pool/.lnd


    # install from binary

    downloadDir="/home/admin/download/pool"  # edit your download directory
    rm -rf "${downloadDir}"
    mkdir -p "${downloadDir}"
    cd "${downloadDir}" || exit 1

    # check who signed the release in https://github.com/lightninglabs/pool/releases
    PGPsigner="roasbeef"
    if [ $PGPsigner = "roasbeef" ];then
      PGPpkeys="https://keybase.io/roasbeef/pgp_keys.asc"
      PGPcheck="372CBD7633C61696"
    fi
    if [ $PGPsigner = "guggero" ];then
      PGPpkeys="https://keybase.io/guggero/pgp_keys.asc"
      PGPcheck="03DB6322267C373B"
    fi

    echo "Detect CPU architecture ..." 
    isARM=$(uname -m | grep -c 'arm')
    isAARCH64=$(uname -m | grep -c 'aarch64')
    isX86_64=$(uname -m | grep -c 'x86_64')
    if [ ${isARM} -eq 0 ] && [ ${isAARCH64} -eq 0 ] && [ ${isX86_64} -eq 0 ]; then
      echo "!!! FAIL !!!"
      echo "Can only build on ARM, aarch64, x86_64 or i386 not on:"
      uname -m
      exit 1
    else
    echo "OK running on $(uname -m) architecture."
    fi

    # extract the SHA256 hash from the manifest file for the corresponding platform
    #https://github.com/lightninglabs/pool/releases/download/v0.5.0-alpha/manifest-v0.5.0-alpha.txt
    wget -N https://github.com/lightninglabs/pool/releases/download/${poolVersion}/manifest-${poolVersion}.txt
    if [ ${isARM} -eq 1 ] ; then
      OSversion="armv7"
    elif [ ${isAARCH64} -eq 1 ] ; then
      OSversion="arm64"
    elif [ ${isX86_64} -eq 1 ] ; then
      OSversion="amd64"
    fi 
    SHA256=$(grep -i "linux-$OSversion" manifest-${poolVersion}.txt | cut -d " " -f1)

    echo
    echo "# Pool ${poolVersion} for ${OSversion}"
    echo "# SHA256 hash: $SHA256"
    echo
    echo "# get Pool binary"
    binaryName="pool-linux-${OSversion}-${poolVersion}.tar.gz"
    wget -N https://github.com/lightninglabs/pool/releases/download/${poolVersion}/${binaryName}

    echo "# check binary was not manipulated (checksum test)"
    # https://github.com/lightninglabs/pool/releases/download/v0.5.0-alpha/manifest-v0.5.0-alpha.txt.sig
    wget -N https://github.com/lightninglabs/pool/releases/download/${poolVersion}/manifest-${poolVersion}.txt.sig
    sudo -u admin wget --no-check-certificate -N -O "pgp_keys.asc" ${PGPpkeys}
    #wget --no-check-certificate ${PGPpkeys}
    binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
    if [ "${binaryChecksum}" != "${SHA256}" ]; then
      echo "!!! FAIL !!! Downloaded Pool BINARY not matching SHA256 checksum: ${SHA256}"
      exit 1
    fi

    echo "# check gpg finger print"
    gpg --keyid-format LONG ./pgp_keys.asc
    fingerprint=$(gpg --keyid-format LONG "./pgp_keys.asc" 2>/dev/null \
    | grep "${PGPcheck}" -c)
    if [ ${fingerprint} -lt 1 ]; then
      echo ""
      echo "!!! BUILD WARNING --> Pool PGP author not as expected"
      echo "Should contain PGP: ${PGPcheck}"
      echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
      read key
    fi
    gpg --import ./pgp_keys.asc
    sleep 3
    verifyResult=$(gpg --verify manifest-${poolVersion}.txt.sig manifest-${poolVersion}.txt 2>&1)
    goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
    echo "goodSignature(${goodSignature})"
    correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${GPGcheck}" -c)
    echo "correctKey(${correctKey})"
    if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
      echo ""
      echo "!!! BUILD FAILED --> PGP verification failed / signature(${goodSignature}) verify(${correctKey})"
      exit 1
    fi
    ###########
    # install #
    ###########
    tar -xzf ${binaryName}
    sudo install -m 0755 -o root -g root -t /usr/local/bin pool-linux-${OSversion}-${poolVersion}/*

    # install from source
    # install Go
    # /home/admin/config.scripts/bonus.go.sh on
    # get Go vars
    # source /etc/profile
    # cd /home/pool
    # 
    # sudo -u pool git clone https://github.com/lightninglabs/pool.git || exit 1
    # cd /home/pool/pool
    # # pin version 
    # sudo -u pool git reset --hard $pinnedVersion
    # # install to /home/pool/go/bin/
    # sudo -u pool /usr/local/go/bin/go install ./... || exit 1

    # sync all macaroons and unix groups for access
    /home/admin/config.scripts/lnd.credentials.sh sync
    # macaroons will be checked after install

    # add user to group with admin access to lnd
    sudo /usr/sbin/usermod --append --groups lndadmin pool
    # add user to group with readonly access on lnd
    sudo /usr/sbin/usermod --append --groups lndreadonly pool
    # add user to group with invoice access on lnd
    sudo /usr/sbin/usermod --append --groups lndinvoice pool
    # add user to groups with all macaroons
    sudo /usr/sbin/usermod --append --groups lndinvoices pool
    sudo /usr/sbin/usermod --append --groups lndchainnotifier pool
    sudo /usr/sbin/usermod --append --groups lndsigner pool
    sudo /usr/sbin/usermod --append --groups lndwalletkit pool
    sudo /usr/sbin/usermod --append --groups lndrouter pool

    # make systemd service
    if [ "${runBehindTor}" = "on" ]; then
      echo " # Connect to the Pool server through Tor"
      proxy="torify"
    else
      echo "# Connect to Pool server through clearnet"
      proxy=""
    fi

    # sudo nano /etc/systemd/system/poold.service 
    echo "
[Unit]
Description=poold.service
After=lnd.service

[Service]
ExecStart=$proxy /usr/local/bin/poold --network=${chain}net --debuglevel=trace
User=pool
Group=pool
Type=simple
TimeoutSec=60
Restart=always
RestartSec=60

# Hardening measures
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
" | sudo tee /etc/systemd/system/poold.service
    sudo systemctl enable poold
    echo "# OK - the poold.service is now enabled"

  else 
    echo "the poold.service already installed."
  fi

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# OK - the poold.service is enabled, system is on ready so starting service"
    sudo systemctl start poold
  else
    echo "# OK - the poold.service is enabled, to start manually use: sudo systemctl start poold"
  fi
  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set pool "on"
  
  isInstalled=$(sudo -u pool /usr/local/bin/poold  | grep -c pool)
  if [ ${isInstalled} -gt 0 ]; then
    echo "
# Usage and examples: https://github.com/lightninglabs/pool
# Use the command: 'sudo su - pool' 
# in the terminal to switch to the dedicated user.
# Type 'pool' again to see the options.
"
  else
    echo "# Failed to install Lightning Pool "
    exit 1
  fi
  
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set pool "off"

  isInstalled=$(sudo ls /etc/systemd/system/poold.service 2>/dev/null | grep -c 'poold.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# Removing the Pool service"
    # remove the systemd service
    sudo systemctl stop poold
    sudo systemctl disable poold
    sudo rm /etc/systemd/system/poold.service
    # delete user and it's home directory
    sudo userdel -rf pool
    # delete the binary
    sudo rm /usr/local/bin/poold
    echo "# OK, the Pool Service is removed."
  else 
    echo "# Pool is not installed."
  fi

  exit 0
fi

# # update
# if [ "$1" = "update" ]; then
#   echo "# Updating Pool "
#   cd /home/pool/pool
#   # from https://github.com/apotdevin/thunderhub/blob/master/scripts/updateToLatest.sh
#   # fetch latest master
#   sudo -u pool git fetch
#   # unset $1
#   set --
#   UPSTREAM=${1:-'@{u}'}
#   LOCAL=$(git rev-parse @)
#   REMOTE=$(git rev-parse "$UPSTREAM")
#   
#   if [ $LOCAL = $REMOTE ]; then
#     TAG=$(git tag | sort -V | tail -1)
#     echo "# You are up-to-date on version" $TAG
#   else
#     echo "# Pulling the latest changes..."
#     sudo -u pool git pull -p
#     echo "# Reset to the latest release tag"
#     TAG=$(git tag | sort -V | tail -1)
#     sudo -u pool git reset --hard $TAG
#     echo "# Updating ..."
#     # install to /home/pool/go/bin/
#     sudo -u pool /usr/local/go/bin/go install ./... || exit 1
#     isInstalled=$(sudo -u pool /home/pool/go/bin/pool  | grep -c pool)
#     if [ ${isInstalled} -gt 0 ]; then
#       TAG=$(git tag | sort -V | tail -1)
#       echo "# Updated to version" $TAG
#     else
#       echo "# Failed to install Lightning Pool "
#       exit 1
#     fi
#   fi
# 
#   echo "# At the latest in https://github.com/lightninglabs/pool/releases/"
#   echo ""
#   echo "# Starting the poold.service ... *** "
#   sudo systemctl start poold
#   exit 0
# fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run normal again"
exit 1
