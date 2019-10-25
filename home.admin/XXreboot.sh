#!/bin/bash

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# MAIN MENU AFTER SETUP
source ${infoFile}
source ${configFile}

echo ""
echo "Going down for reboot."
echo "LCD turns white when shutdown complete."
echo "Will power up again automatically after ~5 seconds."
echo "-----------------------------------------------"
echo "stop lnd - please wait .."
sudo systemctl stop lnd
echo "stop ${network}d (1) - please wait .."
sudo -u bitcoin ${network}-cli stop
sleep 10
echo "stop ${network}d (2) - please wait .."
sudo systemctl stop ${network}d
sleep 3
sync
echo "starting shutdown ..."
sudo shutdown -r now
exit 0
