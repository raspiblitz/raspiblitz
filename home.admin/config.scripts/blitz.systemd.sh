#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "additional systemd services"
 echo "blitz.systemd.sh log blockchain STARTED"
 echo "blitz.systemd.sh log lightning STARTED"
 exit 1
fi

# check parameter
if [ "${1}" != "log" ]; then
  echo "# FAIL: unkown parameter"
fi

# writing log file entry
logFile="/home/admin/systemd.${2}.log"
echo "$(date +%s) ${3}" >> ${logFile}
echo "# OK: log '${3}' written to ${logFile}"
