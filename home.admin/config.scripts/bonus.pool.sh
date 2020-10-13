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

echo "# move existing data dir to /mnt/hdd/app-data/"
sudo mv /home/pool/.pool /mnt/hdd/app-data/ 2>/dev/null

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
    sudo -u pool mkdir -p /mnt/hdd/app-data/.pool
    echo "# symlink"
    sudo ln -s /mnt/hdd/app-data/.pool /home/pool/ 2>/dev/null
    sudo chown pool:pool -R /mnt/hdd/app-data/.pool

    # set PATH for the user
    sudo bash -c "echo 'PATH=$PATH:/home/pool/go/bin/' >> /home/pool/.profile"

    # make sure symlink to central app-data directory exists
    sudo rm -rf /home/pool/.lnd  # not a symlink.. delete it silently
    # create symlink
    sudo ln -s /mnt/hdd/app-data/lnd/ /home/pool/.lnd

    # install from source
    cd /home/pool
    # copy ssh keys from admin
    sudo cp -R /home/admin/.ssh /home/pool/
    sudo chown -R pool:pool /home/pool/.ssh
    sudo -u pool git clone git@gitlab.com:lightning-labs/pool.git || exit 1
    # pin version
    # sudo -u pool git reset --hard
    cd /home/pool/pool
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
    echo "Find info on how to use on https://gitlab.com/lightning-labs/pool"
    
    # add to _commands.sh
    if [ $(grep -c "sudo su - pool" < /home/admin/_commands.sh) -eq 0 ]; then
      cat << EOF | tee -a /home/admin/_commands.sh >/dev/null
# command: pool
# switch to the pool user for the Pool Service
function pool() {
  if [ $(grep -c "pool=on"  < /mnt/hdd/raspiblitz.conf) -eq 1 ]; then
    echo "# switching to the pool user with the command: 'sudo su - pool'"
    sudo su - pool
  else
    echo "Pool is not installed - to install run:"
    echo "/home/admin/config.scripts/bonus.pool.sh on"
  fi
}
EOF
    
    fi
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
    # delete user and it's home directory
    sudo userdel -rf pool
    echo "# OK, the pool Service is removed."
  else 
    echo "# pool is not installed."
  fi

  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run normal again"
exit 1
