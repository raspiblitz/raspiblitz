#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install, uninstall ZeroTier"
 echo "bonus.zerotier.sh [on|off|menu]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^zerotier=" /mnt/hdd/raspiblitz.conf; then
  echo "zerotier=off" >> /mnt/hdd/raspiblitz.conf
fi

# show info menu
if [ "$1" = "menu" ]; then

networkDetails=$(sudo zerotier-cli listnetworks | grep OK)

dialog --title " Info ZeroTier " --msgbox "\n\
Manage your ZeroTier account at https://my.zerotier.com. Add additional devices
(desktop/laptop/mobile) to your network so they can communicate.\n\n\

Currentlly connected to: $(echo $networkDetails | awk '{ print $3}')\n
Assigned IP: $(echo $networkDetails | awk '{ print $9}')\n\n\

Find more information on how to get started:\n
https://zerotier.atlassian.net/wiki/spaces/SD/pages/8454145/Getting+Started+with+ZeroTier
" 13 100
  exit 0
fi

# install
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ "${zerotier}" == "on" ]; then
    echo "# FAIL - ZeroTier already installed"
    sleep 3
    exit 1
  fi

  echo "*** INSTALL ZeroTier ***"

  # Download ZeroTier GPG key and install ZeroTier
  curl -s 'https://raw.githubusercontent.com/zerotier/ZeroTierOne/master/doc/contact%40zerotier.com.gpg' | gpg --import
  if z=$(curl -s 'https://install.zerotier.com/' | gpg); then echo "$z" | sudo bash; fi

  # setting value in raspi blitz config
  sudo sed -i "s/^zerotier=.*/zerotier=on/g" /mnt/hdd/raspiblitz.conf

  echo ""
  echo "# ZeroTier is now installed on your RaspiBlitz"
  echo "# Check the ZeroTier menu entry for more details."
  echo ""

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "*** REMOVING ZEROTIER ***"
  sudo -u admin sudo apt -y purge zerotier-one

  # setting value in raspi blitz config
  sudo sed -i "s/^zerotier=.*/zerotier=off/g" /mnt/hdd/raspiblitz.conf

  echo ""
  echo "# OK, ZeroTier is removed."
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
