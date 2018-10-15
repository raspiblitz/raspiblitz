#!/bin/bash

# get raspiblitz config
source /mnt/hdd/raspiblitz.conf

# show select dialog
CHOICES=$(dialog --checklist "Choose OS:" 15 40 5 \
1 "Channel Autopilot" ${autoPilot} \
2>&1 >/dev/tty)
#CHOICES=$(dialog --checklist "Choose OS:" 15 40 5 \
#1 "Channel Autopilot" ${autoPilot} \
#2 "Seed Torrent Blockchain" ${torrentSeeding} \
#3 "RTL Webinterface" ${rtlWebinterface} \
#4 "Electrum Server" ${electrumServer} \
#2>&1 >/dev/tty)
clear

# check if user canceled dialog
if [ ${#CHOICES} -eq 0 ]; then
  echo "user canceled"
  exit 1
fi

# AUTOPILOT process choice
choice="off"; check=$(echo "${CHOICES}" | grep -c "1")
if [ ${check} -eq 1 ]; then choice="on"; fi
sudo sed -i "s/^autoPilot=.*/autoPilot=${choice}/g" /mnt/hdd/raspiblitz.conf

# TORRENTSEED process choice
#choice="off"; check=$(echo "${CHOICES}" | grep -c "2")
#if [ ${check} -eq 1 ]; then choice="on"; fi
#sudo sed -i "s/^torrentSeeding=.*/torrentSeeding=${choice}/g" /mnt/hdd/raspiblitz.conf

# RTLWEBINTERFACE process choice
#choice="off"; check=$(echo "${CHOICES}" | grep -c "3")
#if [ ${check} -eq 1 ]; then choice="on"; fi
#sudo sed -i "s/^rtlWebinterface=.*/rtlWebinterface=${choice}/g" /mnt/hdd/raspiblitz.conf

# ELECTRUMSERVER  process choice
#choice="off"; check=$(echo "${CHOICES}" | grep -c "4")
#if [ ${check} -eq 1 ]; then choice="on"; fi
#sudo sed -i "s/^electrumServer=.*/electrumServer=${choice}/g" /mnt/hdd/raspiblitz.conf

# show password info dialog
dialog --backtitle "Rebooting" --msgbox "To activate the settings a reboot is needed." 6 52
sudo shutdown -r now