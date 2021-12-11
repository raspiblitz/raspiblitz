#!/bin/bash

# based on: https://github.com/raspibolt/raspibolt/issues/249

if [ $# -eq 0 ]; then
 echo "small config script to switch the LND autoNatDiscovery on or off"
 echo "lnd.autonat.sh [on|off]"
 exit 1
fi

# check lnd.conf exits 
lndConfExists=$(sudo ls /mnt/hdd/lnd/lnd.conf | grep -c 'lnd.conf')
if [ ${lndConfExists} -eq 0 ]; then
  echo "FAIL - /mnt/hdd/lnd/lnd.conf not found"
  exit 1
fi

# check if "nat=" exists in lnd config
valueExists=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep -c 'nat=')
if [ ${valueExists} -eq 0 ]; then
  echo "Adding autonat config defaults to /mnt/hdd/lnd/lnd.conf"
  sudo sed -i '$ a nat=false' /mnt/hdd/lnd/lnd.conf
fi

# stop services
echo "making sure services are not running"
sudo systemctl stop lnd 2>/dev/null

# add default value to raspi config if needed
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "switching the LND autonat ON"
  # editing lnd config
  echo "editing /mnt/hdd/lnd/lnd.conf"
  sudo sed -i "s/^nat=.*/nat=true/g" /mnt/hdd/lnd/lnd.conf
  # edit raspi blitz config
  echo "editing /mnt/hdd/raspiblitz.conf"
  /home/admin/config.scripts/blitz.conf.sh set autoNatDiscovery "on"
  echo "OK - autonat is now ON"
  echo "needs reboot to activate new setting"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "switching the LND autonat OFF"
  # editing lnd config
  echo "editing /mnt/hdd/lnd/lnd.conf"
  sudo sed -i "s/^nat=.*/nat=false/g" /mnt/hdd/lnd/lnd.conf
  # edit raspi blitz config
  echo "editing /mnt/hdd/raspiblitz.conf"
  /home/admin/config.scripts/blitz.conf.sh set autoNatDiscovery "off"
  echo "OK - autonat is now OFF"
  echo "needs reboot to activate new setting"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
echo "may needs reboot to run normal again"
exit 1