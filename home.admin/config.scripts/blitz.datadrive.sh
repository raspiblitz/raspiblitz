#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "managing additional data storage"
 echo "blitz.datadrive.sh [on|off]"
 echo "exits on 0 = needs reboot"
 exit 1
fi

# check if sudo
if [ "$EUID" -ne 0 ]
  then echo "Please run as root (with sudo)"
  exit 1
fi

# update install sources
echo "make sure BTRFS is installed ..."
sudo apt-get install -y btrfs-tools
echo ""

# check on/off state
dataStorageNotAvailableYet=$(sudo btrfs filesystem df /mnt/data 2>&1 | grep -c "ERROR: not a btrfs filesystem")
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "Trying to switch additional data storage on ..."
  if [ ${dataStorageNotAvailableYet} -eq 0 ]; then
    echo "FAIL -> data storage is already on"
    exit 1
  fi
elif [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "Trying to switch additional data storage off ..."
  if [ ${dataStorageNotAvailableYet} -eq 1 ]; then
    echo "FAIL -> data storage is already off"
    exit 1
  fi
else
  echo "FAIL -> Parameter '${$1}' not known."
  exit 1
fi

###################
# SWITCH ON
###################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # detect the two usb drives
  echo "Detecting two USB sticks/drives with same size ..."
  lsblk -o NAME | grep "^sd" | while read -r test1 ; do
    size1=$(lsblk -o NAME,SIZE -b | grep "^${test1}" | awk '$1=$1' | cut -d " " -f 2)
    echo "Checking : ${test1} size(${size1})"
    lsblk -o NAME | grep "^sd" | grep -v "${test1}" | while read -r test2 ; do
      size2=$(lsblk -o NAME,SIZE -b | grep "^${test2}" | awk '$1=$1' | cut -d " " -f 2)
      if [ "${size1}" = "${size2}" ]; then
        echo "  MATCHING ${test2} size(${size2})"
        echo "${test1}" > .dev1.tmp
        echo "${test2}" > .dev2.tmp
      else
        echo "  different ${test2} size(${size2})"
      fi
    done
  done
  dev1=$(cat .dev1.tmp)
  dev2=$(cat .dev2.tmp)
  rm -f .dev1.tmp
  rm -f .dev2.tmp
  echo "RESULTS:"
  echo "dev1(${dev1})"
  echo "dev2(${dev2})"
  echo ""

  # check that results are available
  if [ ${#dev1} -eq 0 ] || [ ${#dev2} -eq 0 ]; then
    echo "!! FAIL -> was not able to detect two devices with the same size"
    exit 1
  fi

  # check size (at least 4GB minus some tolerance)
  size=$(lsblk -o NAME,SIZE -b | grep "^${dev1}" | awk '$1=$1' | cut -d " " -f 2)
  if [ ${size} -lt  3500000000 ]; then
    echo "!! FAIL -> too small - additional storage needs to be bigger than 4GB"
    exit 1
  fi

  # check if devices are containing old data
  echo "Analysing Drives ..."
  nameDev1=$(lsblk -o NAME,LABEL | grep "^${dev1}" | awk '$1=$1' | cut -d " " -f 2)
  nameDev2=$(lsblk -o NAME,LABEL | grep "^${dev2}" | awk '$1=$1' | cut -d " " -f 2)
  if [ "${nameDev1}" = "DATASTORE" ] || [ "${nameDev2}" = "DATASTORE" ]; then
    # TODO: once implemented -> also make sure that dev1 is named "DATASTORE" and if 2nd is other -> format and add as raid
    echo "!! NOT IMPLEMENTED YET -> devices seem contain old data, because name is 'DATASTORE'"
    echo "if you dont care about that data: format devices devices on other computer with FAT(32) named TEST"
    exit 1
  fi
  echo "OK drives dont contain old data."
  echo ""

  # format first drive
  echo "Formatting /dev/${dev1} with BTRFS ..."
  sudo mkfs.btrfs -L DATASTORE -f /dev/${dev1}
  echo "OK"
  echo ""

  # mount the BTRFS drive
  echo "Mounting under /mnt/data ..."
  sudo mkdir -p /mnt/data
  sudo mount /dev/${dev1} /mnt/data
  echo "OK"
  echo ""

  # adding the second device
  echo "Adding the second device as RAID1 .."
  sudo btrfs device add -f /dev/${dev2} /mnt/data
  sudo btrfs filesystem balance start -dconvert=raid1 -mconvert=raid1 /mnt/data
  echo ""
  exit 0

    # adding the second device
  uuid=$(sudo btrfs filesystem show /mnt/data | grep "uuid:" | awk '$1=$1' | cut -d " " -f 4)

fi

###################
# SWITCH OFF
###################

if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "TODO -> Turn off"

  sudo btrfs filesystem show /mnt/data
  sudo btrfs filesystem df /mnt/data

  sudo umount /mnt/data

  exit 0

fi
