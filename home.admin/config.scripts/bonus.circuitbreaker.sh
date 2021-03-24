#!/bin/bash

pinnedVersion="v0.2.0"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Config script to switch the circuitbreaker on, off or update to the latest release tag or commit"
  echo "bonus.circuitbreaker.sh [on|off|update|update commit|menu]"
  echo
  echo "Version to be installed by default: $pinnedVersion"
  echo "Source: https://github.com/lightningequipment/circuitbreaker"
  echo
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspiblitz.conf if needed
if ! grep -Eq "^circuitbreaker=" /mnt/hdd/raspiblitz.conf; then
  echo "circuitbreaker=off" >> /mnt/hdd/raspiblitz.conf
fi

isInstalled=$(sudo ls /etc/systemd/system/circuitbreaker.service 2>/dev/null | grep -c 'circuitbreaker.service')

# switch on
if [ "$1" = "menu" ]; then
  if [ ${isInstalled} -eq 1 ]; then
    dialog --title " circuitbreaker ${pinnedVersion} " --msgbox "\n
circuitbreaker is to Lightning what firewalls are to the internet.\n\n
Its a service running in the background - use to monitor:\n
sudo journalctl -fu circuitbreaker\n\n
For details and further information see:\n
https://github.com/lightningequipment/circuitbreaker/blob/master/README.md
" 11 78
    clear
  else
    echo "# Circuit Breaker is not installed."
  fi
  exit 0
fi

# stop services
echo "# Making sure the service is not running"
sudo systemctl stop circuitbreaker 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# Installing circuitbreaker $pinnedVersion"
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
    sudo -u circuitbreaker git reset --hard $pinnedVersion
    sudo -u circuitbreaker /usr/local/go/bin/go install ./... || exit 1

    ##################
    # config
    ##################
    echo
    echo "# Setting the example configuration from:"
    echo "# https://github.com/lightningequipment/circuitbreaker/blob/$pinnedVersion/circuitbreaker-example.yaml"
    echo "# Find it at: /home/circuitbreaker/.circutbreaker/circuitbreaker.yaml"
    echo
    sudo -u circuitbreaker mkdir /home/circuitbreaker/.circuitbreaker 2>/dev/null
    sudo -u circuitbreaker cp circuitbreaker-example.yaml \
    /home/circuitbreaker/.circuitbreaker/circuitbreaker.yaml

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
    echo "# OK - the circuitbreaker.service is now enabled"

  else 
    echo "# The circuitbreaker.service is already installed."
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^circuitbreaker=.*/circuitbreaker=on/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo -u circuitbreaker /home/circuitbreaker/go/bin/circuitbreaker --version | grep -c "circuitbreaker version")
  if [ ${isInstalled} -eq 1 ]; then
    echo

    source /home/admin/raspiblitz.info
    if [ "${state}" == "ready" ]; then
      echo "# OK - the circuitbreaker.service is enabled, system is on ready so starting service"
      sudo systemctl start circuitbreaker
    else
      echo "# OK - the circuitbreaker.service is enabled, to start manually use: sudo systemctl start circuitbreaker"
    fi
    echo "# Find more info at https://github.com/lightningequipment/circuitbreaker"
    echo "# Monitor with: 'sudo journalctl -fu circuitbreaker'"
  else
    echo "# Failed to install circuitbreaker "
    exit 1
  fi
  
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  if [ ${isInstalled} -eq 1 ]; then
    echo "# Removing the circuitbreaker.service"
    sudo systemctl stop circuitbreaker
    sudo systemctl disable circuitbreaker
    sudo rm /etc/systemd/system/circuitbreaker.service
    echo "# Removing the user and it's home directory"
    sudo userdel -rf circuitbreaker 2>/dev/null
    echo "# OK, Circuit Breaker is removed."
  else
    echo "# Circuit Breaker is not installed."
  fi

  # setting value in raspiblitz.conf
  sudo sed -i "s/^circuitbreaker=.*/circuitbreaker=off/g" /mnt/hdd/raspiblitz.conf

  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "# Updating Circuit Braker"
  cd /home/circuitbreaker/circuitbreaker
  # from https://github.com/apotdevin/thunderhub/blob/master/scripts/updateToLatest.sh
  # fetch latest master
  sudo -u circuitbreaker git fetch
  if [ "$2" = "commit" ]; then
    echo "# Updating to the latest commit in the default branch"
    TAG=$(git describe --tags)
  else
    TAG=$(git tag | sort -V | tail -1)
    # unset $1
    set --
    UPSTREAM=${1:-'@{u}'}
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse "$UPSTREAM")
    if [ $LOCAL = $REMOTE ]; then
      echo "# You are up-to-date on version" $TAG
      echo "# Starting the circuitbreaker service ... "
      sudo systemctl start circuitbreaker
      exit 0
    fi
  fi
  echo "# Pulling latest changes..."
  sudo -u circuitbreaker git pull -p
  sudo -u circuitbreaker git reset --hard $TAG
  echo "# Installing the version: $TAG"
  sudo -u circuitbreaker /usr/local/go/bin/go install ./... || exit 1
  echo
  echo "# Setting the example configuration from:"
  echo "# https://github.com/lightningequipment/circuitbreaker/blob/$TAG/circuitbreaker-example.yaml"
  echo "# Find it at: /home/circuitbreaker/.circutbreaker/circuitbreaker.yaml"
  sudo -u circuitbreaker mkdir /home/circuitbreaker/.circuitbreaker 2>/dev/null
  sudo -u circuitbreaker cp circuitbreaker-example.yaml \
  /home/circuitbreaker/.circuitbreaker/circuitbreaker.yaml
  echo
  echo "# Updated to version" $TAG
  echo
  echo "# Starting the circuitbreaker service ... "
  sudo systemctl start circuitbreaker
  echo "# Monitor with: 'sudo journalctl -fu circuitbreaker'"
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
echo "# may need reboot to run normal again"
exit 1