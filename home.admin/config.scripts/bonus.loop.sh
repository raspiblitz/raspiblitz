#!/bin/bash

# !! NOTICE: Faraday is now part of the 'bonus.lit.sh' bundle
# this single install script will still be available for now
# but main focus for the future development should be on LIT

# https://github.com/lightninglabs/loop/releases-
pinnedVersion="v0.15.0-beta"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the Lightning Loop Service on,off or update"
 echo "bonus.loop.sh [on|off|menu|update]"
 echo "!! DEPRECATED use instead: bonus.lit.sh"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^loop=" /mnt/hdd/raspiblitz.conf; then
  echo "loop=off" | tee -a  /mnt/hdd/raspiblitz.conf
fi

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " Info Loop Service " --msgbox "\n\
Usage and examples: https://github.com/lightninglabs/loop#loop-out-swaps\n
Use the shortcut 'loop' in the terminal to switch to the dedicated user.\n
Type 'loop' again to see the available options.
" 10 56
  exit 0
fi

# releases are creatd on GitHub
PGPsigner="web-flow"
PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
PGPpubkeyFingerprint="4AEE18F83AFDEB23"

# TODO download with .tar.gz
#PGPsigner="alexbosworth"
#PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
#PGPpubkeyFingerprint="E80D2F3F311FD87E"

# stop services
echo "making sure the loopd.service is not running"
sudo systemctl stop loopd 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# Install Lightning Loop"
  
  isInstalled=$(sudo ls /etc/systemd/system/loopd.service 2>/dev/null | grep -c 'loopd.service')
  if [ ${isInstalled} -eq 0 ]; then

    # install Go
    /home/admin/config.scripts/bonus.go.sh on
    
    # get Go vars
    source /etc/profile

    # create dedicated user
    sudo adduser --disabled-password --gecos "" loop

    # set PATH for the user
    sudo bash -c "echo 'PATH=\$PATH:/home/loop/go/bin/' >> /home/loop/.profile"

    # make sure symlink to central app-data directory exists
    sudo rm -rf /home/loop/.lnd  # not a symlink.. delete it silently
    # create symlink
    sudo ln -s /mnt/hdd/app-data/lnd/ /home/loop/.lnd

    echo "# persist settings in app-data"
    # move old data if present
    sudo mv /home/loop/.loop /mnt/hdd/app-data/ 2>/dev/null
    echo "# make sure the data directory exists"
    sudo mkdir -p /mnt/hdd/app-data/.loop
    echo "# symlink"
    sudo rm -rf /home/loop/.loop # not a symlink.. delete it silently
    sudo ln -s /mnt/hdd/app-data/.loop/ /home/loop/.loop
    sudo chown loop:loop -R /mnt/hdd/app-data/.loop

    # install from source
    cd /home/loop
    sudo -u loop git clone https://github.com/lightninglabs/loop.git
    cd /home/loop/loop
    sudo -u loop git reset --hard $pinnedversion
    sudo -u loop /home/admin/config.scripts/blitz.git-verify.sh \
     "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1
    cd /home/loop/loop/cmd
    sudo -u loop /usr/local/go/bin/go install ./... || exit 1

    # sync all macaroons and unix groups for access
    /home/admin/config.scripts/lnd.credentials.sh sync
    # macaroons will be checked after install

    # add user to group with admin access to lnd
    sudo /usr/sbin/usermod --append --groups lndadmin loop
    # add user to group with readonly access on lnd
    sudo /usr/sbin/usermod --append --groups lndreadonly loop
    # add user to group with invoice access on lnd
    sudo /usr/sbin/usermod --append --groups lndinvoice loop
    # add user to groups with all macaroons
    sudo /usr/sbin/usermod --append --groups lndinvoices loop
    sudo /usr/sbin/usermod --append --groups lndchainnotifier loop
    sudo /usr/sbin/usermod --append --groups lndsigner loop
    sudo /usr/sbin/usermod --append --groups lndwalletkit loop
    sudo /usr/sbin/usermod --append --groups lndrouter loop

    # make systemd service
    if [ "${runBehindTor}" = "on" ]; then
      echo "# Will connect to Loop server through Tor"
      proxy="--server.proxy=127.0.0.1:9050"
    else
      echo "# Will connect to Loop server through clearnet"
      proxy=""
    fi

    # sudo nano /etc/systemd/system/loopd.service 
    echo "
[Unit]
Description=Loopd Service
After=lnd.service

[Service]
WorkingDirectory=/home/loop/loop
ExecStart=/home/loop/go/bin/loopd --network=${chain}net ${proxy}
User=loop
Group=loop
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
" | sudo tee -a /etc/systemd/system/loopd.service
    sudo systemctl enable loopd
    echo "# OK - the Lightning Loop service is now enabled"

  else 
    echo "# The Loop service already installed."
  fi

  # in case RTL is installed - check to connect
  sudo /home/admin/config.scripts/bonus.rtl.sh connect-services

  # setting value in raspi blitz config
  sudo sed -i "s/^loop=.*/loop=on/g" /mnt/hdd/raspiblitz.conf
  
  isInstalled=$(sudo -u loop /home/loop/go/bin/loop | grep -c loop)
  if [ ${isInstalled} -gt 0 ] ; then
    echo "# Find info on how to use on https://github.com/lightninglabs/loop#loop-out-swaps"
  else
    echo "# Failed to install Lightning Loop "
    exit 1
  fi
  
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^loop=.*/loop=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/loopd.service 2>/dev/null | grep -c 'loopd.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# Removing the Lightning Loop service"
    # remove the systemd service
    sudo systemctl stop loopd
    sudo systemctl disable loopd
    sudo rm /etc/systemd/system/loopd.service
    # delete user and it's home directory
    sudo userdel -rf loop
    echo "# OK, the Loop Service is removed."
  else 
    echo "# Loop is not installed."
  fi

  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "# Updating Loop "
  cd /home/loop/loop
  # from https://github.com/apotdevin/thunderhub/blob/master/scripts/updateToLatest.sh
  # fetch latest master
  sudo -u loop git fetch
  # unset $1
  set --
  UPSTREAM=${1:-'@{u}'}
  LOCAL=$(git rev-parse @)
  REMOTE=$(git rev-parse "$UPSTREAM")

  if [ $LOCAL = $REMOTE ]; then
    TAG=$(git tag | sort -V | tail -1)
    echo "# You are up-to-date on version" $TAG
  else
    echo "# Pulling the latest changes..."
    sudo -u loop git pull -p
    echo "# Reset to the latest release tag"
    TAG=$(git tag | sort -V | tail -1)
    sudo -u loop git reset --hard $TAG
    sudo -u loop /home/admin/config.scripts/blitz.git-verify.sh \
     "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1
    echo "# Updating ..."
    # install to /home/loop/go/bin/
    cd /home/loop/loop/cmd
    sudo -u loop /usr/local/go/bin/go install ./... || exit 1
    isInstalled=$(sudo -u loop /home/loop/go/bin/loop  | grep -c loop)
    if [ ${isInstalled} -gt 0 ]; then
      TAG=$(git tag | sort -V | tail -1)
      echo "# Updated to version" $TAG
    else
      echo "# Failed to install Lightning Loop "
      exit 1
    fi
  fi

  echo "# At the latest in https://github.com/lightninglabs/loop/releases/"
  echo ""
  echo "# Starting the loopd.service ..."
  sudo systemctl start loopd
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run normal again"
exit 1
  