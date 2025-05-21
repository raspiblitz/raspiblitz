#!/bin/bash
# for reboot call: sudo /home/admin/config.scripts/blitz.shutdown.sh reboot

# use this script instead of direct shutdown command to:
# 1) give UI the info that a reboot/shutdown is now happening
# 2) shutdown/reboot in a safe way to prevent data corruption

# check if sudo
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (with sudo)"
  exit 1
fi

source <(/home/admin/_cache.sh get network)

# display info
echo
rpiModel=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
if [ -n "${rpiModel}" ]; then
  echo "${rpiModel}"
  if echo ${rpiModel} | grep -Eq 'Raspberry Pi 4'; then
    echo "When shutdown is complete the green activity light stays dark and the LCD turns white on the ${rpiModel}."
  elif echo ${rpiModel} | grep -Eq 'Raspberry Pi 5'; then
    echo "When shutdown is complete the activity light turns red and the LCD turns white on the ${rpiModel}."
  fi
fi

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

# general services to stop
servicesToStop="electrs fulcrum elementsd"
for service in ${servicesToStop}; do
  if systemctl is-active --quiet ${service}; then
    echo "stopping ${service} - please wait .."
    timeout 240 systemctl stop ${service}
  fi
done

# stop heavy load apps (if installed)
systemctl stop mempool.service 2>/dev/null
systemctl stop publicpool.service 2>/dev/null
systemctl stop btcpayserver.service 2>/dev/null
systemctl stop nbxplorer.service 2>/dev/null

# lndg
# stopping LNDg (if installed)
isInstalled=$(sudo ls /etc/systemd/system/jobs-lndg.service 2>/dev/null | grep -c 'jobs-lndg.service')
if ! [ ${isInstalled} -eq 0 ]; then
  echo "stop LNDg - please wait .."
  timeout 120 systemctl stop gunicorn.service 2>/dev/null
  timeout 120 systemctl stop jobs-lndg.timer 2>/dev/null
  timeout 120 systemctl stop jobs-lndg.service 2>/dev/null
  timeout 120 systemctl stop rebalancer-lndg.timer 2>/dev/null
  timeout 120 systemctl stop rebalancer-lndg.service 2>/dev/null
  timeout 120 systemctl stop htlc-stream-lndg.service 2>/dev/null
fi

# lightning
lightningServicesToStop="lnd tlnd slnd lightningd tlightningd slightningd"
for service in ${lightningServicesToStop}; do
  if systemctl is-active --quiet ${service}; then
    echo "stopping ${service} - please wait .."
    timeout 240 systemctl stop ${service}
  fi
done

# bitcoind
if [ "${network}" != "" ]; then
  # stopping bitcoin (thru cli)
  echo "stop ${network}d (1) - please wait .."
  timeout 120 sudo -u bitcoin ${network}-cli stop 2>/dev/null

  # stopping bitcoind (thru systemd)
  echo "stop ${network}d (2) - please wait .."
  timeout 360 systemctl stop ${network}d 2>/dev/null
  timeout 120 systemctl stop t${network}d 2>/dev/null
  timeout 120 systemctl stop s${network}d 2>/dev/null
  sleep 3
else
  echo "skipping stopping layer1 (network=='' in cache)"
fi

# make sure drives are synced before shutdown
sync

echo "starting shutdown ..."
shutdown ${shutdownParams}

# detect missing DBUS
if [ "${DBUS_SESSION_BUS_ADDRESS}" == "" ]; then
  echo "WARN: Missing \$DBUS_SESSION_BUS_ADDRESS .. "
  if [ "$1" = "reboot" ]; then
    echo "RUNNING FALLBACK REBOOT .. "
    systemctl --force --force reboot
  else
    echo "RUNNING FALLBACK SHUTDOWN .. "
    systemctl --force --force poweroff
  fi
fi

exit 0
