#!/bin/bash

# get raspiblitz config
source /mnt/hdd/raspiblitz.conf

# show select dialog
CHOICES=$(dialog --checklist "Activate/Deactivate Services:" 15 40 5 \
1 "Channel Autopilot" ${autoPilot} \
2 "Testnet" ${chain} \
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

needsReboot=0

# AUTOPILOT process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "1")
if [ ${check} -eq 1 ]; then choice="on"; fi
if [ "${autoPilot}" != "${choice}" ]; then
  echo "Autopilot Setting changed"
  echo "Stopping Service"
  sudo systemctl stop lnd
  echo "Executing change"
  sudo /home/admin/config.scripts/lnd.autopilot.sh ${choice}
  needsReboot=1
else 
  echo "Autopilot Setting unchanged."
fi

# TESTNET process choice
choice="main"; check=$(echo "${CHOICES}" | grep -c "2")
if [ ${check} -eq 1 ]; then choice="test"; fi
if [ "${chain}" != "${choice}" ]; then
  if [ "${network}" = "litecoin" ] && [ "${choice}"="test" ]; then
     dialog --title 'FAIL' --msgbox 'Litecoin-Testnet not available.' 5 25
  else
    echo "Testnet Setting changed"
    echo "Stopping Service"
    sudo systemctl stop lnd
    sudo systemctl stop ${network}d
    echo "Executing change"
    sudo /home/admin/config.scripts/network.chain.sh ${choice}net
    needsReboot=1
  fi
else 
  echo "Testnet Setting unchanged."
fi

if [ ${needsReboot} -eq 1 ]; then
   dialog --title 'OK' --msgbox 'System will reboot to activate changes.' 5 25
   sudo shutdown -r now
fi