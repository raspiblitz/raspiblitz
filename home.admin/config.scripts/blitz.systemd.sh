#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "additional systemd services"
 echo "blitz.systemd.sh update-sshd"
 echo "blitz.systemd.sh log blockchain STARTED"
 echo "blitz.systemd.sh log lightning STARTED"
 exit 1
fi

# edit of sshd service file
if [ "${1}" == "update-sshd" ]; then
  echo "# blitz.systemd.sh -> update sshd service config"
  # make sure its updated to wait for HDD mount before start
  # https://github.com/rootzoll/raspiblitz/issues/1785#issuecomment-730476628
  sudo sed -i "s/^After=.*/After=network.target auditd.service mnt-hdd.mount/g" /etc/systemd/system/sshd.service
  # make sure sto restart service
  sudo systemctl daemon-reload
  sudo systemctl restart sshd
  echo "# OK sshd config edit done and service restarted"
  exit 0
fi

# check parameter
if [ "${1}" != "log" ]; then
  echo "# FAIL: unkown parameter"
fi

# writing log file entry
logFile="/home/admin/systemd.${2}.log"
echo "$(date +%s) ${3}" >> ${logFile}
echo "# OK: log '${3}' written to ${logFile}"
