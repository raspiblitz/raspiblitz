#!/bin/bash

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# get network info from config
source ${infoFile} 2>/dev/null
source /mnt/hdd/raspiblitz.conf 2>/dev/null
if [ ${#network} -eq 0 ]; then
  network=bitcoin
fi

# display info
echo ""
echo "LCD turns white when shutdown complete."
if [ "$1" = "reboot" ]; then
  shutdownParams="-h -r now"
  echo "It will then reboot again automatically."
  sed -i "s/^state=.*/state=reboot/g" ${infoFile}
  sed -i "s/^message=.*/message=''/g" ${infoFile}
else
  shutdownParams="-h now"
  echo "Then wait 5 seconds and disconnect power."
  sed -i "s/^state=.*/state=shutdown/g" ${infoFile}
  sed -i "s/^message=.*/message=''/g" ${infoFile}
fi

# do shutdown/reboot
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
sudo shutdown ${shutdownParams}
exit 0
