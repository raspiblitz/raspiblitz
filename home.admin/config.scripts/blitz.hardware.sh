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

# detect RaspberryPi 3
isRaspberryPi3=$(cat /proc/device-tree/model 2>/dev/null | grep -c "Raspberry Pi 3")
if [ "${isRaspberryPi3}" == "1" ]; then
    board="rp3"
fi

# detect RaspberryPi 4
isRaspberryPi4=$(cat /proc/device-tree/model 2>/dev/null | grep -c "Raspberry Pi 4")
if [ "${isRaspberryPi4}" == "1" ]; then
    board="rp4"
fi

# detect RaspberryPi 5
isRaspberryPi5=$(cat /proc/device-tree/model 2>/dev/null | grep -c "Raspberry Pi 5")
if [ "${isRaspberryPi5}" == "1" ]; then
    board="rp5"
fi

# detect VM
isVM=$(grep -c 'hypervisor' /proc/cpuinfo)
if [ ${isVM} -gt 0 ]; then
    board="vm"
fi

# get how many RAM (in MB)
ramMB=$(awk '/MemTotal/ {printf( "%d\n", $2 / 1024 )}' /proc/meminfo)

# get how many RAM (in GB - approx)
ramGB=$(awk '/MemTotal/ {printf( "%d\n", $2 / 950000 )}' /proc/meminfo)

########################
# OUTPUT HARDWARE INFO
#######################

if [ "$1" = "status" ]; then
    echo "board='${board}'"
    echo "ramMB=${ramMB}"
    echo "ramGB=${ramGB}"
fi
