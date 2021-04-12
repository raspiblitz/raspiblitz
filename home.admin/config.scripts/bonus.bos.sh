#!/bin/bash

# https://github.com/alexbosworth/balanceofsatoshis/blob/ba7c35b42f1bad0dbb0c9c03d64ee34472665029/package.json#L79
BOSVERSION="8.0.5"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install, update or uninstall Balance of Satoshis"
 echo "bonus.bos.sh [on|off|menu|update]"
 echo "installs the version $BOSVERSION by default"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^bos=" /mnt/hdd/raspiblitz.conf; then
  echo "bos=off" >> /mnt/hdd/raspiblitz.conf
fi

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " Info Balance of Satoshis " --msgbox "
Balance of Satoshis is a command line tool.
Type: 'bos' in the command line to switch to the dedicated user.
Then see 'bos help' for the options.
Usage: https://github.com/alexbosworth/balanceofsatoshis/blob/master/README.md
" 10 75
  exit 0
fi

# install
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ $(sudo ls /home/bos/.npmrc 2>/dev/null | grep -c ".npmrc") -gt 0 ]; then
    echo "# FAIL - bos already installed"
    sleep 3
    exit 1
  fi
  
  echo "*** INSTALL BALANCE OF SATOSHIS ***"
  # check and install NodeJS
  /home/admin/config.scripts/bonus.nodejs.sh on
  
  # create bos user
  sudo adduser --disabled-password --gecos "" bos
  
  # set up npm-global
  sudo -u bos mkdir /home/bos/.npm-global
  sudo -u bos npm config set prefix '/home/bos/.npm-global'
  sudo bash -c "echo 'PATH=$PATH:/home/bos/.npm-global/bin' >> /home/bos/.bashrc"
  
  # download source code
  sudo -u bos git clone https://github.com/alexbosworth/balanceofsatoshis.git /home/bos/balanceofsatoshis
  cd /home/bos/balanceofsatoshis
  
  # make sure symlink to central app-data directory exists ***"
  sudo rm -rf /home/bos/.lnd  # not a symlink.. delete it silently
  # create symlink
  sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/bos/.lnd"
  
  # add user to group with admin access to lnd
  sudo /usr/sbin/usermod --append --groups lndadmin bos
  
  # install bos
  # check latest version:
  # https://github.com/alexbosworth/balanceofsatoshis/blob/master/package.json#L70
  sudo -u bos npm install -g balanceofsatoshis@$BOSVERSION
  if ! [ $? -eq 0 ]; then
    echo "FAIL - npm install did not run correctly, aborting"
    exit 1
  fi


  # setting value in raspi blitz config
  sudo sed -i "s/^bos=.*/bos=on/g" /mnt/hdd/raspiblitz.conf

  echo "# Usage: https://github.com/alexbosworth/balanceofsatoshis/blob/master/README.md"
  echo "# To start type: 'sudo su bos' in the command line."
  echo "# Then see 'bos help' for options."
  echo "# To exit the user - type 'exit' and press ENTER"

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^bos=.*/bos=off/g" /mnt/hdd/raspiblitz.conf
  
  echo "*** REMOVING BALANCE OF SATOSHIS ***"
  sudo userdel -rf bos
  echo "# OK, bos is removed."
  exit 0

fi

# update
if [ "$1" = "update" ]; then
  echo "*** UPDATING BALANCE OF SATOSHIS ***"
  sudo -u bos npm i -g balanceofsatoshis
  echo "*** Updated to the latest in https://github.com/alexbosworth/balanceofsatoshis ***"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
