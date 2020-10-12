#!/bin/bash
echo ""

# load setup config
source /home/admin/raspiblitz.info

# in case the config already exists
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# load version
source /home/admin/_version.info

# show info to user
sudo sed -i "s/^state=.*/state=reboot/g" /home/admin/raspiblitz.info
dialog --backtitle "RaspiBlitz - Setup" --title " RaspiBlitz Setup is done :) " --msgbox "
    After reboot RaspiBlitz
    needs to be unlocked and
    sync with the network.

    Press OK for a final reboot.
" 10 42

# let migration/init script do the rest
/home/admin/_bootstrap.migration.sh

# copy logfile to analyse setup
cp $logFile /home/admin/raspiblitz.setup.log

# set the name of the node
echo "Setting the Name/Alias/Hostname .."
sudo /home/admin/config.scripts/lnd.setname.sh ${hostname}

# expanding the root of the sd card

if [ "${baseImage}" = "raspbian" ]; then
  sudo raspi-config --expand-rootfs
  sudo sed -i "s/^fsexpanded=.*/fsexpanded=1/g" /home/admin/raspiblitz.info
elif [ "${baseImage}" = "armbian" ]; then
  sudo /usr/lib/armbian/armbian-resize-filesystem start
  sudo sed -i "s/^fsexpanded=.*/fsexpanded=1/g" /home/admin/raspiblitz.info
fi

# mark setup is done
sudo sed -i "s/^setupStep=.*/setupStep=100/g" /home/admin/raspiblitz.info

clear
echo "Setup done. Rebooting now."
sudo -u bitcoin ${network}-cli stop

sleep 3
sudo /home/admin/XXshutdown.sh reboot