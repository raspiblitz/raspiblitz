#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install or uninstall balance of satoshis"
 echo "bonus.bos.sh [on|off|menu]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^bos=" /mnt/hdd/raspiblitz.conf; then
  echo "bos=off" >> /mnt/hdd/raspiblitz.conf
fi

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " Info Balance of Satoshis " --msgbox "\n\
Usage: https://github.com/alexbosworth/balanceofsatoshis/blob/master/README.md
To start type: 'sudo su bos' in the command line.\n
Then see 'bos help' for options.
" 9 75
  exit 0
fi

# install
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ "${bos}" == "on" ]; then
    echo "# FAIL - bos already installed"
    sleep 3
    exit 1
  fi
  
  echo "*** INSTALL BALANCE OF SATOSHIS ***"
  # check and install NodeJS
  /home/admin/config.scripts/bonus.nodejs.sh
  
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
  
  # make sure rtl is member of lndadmin
  sudo /usr/sbin/usermod --append --groups lndadmin bos
  
  # install bos
  sudo -u bos npm install -g balanceofsatoshis

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

echo "FAIL - Unknown Parameter $1"
exit 1
