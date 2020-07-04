#!/bin/bash

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# adding and removing a backup device (usb thumbdrive)"
 echo "# blitz.backupdevice.sh status"
 echo "# blitz.backupdevice.sh on [?DEVICEUUID]"
 echo "# blitz.backupdevice.sh off"
 echo "error='missing parameters'"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

#########################
# STATUS
#########################

# is on or off
if [ ${#localBackupDeviceUUID} -eq 0 ]; then

  # get all the devices that are not mounted and possible candidates
  drivecounter=0
  for disk in $(lsblk -o NAME,TYPE | grep "disk" | awk '$1=$1' | cut -d " " -f 1)
  do
    devMounted=$(lsblk -o MOUNTPOINT,NAME | grep "$disk" | grep -c "^/")
    # is raid candidate when not mounted and not the data drive cadidate (hdd/ssd)
    if [ ${devMounted} -eq 0 ] && [ "${disk}" != "${hdd}" ]; then
      sizeBytes=$(lsblk -o NAME,SIZE -b | grep "^${disk}" | awk '$1=$1' | cut -d " " -f 2)
      sizeGigaBytes=$(echo "scale=0; ${sizeBytes}/1024/1024/1024" | bc -l)
      vedorname=$(lsblk -o NAME,VENDOR | grep "^${disk}" | awk '$1=$1' | cut -d " " -f 2)
      mountoption="${disk} ${sizeGigaBytes} GB ${vedorname}"
      echo "backupCandidate[${drivecounter}]='${mountoption}'"
      drivecounter=$(($drivecounter +1))
    fi
  done
  echo "backupCandidates=${drivecounter}"

fi

if [ "$1" = "status" ]; then

  echo "# Backup Device Status"
  if [ ${#localBackupDeviceUUID} -gt 0 ]; then
    echo "backupdevice=on"
    echo "backupdeviceUUID='${localBackupDeviceUUID}'"
  else
    echo "backupdevice=off"
  fi

fi

#########################
# TURN ON
#########################

if [ "$1" = "on" ]; then

  echo "# BACKUP DEVICE ADD"

fi

#########################
# TURN OFF
#########################

if [ "$1" = "off" ]; then

  echo "# BACKUP DEVICE REMOVE"

fi

echo "error='unkown command'"
exit 1