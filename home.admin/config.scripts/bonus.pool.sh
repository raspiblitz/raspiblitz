#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the pool on or off"
 echo "bonus.pool.sh [on|off|menu]"
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
Usage and examples: https://gitlab.com/lightning-labs/pool\n
Use the shortcut 'pool' on the terminal to switch to the dedicated user.\n
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

    # install from source
    cd /home/admin
    git clone git@gitlab.com:lightning-labs/pool.git || exit 1
    cd pool

    make install

    # make systemd service
    # sudo nano /etc/systemd/system/poold.service 
    echo "
[Unit]
Description=poold Service
After=lnd.service

[Service]
ExecStart=/usr/local/gocode/bin/poold --network=${chain}net --debuglevel=trace
User=admin
Group=admin
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

  # sync all macaroons and unix groups for access
  /home/admin/config.scripts/lnd.credentials.sh sync
  # macaroons will be checked after install
  # add user to group with admin access to lnd
  sudo /usr/sbin/usermod --append --groups lndadmin admin
  # add user to group with readonly access on lnd
  sudo /usr/sbin/usermod --append --groups lndreadonly admin
  # add user to group with invoice access on lnd
  sudo /usr/sbin/usermod --append --groups lndinvoice admin
  # add user to groups with all macaroons
  sudo /usr/sbin/usermod --append --groups lndinvoices admin
  sudo /usr/sbin/usermod --append --groups lndchainnotifier admin
  sudo /usr/sbin/usermod --append --groups lndsigner admin
  sudo /usr/sbin/usermod --append --groups lndwalletkit admin
  sudo /usr/sbin/usermod --append --groups lndrouter admin

  # start service
  sudo systemctl start poold.service

  # setting value in raspi blitz config
  sudo sed -i "s/^pool=.*/pool=on/g" /mnt/hdd/raspiblitz.conf
  
  isInstalled=$(pool | grep -c pool)
  if [ ${isInstalled} -gt 0 ] ; then
    echo "Find info on how to use on https://gitlab.com/lightning-labs/pool"
  else
    echo " Failed to install Lightning pool "
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
    echo "# REMOVING pool SERVICE"
    # remove the systemd service
    sudo systemctl stop poold
    sudo systemctl disable poold
    sudo rm /etc/systemd/system/poold.service
    # delete user 
    sudo rm -rf pool
    echo "# OK, the pool Service is removed."
  else 
    echo "# pool is not installed."
  fi

  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run normal again"
exit 1
