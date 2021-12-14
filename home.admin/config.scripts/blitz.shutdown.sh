#!/bin/bash
# for reboot call: sudo /home/admin/config.scripts/blitz.shutdown.sh reboot

# use this script instead of direct shutdown command to:
# 1) give UI the info that a reboot/shutdown is now happening
# 2) shutdown/reboot in a safe way to prevent data corruption

source <(/home/admin/_cache.sh get network)

# display info
echo ""
echo "Green activity light stays dark and LCD turns white when shutdown complete."
if [ "$1" = "reboot" ]; then
  shutdownParams="-h -r now"
  echo "It will then reboot again automatically."
  /home/admin/_cache.sh set state "reboot"
  /home/admin/_cache.sh set message "$2"
else
  shutdownParams="-h now"
  echo "Then wait 5 seconds and disconnect power."
  /home/admin/_cache.sh set state "shutdown"
  /home/admin/_cache.sh set message ""
fi

# do shutdown/reboot
echo "-----------------------------------------------"
sleep 3

# stopping electRS (if installed)
echo "stop electrs - please wait .."
sudo systemctl stop electrs 2>/dev/null

# stopping lightning
echo "stop lightning - please wait .."
sudo systemctl stop lnd 2>/dev/null
sudo systemctl stop lightningd 2>/dev/null
sudo systemctl stop tlnd 2>/dev/null
sudo systemctl stop tlightningd 2>/dev/null
sudo systemctl stop slnd 2>/dev/null
sudo systemctl stop slightningd 2>/dev/null

# stopping bitcoin (thru cli)
echo "stop ${network}d (1) - please wait .."
timeout 10 sudo -u bitcoin ${network}-cli stop 2>/dev/null

# stopping bitcoind (thru systemd)
echo "stop ${network}d (2) - please wait .."
sudo systemctl stop ${network}d 2>/dev/null
sudo systemctl stop t${network}d 2>/dev/null
sudo systemctl stop s${network}d 2>/dev/null
sleep 3

# make sure drives are synced before shutdown
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
if [ "${isBTRFS}" == "1" ] && [ "${isMounted}" == "1" ]; then
  echo "STARTING BTRFS RAID DATA CHECK ..."
  sudo btrfs scrub start /mnt/hdd/
fi
sync

echo "starting shutdown ..."
sudo shutdown ${shutdownParams}
exit 0