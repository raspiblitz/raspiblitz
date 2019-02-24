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
lsblk -o NAME | grep "^sd" | grep -v "sda" | while read -r line ; do
    echo "Processing: $line"
done

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