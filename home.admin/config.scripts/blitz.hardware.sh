#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "Hardware Tool Script"
 echo "blitz.hardware.sh [status]"
 exit 1
fi

########################
# GATHER HARDWARE INFO
#######################

# detect known SBCs
board=""
isRaspberryPi4=$(cat /proc/device-tree/model | grep -c "Raspberry Pi 4")
if [ "${isRaspberryPi4}" == "1" ]; then
    board="rp4"
fi

# get how many RAM (in MB)
ramMB=$(awk '/MemTotal/ {printf( "%d\n", $2 / 1024 )}' /proc/meminfo)


########################
# OUTPUT HARDWARE INFO
#######################

if [ "$1" = "status" ]; then
    echo "board='${board}'"
    echo "ramMB=${ramMB}"
fi
