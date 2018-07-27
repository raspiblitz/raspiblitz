#!/bin/sh
echo ""

# add bonus scripts
./91addBonus.sh

###### SWAP
echo "*** SWAP file ***"
swapExists=$(swapon -s | grep -c /mnt/hdd/swapfile)
if [ ${swapExists} -eq 1 ]; then
  echo "SWAP on HDD already exists"
else
  echo "No SWAP found ... creating 1GB SWAP on HDD"
  sudo sed -i "12s/.*/CONF_SWAPFILE=\/mnt\/hdd\/swapfile/" /etc/dphys-swapfile
  sudo sed -i "16s/.*/CONF_SWAPSIZE=1024/" /etc/dphys-swapfile
  echo "OK - edited /etc/dphys-swapfile"
  echo "Creating file ... this can take some seconds .."
  sudo dd if=/dev/zero of=/mnt/hdd/swapfile bs=1024 count=1024000
  sudo mkswap /mnt/hdd/swapfile
  sudo dphys-swapfile setup
  sudo chmod 0600 /mnt/hdd/swapfile
  sudo dphys-swapfile swapon
fi
swapExists=$(swapon -s | grep -c /mnt/hdd/swapfile)
if [ ${swapExists} -eq 1 ]; then
  echo "OK - SWAP is working"
else
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "WARNING - Not able to to build SWAP on HDD"
  echo "This is not critical ... but try to fix later."
  echo "--> will continue in 60 seconds <--"
  sleep 60
fi

# mark setup is done
echo "90" > /home/admin/.setup

# set the hostname inputed on initDialog
hostname=`cat .hostname`
echo "Setting new network hostname '$hostname'"
sudo hostnamectl set-hostname ${hostname}

# show info to user
dialog --backtitle "RaspiBlitz - Setup" --title " RaspiBlitz Setup is done :) " --msgbox "
    Press OK for a final reboot.

    Remember: After every reboot
  you need to unlock the LND wallet.
" 10 42

# mark setup is done (100%)
echo "100" > /home/admin/.setup

sudo shutdown -r now