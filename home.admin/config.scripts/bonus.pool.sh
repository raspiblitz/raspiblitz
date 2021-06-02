#!/bin/bash

# !! NOTICE: Pool is now prt of the 'bonus.lit.sh' bundle
# this single install script will still be available for now
# but main focus for the future development should be on LIT

# https://github.com/lightninglabs/pool/releases/
pinnedVersion="v0.3.4-alpha"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# config script to switch Lightning Pool on, off or update"
 echo "# bonus.pool.sh [on|off|menu|update]"
 echo "# DEPRECATED use instead: bonus.lit.sh"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^pool=" /mnt/hdd/raspiblitz.conf; then
  echo "pool=off" >> /mnt/hdd/raspiblitz.conf
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
  
  isInstalled=$(sudo ls /etc/systemd/system/poold.service 2>/dev/null | grep -c 'poold.service')
  if [ ${isInstalled} -eq 0 ]; then

    # install Go
    /home/admin/config.scripts/bonus.go.sh on
    
    # get Go vars
    source /etc/profile

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

    # install from source
    cd /home/pool
    
    sudo -u pool git clone https://github.com/lightninglabs/pool.git || exit 1
    cd /home/pool/pool
    # pin version 
    sudo -u pool git reset --hard $pinnedVersion
    # install to /home/pool/go/bin/
    sudo -u pool /usr/local/go/bin/go install ./... || exit 1

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
      echo " # Connect tothe Pool server through Tor"
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
ExecStart=$proxy /home/pool/go/bin/poold --network=${chain}net --debuglevel=trace
User=pool
Group=pool
Type=simple
KillMode=process
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

  source /home/admin/raspiblitz.info
  if [ "${state}" == "ready" ]; then
    echo "# OK - the poold.service is enabled, system is on ready so starting service"
    sudo systemctl start poold
  else
    echo "# OK - the poold.service is enabled, to start manually use: sudo systemctl start poold"
  fi
  # setting value in raspi blitz config
  sudo sed -i "s/^pool=.*/pool=on/g" /mnt/hdd/raspiblitz.conf
  
  isInstalled=$(sudo -u pool /home/pool/go/bin/pool  | grep -c pool)
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
  sudo sed -i "s/^pool=.*/pool=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/poold.service 2>/dev/null | grep -c 'poold.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# Removing the Pool service"
    # remove the systemd service
    sudo systemctl stop poold
    sudo systemctl disable poold
    sudo rm /etc/systemd/system/poold.service
    # delete user and it's home directory
    sudo userdel -rf pool
    # remove symlink
    sudo rm -r /mnt/hdd/app-data/.pool
    echo "# OK, the Pool Service is removed."
  else 
    echo "# Pool is not installed."
  fi

  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "# Updating Pool "
  cd /home/pool/pool
  # from https://github.com/apotdevin/thunderhub/blob/master/scripts/updateToLatest.sh
  # fetch latest master
  sudo -u pool git fetch
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
    sudo -u pool git pull -p
    echo "# Reset to the latest release tag"
    TAG=$(git tag | sort -V | tail -1)
    sudo -u pool git reset --hard $TAG
    echo "# Updating ..."
    # install to /home/pool/go/bin/
    sudo -u pool /usr/local/go/bin/go install ./... || exit 1
    isInstalled=$(sudo -u pool /home/pool/go/bin/pool  | grep -c pool)
    if [ ${isInstalled} -gt 0 ]; then
      TAG=$(git tag | sort -V | tail -1)
      echo "# Updated to version" $TAG
    else
      echo "# Failed to install Lightning Pool "
      exit 1
    fi
  fi

  echo "# At the latest in https://github.com/lightninglabs/pool/releases/"
  echo ""
  echo "# Starting the poold.service ... *** "
  sudo systemctl start poold
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run normal again"
exit 1
