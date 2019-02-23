#!/bin/bash

# based on: https://github.com/rootzoll/raspiblitz/issues/100#issuecomment-465997126

if [ $# -eq 0 ]; then
 echo "small config script set the port LND is running on"
 echo "lnd.setport.sh [portnumber]"
 exit 1
fi

portnumber=$1

# check port number is bigger then zero
if [ ${portnumber} -lt 1 ]; then
  echo "FAIL - portnumber(${portnumber}) not above 0"
  exit 1
fi

# check port number is smaller than max
if [ ${portnumber} -gt 65535 ]; then
  echo "FAIL - portnumber(${portnumber}) not below 65535"
  exit 1
fi

# check lnd.conf exits 
lndConfExists=$(sudo ls /mnt/hdd/lnd/lnd.conf | grep -c 'lnd.conf')
if [ ${lndConfExists} -eq 0 ]; then
  echo "FAIL - /mnt/hdd/lnd/lnd.conf not found"
  exit 1
fi

echo "DEBUG EXIT"
exit 0

# check if "listen=" exists in lnd config
valueExists=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep -c 'nat=')
if [ ${valueExists} -eq 0 ]; then
  echo "Adding autonat config defaults to /mnt/hdd/lnd/lnd.conf"
  sudo sed -i '$ a listen=0.0.0.0:9735' /mnt/hdd/lnd/lnd.conf
fi

# stop services
echo "making sure services are not running"
sudo systemctl stop lnd 2>/dev/null

echo "needs reboot to activate new setting"