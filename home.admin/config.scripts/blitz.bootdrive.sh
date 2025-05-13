#!/bin/bash

# basic background on this feature
# see: https://github.com/rootzoll/raspiblitz/issues/936

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info </dev/null

# command info
if [ "$1" == "" ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# tools for the boot drive / sd card"
 echo "# blitz.bootdrive.sh status"
 echo "# blitz.bootdrive.sh fsexpand"
 exit 1
fi

# check if su
if [ "$EUID" -ne 0 ]
  then echo "Please run as root (with sudo)"
  exit 1
fi

# 1st PARAMETER: action
action=$1

#########################
# STATUS

# gather data on SDcard / OS drive
minimumSizeByte=16384000000
rootPartitionLine=$(sudo mount | grep " / " | cut -d " " -f 1)
rootPartition=$(basename ${rootPartitionLine})
rootPartitionBytes=$(lsblk -b -o NAME,SIZE | grep "${rootPartition}" | awk '{print $2}')

# make conclusions
needsExpansion=0
tooSmall=0
if [ $rootPartitionBytes -lt $minimumSizeByte ]; then
    needsExpansion=1
    if [ "${fsexpanded}" == "1" ]; then
        tooSmall=1
    fi
fi

if [ "${action}" == "status" ]; then

    echo "rootPartition='${rootPartition}'"
    echo "rootPartitionBytes=${rootPartitionBytes}"
    echo "needsExpansion=${needsExpansion}"
    echo "fsexpanded=${fsexpanded}" # from raspiblitz.info
    echo "tooSmall=${tooSmall}"
    exit 0
fi

###########################
# EXPAND FILE SYSTEM OF SD

if [ "${action}" == "fsexpand" ]; then

    echo "# blitz.bootdrive.sh fsexpand"
    echo "# starting expand of file system of sd card"
    sudo sed -i "s/^fsexpanded=.*/fsexpanded=1/g" /home/admin/raspiblitz.info

    if [ "${baseimage}" = "raspios_arm64" ]; then
        resizeRaspbian="/usr/bin/raspi-config"
        if [ -x ${resizeRaspbian} ]; then
            echo "# RUNNING EXPAND RASPBERRYPI: ${resizeRaspbian}"
		    sudo $resizeRaspbian --expand-rootfs 1>&2
            sudo touch /forcefsck
            echo "# DONE - please reboot"
	    else
            echo "# FAIL to execute on ${baseimage}: ${resizeRaspbian}"
            echo "err='expand failed'"
            exit 1
        fi
    else
        echo "#FAIL no implementation for: ${baseimage}"
        echo "err='missing implementation'"
        exit 1
    fi
    exit 0
fi

echo "err='unknown parameter'"
exit 1