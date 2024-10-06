#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to install, uninstall ZeroTier"
  echo "internet.zerotier.sh on [?networkid]"
  echo "internet.zerotier.sh off"
  echo "internet.zerotier.sh menu"
  exit 1
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

  sshUI=0
  networkID=$2
  if [ ${#networkID} -eq 0 ]; then

    sshUI=1
    trap 'rm -f "$_temp"' EXIT
    _temp=$(mktemp -p /dev/shm/)

    dialog --backtitle "RaspiBlitz - Settings" \
      --title "Join ZeroTier Network" \
      --inputbox "\nPlease enter the ZeroTier networkID to connect to:" 10 60 2>"$_temp"

    networkID=$(cat "$_temp")

    # Remove temporary file explicitly, though it's also handled by the EXIT trap
    rm -f "$_temp"

    if [ -z "$networkID" ]; then
      dialog --msgbox "ZeroTier Connection canceled." 8 46
      exit 0
    fi
    clear
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

    /home/admin/config.scripts/blitz.conf.sh set zerotier "${networkID}"

    # adding zero tier IP to LND TLS cert
    # sudo /home/admin/config.scripts/lnd.tlscert.sh ip-add 172.X
    # sudo /home/admin/config.scripts/lnd.credentials.sh reset "${chain:-main}net" tls
    # sudo /home/admin/config.scripts/lnd.credentials.sh sync "${chain:-main}net"

    if [ $sshUI -eq 1 ]; then
      dialog --msgbox "Your RaspiBlitz joined the ZeroTier network." 6 46
    else
      echo "# OK, ZeroTier is joined."
    fi

  else
    sudo -u admin sudo apt -y purge zerotier-one 1>&2
    if [ $sshUI -eq 1 ]; then
      dialog --msgbox "FAILED: Joining the ZeroTier networkID(${networkID})" 6 46
    else
      echo "error='ZeroTier join failed'"
    fi
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
  /home/admin/config.scripts/blitz.conf.sh set zerotier "off"

  echo "# OK, ZeroTier is removed."
  exit 0
fi

echo "error='unknown parameter'"
exit 1
