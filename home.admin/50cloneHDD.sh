#!/bin/bash

# CLODE HDD
# Script to use the HDD of another RaspiBlitz (Ext4) or from another desktop computer (ExFAT)
# and copy blocckhain data over to RaspiBlitz HDD/SSD

## get basic info
source /home/admin/raspiblitz.info

echo ""
echo "*** Check 1st HDD ***"
sleep 4
hddA=$(lsblk | grep /mnt/hdd | grep -c sda1)
if [ ${hddA} -eq 0 ]; then
  echo "FAIL - 1st HDD not found as sda1"
  echo "Try 'sudo shutdown -r now'"
  exit 1
fi

ready=0
while [ ${ready} -eq 0 ]
  do
    hddA=$(lsblk | grep /mnt/hdd | grep -c sda1)
    if [ ${hddA} -eq 1 ]; then
      echo "OK - HDD as sda1 found"
      ready=1
    fi
    if [ ${hddA} -eq 0 ]; then
      echo "FAIL - 1st HDD not found as sda1 or sda"
      echo "Try 'sudo shutdown -r now'"
      exit 1
    fi
    hddB=$(lsblk | grep -c sda)
    if [ ${hddB} -eq 1 ]; then
      echo "OK - HDD as sda found"
      ready=1
    fi
  done

echo ""
echo "*** Clone Blockchain form a second HDD ***"
echo ""
echo "WARNING: The RaspiBlitz cannot run 2 HDDs without extra Power!"
echo ""
echo "You can use a Y cable for the second HDD to inject extra power"
echo "or add a USB Hub with extra power between Raspi and 2nd HDD."
echo "If you see on LCD a error on connecting the 2nd HDD do a restart."
echo ""
echo "You can use the HDD of another RaspiBlitz for this."
echo "The 2nd HDD needs to be formatted Ext4/exFAT and the folder '${network}' is in root of HDD."
echo "The the folder '${network}' needs to be in root of the 1st or 2nd partition on the HDD."
echo ""
echo "**********************************"
echo "--> Please connect now the 2nd HDD"
echo "**********************************"
echo ""
echo "If 2nd HDD is connected but setup does not continue,"
echo "then cancel (CTRL+c) and reboot."
ready=0
while [ ${ready} -eq 0 ]
  do
    found=$(lsblk | grep part | grep -c sdb)
    if [ ${found} -gt 0 ]; then
      echo "OK - 2nd HDD found as part of sdb"
      ready=1
    fi
  done

echo ""
echo "*** Mounting 2nd HDD ***"
sudo mkdir /mnt/genesis 2>/dev/null
echo "try ext4 on sdb1 .."
sudo mount -t ext4 /dev/sdb1 /mnt/genesis
sleep 4
mountOK=$(lsblk | grep -c /mnt/genesis)
if [ ${mountOK} -eq 0 ]; then
  echo "try exfat on sdb1 .."
  sudo mount -t exfat /dev/sdb1 /mnt/genesis
  sleep 4
fi
mountOK=$(lsblk | grep -c /mnt/genesis)
if [ ${mountOK} -eq 0 ]; then
  echo "try ext4 on sdb .."
  sudo mount -t ext4 /dev/sdb /mnt/genesis
  sleep 4
fi
mountOK=$(lsblk | grep -c /mnt/genesis)
if [ ${mountOK} -eq 0 ]; then
  echo "try exfat on sdb.."
  sudo mount -t exfat /dev/sdb /mnt/genesis
  sleep 4
fi
mountOK=$(lsblk | grep -c /mnt/genesis)
if [ ${mountOK} -eq 0 ]; then
  echo "FAIL - not able to mount the 2nd HDD"
  echo "only ext4 and exfat possible"
  echo "PRESS ENTER to return to menu"
  read key
  ./10setupBlitz.sh
  exit 1
else
  echo "OK - 2nd HDD mounted at /mnt/genesis"
fi

echo ""
echo "*** Copy Blockchain ***"
sudo rsync --append --info=progress2 -a /mnt/genesis/bitcoin/blocks /mnt/genesis/bitcoin/chainstate /mnt/hdd/bitcoin
sudo umount -l /mnt/genesis
echo "OK - Copy done :)"
echo ""
# echo "---> You can now disconnect the 2nd HDD"
# If the Odorid HC1 reboots with a HDD attached to the USB it prioritises it over the SATA
echo "---> Disconnect the 2nd HDD and press a Enter"
read key

# set SetupState
# sudo sed -i "s/^setupStep=.*/setupStep=50/g" /home/admin/raspiblitz.info

# sleep 5
#./60finishHDD.sh

# unlink bitcoin user (will created later in setup again)
sudo unlink /home/bitcoin/.bitcoin 

# make quick check if data is there
anyDataAtAll=0
quickCheckOK=1
count=$(sudo ls /mnt/hdd/bitcoin/blocks 2>/dev/null | grep -c '.dat')
if [ ${count} -gt 0 ]; then
   echo "Found data in /mnt/hdd/bitcoin/blocks"
   anyDataAtAll=1
fi
if [ ${count} -lt 3000 ]; then
  echo "FAIL: transfere seems invalid - less then 3000 .dat files (${count})"
  quickCheckOK=0
fi
count=$(sudo ls /mnt/hdd/bitcoin/chainstate 2>/dev/null | grep -c '.ldb')
if [ ${count} -gt 0 ]; then
   echo "Found data in /mnt/hdd/bitcoin/chainstate"
   anyDataAtAll=1
fi
if [ ${count} -lt 1400 ]; then
  echo "FAIL: transfere seems invalid - less then 1400 .ldb files (${count})"
  quickCheckOK=0
fi

# just if any data transferred ..
if [ ${anyDataAtAll} -eq 1 ]; then

  # data was invalid - ask user to keep?
  if [ ${quickCheckOK} -eq 0 ]; then
    echo "*********************************************"
    echo "There seems to be an invalid transfer."
    echo "Wait 5 secs ..."
    sleep 5
    dialog --title " INVALID TRANSFER - DELETE DATA?" --yesno "Quickcheck shows the data you transferred is invalid/incomplete. This can lead further RaspiBlitz setup to get stuck in error state.\nDo you want to reset/delete data data?" 8 60
    response=$?
    echo "response(${response})"
    case $response in
      1) quickCheckOK=1 ;;
    esac
  fi

  if [ ${quickCheckOK} -eq 0 ]; then
    echo "Deleting invalid Data ..."
    sudo rm -rf /mnt/hdd/bitcoin
    sudo rm -rf /home/bitcoin/.bitcoin
    sleep 2
  fi

else

  # when no data transferred - just delete bitcoin base dir again
  sudo rm -rf /mnt/hdd/bitcoin

fi

if [ ${setupStep} -lt 100 ]; then
  # setup script will decide the next logical step
  /home/admin/10setupBlitz.sh
fi