#!/bin/bash

if [ $# -eq 0 ]; then
 echo "small config script to switch the LND auto pilot on or off"
 echo "lnd.autopilot.sh [on|off] <mainnet|testnet|signet>"
 exit 1
fi

# check lnd.conf exits 
lndConfExists=$(sudo ls /mnt/hdd/lnd/${netprefix}lnd.conf | grep -c 'lnd.conf')
if [ ${lndConfExists} -eq 0 ]; then
  echo "FAIL - /mnt/hdd/lnd/${netprefix}lnd.conf not found"
  exit 1
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars lnd $2)

# stop services
echo "making sure services are not running"
sudo systemctl stop lnd 2>/dev/null

# check if "${netprefix}autopilot.active" exists
valueExists=$(sudo cat /mnt/hdd/lnd/${netprefix}lnd.conf | grep -c '${netprefix}autopilot.active=')
if [ ${valueExists} -eq 0 ]; then
  echo "Adding ${netprefix}autopilot config defaults to /mnt/hdd/lnd/${netprefix}lnd.conf"
  sudo sed -i '$ a [autopilot]' /mnt/hdd/lnd/${netprefix}lnd.conf
  sudo sed -i '$ a autopilot.active=0' /mnt/hdd/lnd/${netprefix}lnd.conf
  sudo sed -i '$ a autopilot.allocation=0.6' /mnt/hdd/lnd/${netprefix}lnd.conf
  sudo sed -i '$ a autopilot.maxchannels=5' /mnt/hdd/lnd/${netprefix}lnd.conf
fi

# add default value to raspi config if needed
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#${netprefix}autoPilot} -eq 0 ]; then
  echo "${netprefix}autoPilot=off" >> /mnt/hdd/raspiblitz.conf
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "switching the LND ${netprefix}autopilot ON"
  echo "editing /mnt/hdd/lnd/${netprefix}lnd.conf"
  sudo sed -i "s/^${netprefix}autopilot.active=.*/${netprefix}autopilot.active=1/g" /mnt/hdd/lnd/${netprefix}lnd.conf
  echo "editing /mnt/hdd/raspiblitz.conf"
  sudo sed -i "s/^${netprefix}autoPilot=.*/${netprefix}autoPilot=on/g" /mnt/hdd/raspiblitz.conf
  echo "OK - ${netprefix}autopilot is now ON"
  echo "needs reboot to activate new setting"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "switching the LND ${netprefix}autopilot OFF"
  echo "editing /mnt/hdd/lnd/${netprefix}lnd.conf"
  sudo sed -i "s/^${netprefix}autopilot.active=.*/${netprefix}autopilot.active=0/g" /mnt/hdd/lnd/${netprefix}lnd.conf
  echo "editing /mnt/hdd/raspiblitz.conf"
  sudo sed -i "s/^${netprefix}autoPilot=.*/${netprefix}autoPilot=off/g" /mnt/hdd/raspiblitz.conf
  echo "OK - ${netprefix}autopilot is now OFF"
  echo "needs reboot to activate new setting"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
echo "may needs reboot to run normal again"
exit 1