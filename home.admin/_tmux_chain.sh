#!/bin/bash
# script for custom tmux status bar

if [ -f "/mnt/hdd/raspiblitz.conf" ]; then
    source /mnt/hdd/raspiblitz.conf 2>/dev/null
    echo " ${chain}net "
else
    #echo "$configFile does not exist"
    echo " unknown "
fi
