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
  exit
fi

# update install sources
echo "make sure BTRFS is installed"
sudo apt-get install -y btrfs-tools


# detect the two usb drives
echo "Detecting two USB sticks with same size ..."
dev1=""
dev2=""
lsblk -o NAME | grep "^sd" | grep -v "sda" | while read -r test1 ; do
    size1=$(lsblk -o NAME,SIZE -b | grep "^${test1}")
    echo "Checking : ${test1} -> ${size1}"
    lsblk -o NAME | grep "^sd" | grep -v "sda" | while read -r test2 ; do
      size2=$(lsblk -o NAME,SIZE -b | grep "^${test2}")
      echo "  compare with ${test2} -> ${size2}"
      if [ "${size1}" = "${size2}" ]; then
        echo "  MATCH ${test1} = ${test2}"
        # remember last match
        dev1="${test1}"
        dev2="${test2}"
      fi
    done
done
echo "RESULT: ${dev1} & ${dev2}"

exit 0


lsblk -o UUID,NAME,FSTYPE,SIZE,LABEL,MODEL | greap "^sd"
# TODO: find the drives


# TODO: DETECT if they is already data
lsblk -o UUID,NAME,FSTYPE,SIZE,LABEL,MODEL 

# check if there is already data on there

# create 
sudo mkfs.btrfs -L DATASTORE -f /dev/sdb
sudo mkdir -p /mnt/data
sudo mount /dev/sdb1 /mnt/data
sudo btrfs filesystem show /mnt/data
sudo btrfs device add -f /dev/sdc /mnt/data
sudo btrfs filesystem df /mnt/data
sudo btrfs filesystem balance start -dconvert=raid1 -mconvert=raid1 /mnt/data