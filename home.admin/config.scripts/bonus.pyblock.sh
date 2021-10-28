#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install, update or uninstall PyBlock"
 echo "bonus.pyblock.sh [on|off|menu|update]"
 exit 1
fi

source /mnt/hdd/

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " Info PyBlock " --msgbox "
pyblock is a command line tool.
Type: 'pyblock' in the command line to switch to the dedicated user.
Then 'pyblock' for starting PyBlock.
Usage: https://github.com/curly60e/pyblock/blob/master/README.md
" 10 75
  exit 0
fi

# install
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ $(sudo ls /home/pyblock/PyBLOCK 2>/dev/null | grep -c "bclock.conf") -gt 0 ]; then
    echo "# FAIL - pyblock already installed"
    sleep 3
    exit 1
  fi
  
  echo "*** INSTALL pyblocks***"
  
  # create pyblock user
  sudo adduser --disabled-password --gecos "" pyblock

  
  # download source code
  sudo -u pyblock git clone https://github.com/curly60e/pyblock.git /home/pyblock/PyBLOCK
  cd /home/pyblock/PyBLOCK
  sudo -u pyblock pip3 install -r requirements.txt
  sudo apt-get install hexyl

  # set PATH for the user
  sudo bash -c "echo 'PATH=\$PATH:/home/pyblock/.local/bin/' >> /home/pyblock/.profile"
  
  # add user to group with admin access to lnd
  sudo /usr/sbin/usermod --append --groups lndadmin pyblock
  
  sudo rm -rf /home/pyblock/.bitcoin  # not a symlink.. delete it silently
  sudo -u pyblock mkdir /home/pyblock/.bitcoin
  sudo cp /mnt/hdd/bitcoin/bitcoin.conf /home/pyblock/.bitcoin/
  sudo chown pyblock:pyblock /home/pyblock/.bitcoin/bitcoin.conf

  # make sure symlink to central app-data directory exists ***"
  sudo rm -rf /home/pyblock/.lnd  # not a symlink.. delete it silently
  # create symlink
  sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/pyblock/.lnd"
  
  ## Create conf
  # from xxd -p bclock.conf | tr -d '\n'
  echo 80037d710028580700000069705f706f727471015807000000687474703a2f2f710258070000007270637573657271035800000000710458070000007270637061737371056804580a000000626974636f696e636c697106581a0000002f7573722f6c6f63616c2f62696e2f626974636f696e2d636c697107752e0a | xxd -r -p -  ~/bclock.conf
  sudo mv ~/bclock.conf /home/pyblock/bclock.conf
  sudo chown pyblock:pyblock /home/pyblock/bclock.conf

  # from xxd -p blndconnect.conf | tr -d '\n'
  echo 80037d710028580700000069705f706f72747101580000000071025803000000746c737103680258080000006d616361726f6f6e7104680258020000006c6e710558140000002f7573722f6c6f63616c2f62696e2f6c6e636c697106752e0a | xxd -r -p -  ~/blndconnect.conf
  sudo mv ~/blndconnect.conf /home/pyblock/blndconnect.conf
  sudo chown pyblock:pyblock /home/pyblock/blndconnect.conf

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set pyblock "on"
  
  ## pyblock short command
  sudo bash -c "echo 'alias pyblock=\"cd ~; python3 ~/PyBLOCK/PyBlock.py\"' >> /home/pyblock/.bashrc"
  
  echo "# Usage: https://github.com/curly60e/pyblock/blob/master/README.md"
  echo "# To start type: 'sudo su pyblock' in the command line."
  echo "# Then pyblock"
  echo "# To exit the user - type 'exit' and press ENTER"

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set pyblock "off"
  
  echo "*** REMOVING PyBLOCK ***"
  sudo userdel -rf pyblock
  echo "# OK, pyblock is removed."
  exit 0

fi

# update
if [ "$1" = "update" ]; then
  echo "*** UPDATING PyBLOCK ***"
  cd /home/pyblock/PyBLOCK
  sudo -u pyblock git pull
  sudo -u pyblock pip3 install -r requirements.txt
  echo "*** Updated to the latest in https://github.com/curly60e/pyblock ***"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
