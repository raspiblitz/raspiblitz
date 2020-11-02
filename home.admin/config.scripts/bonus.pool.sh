#!/bin/bash

# https://github.com/lightninglabs/pool/releases/
pinnedVersion=v0.3.2-alpha

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the pool on or off"
 echo "bonus.pool.sh [on|off|menu]"
 echo "Installs the Pool $pinnedVersion by default"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^pool=" /mnt/hdd/raspiblitz.conf; then
  echo "pool=off" >> /mnt/hdd/raspiblitz.conf
fi

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " Info Pool Service " --msgbox "\n\
Usage and examples: https://github.com/lightninglabs/pool\n
Use the shortcut 'pool' in the terminal to switch to the dedicated user.\n
Type 'pool' again to see the options.
" 11 56
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
Description=poold Service
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

[Install]
WantedBy=multi-user.target
" | sudo tee -a /etc/systemd/system/poold.service
    sudo systemctl enable poold
    echo "# OK - the poold.service is now enabled"

  else 
    echo "the poold.service already installed."
  fi

  # start service
  sudo systemctl start poold.service

  # setting value in raspi blitz config
  sudo sed -i "s/^pool=.*/pool=on/g" /mnt/hdd/raspiblitz.conf
  
  isInstalled=$(sudo -u pool /home/pool/go/bin/pool  | grep -c pool)
  if [ ${isInstalled} -gt 0 ]; then
    echo "
# Usage and examples: https://gitlab.com/lightning-labs/pool
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
    echo "# OK, the Pool Service is removed."
  else 
    echo "# Pool is not installed."
  fi

  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run normal again"
exit 1
