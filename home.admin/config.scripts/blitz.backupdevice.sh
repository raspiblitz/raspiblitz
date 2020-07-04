#!/bin/bash

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# adding and removing a backup device (usb thumbdrive)"
 echo "# blitz.backupdevice.sh status"
 echo "# blitz.backupdevice.sh on [?DEVICEUUID|DEVICENAME]"
 echo "# blitz.backupdevice.sh off"
 echo "# blitz.backupdevice.sh mount"
 echo "error='missing parameters'"
 exit 1
fi

echo "### blitz.backupdevice.sh ###"
source /mnt/hdd/raspiblitz.conf

#########################
# STATUS
#########################

if [ "$1" = "status" ]; then

  if [ "${localBackupDeviceUUID}" != "" ] && [ "${localBackupDeviceUUID}" != "off" ]; then

    echo "backupdevice=1"
    echo "UUID='${localBackupDeviceUUID}'"

    # check if nackup device is mounted
    backupDeviceExists=$(df | grep -c "/mnt/backup")
    if [ ${backupDeviceExists} -gt 0 ]; then
      echo "isMounted=1"
    else
      echo "isMounted=0"
    fi

  else
    echo "backupdevice=0"
    
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

  exit 0
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='missing sudo'"
  exit 1
fi

#########################
# TURN ON
#########################

if [ "$1" = "on" ]; then

  echo "# BACKUP DEVICE ADD"

  # select and format device if UUID is not given
  uuid=$2
  if [ "${uuid}" == "" ]; then
    echo "# TODO: dialog to connect, choose and format device"
    exit 1
  fi

  # check that device is connected
  uuidConnected=$(lsblk -o UUID | grep -c "${uuid}")
  if [ ${uuidConnected} -eq 0 ]; then
    echo "# UUID not found - test is its a valid device name like sdb ..."
    isDeviceName=$(lsblk -o NAME,TYPE | grep "disk" | awk '$1=$1' | cut -d " " -f 1 | grep -c "${uuid}")
    if [ ${isDeviceName} -eq 1 ]; then
      hdd="${uuid}"
      # check if mounted
      checkIfAlreadyMounted=$(lsblk | grep "${hdd}" | grep -c '/mnt/')
      if [ ${checkIfAlreadyMounted} -gt 0 ]; then
        echo "# cannot format a device that is mounted"
        echo "error='device is used'"
        exit 1
      fi
      echo "# OK found device name ${hdd} that will now be formatted ..."
      echo "# Wiping all partitions (sfdisk/wipefs)"
      sudo sfdisk --delete /dev/${hdd} 1>&2
      sudo wipefs -a /dev/${hdd} 1>&2
      partitions=$(lsblk | grep -c "─${hdd}")
      if [ ${partitions} -gt 0 ]; then
        echo "# WARNING: partitions are still not clean"
        echo "error='partitioning failed'"
        exit 1
      fi
      # using FAT32 here so that the backup can be easily opened on Windows and Mac
      echo "# Create on big partition"
      sudo parted /dev/${hdd} mklabel msdos
      sudo parted /dev/${hdd} mkpart primary fat32 0% 100% 1>&2
      echo "# Formatting FAT32"
      sudo mkfs.vfat -F 32 -n 'BLITZBACKUP' /dev/${hdd}1 1>&2
      echo "# Getting new UUID"
      uuid=$(lsblk -o UUID,NAME | grep "${hdd}1" | cut -d " " -f 1)
      if [ "${uuid}" == "" ]; then
        echo "error='formatting failed'"
        exit 1
      fi
      echo "# OK device formatted --> UUID is ${uuid}"

    else
      echo "error='device not found'"
      exit 1
    fi
  fi

  # change raspiblitz.conf
  entryExists=$(cat /mnt/hdd/raspiblitz.conf | grep -c 'localBackupDeviceUUID=')
  if [ ${entryExists} -eq 0 ]; then
    echo "localBackupDeviceUUID='off'" >> /mnt/hdd/raspiblitz.conf
  fi
  sudo sed -i "s/^localBackupDeviceUUID=.*/localBackupDeviceUUID='${uuid}'/g" /mnt/hdd/raspiblitz.conf
  echo "activated=1"

  # mount device (so that no reboot is needed)
  source <(sudo /home/admin/config.scripts/blitz.backupdevice.sh mount)
  echo "isMounted=${isMounted}"
  if [ ${isMounted} -eq 0 ]; then
    echo "error='failed to mount'"
  fi

  exit 0
fi

#########################
# MOUNT
#########################

if [ "$1" = "mount" ]; then

  echo "# BACKUP DEVICE MOUNT"

  # check if feature is on
  if [ "${localBackupDeviceUUID}" == "" ] || [ "${localBackupDeviceUUID}" == "off" ]; then
    echo "error='feature is off'"
    exit 1
  fi

  checkIfAlreadyMounted=$(df | grep -c "/mnt/backup")
  if [ ${checkIfAlreadyMounted} -gt 0 ]; then
    echo "# there is something already mounted on /mnt/backup"
    echo "error='already mounted'"
    exit 1
  fi

  sudo mkdir -p /mnt/backup 1>&2
  sudo mount --uuid ${localBackupDeviceUUID} /mnt/backup 1>&2
  mountWorked=$(df | grep -c "/mnt/backup")
  if [ ${mountWorked} -gt 0 ]; then
    echo "# OK BackupDrive mounted to: /mnt/backup"
    echo "isMounted=1"
  else
    echo "# FAIL BackupDrive mount - check if device is connected & UUID is correct"
    echo "isMounted=0"
    echo "error='mount failed'"
  fi

  exit 0
fi

#########################
# TURN OFF
#########################

if [ "$1" = "off" ]; then

  echo "# BACKUP DEVICE REMOVE"
  exit 0
fi

echo "error='unkown command'"
exit 1