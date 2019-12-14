#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the Lightning Loop Service on or off"
 echo "bonus.loop.sh [on|off]"
 exit 1
fi

# add default value to raspi config if needed
if [ ${#loop} -eq 0 ]; then
  echo "loop=off" >> /mnt/hdd/raspiblitz.conf
fi

# stop services
echo "making sure the loop service is not running"
sudo systemctl stop loopd 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL LIGHTNING LOOP ***"
  
  isInstalled=$(sudo ls /etc/systemd/system/loopd.service 2>/dev/null | grep -c 'loopd.service')
  if [ ${isInstalled} -eq 0 ]; then
    /home/admin/config.scripts/go.install.sh
    
    cd /home/bitcoin
    sudo -u bitcoin git clone https://github.com/lightninglabs/loop.git
    cd /home/bitcoin/loop
    sudo -u bitcoin git reset --hard v0.3.0-alpha
    cd /home/bitcoin/loop/cmd
    go install ./...
    
    # make systemd service
    # sudo nano /etc/systemd/system/electrs.service 
    echo "
[Unit]
Description=Loopd Service
After=lnd.service

[Service]
WorkingDirectory=/home/bitcoin/loop
ExecStart=/usr/local/gocode/bin/loopd
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
    echo "OK - the the Lightning Loop service is now enabled"

  else 
    echo "RTL already installed."
  fi
  
  # start service
  echo "Starting service"
  sudo systemctl start loopd 2>/dev/null

  # setting value in raspi blitz config
  sudo sed -i "s/^loop=.*/loop=on/g" /mnt/hdd/raspiblitz.conf

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^loop=.*/loop=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/loop.service 2>/dev/null | grep -c 'loop.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** REMOVING LIGHTNING LOOP SERVICE ***"
    sudo systemctl stop loop
    sudo systemctl disable loop
    sudo rm /etc/systemd/system/loop.service
    sudo rm -rf /home/bitcoin/loop
    echo "OK, the Loop Service is removed."
  else 
    echo "Loop is not installed."
  fi

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
echo "may need reboot to run normal again"
exit 1
  