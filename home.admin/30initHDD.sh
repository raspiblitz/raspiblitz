#!/bin/sh
echo ""
echo "*** Checking if HDD is connected ***"
sleep 5
existsHDD=$(lsblk | grep -c sda1)
if [ ${existsHDD} -eq 1 ]; then
  echo "OK - HDD found as sda1"
  mountOK=$(df | grep -c /mnt/hdd)
  if [ ${mountOK} -eq 1 ]; then
    echo "FAIL - HDD is mounted"
    echo "If you really want to reinit the HDD, then unmount the HDD first and try again"
  else  
    echo ""
    echo "*** Formatting the HDD ***"
    echo "WARNING ALL DATA ON HDD WILL GET DELETED"
    echo "Wait until you get a OK or FAIL"
    sleep 4
    sudo mkfs.ext4 /dev/sda1 -F -L BLOCKCHAIN
    echo "format ext4 done - wait 6 secs"
    sleep 6
    formatExt4OK=$(lsblk -o UUID,NAME,FSTYPE,SIZE,LABEL,MODEL | grep BLOCKCHAIN | grep -c ext4) 
    if [ ${formatExt4OK} -eq 1 ]; then
      echo "OK - HDD is now formatted in ext4"
      sleep 1

      # set SetupState
      echo "30" > /home/admin/.setup

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
