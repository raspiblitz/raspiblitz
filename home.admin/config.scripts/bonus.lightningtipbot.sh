#!/bin/bash

# https://github.com/LightningTipBot/LightningTipBot/
BOTVERSION="v0.5"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "config script to install or uninstall LightningTipBot"
  echo "bonus.LightningTipBot.sh [on|off|update|menu]"
  echo
  echo "Version to be installed by default: $BOTVERSION"
  echo "Source: https://github.com/LightningTipBot/LightningTipBot/"
  echo 
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

isInstalled=$(sudo ls /etc/systemd/system/lightningtipbot.service 2>/dev/null | grep -c 'lightningtipbot.service')

# switch on
if [ "$1" = "menu" ]; then
  if [ ${isInstalled} -eq 1 ]; then
    whiptail --title " LightningTipBot " --msgbox "A tip bot and Bitcoin Lightning wallet on Telegram.\n
Its a service running in the background - use to monitor:
sudo journalctl -fu lightningtipbot\n
For more details and further information see:
https://github.com/LightningTipBot/LightningTipBot/blob/$BOTVERSION/README.md\n
Config file: /mnt/hdd/app-data/LightningTipBot/config.yaml" 15 78
    clear
  else
    echo "# LightningTipBot is not installed."
  fi
  exit 0
fi

# stop service
echo "making sure the LightningTipBot service is not running"
sudo systemctl stop lightningtipbot 2>/dev/null

# install
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL LightningTipBot ***"

  if [ ${isInstalled} -eq 0 ]; then

    # install Go
    /home/admin/config.scripts/bonus.go.sh on

    # get Go vars
    source /etc/profile

    # create dedicated user
    sudo adduser --system --group --home /home/lightningtipbot lightningtipbot

    # install from source
    cd /home/lightningtipbot
    sudo -u lightningtipbot git clone https://github.com/LightningTipBot/LightningTipBot.git
    cd LightningTipBot
    sudo -u lightningtipbot git reset --hard $BOTVERSION

    # Remove the old binary
    sudo rm -f LightningTipBot 2>/dev/null
    # Build the new binary
    sudo -u lightningtipbot /usr/local/go/bin/go build . || exit 1

    # set database path to HDD data so that its survives updates and migrations
    sudo mkdir /mnt/hdd/app-data/LightningTipBot 2>/dev/null

    # check if data exists
    dataExists=$(ls /mnt/hdd/app-data/LightningTipBot/config.yaml 2>/dev/null | grep -c "config.yaml")
    if [ "${dataExists}" == "0" ]; then
      sudo cp config.yaml.example /mnt/hdd/app-data/LightningTipBot/config.yaml
      sudo cp -r data/ /mnt/hdd/app-data/LightningTipBot/
    fi
    
    # backup just in case
    sudo mv data/ data.old
    sudo mv config.yaml config.yaml.old

    # set permissions on data
    sudo chown lightningtipbot:lightningtipbot -R /mnt/hdd/app-data/LightningTipBot

    # create symbolic links
    sudo ln -s /mnt/hdd/app-data/LightningTipBot/config.yaml /home/lightningtipbot/LightningTipBot/config.yaml
    sudo ln -s /mnt/hdd/app-data/LightningTipBot/data/ /home/lightningtipbot/LightningTipBot/

    echo "
[Unit]
Description=LightningTipBot Service
After=lnd.service
PartOf=lnd.service

[Service]
WorkingDirectory=/home/lightningtipbot/LightningTipBot
ExecStart=/home/lightningtipbot/LightningTipBot/LightningTipBot
User=lightningtipbot
Group=lightningtipbot
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
" | sudo tee -a /etc/systemd/system/lightningtipbot.service
    sudo systemctl enable lightningtipbot
    echo "# OK - the LightningTipBot service is now enabled"
  else 
    echo "# The LightningTipBot service is already installed."
  fi

  isInstalled=$(sudo ls /home/lightningtipbot/LightningTipBot/ 2>/dev/null | grep -c LightningTipBot)
  if [ ${isInstalled} -gt 0 ] ; then
    echo "# Find info on how to use on https://github.com/LightningTipBot/LightningTipBot/tree/$BOTVERSION#set-up-lnbits"
    echo "Please edit your config file: sudo nano /home/lightningtipbot/LightningTipBot/config.yaml"
    echo "Start the service when done: sudo systemctl start lightningtipbot"
    # setting value in raspi blitz config
    /home/admin/config.scripts/blitz.conf.sh set lightningtipbot "on"
  else
    echo "# Failed to build LightningTipBot"
    exit 1
  fi
  
  exit 0
fi


# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # check for second parameter: should data be deleted?
  deleteData=0
  if [ "$2" = "--delete-data" ]; then
    deleteData=1
  elif [ "$2" = "--keep-data" ]; then
    deleteData=0
  else
    if (whiptail --title " DELETE DATA? " --yesno "Do you want to delete\nthe LightningTipBot config and data?" 8 30); then
      deleteData=1
   else
      deleteData=0
    fi
  fi
  echo "# deleteData(${deleteData})"

  isInstalled=$(sudo ls /etc/systemd/system/lightningtipbot.service 2>/dev/null | grep -c 'lightningtipbot.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "# Removing the LightningTipBot service"
    # remove the systemd service
    sudo systemctl disable lightningtipbot
    sudo rm /etc/systemd/system/lightningtipbot.service
    # delete user and it's home directory
    sudo userdel -rf lightningtipbot
    echo "# OK, the LightningTipBot Service is removed."

    if [ ${deleteData} -eq 1 ]; then
      echo "# deleting data"
      sudo rm -R /mnt/hdd/app-data/LightningTipBot
    else
      echo "# keeping data"
    fi

  else 
    echo "# LightningTipBot is not installed."
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set lightningtipbot "off"

  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "# Updating LightningTipBot"
  cd /home/lightningtipbot/LightningTipBot

  # fetch latest master
  sudo -u lightningtipbot git fetch

  # unset $1
  set --
  UPSTREAM=${1:-'@{u}'}
  LOCAL=$(git rev-parse @)
  REMOTE=$(git rev-parse "$UPSTREAM")
  if [ $LOCAL = $REMOTE ]; then
    echo "# LightningTipBot is up-to-date"
  else
    echo "# Pulling latest changes..."
    sudo -u lightningtipbot git pull -p

    # Remove the old binary
    sudo rm -f LightningTipBot 2>/dev/null
    echo "# Build the new binary"
    sudo -u lightningtipbot /usr/local/go/bin/go build . || exit 1
  fi

  echo "# Start service"
  sudo systemctl start lightningtipbot
  echo "# Monitor with: 'sudo journalctl -fu lightningtipbot'"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit
