#!/bin/bash

# using https://github.com/foundObjects/zram-swap
VERSION="205ea1ec5b169f566e5e98ead794e9daf90cf245"

if [ "$1" = status ]; then

  # check if file /home/admin/download/zram-swap/install.sh exists
  if [ ! -f /home/admin/download/zram-swap/install.sh ]; then
    echo "downloaded=1"
  else
    echo "downloaded=0"
  fi

  # check if service zram-swap is loaded/active
  serviceLoaded='sudo systemctl status zram-swap | grep -c loaded'
  if [ ${serviceLoaded} -gt 0 ]; then
    echo "serviceLoaded=1"
  else
    echo "serviceLoaded=0"
  fi  
  serviceActive='sudo systemctl status zram-swap | grep -c active'
  if [ ${serviceActive} -gt 0 ]; then
    echo "serviceActive=1"
  else
    echo "serviceActive=0"
  fi

  exit 0
fi

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to install ZRAM"
  echo "blitz.zram.sh [on|off|status]"
  echo "using https://github.com/foundObjects/zram-swap"
  exit 1
fi

mkdir /home/admin/download 2>/dev/null
cd /home/admin/download || exit 1
if [ ! -d zram-swap ]; then
  sudo -u admin git clone https://github.com/foundObjects/zram-swap.git
  cd zram-swap || exit 1
  git reset --hard $VERSION || exit 1
else
  cd zram-swap || exit 1
fi

if [ "$1" = on ]; then
  if [ $(sudo cat /proc/swaps | grep -c zram) -eq 0 ]; then
    # install zram to 1/2 of RAM, activate and prioritize
    sudo /home/admin/download/zram-swap/install.sh

    # make better use of zram
    echo "\
vm.vfs_cache_pressure=500
vm.swappiness=100
vm.dirty_background_ratio=1
vm.dirty_ratio=50
" | sudo tee -a  /etc/sysctl.conf

    # apply
    sudo sysctl --system
    echo "# ZRAM is installed and activated"
  else
    echo "# ZRAM was already installed and active."
  fi

  echo "Current swap usage:"
  sudo cat /proc/swaps
  exit 0
fi

if [ "$1" = off ]; then
  sudo /home/admin/download/zram-swap/install.sh --uninstall
  sudo rm /etc/default/zram-swap
  sudo rm -rf /home/admin/download/zram-swap
  echo "ZRAM was removed"
  echo "Current swap usage:"
  sudo cat /proc/swaps
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1