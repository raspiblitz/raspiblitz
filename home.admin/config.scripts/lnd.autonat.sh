#!/bin/bash

# based on: https://github.com/raspibolt/raspibolt/issues/249

if [ $# -eq 0 ]; then
 echo "small config script to switch the LND autoNatDiscovery on or off"
 echo "lnd.autonat.sh [on|off|info]"
 exit 1
fi

# check lnd.conf exits
lndConfExists=$(sudo ls /mnt/hdd/lnd/lnd.conf | grep -c 'lnd.conf')
if [ ${lndConfExists} -eq 0 ]; then
  echo "# FAIL - /mnt/hdd/lnd/lnd.conf not found"
  exit 1
fi

# info
if [ "$1" = "info" ]; then
  natIsOn=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep -c 'nat=true')
  if [ "${natIsOn}" == "1" ]; then
    echo "autoNatDiscovery=on"
  else
    echo "autoNatDiscovery=off"
  fi
  exit 0
fi

# check if "nat" exists in lnd config
valueExists=$(sudo cat /mnt/hdd/lnd/lnd.conf | grep -c 'nat=')
if [ ${valueExists} -eq 0 ]; then
  echo "# Adding autonat config defaults to /mnt/hdd/lnd/lnd.conf"
  applicationOptionsLineNumber=$(grep -n "\[Application Options\]" /mnt/hdd/lnd/lnd.conf | cut -d ":" -f1)
  applicationOptionsLineNumber="$(($applicationOptionsLineNumber+1))"
  sudo sed -i "${applicationOptionsLineNumber}inat=false" /mnt/hdd/lnd/lnd.conf
fi

# delete nat is still in raspiblitz.conf (its OK when just in lnd.conf since v1.7.2)
/home/admin/config.scripts/blitz.conf.sh delete autoNatDiscovery

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# switching the LND autonat ON"
  sudo sed -i "s/^nat=.*/nat=true/g" /mnt/hdd/lnd/lnd.conf
  echo "# OK - autonat is now ON"
  echo "# needs reboot to activate new setting"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# switching the LND autonat OFF"
  sudo sed -i "s/^nat=.*/nat=false/g" /mnt/hdd/lnd/lnd.conf
  echo "# OK - autonat is now OFF"
  echo "# needs reboot to activate new setting"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
echo "may needs reboot to run normal again"
exit 1