#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# handle the wifi"
 echo "# internet.wifi.sh status"
 echo "# internet.wifi.sh on SSID PASSWORD"
 echo "# internet.wifi.sh off"
 echo "# internet.wifi.sh backup-restore"
 exit 1
fi

wifiIsSet=$(sudo cat /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null| grep -c "network=")
wifiLocalIP=$(ip addr | grep 'state UP' -A2 | egrep -v 'docker0' | egrep -i '([wlan][0-9]$)' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
connected=0
if [ ${#wifiLocalIP} -gt 0 ]; then
  connected=1
fi

if [ "$1" == "status" ]; then

  echo "activated=${wifiIsSet}"
  echo "connected=${connected}"
  echo "localip='${wifiLocalIP}'"
  exit 0

elif [ "$1" == "on" ]; then

  ssid="$2"
  password="$3"

  if [ ${#ssid} -eq 0 ]; then
    echo "err='no ssid given'"
    exit 1
  fi

  if [ ${#password} -eq 0 ]; then
    echo "err='no password given'"
    exit 1
  fi

  wifiConfig="country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
network={
  ssid=\"${ssid}\"
  scan_ssid=1
  psk=\"${password}\"
  key_mgmt=WPA-PSK
}"
  echo "${wifiConfig}" > "/home/admin/wpa_supplicant.conf"
  sudo chown root:root /home/admin/wpa_supplicant.conf
  sudo mv /home/admin/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf
  sudo chmod 755 /etc/wpa_supplicant/wpa_supplicant.conf

  # activate new wifi settings
  sudo wpa_cli -i wlan0 reconfigure 1>/dev/null
  echo "# OK - changes should be actrive now - maybe reboot needed"
  exit 0

elif [ "$1" == "off" ]; then

  wifiConfig="country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1"
  echo "${wifiConfig}" > "/home/admin/wpa_supplicant.conf"
  sudo chown root:root /home/admin/wpa_supplicant.conf
  sudo mv /home/admin/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf
  sudo chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
  sudo rm /boot/wpa_supplicant.conf 2>/dev/null
  sudo rm /mnt/hdd/app-data/wpa_supplicant.conf 2>/dev/null


  # activate new wifi settings
  sudo wpa_cli -i wlan0 reconfigure 1>/dev/null
  echo "# OK - changes should be actrive now - maybe reboot needed"
  exit 0

# https://github.com/rootzoll/raspiblitz/issues/560
# when calling this it will backup wpa_supplicant.conf to HDD (if WIFI is active)
# or when WIFI is inactive but a wpa_supplicant.conf exists restore this
elif [ "$1" == "backup-restore" ]; then

  # check if HDD already exists
  if [ -d /mnt/hdd/app-data ]; then
    echo "# running backup/restore wifi settings"
  else
    echo "error='no hdd'"
    exit 1
  fi

  wifiBackUpExists=$()
  if [ ${wifiIsSet} -eq 1 ]; then
    # BACKUP latest wifi settings to HDD
    sudo cp /etc/wpa_supplicant/wpa_supplicant.conf /mnt/hdd/app-data/wpa_supplicant.conf 
    echo "wifiRestore=0"
    echo "wifiBackup=1"
    exit 0
  elif [ -f /mnt/hdd/app-data/wpa_supplicant.conf ]; then
    # RESTORE backuped wifi settings from HDD to RaspiBlitz
    sudo cp /mnt/hdd/app-data/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf
    echo "# restoring old wifi settings ... wait 4 secounds to connect"
    sudo wpa_cli -i wlan0 reconfigure 1>/dev/null
    sleep 4
    echo "wifiRestore=1"
    echo "wifiBackup=0"
    exit 0
  else
    # noting to backup or restore
    echo "wifiRestore=0"
    echo "wifiBackup=0"
    exit 0
  fi

else
  echo "err='parameter not known - run with -help'"
fi
