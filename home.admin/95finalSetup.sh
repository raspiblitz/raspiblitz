#!/bin/bash
echo ""

# set raspiblitz config file
configFile="/mnt/hdd/raspiblitz.conf"

# load setup config
source /home/admin/raspiblitz.info

# load version
source /home/admin/_version.info

# show info to user
dialog --backtitle "RaspiBlitz - Setup" --title " RaspiBlitz Setup is done :) " --msgbox "
    After reboot RaspiBlitz
    needs to be unlocked and
    sync with the network.

    Press OK for a final reboot.
" 10 42

# init the RASPIBLITZ Config
echo "# RASPIBLITZ CONFIG FILE" > $configFile
echo "raspiBlitzVersion='${codeVersion}'" >> $configFile
sudo chmod 777 ${configFile}

# transfer data from SD info file
echo "hostname=${hostname}" >> $configFile
echo "network=${network}" >> $configFile
echo "chain=${chain}" >> $configFile

# let migration/init script do the rest
/home/admin/_bootstrap.migration.sh

# copy logfile to analyse setup
cp $logFile /home/admin/raspiblitz.setup.log

# set the name of the node
echo "Setting the Name/Alias/Hostname .."
sudo /home/admin/config.scripts/lnd.setname.sh ${hostname}

# mark setup is done (100%)
sudo sed -i "s/^setupStep=.*/setupStep=100/g" /home/admin/raspiblitz.info

clear
echo "Setup done. Rebooting now."

sleep 3
sudo shutdown -r now