#!/bin/bash

# backup usb thumbdrive needs to be smaller than 32GB so its ignored for system drive layout
# and can be easily formatted with FAT32 and used on Windows/Mac/Linux

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# adding and removing a backup device (usb thumbdrive - smaller than 32GB)"
 echo "# blitz.backupdevice.sh status"
 echo "# blitz.backupdevice.sh on [?DEVICEUUID|DEVICENAME]"
 echo "# blitz.backupdevice.sh off"
 echo "# blitz.backupdevice.sh mount"
 exit 1
fi

echo "### blitz.backupdevice.sh ###"
source /mnt/hdd/app-data/raspiblitz.conf

#########################
# STATUS
#########################

if [ "$1" = "status" ]; then

  if [ "${localBackupDeviceUUID}" != "" ] && [ "${localBackupDeviceUUID}" != "off" ]; then

    echo "backupdevice=1"
    echo "UUID='${localBackupDeviceUUID}'"

    # check if backup device is mounted
    backupDeviceExists=$(df | grep -c "/mnt/backup")
    if [ ${backupDeviceExists} -gt 0 ]; then
       backupDeviceName=$(lsblk -o NAME,UUID | grep "${localBackupDeviceUUID}" | cut -d " " -f 1)
       backupDeviceName=${backupDeviceName:2:4}
       backupDeviceIsBackupDevice=$(df | grep -c ${backupDeviceName})
       if [ ${backupDeviceIsBackupDevice} -gt 0 ]; then
          echo "isMounted=1"
       else
          echo "isMounted=0"
       fi
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
      # is raid candidate when: not mounted & not the data drive candidate (hdd/ssd) & not BTRFS RAID & not zram
      if [ "${devMounted}" -eq 0 ] && [ "${disk}" != "${hdd}" ] && \
         [ "${disk}" != "${raidUsbDev}" ] && ! echo "${disk}" | grep "zram" 1>/dev/null; then
        sizeBytes=$(lsblk -o NAME,SIZE -b | grep "^${disk}" | awk '$1=$1' | cut -d " " -f 2)
        sizeGigaBytes=$(echo "scale=0; ${sizeBytes}/1024/1024/1024" | bc -l)
        vendorname=$(lsblk -o NAME,VENDOR | grep "^${disk}" | awk '$1=$1' | cut -d " " -f 2)
        mountoption="${disk} ${sizeGigaBytes} GB ${vendorname}"
        # backup devices needs to be less then 30GB
        if [ ${sizeGigaBytes} -gt 0 ] && [ ${sizeGigaBytes} -lt 31 ]; then
          # add to array of candidates
          backupCandidate[${drivecounter}]="${mountoption}"
          echo "backupCandidate[${drivecounter}]='${mountoption}'"
          drivecounter=$(($drivecounter +1))
        else
          echo "# ${disk} is not a candidate for backup device - size is ${sizeGigaBytes} GB"
        fi
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
  userinteraction=0

  # select and format device if UUID is not given
  uuid=$2
  if [ "${uuid}" == "" ]; then
    userinteraction=1

    # get status data
    source <(sudo /home/admin/config.scripts/blitz.backupdevice.sh status)
    if [ ${backupdevice} -eq 1 ]; then
      echo "error='already on'"
      exit 1
    fi

    # check if backup device is already connected
    if [ ${backupCandidates} -eq 0 ]; then
      dialog --title ' Adding Backup Device ' --msgbox 'Please connect now the backup device\nFor example a thumb drive bigger than 1GB but smaller then 32GB.' 9 50
      clear
      echo
      echo "detecting device ... (please wait)"
      sleep 3
      source <(sudo /home/admin/config.scripts/blitz.backupdevice.sh status)
      if [ ${backupCandidates} -eq 0 ]; then
        dialog --title ' FAIL ' --msgbox 'NOT able to detect a possible backup device.\nProcess was not successful.' 6 50
        clear
        exit 1
      fi
    fi

    # check if there is only one candidate
    if [ ${backupCandidates} -gt 1 ]; then
      dialog --title ' FAIL ' --msgbox 'There is more than one possible backup target connected.\nMake sure that just that one device is connected maller than 32GB and try again.' 8 40
      clear
      exit 1
    fi

    whiptail --title " FORMATTING DEVICE " --yes-button "FORMAT" --no-button "Cancel" --yesno "Will format the following device as Backup drive:
---> ${backupCandidate[0]}

THIS WILL DELETE ALL DATA ON THAT DEVICE!
    " 10 55
    if [ $? -gt 0 ]; then
      echo "# CANCEL"
      exit 1
    fi

    uuid=$(echo "${backupCandidate[0]}" | cut -d " " -f 1)
    echo "# will format device ${uuid}"
  fi

  # check that device is connected
  uuidConnected=$(lsblk -o UUID | grep -c "${uuid}")
  if [ ${uuidConnected} -eq 0 ]; then
    echo "# UUID not found - test is its a valid device name like sdb ..."
    isDeviceName=$(lsblk -o NAME,TYPE | grep "disk" | awk '$1=$1' | cut -d " " -f 1 | grep -c "${uuid}")
    if [ ${isDeviceName} -eq 1 ]; then
      hdd="${uuid}"
      # check if mounted
      checkIfAlreadyMounted=$(lsblk -o NAME,UUID,MOUNTPOINT | grep "${hdd}" | grep -c '/mnt/')
      if [ ${checkIfAlreadyMounted} -gt 0 ]; then
        echo "# cannot format a device that is mounted"
        echo "error='device is in use'"
        exit 1
      fi
      echo "# OK found device name ${hdd} that will now be formatted ..."
      echo "# Wiping all partitions (sfdisk/wipefs)"
      sfdisk --delete /dev/${hdd} 1>&2
      sleep 4
      wipefs -a /dev/${hdd} 1>&2
      sleep 4
      partitions=$(lsblk | grep -c "─${hdd}")
      if [ ${partitions} -gt 0 ]; then
        echo "# WARNING: partitions are still not clean"
        echo "error='partitioning failed'"
        exit 1
      fi
      # using FAT32 here so that the backup can be easily opened on Windows and Mac
      echo "# Create on big partition /dev/${hdd}"
      parted /dev/${hdd} mklabel msdos 1>&2
      parted /dev/${hdd} mkpart primary fat32 0% 100% 1>&2
      echo "# Formatting FAT32"
      mkfs.vfat -F 32 -n 'BLITZBACKUP' /dev/${hdd}1 1>&2
      sleep 2
      # Force kernel to re-read partition table and update device info
      partprobe /dev/${hdd} 1>&2
      sleep 1
      # Trigger udev to update device information
      udevadm settle
      udevadm trigger --subsystem-match=block
      sleep 2
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
  /home/admin/config.scripts/blitz.conf.sh set localBackupDeviceUUID "${uuid}"
  echo "activated=1"

  # mount device (so that no reboot is needed)
  source <(sudo /home/admin/config.scripts/blitz.backupdevice.sh mount)
  echo "isMounted=${isMounted}"
  if [ ${isMounted} -eq 0 ]; then
    echo "error='failed to mount'"
  fi

  if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
    # copy SCB over
    cp /mnt/hdd/app-data/lnd/data/chain/bitcoin/mainnet/channel.backup /mnt/backup/channel.backup 1>&2
  fi
  if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ]; then
    # copy ER over
    cp /home/bitcoin/.lightning/bitcoin/emergency.recover /mnt/backup/emergency.recover 1>&2
  fi

  if [ ${userinteraction} -eq 1 ]; then
    if [ ${isMounted} -eq 0 ]; then
      /home/admin/config.scripts/blitz.conf.sh set localBackupDeviceUUID "off"
      dialog --title ' Adding Backup Device ' --msgbox '\nFAIL - Not able to add device.' 7 40
    else
      dialog --title ' Adding Backup Device ' --msgbox '\nOK - Device added for Backup.' 7 40
    fi
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
  /home/admin/config.scripts/blitz.conf.sh set localBackupDeviceUUID "off"
  sudo umount /mnt/backup 2>/dev/null
  echo "# OK backup device is off"
  exit 0
fi

echo "error='unknown command'"
exit 1
