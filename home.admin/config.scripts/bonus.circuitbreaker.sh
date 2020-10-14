#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the circuitbreaker on or off"
 echo "bonus.circuitbreaker.sh [on|off|menu]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^circuitbreaker=" /mnt/hdd/raspiblitz.conf; then
  echo "circuitbreaker=off" >> /mnt/hdd/raspiblitz.conf
fi

# stop services
echo "# making sure the service is not running"
sudo systemctl stop circuitbreaker 2>/dev/null

isInstalled=$(sudo ls /etc/systemd/system/circuitbreaker.service 2>/dev/null | grep -c 'circuitbreaker.service')

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# installing circuitbreaker"
  if [ ${isInstalled} -eq 0 ]; then
    # install Go
    /home/admin/config.scripts/bonus.go.sh on
    
    # get Go vars
    source /etc/profile
    # create dedicated user
    sudo adduser --disabled-password --gecos "" circuitbreaker
    # set PATH for the user
    sudo bash -c "echo 'PATH=\$PATH:/home/circuitbreaker/go/bin/' >> /home/circuitbreaker/.profile"
    
    # make sure symlink to central app-data directory exists"
    sudo rm -rf /home/circuitbreaker/.lnd  # not a symlink.. delete it silently
    # create symlink
    sudo ln -s /mnt/hdd/app-data/lnd/ /home/circuitbreaker/.lnd
  
    # sync all macaroons and unix groups for access
    /home/admin/config.scripts/lnd.credentials.sh sync
    # macaroons will be checked after install  
    
    # add user to group with admin access to lnd
    sudo /usr/sbin/usermod --append --groups lndadmin circuitbreaker
    
    # install from source
    cd /home/circuitbreaker
    sudo -u circuitbreaker git clone https://github.com/lightningequipment/circuitbreaker.git
    cd circuitbreaker
    sudo -u circuitbreaker /usr/local/go/bin/go install ./... || exit 1

    ##################
    # config
    ##################
    # see https://github.com/lightningequipment/circuitbreaker#configuration
    echo "# create circuitbreaker.yaml"
    cat > /home/admin/circuitbreaker.yaml <<EOF
maxPendingHtlcs: 5
EOF
    # move in place and fix ownersip
    sudo -u circuitbreaker mkdir /home/circuitbreaker/.circuitbreaker
    sudo mv /home/admin/circuitbreaker.yaml /home/circuitbreaker/.circuitbreaker/circuitbreaker.yaml
    sudo chown circuitbreaker:circuitbreaker /home/circuitbreaker/.circuitbreaker/circuitbreaker.yaml
    
    # make systemd service
    # sudo nano /etc/systemd/system/circuitbreaker.service 
    echo "
[Unit]
Description=circuitbreaker Service
After=lnd.service

[Service]
WorkingDirectory=/home/circuitbreaker/circuitbreaker
ExecStart=/home/circuitbreaker/go/bin/circuitbreaker --network=${chain}net
User=circuitbreaker
Group=circuitbreaker
Type=simple
KillMode=process
TimeoutSec=60
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
" | sudo tee -a /etc/systemd/system/circuitbreaker.service
    sudo systemctl enable circuitbreaker
    echo "# OK - the circuitbreaker service is now enabled"

  else 
    echo "# circuitbreaker service is already installed."
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^circuitbreaker=.*/circuitbreaker=on/g" /mnt/hdd/raspiblitz.conf

  if [ ${isInstalled} -eq 0 ]; then
    echo "# Start in the background with: 'sudo systemctl start circuitbreaker'"
    echo "# Find more info at https://github.com/lightningequipment/circuitbreaker"
  else
    echo " Failed to install circuitbreaker "
    exit 1
  fi
  
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  if [ ${isInstalled} -eq 1 ]; then
    echo "# REMOVING the circuitbreaker SERVICE"
    # remove the systemd service
    sudo systemctl stop circuitbreaker
    sudo systemctl disable circuitbreaker
    sudo rm /etc/systemd/system/circuitbreaker.service
    # delete user and it's home directory
    sudo userdel -rf circuitbreaker
    echo "# OK, the circuitbreaker Service is removed."
  else 
    echo "# circuitbreaker is not installed."
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^circuitbreaker=.*/circuitbreaker=off/g" /mnt/hdd/raspiblitz.conf

  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run normal again"
exit 1