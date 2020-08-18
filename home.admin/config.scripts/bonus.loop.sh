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
    /home/admin/config.scripts/bonus.go.sh on
    
    # get Go vars
    source /etc/profile

    cd /home/bitcoin
    sudo -u bitcoin git clone https://github.com/lightninglabs/loop.git
    cd /home/bitcoin/loop
    # https://github.com/lightninglabs/loop/releases
    source <(sudo -u admin /home/admin/config.scripts/lnd.update.sh info)
    if [ ${lndInstalledVersionMain} -lt 10 ]; then
      sudo -u bitcoin git reset --hard v0.5.1-beta
    else
      sudo -u bitcoin git reset --hard v0.8.0-beta
    fi
    cd /home/bitcoin/loop/cmd
    go install ./...
    
    # make systemd service
    # sudo nano /etc/systemd/system/loopd.service 
    echo "
[Unit]
Description=Loopd Service
After=lnd.service

[Service]
WorkingDirectory=/home/bitcoin/loop
ExecStart=/usr/local/gocode/bin/loopd --network=${chain}net
User=bitcoin
Group=bitcoin
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
  
  isInstalled=$(loop | grep -c loop)
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
    sudo systemctl stop loopd
    sudo systemctl disable loopd
    sudo rm /etc/systemd/system/loopd.service
    sudo rm -rf /home/bitcoin/loop
    sudo rm  /usr/local/gocode/bin/loop
    sudo rm  /usr/local/gocode/bin/loopd
    echo "OK, the Loop Service is removed."
  else 
    echo "Loop is not installed."
  fi

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
echo "may need reboot to run normal again"
exit 1
  