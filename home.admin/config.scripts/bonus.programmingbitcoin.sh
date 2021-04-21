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
This service downloads the book and exercises of 'Programming Bitcoin' by Jimmy Song.
Type 'pb' in the command line to start the environment.
" 11 78
  exit 0
fi


# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

    echo ""
    echo "# ***"
    echo "# Installing the book, excercises and materials of 'Programming Bitcoin' by Jimmy Song ..."
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

    echo ""
    echo "# ***"
    echo "# Installing virtualenv and requirements ..."
    echo "# ***"
    echo ""
    
    cd /home/programmingbitcoin/programmingbitcoin
    pip install virtualenv
    virtualenv -p python3 .venv
    . .venv/bin/activate
    pip install -r requirements.txt


    echo "# setting the autostart script for programmingbitcoin"
    echo "
cd /home/programmingbitcoin/programmingbitcoin
. .venv/bin/activate
jupyter notebook
    " | sudo -u programmingbitcoin tee -a /home/programmingbitcoin/.bashrc


   # setting value in raspi blitz config
    sudo sed -i "s/^programmingbitcoin=.*/programmingbitcoin=on/g" /mnt/hdd/raspiblitz.conf
   
    echo ""
    echo "# ***"
    echo "# OK - 'Programming Bitcoin' book and materials installed. Type 'pb' in the console to start the environment."
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