#!/bin/bash
# script for custom tmux status bar

configFile="/mnt/hdd/raspiblitz.conf"

if [ -f "$configFile" ]; then
    source ${configFile} 2>/dev/null
    echo " ${chain}net "
else
    #echo "$configFile does not exist"
    echo " unknown "
fi
