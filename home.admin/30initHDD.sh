#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info 2>/dev/null

echo ""
echo "*** Checking if HDD is connected ***"
sleep 5
device="sda1"
existsHDD=$(lsblk | grep -c sda1)

if [ ${existsHDD} -eq 1 ]; then
  echo "OK - HDD found at sda1"

  # check if there is s sda2
  existsHDD2=$(lsblk | grep -c sda2)
  if [ ${existsHDD2} -eq 1 ]; then
    echo "OK - HDD found at sda2 ... determine which is bigger"

    # get both with size
    size1=$(lsblk -o NAME,SIZE -b | grep "sda1" | awk '{ print substr( $0, 12, length($0)-2 ) }' | xargs)
    echo "sda1(${size1})"
    size2=$(lsblk -o NAME,SIZE -b | grep "sda2" | awk '{ print substr( $0, 12, length($0)-2 ) }' | xargs)
    echo "sda2(${size2})"

    # chosse to run with the bigger one
    if [ ${size2} -gt ${size1} ]; then
      echo "sda2 is BIGGER - run with this one"
      device="sda2"
    else
      echo "sda1 is BIGGER - run with this one"
    fi

  fi

  # quick basic size check
  echo ""
  echo "*** HDD Size Check ***"
  # bitcoin  > 450 GB
  minSize=450000000000
  # litecoin > 31 GB
  if [ "${network}" = "litecoin" ]; then
    minSize=31000000000
  fi
  isSize=$(lsblk -o NAME,SIZE -b | grep "${device}" | awk '$1=$1' | cut -d " " -f 2)
  if [ ${isSize} -lt ${minSize} ]; then
    if [ ${isSize} -gt 1 ]; then
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      echo "WARNING: HDD might be too small"
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      echo "You HDD was detected with the size of ${isSize} bytes"
      echo "For ${network} at least ${minSize} bytes is recommended"
      echo "If you want to change to a bigger HDD:"
      echo "* Unplug power of RaspiBlitz"
      echo "* Make a fresh SD card again"
      echo "* Start again with bigger HDD"
      echo "If you want to try with HDD connected, press ENTER to continue."
      read key
    else
      echo "WARN: Was not able to get size of HDD ... skipping"
      sleep 3
    fi
  else
    echo "OK: HDD seems big enough"
  fi
  echo ""

  mountOK=$(df | grep -c /mnt/hdd)
  if [ ${mountOK} -eq 1 ]; then
    echo "FAIL - HDD is mounted"
    echo "If you really want to reinit the HDD, then unmount the HDD first and try again"
  else  
    echo ""
    echo "*** Formatting the HDD ***"
    echo "WARNING ALL DATA ON HDD WILL GET DELETED - CAN TAKE SOME TIME"
    echo "Wait until you get a OK or FAIL"
    sleep 4
    sudo mkfs.ext4 /dev/${device} -F -L BLOCKCHAIN
    echo "format ext4 done - wait 6 secs"
    sleep 6
    formatExt4OK=$(lsblk -o UUID,NAME,FSTYPE,SIZE,LABEL,MODEL | grep BLOCKCHAIN | grep -c ext4) 
    if [ ${formatExt4OK} -eq 1 ]; then
      echo "OK - HDD is now formatted in ext4"
      sleep 1

      # set SetupState
      sudo sed -i "s/^setupStep=.*/setupStep=30/g" /home/admin/raspiblitz.info

      # automatically now add the HDD to the system
      ./40addHDD.sh
    else
      echo "FAIL - was not able to format the HDD to ext4 with the name 'BLOCKCHAIN'"
    fi
  fi
else
  echo "FAIL - no HDD as device sda1 found"
  echo "lsblk -o UUID,NAME,FSTYPE,SIZE,LABEL,MODEL"
  echo "check if HDD is properly connected and has enough power - then try again"
  echo "sometimes a reboot helps: sudo shutdown -r now"
fi
