#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the Lightning Loop Service on or off"
 echo "bonus.loop.sh [on|off|menu]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^loop=" /mnt/hdd/raspiblitz.conf; then
  echo "loop=off" >> /mnt/hdd/raspiblitz.conf
fi

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " Info Loop Service " --msgbox "\n\
Usage and examples: https://github.com/lightninglabs/loop#loop-out-swaps\n
Use the command 'loop' on the terminal to see the options.
" 10 56
  exit 0
fi

# stop services
echo "making sure the loop service is not running"
sudo systemctl stop loopd 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL LIGHTNING LOOP ***"
  
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

    # make sure symlink to central app-data directory exists ***"
    sudo rm -rf /home/loop/.lnd  # not a symlink.. delete it silently
    # create symlink
    sudo ln -s /mnt/hdd/app-data/lnd/ /home/loop/.lnd

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

    # install from source
    cd /home/loop
    sudo -u loop git clone https://github.com/lightninglabs/loop.git
    cd /home/loop/loop
    # https://github.com/lightninglabs/loop/releases
    sudo -u loop git reset --hard v0.9.0-beta
    cd /home/loop/loop/cmd
    sudo -u loop /usr/local/go/bin/go install ./... || exit 1

    # make systemd service
    if [ "${runBehindTor}" = "on" ]; then
      echo "Will connect to Loop server through Tor"
      proxy="--server.proxy=127.0.0.1:9050"
    else
      echo "Will connect to Loop server through clearnet"
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
KillMode=process
TimeoutSec=60
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
" | sudo tee -a /etc/systemd/system/loopd.service
    sudo systemctl enable loopd
    echo "OK - the Lightning Loop service is now enabled"

  else 
    echo "Loop service already installed."
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^loop=.*/loop=on/g" /mnt/hdd/raspiblitz.conf
  
  isInstalled=$(sudo -u loop /home/loop/go/bin/loop | grep -c loop)
  if [ ${isInstalled} -gt 0 ] ; then
    echo "Find info on how to use on https://github.com/lightninglabs/loop#loop-out-swaps"
  else
    echo " Failed to install Lightning Loop "
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
    echo "*** REMOVING LIGHTNING LOOP SERVICE ***"
    # remove the systemd service
    sudo systemctl stop loopd
    sudo systemctl disable loopd
    sudo rm /etc/systemd/system/loopd.service
    # delete user and it's home directory
    sudo userdel -rf loop
    echo "OK, the Loop Service is removed."
  else 
    echo "Loop is not installed."
  fi

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
echo "may need reboot to run normal again"
exit 1
  