#!/bin/bash

# basic background on this feature
# see: https://github.com/rootzoll/raspiblitz/issues/936

# get basic system information
# these are the same set of infos the WebGUI dialog/controler has
source /home/admin/raspiblitz.info </dev/null

# command info
if [ "$1" == "" ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "tools for the boot drive / sd card"
 echo "blitz.sdcard.sh status"
 echo "blitz.sdcard.sh expand"
 exit 1
fi

# check if sudo
if [ "$EUID" -ne 0 ]
  then echo "Please run as root (with sudo)"
  exit 1
fi

# 1st PARAMETER: action
action=$1

#########################
# STATUS

# gather data on sd card
minimumSizeByte=8192000000
rootPartition=$(sudo mount | grep " / " | cut -d " " -f 1 | cut -d "/" -f 3)
rootPartitionBytes=$(lsblk -b -o NAME,SIZE | grep "${rootPartition}" | tr -s ' ' | cut -d " " -f 2)

# make conculsions
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

    echo "# starting expand of file system of sd card"
    sudo sed -i "s/^fsexpanded=.*/fsexpanded=1/g" ${infoFile}

    if [ "${baseimage}" = "raspbian" ] || [ "${baseimage}" = "raspios_arm64" ]; then
        resizeRaspbian="/usr/bin/raspi-config"
        if [ -x ${resizeRaspbian} ]; then
            echo "# RUNNING EXPAND RASPBERRYPI: ${resizeRaspbian}"
		    sudo $resizeRaspbian --expand-rootfs
	    else
            echo "# FAIL to execute on ${baseimage}: ${resizeRaspbian}"
            echo "err='expand failed'"
            exit 1
        fi
    elif [ "${baseimage}" = "armbian" ]; then
        resizeArmbian="/usr/lib/armbian/armbian-resize-filesystem"
        if [ -x ${resizeArmbian} ]; then
            echo "# RUNNING EXPAND ARMBIAN: ${resizeArmbian}"
            sudo $resizeArmbian start
	    else
            echo "# FAIL to execute on ${baseimage}: ${resizeArmbian}"
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