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
  shutdownParams="-P -h now"
  echo "Then wait 5 seconds and disconnect power."
  /home/admin/_cache.sh set state "shutdown"
  /home/admin/_cache.sh set message ""
fi

# do shutdown/reboot
echo "-----------------------------------------------"
sleep 3

# stopping electRS (if installed)
echo "stop electrs - please wait .."
sudo timeout 120 systemctl stop electrs 2>/dev/null

# stopping LNDg (if installed)
isInstalled=$(sudo ls /etc/systemd/system/jobs-lndg.service 2>/dev/null | grep -c 'jobs-lndg.service')
if ! [ ${isInstalled} -eq 0 ]; then
  echo "stop LNDg - please wait .."
  sudo timeout 120 systemctl stop gunicorn.service 2>/dev/null
  sudo timeout 120 systemctl stop jobs-lndg.timer 2>/dev/null
  sudo timeout 120 systemctl stop jobs-lndg.service 2>/dev/null
  sudo timeout 120 systemctl stop rebalancer-lndg.timer 2>/dev/null
  sudo timeout 120 systemctl stop rebalancer-lndg.service 2>/dev/null
  sudo timeout 120 systemctl stop htlc-stream-lndg.service 2>/dev/null
fi

# stopping lightning
echo "stop lightning - please wait .."
sudo timeout 120 systemctl stop lnd 2>/dev/null
sudo timeout 120 systemctl stop lightningd 2>/dev/null
sudo timeout 120 systemctl stop tlnd 2>/dev/null
sudo timeout 120 systemctl stop tlightningd 2>/dev/null
sudo timeout 120 systemctl stop slnd 2>/dev/null
sudo timeout 120 systemctl stop slightningd 2>/dev/null

if [ "${network}" != "" ]; then

  # stopping bitcoin (thru cli)
  echo "stop ${network}d (1) - please wait .."
  timeout 10 sudo -u bitcoin ${network}-cli stop 2>/dev/null

  # stopping bitcoind (thru systemd)
  echo "stop ${network}d (2) - please wait .."
  sudo timeout 120 systemctl stop ${network}d 2>/dev/null
  sudo timeout 120 systemctl stop t${network}d 2>/dev/null
  sudo timeout 120 systemctl stop s${network}d 2>/dev/null
  sleep 3
else
  echo "skipping stopping layer1 (network=='' in cache)"
fi

# make sure drives are synced before shutdown
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
if [ "${isBTRFS}" == "1" ] && [ "${isMounted}" == "1" ]; then
  echo "STARTING BTRFS RAID DATA CHECK ..."
  sudo btrfs scrub start /mnt/hdd/
fi
sync

# unmount HDD - try to kill all processes first #3114
for pid in $(sudo lsof -t "/mnt/hdd"); do
  process_name=$(ps -p $pid -o comm=)
  echo "# kill -SIGTERM $pid ($process_name)"
  sudo kill -SIGTERM $pid # Send SIGTERM signal
  sleep 5                 # Wait for the process to terminate
done
echo "# unmount /mnt/hdd"
sudo umount "/mnt/hdd"

echo "starting shutdown ..."
sudo shutdown ${shutdownParams}

# detect missing DBUS
if [ "${DBUS_SESSION_BUS_ADDRESS}" == "" ]; then
  echo "WARN: Missing \$DBUS_SESSION_BUS_ADDRESS .. "
  if [ "$1" = "reboot" ]; then
    echo "RUNNING FALLBACK REBOOT .. "
    sudo systemctl --force --force reboot
  else
    echo "RUNNING FALLBACK SHUTDOWN .. "
    sudo systemctl --force --force poweroff
  fi
fi

exit 0
