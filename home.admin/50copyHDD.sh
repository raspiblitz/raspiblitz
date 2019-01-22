#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info 2>/dev/null

echo ""
echo "*** Check 1st HDD ***"
sleep 4
hddA=$(lsblk | grep /mnt/hdd | grep -c sda1)
if [ ${hddA} -eq 0 ]; then
  echo "FAIL - 1st HDD not found as sda1"
  echo "Try 'sudo shutdown -r now'"
  exit 1
fi
echo "OK - HDD as sda1 found"
echo ""
echo "*** Copy Blockchain form a second HDD ***"
echo ""
echo "WARNING: The RaspiBlitz cannot run 2 HDDs without extra Power!"
echo ""
echo "You can use a Y cable for the second HDD to inject extra power."
echo "Like this one: https://www.amazon.de/dp/B00ZJBIHVY"
echo "If you see on LCD a error on connecting the 2nd HDD do a restart."
echo ""
echo "You can use the HDD of another RaspiBlitz for this."
echo "The 2nd HDD needs to be formated Ext4/exFAT and the folder '${network}' is in root of HDD."
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
    hddA=$(lsblk | grep /mnt/hdd | grep -c sda1)
    if [ ${hddA} -eq 0 ]; then
      echo "FAIL - connection to 1st HDD lost"
      echo "It seems there was a POWEROUTAGE while connecting the 2nd HDD."
      echo "Try to avoid this next time by adding extra Power or connect more securely."
      echo "You need now to reboot with 'sudo shutdown -r now' and then try again."
      exit 1
    fi
    hddB=$(lsblk | grep -c sdb1)
    if [ ${hddB} -eq 1 ]; then
      echo "OK - 2nd HDD found"
      ready=1
    fi
  done

echo ""
echo "*** Mounting 2nd HDD ***"
sudo mkdir /mnt/genesis
echo "try ext4 .."
sudo mount -t ext4 /dev/sdb1 /mnt/genesis
sleep 2
mountOK=$(lsblk | grep -c /mnt/genesis)
if [ ${mountOK} -eq 0 ]; then
  echo "try exfat .."
  sudo mount -t exfat /dev/sdb1 /mnt/genesis
  sleep 2
fi
mountOK=$(lsblk | grep -c /mnt/genesis)
if [ ${mountOK} -eq 0 ]; then
  echo "FAIL - not able to mount the 2nd HDD"
  echo "only ext4 and exfat possible"
  sleep 4
  ./10setupBlitz.sh
  exit 1
else
  echo "OK - 2nd HDD mounted at /mnt/genesis"
fi

echo ""
echo "*** Copy Blockchain ***"
sudo rsync --append --info=progress2 -a /mnt/genesis/bitcoin /mnt/hdd/
echo "cleaning up - ok if files do not exists"
sudo rm /mnt/hdd/${network}/${network}.conf
sudo rm /mnt/hdd/${network}/${network}.pid
sudo rm /mnt/hdd/${network}/banlist.dat
sudo rm /mnt/hdd/${network}/debug.log
sudo rm /mnt/hdd/${network}/fee_estimates.dat
sudo rm /mnt/hdd/${network}/mempool.dat
sudo rm /mnt/hdd/${network}/peers.dat
sudo rm /mnt/hdd/${network}/testnet3/banlist.dat
sudo rm /mnt/hdd/${network}/testnet3/debug.log
sudo rm /mnt/hdd/${network}/testnet3/fee_estimates.dat
sudo rm /mnt/hdd/${network}/testnet3/mempool.dat
sudo rm /mnt/hdd/${network}/testnet3/peers.dat
sudo umount -l /mnt/genesis
echo "OK - Copy done :)"
echo ""
echo "---> You can now disconnect the 2nd HDD"

# set SetupState
sudo sed -i "s/^setupStep=.*/setupStep=50/g" /home/admin/raspiblitz.info

sleep 5
./60finishHDD.sh
