#!/bin/bash

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# bonus.i2pd.sh on       -> install the i2pd"
  echo "# bonus.i2pd.sh off      -> uninstall the i2pd"
  echo "# bonus.i2pd.sh addseednodes -> Add all I2P seed nodes from: https://github.com/bitcoin/bitcoin/blob/master/contrib/seeds/nodes_main.txt"
  exit 1
fi

function addAllI2pSeedNodes {
  echo "Add all I2P seed nodes from: https://github.com/bitcoin/bitcoin/blob/master/contrib/seeds/nodes_main.txt"
  i2pSeedNodeList=$(curl -sS https://raw.githubusercontent.com/bitcoin/bitcoin/master/contrib/seeds/nodes_main.txt | grep .b32.i2p:0)
  for i2pSeedNode in ${i2pSeedNodeList}; do
    bitcoin-cli addnode "$i2pSeedNode" "onetry"
  done
  echo
  echo "# Display sudo tail -n 100 /mnt/hdd/bitcoin/debug.log | grep i2p"
  sudo tail -n 100 /mnt/hdd/bitcoin/debug.log | grep i2p
  echo
  echo "# Display bitcoin-cli -netinfo 4"
  bitcoin-cli -netinfo 4
}


echo "# Running: 'bonus.i2pd.sh $*'"
source /mnt/hdd/raspiblitz.conf

isInstalled=$(sudo ls /etc/systemd/system/i2pd.service 2>/dev/null | grep -c "i2pd.service")
isRunning=$(systemctl status i2pd 2>/dev/null | grep -c 'active (running)')

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # dont run install if already installed
  if [ ${isInstalled} -eq 1 ]; then
    echo "# i2pd.service is already installed."
    exit 1
  fi


echo "# Installing i2pd ..."

  # Add repo for the latest version
  # i2pd — https://repo.i2pd.xyz/.help/readme.txt
  wget https://repo.i2pd.xyz/.help/add_repo
  # inspect the script:
  cat add_repo
  # add repo:
  sudo bash add_repo
  sudo apt-get update

  # install and start i2p
  sudo apt-get install i2pd
  sudo systemctl enable i2pd
  sudo systemctl start i2pd

  /home/admin/config.scripts/blitz.conf.sh set debug tor /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh add debug i2p /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh set ipsam 127.0.0.1:7656 /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh set i2pacceptincoming 1 /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh set onlynet i2p /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh add onlynet i2p /mnt/hdd/bitcoin/bitcoin.conf noquotes

  # Restart bitcoind:
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    # start service
    echo "# starting service ..."
    sudo systemctl restart bitcoind 2>/dev/null
    sleep 10
    echo "# monitor i2p in bitcoind"
    sudo tail -n 100 /mnt/hdd/bitcoin/debug.log | grep i2p
    bitcoin-cli -netinfo 4
  fi

fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# stop & remove systemd service"
  sudo systemctl stop i2pd 2>/dev/null
  sudo systemctl disable i2pd.service
  sudo rm /etc/systemd/system/i2pd.service

  echo "# Uninstall with apt"
  sudo apt remove i2pd

  echo "# Remove settings from bitcoind"
  /home/admin/config.scripts/blitz.conf.sh delete debug /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh set debug tor /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh delete debug /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh delete ipsam /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh delete i2pacceptincoming  /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh delete onlynet  /mnt/hdd/bitcoin/bitcoin.conf noquotes
  /home/admin/config.scripts/blitz.conf.sh set onlynet tor /mnt/hdd/bitcoin/bitcoin.conf noquotes

  echo "# OK - app should be uninstalled now"
  exit 0

fi

echo "# FAIL - Unknown Parameter $1"
exit 1
