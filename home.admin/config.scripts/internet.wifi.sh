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

# gather status information
wifiIsSet=$(nmcli connection show | grep -c "wifi")
[ ${wifiIsSet} -gt 1 ] && wifiIsSet=1
wifiLocalIP=$(ip addr | grep 'state UP' -A2 | grep -E -v 'docker0|veth' | grep -E -i '([wlan][0-9]$)' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
connected=0
if [ ${#wifiLocalIP} -gt 0 ]; then
  connected=1
fi

if [ "$1" == "status" ]; then
  echo "activated=${wifiIsSet}"
  echo "connected=${connected}"
  echo "localip='${wifiLocalIP}'"
  exit 0
fi

if [ "$1" == "on" ]; then

  # get and check parameters
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

  # activate wifi
  echo "# activating wifi ... give 10 secs to get ready"
  sudo nmcli radio wifi on
  sleep 10

  echo "# trying to connect to SSID(${ssid}) ..."
  sudo nmcli device wifi connect "${ssid}" password "${password}"
  errorCode=$?
  if [ ${errorCode} -gt 0 ]; then
    echo "err='error code ${errorCode}'"
    exit 1
  fi

  echo "# OK - changes should be active now"
  exit 0
fi

if [ "$1" == "off" ]; then

  # remove all wifi connection coinfigs
  nmcli connection show | grep wifi | cut -d " " -f 1 | while read -r line ; do
    echo "# deactivating wifi connection: ${line}"
    sudo nmcli connection delete "${line}"
  done

  # turn wifi off
  sudo nmcli radio wifi off

  # delete any backups on HDD/SSD (new and legacy)
  sudo rm /mnt/hdd/app-data/wifi/* 2>/dev/null
  sudo rm /mnt/hdd/app-data/wpa_supplicant.conf 2>/dev/null

  echo "# OK - WIFI is now off"
  exit 0
fi

# https://github.com/rootzoll/raspiblitz/issues/560
# when calling this it will backup the wifi config to HDD/SSD (if WIFI is active)
# or when WIFI is inactive but a backup on HDD/SSD exists restore this
if [ "$1" == "backup-restore" ]; then

  # print wifi state 
  echo "wifiIsSet=${wifiIsSet}"

  # check if HDD backup location is available (for backup or restore)
  hddBackupLocationAvailable=0
  if [ -d /mnt/hdd/app-data ]; then
    hddBackupLocationAvailable=1
    sudo mkdir /mnt/hdd/app-data/wifi 2>/dev/null
  fi
  echo "hddBackupLocationAvailable=${hddBackupLocationAvailable}"

  hddRestoreConfigAvailable=0
  if [ ${hddBackupLocationAvailable} -eq 1 ] && [ "$(ls -A /mnt/hdd/app-data/wifi)" ]; then
         # the directory /mnt/hdd/app-data/wifi contains files.
        hddRestoreConfigAvailable=1
  fi
  echo "hddRestoreConfigAvailable=${hddRestoreConfigAvailable}"

  # check if mem copy of wifi config is available (for restore only)
  # this should be available if a backup on HDD exists and HDD is not mounted yet but was inspected by datadrive script
  memRestoreConfigAvailable=0
  if [ -d /var/cache/raspiblitz/hdd-inspect/wifi ] && [ "$(ls -A /var/cache/raspiblitz/hdd-inspect/wifi)" ]; then
    memRestoreConfigAvailable=1
  fi
  echo "memRestoreConfigAvailable=${memRestoreConfigAvailable}"

  restorePending=/etc/NetworkManager/system-connections/.raspiblitz-restore-pending
  if [ ${wifiIsSet} -eq 1 ] && [ ! -f "$restorePending" ]; then
    # BACKUP latest wifi settings to HDD if available
    if [ ${hddBackupLocationAvailable} -eq 1 ]; then
      sudo cp -a /etc/NetworkManager/system-connections/* /mnt/hdd/app-data/wifi
      echo "wifiRestore=0"
      echo "wifiBackup=1"
    else
      echo "wifiRestore=0"
      echo "wifiBackup=0"
    fi
    exit 0
  elif [ ${hddRestoreConfigAvailable} -eq 1 ] || [ ${memRestoreConfigAvailable} -eq 1 ]; then
    restoreFrom=/var/cache/raspiblitz/hdd-inspect/wifi
    if [ ${hddRestoreConfigAvailable} -eq 1 ]; then
      restoreFrom=/mnt/hdd/app-data/wifi
    fi
    if ! sudo python3 /home/admin/config.scripts/internet.wifi.restore.py "$restoreFrom" ||
       ! sudo nmcli radio wifi on; then
      echo "wifiRestore=0"
      echo "wifiBackup=0"
      exit 1
    fi
    sleep 10
    if ! sudo systemctl restart NetworkManager; then
      echo "wifiRestore=0"
      echo "wifiBackup=0"
      exit 1
    fi
    sleep 4
    if LC_ALL=C nmcli -t -f TYPE,STATE device status | grep -Fxq 'wifi:connected'; then
      echo "wifiActive=1"
    else
      echo "wifiActive=0"
    fi
    echo "wifiRestore=1"
    echo "wifiBackup=0"
    exit 0
  elif [ -f "$restorePending" ]; then
    echo "wifiRestore=0"
    echo "wifiBackup=0"
    echo "# Wi-Fi restore was interrupted. Reconnect the original backup and retry."
    exit 1
  else
    # Old releases saved wpa_supplicant settings, which NetworkManager cannot load as a keyfile.
    if [ -f /var/cache/raspiblitz/hdd-inspect/legacy-wifi ] ||
       { [ -f /mnt/hdd/app-data/wpa_supplicant.conf ] && [ -s /mnt/hdd/app-data/wpa_supplicant.conf ] && [ ! -L /mnt/hdd/app-data/wpa_supplicant.conf ]; }; then
      echo "wifiRestoreNeedsSetup=1"
      echo "# Legacy Wi-Fi backup found. Connect Ethernet or run sudo nmtui on the local console."
      echo "# Check the WLAN country if the adapter is unavailable."
    fi
    echo "wifiRestore=0"
    echo "wifiBackup=0"
    exit 0
  fi
fi

# error case
echo "err='parameter not known - run with -help'"
exit 1
