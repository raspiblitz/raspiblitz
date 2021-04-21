#!/bin/bash

ProgrammingBitcoinVersion="v0.1"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# config script to prepare your Raspiblitz to follow the exercises in the book Programming Bitcoin"
  echo "# on: installs the materials and exercises of the Programming Bitcoin book"
  echo "# off: removes the materials and exercises of the Programming Bitcoin book"
  echo "# bonus.programmingbitcoin.sh [on|off|menu]"
  echo "# ProgrammingBitcoin installation script $ProgrammingBitcoinVersion"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^programmingbitcoin=" /mnt/hdd/raspiblitz.conf; then
  echo "programmingbitcoin=off" >> /mnt/hdd/raspiblitz.conf
fi

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " Programming Bitcoin Info" --msgbox "
This service downloads the exercises of the book Programming Bitcoin by Jimmy Song.
Type 'pb' in the command line to start the environment.
" 11 78
  exit 0
fi


# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

    echo ""
    echo "# ***"
    echo "# Installing the excercises and materials of the book 'Programming Bitcoin' by Jimmy Song ..."
    echo "# ***"
    echo ""

    # create user
    sudo adduser --disabled-password --gecos "" programmingbitcoin 2>/dev/null

    # add local directory to path and set PATH for the user
    sudo bash -c "echo 'PATH=\$PATH:/home/programmingbitcoin/.local/bin' >> /home/programmingbitcoin/.profile"
    sudo bash -c "echo 'PATH=\$PATH:/home/programmingbitcoin/.local/share/composer' >> /home/programmingbitcoin/.profile"

    echo ""
    echo "# ***"
    echo "# Downloading data from the GitHub repository 'https://github.com/jimmysong/programmingbitcoin' ..."
    echo "# ***"
    echo ""
    cd /home/programmingbitcoin
    sudo -u programmingbitcoin git clone https://github.com/jimmysong/programmingbitcoin 2>/dev/null

   # setting value in raspi blitz config
    sudo sed -i "s/^programmingbitcoin=.*/programmingbitcoin=on/g" /mnt/hdd/raspiblitz.conf
   
    echo ""
    echo "# ***"
    echo "# OK - Materials from 'Programming Bitcoin' installed. Type 'pb' in the console to start the environment."
    echo "# ***"
    echo ""

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  isInstalled=1
  if [ ${isInstalled} -eq 1 ]; then
    
    echo ""
    echo "# ***"
    echo "# Removing the materials of Programming Bitcoin..."
    echo "# ***"
    echo ""
    # setting value in raspi blitz config
    sudo sed -i "s/^programmingbitcoin=.*/programmingbitcoin=off/g" /mnt/hdd/raspiblitz.conf
    
    # Remove user and stuff here
    sudo userdel -rf programmingbitcoin 2>/dev/null

    echo ""
    echo "# ***"
    echo "# OK - Programming Bitcoin removed."
    echo "# ***"
    echo ""
  else
    echo "# Programming Bitcoin has not been installed yet."
  fi
  exit 0
fi