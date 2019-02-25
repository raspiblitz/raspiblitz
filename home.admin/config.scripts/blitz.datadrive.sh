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