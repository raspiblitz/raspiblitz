
#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to change between testnet and mainnet"
 echo "network.chain.sh [testnet|mainnet]"
 exit 1
fi

# check input
if [ "$1" != "testnet" ] && [ "$1" != "mainnet" ]; then
 echo "FAIL - unknnown value: $1"
 exit 1
fi

# check and load raspiblitz config
# to know which network is running
source /mnt/hdd/raspiblitz.conf 2>/dev/null
if [ ${#network} -eq 0 ]; then
 echo "FAIL - missing /mnt/hdd/raspiblitz.conf"
 exit 1
fi 

# testnet on litecoin cannot be set 
if [ "${network}" = "litecoin" ] && [ "$1" = "testnet" ]; then
  echo "FAIL - no lightning support for litecoin testnet"
  exit 1
fi

# editing network config files (hdd & admin user)
echo "edit ${network} config .."
if [ "$1" = "testnet" ]; then
  sudo sed -i "s/^testnet=.*/testnet=1/g" /mnt/hdd/${network}/${network}.conf
  sudo sed -i "s/^testnet=.*/testnet=1/g" /home/admin/.${network}/${network}.conf
else
  sudo sed -i "s/^testnet=.*/testnet=0/g" /mnt/hdd/${network}/${network}.conf
  sudo sed -i "s/^testnet=.*/testnet=0/g" /home/admin/.${network}/${network}.conf
fi

# editing lnd config files (hdd & admin user)
echo "edit lightning config .."
if [ "$1" = "testnet" ]; then
  sudo sed -i "s/^${network}.mainnet.*/${network}.mainnet=0/g" /mnt/hdd/lnd/lnd.conf
  sudo sed -i "s/^${network}.testnet.*/${network}.testnet=1/g" /mnt/hdd/lnd/lnd.conf
  sudo sed -i "s/^${network}.mainnet.*/${network}.mainnet=0/g" /home/admin/.lnd/lnd.conf
  sudo sed -i "s/^${network}.testnet.*/${network}.testnet=1/g" /home/admin/.lnd/lnd.conf
else
  sudo sed -i "s/^${network}.mainnet.*/${network}.mainnet=1/g" /mnt/hdd/lnd/lnd.conf
  sudo sed -i "s/^${network}.testnet.*/${network}.testnet=0/g" /mnt/hdd/lnd/lnd.conf
  sudo sed -i "s/^${network}.mainnet.*/${network}.mainnet=1/g" /home/admin/.lnd/lnd.conf
  sudo sed -i "s/^${network}.testnet.*/${network}.testnet=0/g" /home/admin/.lnd/lnd.conf
fi

# editing the raspi blitz config file
echo "edit raspiblitz config .."
if [ "$1" = "testnet" ]; then
  sudo sed -i "s/^chain=.*/chain=test/g" /mnt/hdd/raspiblitz.conf
else
  sudo sed -i "s/^chain=.*/chain=main/g" /mnt/hdd/raspiblitz.conf
fi

# now a reboot is needed to load all services fresh
# starting up process will display chain sync
# ask user todo reboot
echo "OK - all configs changed to: $1"
echo "needs reboot to activate new setting"
