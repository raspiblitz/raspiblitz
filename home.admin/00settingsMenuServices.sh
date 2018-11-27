#!/bin/bash

# get raspiblitz config
source /mnt/hdd/raspiblitz.conf

# show select dialog
CHOICES=$(dialog --checklist "Activate/Deactivate Services:" 15 40 5 \
1 "Channel Autopilot" ${autoPilot} \
2>&1 >/dev/tty)
#CHOICES=$(dialog --checklist "Activate/Deactivate Services:" 15 40 5 \
#1 "Channel Autopilot" ${autoPilot} \
#2 "UPnP Router-Portforwarding" ${natUPnP} \
#3 "Auto Unlock on Start" ${autoUnlock} \
#4 "Seed Torrent Blockchain" ${torrentSeed} \
#4 "RTL Webinterface" ${rtlWebinterface} \
#2>&1 >/dev/tty)
dialogcancel=$?
clear

# check if user canceled dialog
if [ ${dialogcancel} -eq 1 ]; then
  echo "user canceled"
  exit 1
fi

# AUTOPILOT process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "1")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${autoPilot}" != "${choice}" ]; then
  echo "Autopilot Setting changed"
  echo "Stopping Service"
  sudo systemctl stop lnd
  echo "Changing raspiblitz.conf"
  sudo sed -i "s/^autoPilot=.*/autoPilot=${choice}/g" /mnt/hdd/raspiblitz.conf
  echo "Executing change"
  sudo /home/admin/config.scripts/lnd.autopilot.sh ${choice}
  echo "Restarting Service" 
  echo "You may need to unlock after restart ..."
  sudo systemctl start lnd
  echo "Giving LND 120 seconds to get ready ..."
  sleep 120
else 
  echo "Autopilot Setting unchanged."
fi