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
  echo "# FAIL: unknown parameter"
fi

# count for statistics in cache
/home/admin/_cache.sh increment system_count_start_${2}