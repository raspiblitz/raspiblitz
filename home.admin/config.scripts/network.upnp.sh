#!/bin/bash

# based on: https://github.com/raspibolt/raspibolt/issues/249

if [ $# -eq 0 ]; then
 echo "small config script to switch the BTC UPnP on or off"
 echo "network.upnp.sh [on|off]"
 exit 1
fi

# load config values
source /home/admin/raspiblitz.info 2>/dev/null
source /mnt/hdd/raspiblitz.conf 2>/dev/null
if [ ${#network} -eq 0 ]; then
  echo "FAIL - was not able to load config data / network"
  exit 1
fi

# check lnd.conf exits 
confExists=$(sudo ls /mnt/hdd/${network}/${network}.conf | grep -c "${network}.conf")
if [ ${confExists} -eq 0 ]; then
  echo "FAIL - /mnt/hdd/${network}/${network}.conf"
  exit 1
fi

# check if "nat=" exists in lnd config
valueExists=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep -c 'upnp=')
if [ ${valueExists} -eq 0 ]; then
  echo "Adding upnp config defaults to /mnt/hdd/${network}/${network}.conf"
  sudo sed -i '$ a upnp=0' /mnt/hdd/${network}/${network}.conf
fi

# stop services
echo "making sure services are not running"
sudo systemctl stop ${network}d 2>/dev/null

# add default value to raspi config if needed
if [ ${#networkUPnP} -eq 0 ]; then
  echo "networkUPnP=off" >> /mnt/hdd/raspiblitz.conf
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "switching the NETWORK UPnP ON"
  # editing config
  echo "editing /mnt/hdd/${network}/${network}.conf"
  sudo sed -i "s/^upnp=.*/upnp=1/g" /mnt/hdd/${network}/${network}.conf
# edit raspi blitz config
  echo "editing /mnt/hdd/raspiblitz.conf"
  sudo sed -i "s/^networkUPnP=.*/networkUPnP=on/g" /mnt/hdd/raspiblitz.conf
  # enable lnd service
  echo "OK - UPnP is now ON"
  echo "needs reboot to activate new setting"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "switching the NETWORK UPnP OFF"
  # editing config
  echo "editing /mnt/hdd/${network}/${network}.conf"
  sudo sed -i "s/^upnp=.*/upnp=0/g" /mnt/hdd/${network}/${network}.conf
  # edit raspi blitz config
  echo "editing /mnt/hdd/raspiblitz.conf"
  sudo sed -i "s/^networkUPnP=.*/networkUPnP=off/g" /mnt/hdd/raspiblitz.conf
  # enable lnd service
  echo "OK - UPnP is now OFF"
  echo "needs reboot to activate new setting"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
echo "may needs reboot to run normal again"
exit 1