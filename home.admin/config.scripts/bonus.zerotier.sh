#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install, uninstall ZeroTier"
 echo "bonus.zerotier.sh on [?networkid]"
 echo "bonus.zerotier.sh off"
 echo "bonus.zerotier.sh menu"
 exit 1
fi 

# add default value to raspi config if needed
if ! grep -Eq "^zerotier=" /mnt/hdd/raspiblitz.conf; then
  echo "zerotier=off" | tee -a  /mnt/hdd/raspiblitz.conf
fi
source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then

networkDetails=$(sudo zerotier-cli listnetworks | grep OK)

whiptail --title " Info ZeroTier " --msgbox "\n\
Manage your ZeroTier account at https://my.zerotier.com. Add additional devices
(desktop/laptop/mobile) to your network so they can communicate.\n\n\

Currently connected to: $(echo $networkDetails | awk '{ print $3}')\n
Assigned IP: $(echo $networkDetails | awk '{ print $9}')\n\n\

Find more information on how to get started:\n
https://zerotier.atlassian.net/wiki/spaces/SD/pages/8454145/Getting+Started+with+ZeroTier
" 20 100
  exit 0
fi

# install
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ "${zerotier}" == "on" ]; then
    echo "# FAIL - ZeroTier already installed"
    sleep 3
    exit 1
  fi

  networkID=$2
  if [ ${#networkID} -eq 0 ]; then
    networkID=$(whiptail --inputbox "\nPlease enter the ZeroTier networkID to connect to:" 10 38 "" --title " Join ZeroTier Network " --backtitle "RaspiBlitz - Settings" 3>&1 1>&2 2>&3)
    networkID=$(echo "${networkID[0]}")
    if [ ${#networkID} -eq 0 ]; then
      echo "error='cancel'"
      exit 0
    fi
  fi

  echo "# *** INSTALL ZeroTier ***"

  # Download ZeroTier GPG key and install ZeroTier
  $(curl -s 'https://raw.githubusercontent.com/zerotier/ZeroTierOne/master/doc/contact%40zerotier.com.gpg' | gpg --import)
  if z=$(curl -s 'https://install.zerotier.com/' | gpg); then echo "$z" | sudo bash 1>&2; fi

  echo "# ZeroTier is now installed on your RaspiBlitz"
  echo "# Joining zerotier network: ${networkID}"

  joinOK=$(sudo zerotier-cli join ${networkID} | grep -c '200 join OK')
  if [ ${joinOK} -eq 1 ]; then
    echo "# OK - joined"

    # setting value in raspi blitz config
    sudo sed -i "s/^zerotier=.*/zerotier=${networkID}/g" /mnt/hdd/raspiblitz.conf

    # adding zero tier IP to LND TLS cert
    # sudo /home/admin/config.scripts/lnd.tlscert.sh ip-add 172.X
    # sudo /home/admin/config.scripts/lnd.credentials.sh reset tls
    # sudo /home/admin/config.scripts/lnd.credentials.sh sync

  else
    sudo -u admin sudo apt -y purge zerotier-one 1>&2
    echo "error='ZeroTier join failed'"
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# *** REMOVING ZEROTIER ***"

  # leaving network & deinstall
  sudo zerotier-cli leave ${zerotier} 1>&2
  sudo -u admin sudo apt -y purge zerotier-one 1>&2

  # setting value in raspi blitz config
  sudo sed -i "s/^zerotier=.*/zerotier=off/g" /mnt/hdd/raspiblitz.conf

  echo "# OK, ZeroTier is removed."
  exit 0
fi

echo "error='unknown parameter'"
exit 1