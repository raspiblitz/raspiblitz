#!/bin/bash

# deprecated - see: https://github.com/rootzoll/raspiblitz/issues/2290

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to change between testnet and mainnet"
 echo "network.chain.sh [testnet|mainnet]"
 exit 1
fi

# check input
if [ "$1" != "testnet" ] && [ "$1" != "mainnet" ]; then
 echo "FAIL - unknown value: $1"
 exit 1
fi

# check and load raspiblitz config
# to know which network is running
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then
 echo "FAIL - missing network info"
 exit 1
fi

# testnet on litecoin cannot be set 
if [ "${network}" = "litecoin" ] && [ "$1" = "testnet" ]; then
  echo "FAIL - no lightning support for litecoin testnet"
  exit 1
fi

# stop services
echo "making sure services are not running"
sudo systemctl stop lnd 2>/dev/null
sudo systemctl stop ${network}d 2>/dev/null

# editing network config files (hdd & admin user)
echo "edit ${network} config .."
# fix old lnd config file (that worked with switching comment)
sudo sed -i "s/^#testnet=.*/testnet=1/g" /mnt/hdd/${network}/${network}.conf
sudo sed -i "s/^#testnet=.*/testnet=1/g" /home/admin/.${network}/${network}.conf
# changes based on parameter
if [ "$1" = "testnet" ]; then
  echo "editing /mnt/hdd/${network}/${network}.conf"
  sudo sed -i "s/^testnet=.*/testnet=1/g" /mnt/hdd/${network}/${network}.conf
  echo "editing /home/admin/.${network}/${network}.conf"
  sudo sed -i "s/^testnet=.*/testnet=1/g" /home/admin/.${network}/${network}.conf
else
  echo "editing /mnt/hdd/${network}/${network}.conf"
  sudo sed -i "s/^testnet=.*/testnet=0/g" /mnt/hdd/${network}/${network}.conf
  echo "editing /home/admin/.${network}/${network}.conf"
  sudo sed -i "s/^testnet=.*/testnet=0/g" /home/admin/.${network}/${network}.conf
fi

# editing lnd config files (hdd & admin user)
echo "edit lightning config .."
# fix old lnd config file (that worked with switching comment)
sudo sed -i "s/^#bitcoin.testnet=.*/bitcoin.testnet=1/g" /mnt/hdd/lnd/lnd.conf
sudo sed -i "s/^#bitcoin.testnet=.*/bitcoin.testnet=1/g" /home/admin/.lnd/lnd.conf
# changes based on parameter
if [ "$1" = "testnet" ]; then
  echo "editing /mnt/hdd/lnd/lnd.conf"
  sudo sed -i "s/^${network}.mainnet.*/${network}.mainnet=0/g" /mnt/hdd/lnd/lnd.conf
  sudo sed -i "s/^${network}.testnet.*/${network}.testnet=1/g" /mnt/hdd/lnd/lnd.conf
  echo "editing /home/admin/.lnd/lnd.conf"
  sudo sed -i "s/^${network}.mainnet.*/${network}.mainnet=0/g" /home/admin/.lnd/lnd.conf
  sudo sed -i "s/^${network}.testnet.*/${network}.testnet=1/g" /home/admin/.lnd/lnd.conf
else
  echo "editing /mnt/hdd/lnd/lnd.conf"
  sudo sed -i "s/^${network}.mainnet.*/${network}.mainnet=1/g" /mnt/hdd/lnd/lnd.conf
  sudo sed -i "s/^${network}.testnet.*/${network}.testnet=0/g" /mnt/hdd/lnd/lnd.conf
  echo "editing /home/admin/.lnd/lnd.conf"
  sudo sed -i "s/^${network}.mainnet.*/${network}.mainnet=1/g" /home/admin/.lnd/lnd.conf
  sudo sed -i "s/^${network}.testnet.*/${network}.testnet=0/g" /home/admin/.lnd/lnd.conf
fi

# editing the raspi blitz config file
echo "editing /mnt/hdd/raspiblitz.conf"
if [ "$1" = "testnet" ]; then
  /home/admin/config.scripts/blitz.conf.sh set chain "test"
else
  /home/admin/config.scripts/blitz.conf.sh set chain "main"
fi

# edit RTL.conf (if active)
if [ "${rtlWebinterface}" = "on" ]; then
  echo "editing /home/admin/RTL/RTL.conf"
  sudo sed -i "s/^macroonPath=.*/macroonPath=\/mnt\/hdd\/lnd\/data\/chain\/${network}\/$1/g" /home/admin/RTL/RTL.conf
fi

# now a reboot is needed to load all services fresh
# starting up process will display chain sync
# ask user todo reboot
echo "OK - all configs changed to: $1"
echo "needs reboot to activate new setting"
