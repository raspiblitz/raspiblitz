#!/bin/bash
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
    >&2 echo "# managing the data drive(s) with new bootable setups for RaspberryPi, VMs and Laptops"
    >&2 echo "# blitz.data.sh status [-inspect] # auto detect the old/best drives to use for storage, system and data"
    >&2 echo "# blitz.data.sh mount # mounts all drives and link all data folders"
    >&2 echo "# blitz.data.sh link # (re)create all symlinks to files and folders (also mapping old layout to new layout)"
    >&2 echo "# blitz.data.sh setup STOARGE [device] combinedData=[0|1] addSystemPartition=[0|1]"
    >&2 echo "# blitz.data.sh setup SYSTEM [device]"
    >&2 echo "# blitz.data.sh setup DATA [device]"
    >&2 echo "# blitz.data.sh clean STOARGE [device] combinedData=[0|1] addSystemPartition=[0|1]"
    >&2 echo "# blitz.data.sh clean SYSTEM [device]"
    >&2 echo "# blitz.data.sh clean DATA [device]"
    >&2 echo "# blitz.data.sh copy-system [device] [system|storage]"
    >&2 echo "# blitz.data.sh recover STOARGE [device] combinedData=[0|1] bootFromStorage=[0|1]"
    >&2 echo "# blitz.data.sh recover SYSTEM [device]"
    >&2 echo "# blitz.data.sh recover DATA [device]"
    >&2 echo "# blitz.data.sh kill-boot [device] # deactivate boot function from install medium"
    >&2 echo "# blitz.data.sh migration [umbrel|citadel|mynode] [partition] [-test] # will migrate partition to raspiblitz"
    >&2 echo "# blitz.data.sh migration hdd [menu-prepare|run]"
    >&2 echo "# blitz.data.sh uasp-fix [-info] # deactivates UASP for non supported USB HDD Adapters"
    >&2 echo "# blitz.data.sh swap on # creates and activates an 8GB swapfile in / (Debian 12 only)"
    >&2 echo "# blitz.data.sh swap off # deactivates and removes the swapfile"
    >&2 echo "# blitz.data.sh reset # deletes all data & partitions on the storage device"
    >&2 echo "# blitz.data.sh expand [partition] # expands the partition to use all available space"
    echo "error='missing parameters'"
    exit 1
fi

###################
# BASICS
###################

# For the new data drive setup starting v1.12.0 we have 4 areas of data can be stored in different configurations
# A) INSTALL    - inital install medium (SDcard, USB thumbdrive)
# B) SYSTEM     - root drive of the linux system
# C) DATA       - critical & configuration data of system & apps (formally app_data)
# D) STORAGE    - data that is temp or can be redownloaded or generated like blockhain or indexes (formally app_storage)

# On a old RaspiBlitz setup INTSALL+SYSTEM would be the same on the sd card and DATA+STORAGE on the USB conncted HDD.
# On RaspberryPi5+NVMe or Laptop the SYSTEM is one partition while DATA+STORAGE on another, while INSTALL is started once from SD or thumb drive.
# On a VM all 4 areas can be on separate virtual ext4 drives, stored eg by Proxmox with different redundancies & backup strategies. 

# This script should help to setup & manage those different configurations.

# file to print debug info on longer processes to
logFile="/home/admin/raspiblitz.log"

# minimal storage sizes (recommended sizes can get checked by UI)
storagePrunedMinGB=128
storageFullMinGB=890
dataMinGB=32
systemMinGB=32

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='run as root'"
  exit 1
fi

# gather info on hardware
source <(/home/admin/config.scripts/blitz.hardware.sh status)
if [ ${#computerType} -eq 0 ]; then
  echo "error='hardware not detected'"
  exit 1
fi

action=$1
echo "# blitz.data.sh ${action}"
if [ ${#action} -eq 0 ]; then
    echo "error='missing action'"
    exit 1
fi

###################
# SWAP MANAGEMENT
###################

if [ "$action" = "swap" ]; then

    swapAction=$2
    swapFilePath="/swapfile"
    swapSizeGB=8

    if [ "$swapAction" = "on" ]; then

        echo "# blitz.data.sh swap on"
        # check if swap is already active
        if swapon --show | grep -q "${swapFilePath}"; then
            echo "error='swapfile ${swapFilePath} already active'"
            exit 1
        fi
        # check if file exists
        if [ -f "${swapFilePath}" ]; then
            echo "error='file ${swapFilePath} already exists but is not active swap'"
            exit 1
        fi
        echo "# Creating ${swapSizeGB}GB swapfile at ${swapFilePath} ..."
        fallocate -l ${swapSizeGB}G ${swapFilePath}
        if [ $? -ne 0 ]; then
            echo "error='failed to allocate space for swapfile'"
            rm -f ${swapFilePath} 2>/dev/null
            exit 1
        fi
        chmod 600 ${swapFilePath}
        mkswap ${swapFilePath}
        if [ $? -ne 0 ]; then
            echo "error='failed to format swapfile'"
            rm -f ${swapFilePath} 2>/dev/null
            exit 1
        fi
        swapon ${swapFilePath}
        if [ $? -ne 0 ]; then
            echo "error='failed to activate swapfile'"
            rm -f ${swapFilePath} 2>/dev/null
            exit 1
        fi
        # make permanent
        if ! grep -q "${swapFilePath} none swap sw 0 0" /etc/fstab; then
            echo "${swapFilePath} none swap sw 0 0" >> /etc/fstab
            echo "# Added swapfile to /etc/fstab"
        fi
        echo "result='swapfile created and activated'"
        exit 0

    elif [ "$swapAction" = "off" ]; then

        echo "# blitz.data.sh swap off"
        # check if swap is active
        if swapon --show | grep -q "${swapFilePath}"; then
            echo "# Deactivating swapfile ${swapFilePath} ..."
            swapoff ${swapFilePath}
            if [ $? -ne 0 ]; then
                echo "error='failed to deactivate swapfile'"
                # continue trying to remove from fstab and delete file
            fi
        else
            echo "# Swapfile ${swapFilePath} is not active."
        fi
        # remove from fstab
        if grep -q "${swapFilePath} none swap sw 0 0" /etc/fstab; then
            echo "# Removing swapfile entry from /etc/fstab ..."
            sed -i "\#${swapFilePath} none swap sw 0 0#d" /etc/fstab
        fi
        # delete file
        if [ -f "${swapFilePath}" ]; then
            echo "# Deleting swapfile ${swapFilePath} ..."
            rm -f ${swapFilePath}
            if [ $? -ne 0 ]; then
                echo "warning='failed to delete swapfile ${swapFilePath}'"
            fi
        else
             echo "# Swapfile ${swapFilePath} not found."
        fi
        echo "result='swapfile deactivated and removed'"
        exit 0

    else
        echo "error='unknown swap action'"
        exit 1
    fi
fi

###################
# STATUS
###################

if [ "$action" = "status" ]; then

    # optional: parameter
    userWantsInspect=0
    if [ "$2" = "-inspect" ]; then
        userWantsInspect=1
    fi

    ##########################
    # CHECK SWAP STATUS
    isSwapExternal=0
    swapFilePath="/swapfile"
    if swapon --show | grep -q "${swapFilePath}"; then
        isSwapExternal=1
    fi

    ##########################
    # FIND INSTALL DEVICE

    # find the first device (sd card, usb, cd rom) with a boot partition
    installDevice=""
    possibleInstallDevices=$(lsblk -o NAME,TRAN -d | grep -E 'mmc|usb|sr' | cut -d' ' -f1)
    for device in ${possibleInstallDevices}; do
        echo "# check device(${device}) for boot partition"
        if parted --script "/dev/${device}" print 2>/dev/null | grep "^ *[0-9]" | grep -q "boot\|esp\|lba"; then
            installDevice="${device}"
            break
        fi
    done

    # check if any partition of install device is mounted as root
    installDeviceActive=0
    if [ ${#installDevice} -gt 0 ]; then
        rootPartition=$(lsblk -no NAME,MOUNTPOINT "/dev/${installDevice}"| awk '$2 == "/"' | sed 's/[└├]─//g' | cut -d' ' -f1)
        if [ ${#rootPartition} -gt 0 ]; then
            installDeviceActive=1
        fi
    fi

    # check if install device is read-only
    installDeviceReadOnly=0
    if [ ${#installDevice} -gt 0 ]; then
        if [ -f "/sys/block/${installDevice}/ro" ] && [ "$(cat /sys/block/${installDevice}/ro)" = "1" ]; then
            installDeviceReadOnly=1
        fi
    fi

    # check if some drive is already mounted on /mnt/temp
    mountPath=$(findmnt -n -o TARGET "/mnt/temp" 2>/dev/null)
    if [ -n "${mountPath}" ]; then
        echo "error='a drive already mounted on /mnt/temp'"
        exit 1
    fi

    ##########################
    # CHECK EXISTING DRIVES

    # initial values for drives & state to determine
    storageDevice=""
    systemDevice=""
    dataDevice=""
    storageBlockchainGB=0
    dataInspectSuccess=0
    dataConfigFound=0
    combinedDataStorage=0
    
    # get a list of all existing ext4 partitions of connected storage drives (sdX, nvmeX) - sorted by size (smallest first, then by name)
    ext4Partitions=$(lsblk -b -n -l -o NAME,SIZE,FSTYPE,TYPE | grep "part" | grep "ext4" | grep -E "^(sd|nvme)" | awk '{print $1, $2}' | sort -k2,2n -k1,1)
    if [ ${#ext4Partitions} -eq 0 ]; then
        echo "# no ext4 partitions found"
    fi

    # check every partition if it has data to recover
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            name=$(echo "$line" | awk '{print $1}')
            size=$(echo "$line" | awk '{printf "%.0f", $2/(1024*1024*1024)}')
            
            # if user already set a migration source device - ignore it in the list
            source <(/home/admin/_cache.sh get hddMigrateDeviceFrom)
            if [ ${#hddMigrateDeviceFrom} -gt 0 ]; then
                # check if the device is in the list of devices
                if echo "${name}" | grep -q "${hddMigrateDeviceFrom}"; then
                    # remove the device from the list
                    echo "# skipping device ${name} - migration source device set"
                    continue
                fi
            fi

            # mount partition if not already mounted
            needsUnmount=0
            mountPath=$(findmnt -n -o TARGET "/dev/${name}" 2>/dev/null)   
            if [ -z "${mountPath}" ]; then
                # create temp mount point if not exists
                mkdir -p /mnt/temp 2>/dev/null
                # try to mount
                if ! mount "/dev/${name}" /mnt/temp 2>/dev/null; then
                    echo "error='cannot mount /dev/${name}'"
                    continue
                fi
                mountPath="/mnt/temp"
                needsUnmount=1
            fi
            
            dataInspectPartition=0
            deviceName=$(echo "${name}" | sed -E 's/p?[0-9]+$//')
            echo "# Checking partition ${name} (${size}GB) on ${deviceName} mounted at ${mountPath}"

            # Check STORAGE DRIVE
            if [ -d "${mountPath}/app-storage" ]; then

                # set data
                echo "#  - STORAGE partition"
                storageDevice="${deviceName}"
                storageSizeGB="${size}"
                storagePartition="${name}"
                if [ "${needsUnmount}" = "0" ]; then
                    storageMountedPath="${mountPath}"
                fi
                
                # check if its a combined data & storage partition
                if [ -d "${mountPath}/app-data" ]; then
                    if [ ${#dataDevice} -eq 0 ]; then
                        combinedDataStorage=1
                        dataPartition="${name}"
                    fi
                    dataInspectPartition=1
                else
                    combinedDataStorage=0
                fi

                # check blochain data
                storageBlockchainGB=$(du -s ${mountPath}/app-storage/bitcoin/blocks 2>/dev/null| awk '{printf "%.0f", $1/(1024*1024)}')
                if [ "${storageBlockchainGB}" = "" ]; then
                        # check old location
                        storageBlockchainGB=$(du -s ${mountPath}/bitcoin/blocks 2>/dev/null| awk '{printf "%.0f", $1/(1024*1024)}')
                fi
                if [ "${storageBlockchainGB}" = "" ]; then
                    # if nothing found - set to numeric 0
                    storageBlockchainGB=0
                fi

            # Check DATA DRIVE
            elif [ -d "${mountPath}/app-data" ] && [ ${size} -gt 7 ]; then

                # check for unclean setups
                if [ -d "${mountPath}/app-storage" ]; then
                    echo "# there might be two old storage drives connected"
                    echo "error='app-storage found on app-data partition'"
                    exit 1
                fi

                # set data
                echo "#  - DATA partition"
                combinedDataStorage=0
                dataInspectPartition=1
                dataDevice="${deviceName}"
                dataSizeGB="${size}"
                dataPartition="${name}"
                if [ "${needsUnmount}" = "0" ]; then
                    dataMountedPath="${mountPath}"
                fi

            # Check SYSTEM DRIVE
            elif [ -d "${mountPath}/boot" ] && [ -d "${mountPath}/home/admin/raspiblitz" ] && [ ${size} -gt 7 ] && [ "${storageDevice}" != "" ]; then

                # check for unclean setups
                if [ -d "${mountPath}/app-storage" ]; then
                    echo "error='system partition mixed with storage'"
                    exit 1
                fi
                if [ -d "${mountPath}/app-data" ]; then
                    echo "error='system partition mixed with data'"
                    exit 1
                fi

                # check if system is install device (sd card or thumb drive)
                if [ "${installDevice}" = "${deviceName}" ]; then
                    echo "#  - INSTALL partition"
                else
                    # set data
                    echo "#  - SYSTEM partition"
                    systemDevice="${deviceName}"
                    systemSizeGB="${size}"
                    systemPartition="${name}"
                    systemMountedPath="${mountPath}"
                fi

            # Check MIGRATION: UMBREL
            elif [ -f "${mountPath}/umbrel/info.json" ]; then
                echo "#  - UMBREL data detected - use 'blitz.data.sh migration'"
                storageMigration="umbrel"

            # Check MIGRATION: CITADEL
            elif [ -f "${mountPath}/citadel/info.json" ]; then
                echo "#  - CITADEL data detected - use 'blitz.data.sh migration'"
                storageMigration="citadel"

            # Check MIGRATION: MYNODE
            elif [ -f "${mountPath}/mynode/bitcoin/bitcoin.conf" ]; then
                echo "#  - MYNODE data detected - use 'blitz.data.sh migration'"
                storageMigration="mynode"

            else
                echo "#  - no data found on partition"
            fi

            # Check: CONFIG FILE
            if [ -f "${mountPath}/raspiblitz.conf" ] || [ -f "${mountPath}/app-data/raspiblitz.conf" ]; then
                dataConfigFound=1
                echo "#    * found raspiblitz.conf"
            fi

            # Datainspect: copy setup relevant data from partition to temp location
            if [ "$dataInspectPartition" = "1" ]; then
                if [ "$userWantsInspect" = "0" ]; then
                    echo "#  - skipping data inspect - use '-inspect' to copy data to RAMDISK for inspection"
                elif [ ! -d "/var/cache/raspiblitz" ]; then
                    echo "#  - skipping data inspect - RAMDISK not found"
                else

                    echo "#  - RUN INSPECT -> RAMDISK: /var/cache/raspiblitz/hdd-inspect"
                    mkdir /var/cache/raspiblitz/hdd-inspect 2>/dev/null
                    dataInspectSuccess=1

                    # make copy of raspiblitz.conf to RAMDISK (try old and new path)
                    cp -a ${mountPath}/raspiblitz.conf /var/cache/raspiblitz/hdd-inspect/raspiblitz.conf 2>/dev/null
                    cp -a ${mountPath}/app-data/raspiblitz.conf /var/cache/raspiblitz/hdd-inspect/raspiblitz.conf 2>/dev/null
                    if [ -f "/var/cache/raspiblitz/hdd-inspect/raspiblitz.conf" ]; then
                        echo "#    * raspiblitz.conf copied to RAMDISK"
                    fi

                    # make copy of WIFI config to RAMDISK (if available)
                    cp -a ${mountPath}/app-data/wifi /var/cache/raspiblitz/hdd-inspect/ 2>/dev/null
                    if [ -d "/var/cache/raspiblitz/hdd-inspect/wifi" ]; then
                        echo "#    * WIFI config copied to RAMDISK"
                    fi

                    # make copy of SSH keys to RAMDISK (if available)
                    cp -a ${mountPath}/app-data/sshd /var/cache/raspiblitz/hdd-inspect 2>/dev/null
                    cp -a ${mountPath}/app-data/ssh-root /var/cache/raspiblitz/hdd-inspect 2>/dev/null
                    if [ -d "/var/cache/raspiblitz/hdd-inspect/sshd" ] || [ -d "/var/cache/raspiblitz/hdd-inspect/ssh-root" ]; then
                        echo "#    * SSH keys copied to RAMDISK"
                    fi

                    # make copy of raspiblitz.setup to RAMDISK (if available from former systemcopy)
                    cp -a ${mountPath}/app-data/raspiblitz.setup /var/cache/raspiblitz/hdd-inspect/raspiblitz.setup 2>/dev/null
                    if [ -f "/var/cache/raspiblitz/hdd-inspect/raspiblitz.setup" ]; then
                        echo "#    * raspiblitz.setup copied to RAMDISK"
                    fi

                fi
            fi

            # cleanup if we mounted
            if [ "${needsUnmount}" = "1" ]; then
                umount /mnt/temp
                rm -r /mnt/temp
            fi
        fi
    done <<< "${ext4Partitions}"

    # check boot situation
    bootFromStorage=0
    bootFromSD=$(lsblk | grep mmcblk | grep -c /boot)
    if [ ${bootFromSD} -eq 0 ] && [ -n "${storageDevice}" ] && [ "${storageDevice}" = "${systemDevice}" ]; then
        # system runs from storage device
        bootFromStorage=1
        bootFromSD=0
    fi

    # if there is an existing storage device
    biggerDevice=""
    biggerSizeGB=""
    if [ -n "${storageDevice}" ]; then
        # get a list of all connected drives >7GB ordered by size (biggest first)
        listOfBiggerDevices=$(lsblk -dno NAME,SIZE | grep -E "^(sd|nvme)" | \
        awk '{ 
        size=$2
        if(size ~ /T/) { 
        sub("T","",size); size=size*1024 
        } else if(size ~ /G/) { 
        sub("G","",size); size=size*1 
        } else if(size ~ /M/) { 
        sub("M","",size); size=size/1024 
        }
        # Must be strictly bigger than current storage and not the storage device itself
        if (size > '"$storageSizeGB"' && $1 != "'"$storageDevice"'") printf "%s %.0f\n", $1, size
        }' | sort -k2,2nr -k1,1 )
        biggerDevice=$(echo "${listOfBiggerDevices}" | head -n1 | awk '{print $1}')
        biggerSizeGB=$(echo "${listOfBiggerDevices}" | head -n1 | awk '{print $2}')
    fi

    echo "# RESULT AFTER DETECTION"
    echo "# dataDevice: ${dataDevice} (${dataSizeGB}GB) (${dataMountedPath})"
    echo "# storageDevice: ${storageDevice} (${storageSizeGB}GB) (${storageMountedPath})"
    echo "# systemDevice: ${systemDevice} (${systemSizeGB}GB) (${systemMountedPath})"
    echo "# installDevice: ${installDevice} (${installDeviceActive}) (${installDeviceReadOnly})"
    echo "# biggerDevice: ${biggerDevice} (${biggerSizeGB}GB)"
    echo "# combinedDataStorage: ${combinedDataStorage}"

    ########################
    # PROPOSE LAYOUT

    # decide if we need to propose a layout
    proposeLayout=0
    if [ ${combinedDataStorage} -eq 0 ]; then
        if [ ${#dataDevice} -eq 0 ] || [ ${#storageDevice} -eq 0 ]; then
            proposeLayout=1
        fi
    else
        if [ ${#storageDevice} -eq 0 ]; then
            proposeLayout=1
        fi
    fi
    if [ ${proposeLayout} -eq 1 ]; then

        echo "# PROPOSING LAYOUT ..."

        # get a list of all connected drives >7GB ordered by size (biggest first)
        listOfDevices=$(lsblk -dno NAME,SIZE | grep -E "^(sd|nvme)" | \
        awk '{ 
        size=$2
        if(size ~ /T/) { 
        sub("T","",size); size=size*1024 
        } else if(size ~ /G/) { 
        sub("G","",size); size=size*1 
        } else if(size ~ /M/) { 
        sub("M","",size); size=size/1024 
        }
        if (size >= 7) printf "%s %.0f\n", $1, size
        }' | sort -k2,2nr -k1,1 )
        echo "listOfDevices='${listOfDevices}'"

        # if there is a migration device set - remove it from the list
        source <(/home/admin/_cache.sh get hddMigrateDeviceFrom)
        if [ ${#hddMigrateDeviceFrom} -gt 0 ]; then
            # check if the device is in the list of devices
            if echo "${listOfDevices}" | grep -q "${hddMigrateDeviceFrom}"; then
                # remove the device from the list
                listOfDevices=$(echo "${listOfDevices}" | grep -v "${hddMigrateDeviceFrom}")
                echo "# skipping device ${hddMigrateDeviceFrom} - migration source device set"
            fi
        fi

        # Set STORAGE (the biggest drive)
        storageDevice=$(echo "${listOfDevices}" | head -n1 | awk '{print $1}')
        storageSizeGB=$(echo "${listOfDevices}" | head -n1 | awk '{print $2}')
        # remove the storage device from the list
        listOfDevices=$(echo "${listOfDevices}" | grep -v "${storageDevice}")

        if [ ${#storageDevice} -gt 0 ] && [ "${computerType}" = "pc" ]; then
            echo "# on bare metal PC - storage device is the system boot device"
            bootFromStorage=1
            bootFromSD=0
        fi

        # no storage device found (system seems only device)
        if [ "${systemDevice}" = "${storageDevice}" ]; then
            scenario="error:no-storage"
            storageDevice=""
            storageSizeGB=""

        # Set SYSTEM
        elif [ ${#systemDevice} -eq 0 ]; then

            # when no system device yet: take the next biggest drive as the system drive
            systemDevice=$(echo "${listOfDevices}" | head -n1 | awk '{print $1}')
            systemSizeGB=$(echo "${listOfDevices}" | head -n1 | awk '{print $2}')

            # if there is was no spereated system drive left
            if [ ${#systemDevice} -eq 0 ]; then

                # force RaspberryPi with no NVMe to boot from SD
                if [ "${computerType}" == "raspberrypi" ] && [ ${gotNVMe} -lt 1 ] ; then
                    echo "# RaspberryPi with no NVMe - keep booting from SD card"
                    bootFromStorage=0
                    bootFromSD=1

                # force RaspberryPi with small NVMe to boot from SD (old NVMe 1TB setups)
                elif [ "${computerType}" == "raspberrypi" ] && [ ${#storageSizeGB} -gt 0 ]  && [ ${storageSizeGB} -lt $((storageFullMinGB + dataMinGB + systemMinGB)) ]; then
                    echo "# NVMe too small to also host system - keep booting from SD card"
                    storageWarning='too-small-for-boot'
                    bootFromStorage=0
                    bootFromSD=1

                # all other systems boot from storage
                else
                    echo "# all other systems boot from storage"
                    bootFromStorage=1
                    bootFromSD=0
                fi

            # when seperate system drive is found - check size
            else

                # if there is a system drive but its smaller than systemMinGB - boot from storage
                if [ ${systemSizeGB} -lt ${systemMinGB} ] && [ ${storageSizeGB} -gt ${storagePrunedMinGB} ]; then
                    echo "# seprate system too small - boot from storage"
                    bootFromSD=0
                    bootFromStorage=1
                    systemDevice=""
                    systemSizeGB=""

                # dont use install device in proposed layout
                elif [ "${systemDevice}" = "${installDevice}" ]; then
                    systemDevice=""
                    systemSizeGB=""

                # otherwise remove the system device from the list
                else
                    listOfDevices=$(echo "${listOfDevices}" | grep -v "${systemDevice}")
                fi

            fi
        fi

        # Set DATA (check last, because its more common to have STORAGE & DATA combined)
        echo "# Selecting DATA device:"
        echo "#  - so far dataDevice(${dataDevice}) / storageDevice(${storageDevice})"
        if [ ${#dataDevice} -eq 0 ] || [ "${dataDevice}" = "${storageDevice}" ]; then

            # when no data device yet: take the second biggest drive as the data drive
            dataDevice=$(echo "${listOfDevices}" | head -n1 | awk '{print $1}')
            dataSizeGB=$(echo "${listOfDevices}" | head -n1 | awk '{print $2}')
            listOfDevices=$(echo "${listOfDevices}" | grep -v "${dataDevice}")
            echo "#  - seleted dataDevice: ${dataDevice} (${dataSizeGB}GB)"

            # ignore system device if choosen as data device
            if [ "${dataDevice}" = "${systemDevice}" ]; then
                echo "#  - dataDevice(${dataDevice}) is the same as system device - ignore it, check next in list"
                dataDevice=$(echo "${listOfDevices}" | head -n1 | awk '{print $1}')
                dataSizeGB=$(echo "${listOfDevices}" | head -n1 | awk '{print $2}')
                listOfDevices=$(echo "${listOfDevices}" | grep -v "${dataDevice}")
            fi

            # dont use install device in proposed layout
            if [ "${dataDevice}" = "${installDevice}" ]; then
                echo "#  - dataDevice(${dataDevice}) is the same as install device - ignore it, check next in list"
                dataDevice=$(echo "${listOfDevices}" | head -n1 | awk '{print $1}')
                dataSizeGB=$(echo "${listOfDevices}" | head -n1 | awk '{print $2}')
                listOfDevices=$(echo "${listOfDevices}" | grep -v "${dataDevice}")
            fi

            # if there is was no spereated data drive - run combine data & storage partiton
            if [ ${#dataDevice} -eq 0 ]; then
                combinedDataStorage=1

            # when data drive but no storage
            elif [ ${#storageDevice} -eq 0 ]; then
                echo "# ERROR: data drive but no storage"
                scenario="error:system-bigger-than-storage"

            # if there is a data drive but its smaller than dataMinGB & storage drive is big enough - combine data & storage partiton
            elif [ ${dataSizeGB} -lt ${dataMinGB} ] && [ ${storageSizeGB} -gt ${storagePrunedMinGB} ]; then
                combinedDataStorage=1

            # remove the data device from the list
            else
                listOfDevices=$(echo "${listOfDevices}" | grep -v "${dataDevice}")
            fi

        else
            echo "#  - dataDevice(${dataDevice}) already set - skip selection"
        fi

    else
        echo "# NO LAYOUT PROPOSAL ... using existing drive layout"
    fi

    #################
    # Check Mininimal Sizes

    # in case of combined data & storage partition
    if [ ${combinedDataStorage} -eq 1 ]; then
        # add dataMinGB to storagePrunedMinGB
        storagePrunedMinGB=$((${storagePrunedMinGB} + ${dataMinGB}))
        # add dataMinGB to storageFullMinGB
        storageFullMinGB=$((${storageFullMinGB} + ${dataMinGB}))
    fi

    # in case of booting from storage
    if [ ${bootFromStorage} -eq 1 ]; then
        # add systemMinGB to storagePrunedMinGB
        storagePrunedMinGB=$((${storagePrunedMinGB} + ${systemMinGB}))
        # add systemMinGB to storageFullMinGB
        storageFullMinGB=$((${storageFullMinGB} + ${systemMinGB}))
    fi

    # STORAGE
    if [ ${#storageDevice} -gt 0 ]; then
        if [ ${storageSizeGB} -lt $((storageFullMinGB - 1)) ]; then
            storageWarning='only-pruned'
        fi
        if [ ${storageSizeGB} -lt $((storagePrunedMinGB - 1)) ]; then
            storageWarning='too-small'
        fi
    fi

    # SYSTEM
    if [ ${#systemDevice} -gt 0 ] && [ ${bootFromStorage} -eq 0 ]; then
        if [ ${systemSizeGB} -lt $((systemMinGB - 1)) ]; then
            systemWarning='too-small'
        fi
    fi

    # DATA
    if [ ${#dataDevice} -gt 0 ]; then
        if [ ${dataSizeGB} -lt $((dataMinGB - 1)) ]; then
            dataWarning='too-small'
        fi
    fi

    #################
    # Device Names

    # use: find_by_id_filename [DEVICENAME]
    find_by_id_filename() {
        local device="$1"
        for dev in /dev/disk/by-id/*; do
            if [ "$(readlink -f "$dev")" = "/dev/$device" ]; then
                basename "$dev"
            fi
        done | sort | head -n1
    }

    # STORAGE
    if [ ${#storageDevice} -gt 0 ]; then
        storageDeviceName=$(find_by_id_filename "${storageDevice}")
    fi

    # SYSTEM
    if [ ${#systemDevice} -gt 0 ]; then
        systemDeviceName=$(find_by_id_filename "${systemDevice}")
    fi

    # DATA
    if [ ${#dataDevice} -gt 0 ]; then
        dataDeviceName=$(find_by_id_filename "${dataDevice}")
    fi

    # BIGGER
    if [ ${#biggerDevice} -gt 0 ]; then
        biggerDeviceName=$(find_by_id_filename "${biggerDevice}")
    fi

    # count number of partitions
    storagePartitionsCount=0
    systemPartitionsCount=0
    dataPartitionsCount=0
    if [ ${#storageDevice} -gt 0 ]; then
        storagePartitionsCount=$(partx -g /dev/"${storageDevice}" 2>/dev/null | wc -l)
    fi
    if [ ${#systemDevice} -gt 0 ]; then
        systemPartitionsCount=$(partx -g /dev/"${systemDevice}" 2>/dev/null | wc -l)
    fi
    if [ ${#dataDevice} -gt 0 ]; then
        dataPartitionsCount=$(partx -g /dev/"${dataDevice}" 2>/dev/null | wc -l)
    fi

    #################
    # Define Scenario

    # Initialize systemCopy flag to default 0
    systemCopy=0

    # migration: detected data from another node implementation
    if [ ${#scenario} -gt 0 ]; then
        echo "# scenario already set by analysis above to: ${scenario}"
       
    elif [ ${#storageMigration} -gt 0 ]; then
        scenario="migration"
        if [ "${systemMountedPath}" != "/" ] && [ ${bootFromSD} -eq 0 ]; then
            systemCopy=1
        fi

    # nodata: no drives >64GB connected
    elif [ ${#biggerDevice} -gt 0 ]; then
        scenario="biggerdevice"

    # nodata: no drives >64GB connected
    elif [ ${#storageDevice} -eq 0 ]; then
        scenario="error:no-storage"

    # ready: Proxmox VM with all seperated drives mounted
    elif [ ${#storageMountedPath} -gt 0 ]  && [ ${#dataMountedPath} -gt 0 ] && [ ${#systemMountedPath} -gt 0 ]; then
        scenario="ready"

    # ready: RaspberryPi, Laptop or VM with patched thru USB drive
    elif [ ${#storageMountedPath} -gt 0 ] && [ ${combinedDataStorage} -eq 1 ]; then
        scenario="ready"

    # recover: drives there but unmounted & blitz config exists (check raspiblitz.conf with -inspect if its update)
    elif [ ${#storageDevice} -gt 0 ] && [ ${#storageMountedPath} -eq 0 ] && [ ${dataConfigFound} -eq 1 ]; then
        scenario="recover"
        # when not bootet from sd card and device system is not already running
        if [ ${bootFromSD} -eq 0 ] && [ "${systemMountedPath}" != "/" ]; then
            systemCopy=1
        fi
        # when storagePartition > 2 (signals that the first partions are available for system)
        if [ ${#storagePartition} -gt 0 ] && [ ${storagePartitionsCount} -gt 2 ] ; then
            systemCopy=1
        fi

    # setup: drives there but unmounted & no blitz config exists & booted from install media
    elif [ ${#storageDevice} -gt 0 ] && [ ${#storageMountedPath} -eq 0 ] && [ ${dataConfigFound} -eq 0 ] && [ "${systemMountedPath}" != "/" ] && [ ${bootFromSD} -eq 0 ]; then
        scenario="setup"
        systemCopy=1

    # setup: drives there but unmounted & no blitz config exists 
    elif [ ${#storageDevice} -gt 0 ] && [ ${#storageMountedPath} -eq 0 ] && [ ${dataConfigFound} -eq 0 ]; then
        scenario="setup"

    # UNKNOWN SCENARIO
    else
        scenario="error:unknown-state"
    fi

    # no system copy on RaspberryPi <=4
    if [ "${computerType}" = "raspberrypi" ]; then
        rpiVersion=$(strings /proc/device-tree/model | grep -o 'Raspberry Pi [0-9]\+' | grep -o '[0-9]\+')
        if [ "${rpiVersion}" != "" ] && [ ${rpiVersion} -lt 5 ]; then
            echo "# RaspberryPi4 - set systemCopy to 0"
            systemCopy=0
        fi
    fi

    # copy data mounted path on combined storage
    if [ "${storagePartition}" = "${dataPartition}" ] && [ ${#dataMountedPath} -eq 0 ] && [ ${combinedDataStorage} -eq 1 ]; then
        dataMountedPath="${storageMountedPath}"
    fi
    
    # echo "# Used Space"

    # get used space on drives in GB
    storageUsePercent=""
    if [ ${#storagePartition} -gt 0 ]; then
        storageUsePercent=$(df "/dev/${storagePartition}" 2>/dev/null | awk 'NR==2 {sub(/%/, "", $5); print $5}')
    fi
    dataUsePercent=""
    if [ ${#dataPartition} -gt 0 ]; then
        dataUsePercent=$(df "/dev/${dataPartition}" 2>/dev/null | awk 'NR==2 {sub(/%/, "", $5); print $5}')
    elif [ ${combinedDataStorage} -eq 1 ] && [ ${#storagePartition} -gt 0 ]; then
        dataUsePercent="${storageUsePercent}"
    fi
    systemUsePercent=""
    if [ ${#systemPartition} -gt 0 ]; then
        systemUsePercent=$(df "/dev/${systemPartition}" 2>/dev/null | awk 'NR==2 {sub(/%/, "", $5); print $5}')
    fi

    # echo "# Free Space"

    # get free space on drives
    if [ ${#storagePartition} -gt 0 ]; then
        storageFreeKB=$(df -k | grep "/dev/${storagePartition}" 2>/dev/null | awk '{print $4}' | tail -n 1)
    fi
    if [ ${#dataPartition} -gt 0 ]; then
        dataFreeKB=$(df -k | grep "/dev/${dataPartition}" 2>/dev/null | awk '{print $4}' | tail -n 1)
    elif [ $combinedDataStorage -eq 1 ]; then
        dataFreeKB="${storageFreeKB}"
    fi
    if [ ${#systemPartition} -gt 0 ]; then
        systemFreeKB=$(df -k | grep "/dev/${systemPartition}" 2>/dev/null | awk '{print $4}' | tail -n 1)
    fi

    # echo "# Temperature"

    # get Temperature of drives
    if [ ${#storageDevice} -gt 0 ]; then
        storageCelsius=$(smartctl -A /dev/${storageDevice} 2>/dev/null | grep -E '^Temperature:|Temperature Sensor' | awk '{print $(NF-1)}' | head -n 1)
    fi
    if [ ${#dataDevice} -gt 0 ]; then
        dataCelsius=$(smartctl -A /dev/${dataDevice} 2>/dev/null | grep -E '^Temperature:|Temperature Sensor' | awk '{print $(NF-1)}' | head -n 1)
    elif [ $combinedDataStorage -eq 1 ]; then
        dataCelsius="${storageCelsius}"
    fi
    if [ ${#systemDevice} -gt 0 ]; then
        systemCelsius=$(smartctl -A /dev/${systemDevice} 2>/dev/null | grep -E '^Temperature:|Temperature Sensor' | awk '{print $(NF-1)}' | head -n 1)
    fi

    # echo "# Unused Space"

    # get unused space on drives
    storageUnusedPercent=0
    dataUnusedPercent=0
    systemUnusedPercent=0
    if [ ${#storageDevice} -gt 0 ]; then
        storageUnusedPercent=$(parted /dev/${storageDevice} unit % print free 2>/dev/null | awk '/Free Space/ {v=$(NF-2); gsub(/[^0-9.]/, "", v)} END{print int(v)}')
    fi
    if [ ${#dataDevice} -gt 0 ]; then
        dataUnusedPercent=$(parted /dev/${dataDevice} unit % print free 2>/dev/null | awk '/Free Space/ {v=$(NF-2); gsub(/[^0-9.]/, "", v)} END{print int(v)}')
    fi
    if [ ${#systemDevice} -gt 0 ]; then
        systemUnusedPercent=$(parted /dev/${systemDevice} unit % print free 2>/dev/null | awk '/Free Space/ {v=$(NF-2); gsub(/[^0-9.]/, "", v)} END{print int(v)}')
    fi

    # echo "# RESULTS"

    # output the result
    echo "scenario='${scenario}'"
    echo "scenarioSystemCopy='${systemCopy}'"
    echo "storageDevice='${storageDevice}'"
    echo "storageDeviceName='${storageDeviceName}'"
    echo "storageSizeGB='${storageSizeGB}'"
    echo "storagePrunedMinGB='${storagePrunedMinGB}'"
    echo "storageFullMinGB='${storageFullMinGB}'"
    echo "storageFreeKB='${storageFreeKB}'"
    echo "storageUsePercent='${storageUsePercent}'"
    echo "storageCelsius='${storageCelsius}'"
    echo "storageWarning='${storageWarning}'"
    echo "storagePartition='${storagePartition}'"
    echo "storagePartitionsCount='${storagePartitionsCount}'"
    echo "storageMountedPath='${storageMountedPath}'"
    echo "storageBlockchainGB='${storageBlockchainGB}'"
    echo "storageMigration='${storageMigration}'"
    echo "storageUnusedSpacePercent='${storageUnusedPercent}'"
    echo "systemDevice='${systemDevice}'"
    echo "systemDeviceName='${systemDeviceName}'"
    echo "systemSizeGB='${systemSizeGB}'"
    echo "systemMinGB='${systemMinGB}'"
    echo "systemFreeKB='${systemFreeKB}'"
    echo "systemWarning='${systemWarning}'"
    echo "systemUsePercent='${systemUsePercent}'"
    echo "systemCelsius='${systemCelsius}'"
    echo "systemPartition='${systemPartition}'"
    echo "systemPartitionsCount='${systemPartitionsCount}'"
    echo "systemMountedPath='${systemMountedPath}'"
    echo "systemUnusedSpacePercent='${systemUnusedPercent}'"
    echo "dataDevice='${dataDevice}'"
    echo "dataDeviceName='${dataDeviceName}'"
    echo "dataSizeGB='${dataSizeGB}'"
    echo "dataMinGB='${dataMinGB}'"
    echo "dataFreeKB='${dataFreeKB}'"
    echo "dataWarning='${dataWarning}'"
    echo "dataUsePercent='${dataUsePercent}'"
    echo "dataCelsius='${dataCelsius}'"
    echo "dataPartition='${dataPartition}'"
    echo "dataPartitionsCount='${dataPartitionsCount}'"
    echo "dataMountedPath='${dataMountedPath}'"
    echo "dataConfigFound='${dataConfigFound}'"
    echo "dataInspectSuccess='${dataInspectSuccess}'"
    echo "dataUnusedSpacePercent='${dataUnusedPercent}'"
    echo "installDevice='${installDevice}'"
    echo "installDeviceActive='${installDeviceActive}'"
    echo "installDeviceReadOnly='${installDeviceReadOnly}'"
    echo "biggerDevice='${biggerDevice}'"
    echo "biggerDeviceName='${biggerDeviceName}'"
    echo "biggerSizeGB='${biggerSizeGB}'"
    echo "combinedDataStorage='${combinedDataStorage}'"
    echo "bootFromStorage='${bootFromStorage}'"
    echo "bootFromSD='${bootFromSD}'"
    echo "isSwapExternal='${isSwapExternal}'"

    # save to cache when -inspect
    if [ ${userWantsInspect} -eq 1 ]; then
        echo "# saving values to cache as system_setup_*"
        /home/admin/_cache.sh set "system_setup_bootFromStorage" "${bootFromStorage}"
        /home/admin/_cache.sh set "system_setup_combinedDataStorage" "${combinedDataStorage}"
        /home/admin/_cache.sh set "system_setup_storageDevice" "${storageDevice}"
        /home/admin/_cache.sh set "system_setup_storageDeviceName" "${storageDeviceName}"
        /home/admin/_cache.sh set "system_setup_storageSizeGB" "${storageSizeGB}"
        /home/admin/_cache.sh set "system_setup_storageWarning" "${storageWarning}"
        /home/admin/_cache.sh set "system_setup_storageBlockchainGB" "${storageBlockchainGB}"
        /home/admin/_cache.sh set "system_setup_storageMigration" "${storageMigration}"
        /home/admin/_cache.sh set "system_setup_storagePartitionsCount" "${storagePartitionsCount}"
        /home/admin/_cache.sh set "system_setup_systemDevice" "${systemDevice}"
        /home/admin/_cache.sh set "system_setup_systemDeviceName" "${storageDeviceName}"
        /home/admin/_cache.sh set "system_setup_systemSizeGB" "${systemSizeGB}"
        /home/admin/_cache.sh set "system_setup_systemWarning" "${systemWarning}"
        /home/admin/_cache.sh set "system_setup_dataDevice" "${dataDevice}"
        /home/admin/_cache.sh set "system_setup_dataDeviceName" "${dataDeviceName}"
        /home/admin/_cache.sh set "system_setup_dataSizeGB" "${dataSizeGB}"
        /home/admin/_cache.sh set "system_setup_dataWarning" "${dataWarning}"
        /home/admin/_cache.sh set "system_setup_installDevice" "${installDevice}"
        /home/admin/_cache.sh set "system_setup_installDeviceReadOnly" "${installDeviceReadOnly}"
    fi

    if [ "$action" = "status" ]; then
        exit 0
    fi
fi

##############################
# MOUNT
# perma mount all devices
#############################

if [ "$action" = "mount" ]; then

    mainMountPoint="/mnt/hdd"
    storageMountPoint="/mnt/disk_storage"
    dataMountPoint="/mnt/disk_data"

    # Source status to get drive configuration
    source <(/home/admin/config.scripts/blitz.data.sh status)

    # check directories are already mounted
    if [ $(df | grep -c "${storageMountPoint}") -gt 0 ]; then
        echo "# Already mounted: ${storageMountPoint}"
        exit 1
    fi
    if [ ${combinedDataStorage} -eq 0 ] && [ $(df | grep -c "${dataMountPoint}") -gt 0 ]; then
        echo "# Already mounted: ${dataMountPoint}"
        exit 1
    fi

    # check partitions were found
    if [ ${#storagePartition} -eq 0 ]; then
        echo "error='storagePartition not detected'"
        exit 1
    fi
    if [ ${#dataPartition} -eq 0 ] && [ ${combinedDataStorage} -eq 0 ]; then
        echo "error='dataPartition not detected'"
        exit 1
    fi

    # debug info
    echo "# storagePartition: ${storagePartition}"
    echo "# dataPartition: ${dataPartition}"

    # check if partititions are already mounted
    if [ $(findmnt -n -o SOURCE,TARGET | grep -c "/dev/${storagePartition}") -gt 0 ]; then
        echo "# Already mounted: ${storagePartition}"
        exit 1
    fi    
    if [ ${combinedDataStorage} -eq 0 ] && [ $(findmnt -n -o SOURCE,TARGET | grep -c "/dev/${dataPartition}") -gt 0 ]; then
        echo "# Already mounted: ${dataPartition}"
        exit 1
    fi

    # determine UUID of storage partition
    storageUUID=$(blkid -s UUID -o value "/dev/${storagePartition}")
    if [ "${storageUUID}" = "" ]; then
        echo "# storageUUID not found with blkid - trying lsblk"
        storageUUID=$(lsblk -n -o UUID "/dev/${storagePartition}")
    fi
    if [ "${storageUUID}" = "" ]; then
        echo "error='Could not find UUID for storage partition ${storagePartition} (${storageUUID})'"
        exit 1
    fi

    # determine UUID of data partition (if needed)
    dataUUID=""
    if [ ${combinedDataStorage} -eq 0 ]; then
        dataUUID=$(blkid -s UUID -o value "/dev/${dataPartition}")
        if [ "${dataUUID}" = "" ]; then
            echo "# dataUUID not found with blkid - trying lsblk"
            dataUUID=$(lsblk -n -o UUID "/dev/${dataPartition}")
        fi
        if [ "${dataUUID}" = "" ]; then
            echo "error='Could not find UUID for data partition ${dataPartition} (${dataUUID})'"
            exit 1
        fi
    fi

    # debug info
    echo "# storageUUID: ${storageUUID}"
    echo "# dataUUID: ${dataUUID}"
    echo "# storageMountPoint: ${storageMountPoint}"
    echo "# dataMountPoint: ${dataMountPoint}"
    echo "# mainMountPoint: ${mainMountPoint}"
    echo "# combinedDataStorage: ${combinedDataStorage}"

    # update fstab
    sed -i "\#${storageMountPoint}#d" /etc/fstab
    sed -i "/UUID=${storageUUID}/d" /etc/fstab
    echo "# Updating fstab for ${storagePartition} (${storageUUID}) -> ${storageMountPoint}"
    echo "UUID=${storageUUID} ${storageMountPoint} ext4 defaults,noexec 0 2" >> /etc/fstab
    echo "# combinedDataStorage: ${combinedDataStorage}"
    if [ ${combinedDataStorage} -eq 0 ]; then
        sed -i "\#${dataMountPoint}#d" /etc/fstab
        sed -i "/UUID=${dataUUID}/d" /etc/fstab 
        echo "# Also Updating fstab for ${dataPartition} (${dataUUID}) -> ${dataMountPoint}"
        echo "UUID=${dataUUID} ${dataMountPoint} ext4 defaults,noexec 0 2" >> /etc/fstab
    fi

    # Ensure all potential mount points exist
    echo "# Running mount -a"
    sync
    systemctl daemon-reload
    mkdir -p ${storageMountPoint} ${dataMountPoint} ${mainMountPoint}
    chmod 000 ${storageMountPoint} ${dataMountPoint} ${mainMountPoint}
    mount -a
    sleep 2

    # Verify mounts after attempt
    if [ $(df | grep -c "${storageMountPoint}") -eq 0 ]; then
        echo "error='Failed to mount ${storagePartition} on ${storageMountPoint} after fstab update'"
        exit 1
    fi
    if [ ${combinedDataStorage} -eq 0 ] && [ $(df | grep -c "${dataMountPoint}") -eq 0 ]; then
        echo "error='Failed to mount ${dataPartition} on ${dataMountPoint} after fstab update'"
        exit 1
    fi
    
    echo "# Mount successful." >> ${logFile}
    exit 0
fi

###################
# LINK
###################

if [ "$action" = "link" ]; then

    mainMountPoint="/mnt/hdd"

    # Source status to get drive configuration
    source <(/home/admin/config.scripts/blitz.data.sh status)

    # check drive pathes are available
    if [ ${#storageMountedPath} -eq 0 ]; then
        echo "error='storageMountedPath not detected'"
        exit 1
    fi
    if [ ${combinedDataStorage} -eq 1 ]; then
        dataMountedPath="${storageMountedPath}"
    else
        if [ ${#dataMountedPath} -eq 0 ]; then
            echo "error='dataMountedPath not detected'"
            exit 1
        fi
    fi

    echo "# storageMountedPath: ${storageMountedPath}"
    echo "# dataMountedPath: ${dataMountedPath}"
    echo "# mainMountPoint: ${mainMountPoint}"

    ####################################
    # combine storage & data

    echo "# adding main folders to ${mainMountPoint}"
    mkdir -p ${mainMountPoint}

    # /app-storage
    unlink ${mainMountPoint}/app-storage 2>/dev/null
    if [ -d "${mainMountPoint}/app-storage" ]; then
        echo "error='${mainMountPoint}/app-storage is real directory'"
        exit 1
    fi
    ln -s ${storageMountedPath}/app-storage ${mainMountPoint}/app-storage
    chown bitcoin:bitcoin ${storageMountedPath}/app-storage ${mainMountPoint}/app-storage
    chmod 755 ${storageMountedPath}/app-storage ${mainMountPoint}/app-storage
    chmod o+x ${storageMountedPath}
    chmod o+x ${storageMountedPath}/app-storage

     # /app-data
    unlink ${mainMountPoint}/app-data 2>/dev/null
    if [ -d "${mainMountPoint}/app-data" ];then
        echo "error='${mainMountPoint}/app-data is real directory'"
        exit 1
    fi
    ln -s ${dataMountedPath}/app-data ${mainMountPoint}/app-data
    chown bitcoin:bitcoin ${dataMountedPath}/app-data ${mainMountPoint}/app-data
    mkdir -p /mnt/hdd/app-data/bitcoin/wallets 2>/dev/null
    chown -R bitcoin:bitcoin ${dataMountedPath}/app-data/bitcoin
    chmod 755 ${dataMountedPath}/app-data ${mainMountPoint}/app-data
    chmod o+x ${dataMountedPath}
    chmod o+x ${dataMountedPath}/app-data

    # /temp
    mkdir -p ${storageMountedPath}/temp 2>/dev/null
    unlink ${mainMountPoint}/temp 2>/dev/null
    ln -s ${storageMountedPath}/temp ${mainMountPoint}/temp
    chown bitcoin:bitcoin ${mainMountPoint}/temp
    chmod 777 ${storageMountedPath}/temp
    chmod 777 ${mainMountPoint}/temp

    # /mnt/hdd/bitcoin directory (move old data if needed & link for backwards compatibility)
    mkdir -p "${storageMountedPath}/app-storage/bitcoin"
    mkdir -p "${dataMountedPath}/app-data/bitcoin"
    chown bitcoin:bitcoin "${dataMountedPath}/app-data/bitcoin"
    if [ -d "${storageMountedPath}/bitcoin" ]; then
        echo "# moving old data from ${storageMountedPath}/bitcoin to ${storageMountedPath}/app-storage/bitcoin"
        rsync -a --remove-source-files --prune-empty-dirs ${storageMountedPath}/bitcoin/ ${storageMountedPath}/app-storage/bitcoin/
        if [ $? -ne 0 ]; then
            echo "error='failed to move ${storageMountedPath}/bitcoin/* to ${storageMountedPath}/app-storage/bitcoin/'"
        else
            rm -rf ${storageMountedPath}/bitcoin
        fi
    fi
    if [ -d "${storageMountedPath}/app-storage/bitcoin/wallet.dat" ]; then
        echo "# moving old wallet from ${storageMountedPath}/app-storage/bitcoin/wallet.dat to ${dataMountedPath}/app-data/bitcoin/wallets/wallet.dat"
        mv --force ${storageMountedPath}/app-storage/bitcoin/wallet.dat ${dataMountedPath}/app-data/bitcoin/wallets/wallet.dat
        if [ $? -ne 0 ]; then
            echo "error='failed to move ${storageMountedPath}/app-storage/bitcoin/wallet.dat to ${dataMountedPath}/app-data/bitcoin/wallets/wallet.dat'"
        fi
    fi
    if [ -f "${storageMountedPath}/app-storage/bitcoin/bitcoin.conf" ] && [ ! -L "${storageMountedPath}/app-storage/bitcoin/bitcoin.conf" ]; then
        if [ ! -f "${dataMountedPath}/app-data/bitcoin/bitcoin.conf" ]; then
            echo "# moving bitcoin config file from ${storageMountedPath}/app-storage/bitcoin to ${dataMountedPath}/app-data/bitcoin"
            mv --force ${storageMountedPath}/app-storage/bitcoin/bitcoin.conf ${dataMountedPath}/app-data/bitcoin/bitcoin.conf
            if [ $? -ne 0 ]; then
                echo "error='failed to move ${storageMountedPath}/app-storage/bitcoin/bitcoin.conf to ${dataMountedPath}/app-data/bitcoin/bitcoin.conf'"
            fi
        else
            echo "error='there is ${storageMountedPath}/app-storage/bitcoin/bitcoin.conf AND ${dataMountedPath}/app-data/bitcoin/bitcoin.conf'"
        fi
    fi
    unlink ${mainMountPoint}/app-storage/bitcoin/bitcoin.conf 2>/dev/null

    echo "# For backwards compatibility: Liniking ${mainMountPoint}/bitcoin"
    unlink ${mainMountPoint}/bitcoin 2>/dev/null
    ln -s ${storageMountedPath}/app-storage/bitcoin ${mainMountPoint}/bitcoin
    chown bitcoin:bitcoin ${mainMountPoint}/bitcoin
    chmod 777 ${mainMountPoint}/bitcoin

    # /mnt/hdd/lnd directory (move old data if needed & link for backwards compatibility)
    mkdir -p "${dataMountedPath}/app-data/lnd"
    chown bitcoin:bitcoin "${dataMountedPath}/app-data/lnd"
    if [ -d "${storageMountedPath}/lnd" ]; then
        echo "# moving old data from ${storageMountedPath}/lnd to ${dataMountedPath}/app-data/lnd"
        rsync -a --remove-source-files --prune-empty-dirs ${storageMountedPath}/lnd/ ${dataMountedPath}/app-data/lnd/
        if [ $? -ne 0 ]; then
            echo "error='failed to rsync /app-data/lnd/'"
        else
            rm -rf ${storageMountedPath}/lnd
        fi
    fi
    echo "# For backwards compatibility: Liniking ${mainMountPoint}/lnd"
    unlink ${mainMountPoint}/lnd 2>/dev/null
    if [ -d "${mainMountPoint}/lnd" ]; then
        echo "error='${mainMountPoint}/lnd is real directory'"
        exit 1
    fi
    ln -s ${dataMountedPath}/app-data/lnd ${mainMountPoint}/lnd
    chown bitcoin:bitcoin ${mainMountPoint}/lnd
    chmod 770 ${mainMountPoint}/lnd

    # /mnt/hdd/tor directory (move old data if needed & link for backwards compatibility)
    mkdir -p "${dataMountedPath}/app-data/tor"
    chown debian-tor:debian-tor "${dataMountedPath}/app-data/tor"
    if [ -d "${storageMountedPath}/tor" ]; then
        echo "# moving old data from ${storageMountedPath}/tor to ${dataMountedPath}/app-data/tor"
        rsync -a --remove-source-files --prune-empty-dirs ${storageMountedPath}/tor/ ${dataMountedPath}/app-data/tor/
        if [ $? -ne 0 ]; then
            echo "error='failed to rsync /app-data/tor/'"
        else
            rm -rf ${storageMountedPath}/tor
        fi
    fi
    echo "# For backwards compatibility: Liniking ${mainMountPoint}/tor"
    unlink ${mainMountPoint}/tor 2>/dev/null
    if [ -d "${mainMountPoint}/tor" ]; then
        echo "error='${mainMountPoint}/tor is real directory'"
        exit 1
    fi
    chown -R debian-tor:debian-tor ${mainMountPoint}/app-data/tor
    chmod -R 700 ${mainMountPoint}/app-data/tor
    ln -s ${dataMountedPath}/app-data/tor ${mainMountPoint}/tor
    chown debian-tor:debian-tor ${mainMountPoint}/tor
    chmod 700 ${mainMountPoint}/tor

    # /mnt/hdd/aspiblitz.conf (move old file if needed & link for backwards compatibility)
    if [ -f "${storageMountedPath}/raspiblitz.conf" ] && [ ! -L "${storageMountedPath}/raspiblitz.conf" ]; then
        echo "# moving old config from ${storageMountedPath}/raspiblitz.conf to ${dataMountedPath}/app-data/raspiblitz.conf"
        mv --force ${storageMountedPath}/raspiblitz.conf ${dataMountedPath}/app-data/raspiblitz.conf
    fi
    if [ -f "${mainMountPoint}/raspiblitz.conf" ] && [ ! -L "${mainMountPoint}/raspiblitz.conf" ]; then
        mv --force ${mainMountPoint}/raspiblitz.conf ${mainMountPoint}/app-data/raspiblitz.conf
    fi

    echo "you find bitcoin.conf now in ${mainMountPoint}/app-data/bitcoin/bitcoin.conf" > ${mainMountPoint}/bitcoin/bitcoin-conf.info

    if [ -f "${mainMountPoint}/.tmux.conf.local" ] && [ ! -L "${mainMountPoint}/.tmux.conf.local" ]; then
        mv --force ${mainMountPoint}/.tmux.conf.local ${mainMountPoint}/app-data/.tmux.conf.local
    fi
    if [ -f "${storageMountedPath}/.tmux.conf.local" ] && [ ! -L "${storageMountedPath}/.tmux.conf.local" ]; then
        mv --force ${storageMountedPath}/.tmux.conf.local ${mainMountPoint}/app-data/.tmux.conf.local
    fi

    ### bitcoin user symbol links
    echo "# bitcoin user symbol link: /home/bitcoin/.bitcoin"
    unlink /home/bitcoin/.bitcoin 2>/dev/null
    ln -s /mnt/hdd/app-data/bitcoin /home/bitcoin/.bitcoin
    chown bitcoin:bitcoin /home/bitcoin/.bitcoin
    echo "# bitcoin user symbol link: /home/bitcoin/.lnd"
    unlink /home/bitcoin/.lnd 2>/dev/null
    ln -s /mnt/hdd/app-data/lnd /home/bitcoin/.lnd
    chown bitcoin:bitcoin /home/bitcoin/.lnd

    ### admin user symbol links
    echo "# admin user symbol link: /home/admin/.bitcoin"
    unlink /home/admin/.bitcoin 2>/dev/null
    ln -s /mnt/hdd/app-data/bitcoin /home/admin/.bitcoin
    echo "# admin user symbol link: /home/admin/.lnd"
    unlink /home/admin/.lnd 2>/dev/null
    ln -s /mnt/hdd/app-data/lnd /home/admin/.lnd
    chmod -R g+X /home/admin/.lnd

    # set permissions on complete lnd macaroon folder path
    chmod a+rx ${mainMountPoint} 2>/dev/null
    chmod a+rx ${mainMountPoint}/app-data 2>/dev/null
    chmod a+rx ${mainMountPoint}/app-data/lnd 2>/dev/null
    chmod a+rx ${mainMountPoint}/app-data/lnd/data 2>/dev/null
    chmod a+rx ${mainMountPoint}/app-data/lnd/data/chain 2>/dev/null
    chmod a+rx ${mainMountPoint}/app-data/lnd/data/chain/bitcoin 2>/dev/null
    chmod a+rx ${mainMountPoint}/app-data/lnd/data/chain/bitcoin/mainnet 2>/dev/null
    chmod a+rx ${mainMountPoint}/app-data/lnd/data/chain/bitcoin/testnet 2>/dev/null
    chmod a+rx ${mainMountPoint}/app-data/lnd/data/chain/bitcoin/signet 2>/dev/null
    chmod a+rx ${mainMountPoint}/app-data/lnd/tls.cert 2>/dev/null

    exit 0
fi

###################
# COPY-SYSTEM
###################

if [ "$action" = "copy-system" ]; then

    actionDevice=$2
    actionDeviceType=$(echo "$3" | tr '[:upper:]' '[:lower:]')
    echo "STARTED blitz.data.sh ${action} (${actionDevice})..." >> ${logFile}
        
    # check that device is set & exists & not mounted
    if [ ${#actionDevice} -eq 0 ]; then
        echo "error='missing device'"
        echo "error='missing device'" >> ${logFile}
        exit 1
    fi
    if ! lsblk -no NAME | grep -q "${actionDevice}$"; then
        echo "error='device not found'"
        echo "error='device not found'" >> ${logFile}
        exit 1
    fi
    if findmnt -n -o TARGET "/dev/${actionDevice}" 2>/dev/null; then
        echo "error='device is mounted'"
        echo "error='device is mounted'" >> ${logFile}
        exit 1
    fi

    # determine the partition base name
    actionDevicePartitionBase=${actionDevice}
    if [[ "${actionDevice}" =~ nvme ]]; then
        actionDevicePartitionBase="${actionDevice}p"
    fi

    if [ "${actionDeviceType}" != "system" ] && [ "${actionDeviceType}" != "storage" ]; then
        echo "# actionDeviceType(${actionDeviceType}) UNKOWN" >> ${logFile}
        echo "error='type not supported'"
        exit 1
    fi
    if [ "${actionDeviceType}" = "system" ]; then
        systemPartition="${actionDevicePartitionBase}2"
    fi
    if [ "${actionDeviceType}" = "storage" ]; then
        systemPartition="${actionDevicePartitionBase}2"
    fi  

    # debug info
    echo "# actionDevice(${actionDevice})" >> ${logFile}
    echo "# actionDevicePartitionBase(${actionDevicePartitionBase})" >> ${logFile}
    echo "# actionDeviceType(${actionDeviceType})" >> ${logFile}
    echo "# systemPartition(${systemPartition})" >> ${logFile}
    echo "# computerType(${computerType})" >> ${logFile}

    ##########################
    # MAKE BOOTABLE
    echo "# MAKE BOOTABLE" >> ${logFile}

    # RASPBERRY PI
    if [ "${computerType}" = "raspberrypi" ]; then
        echo "# RaspberryPi - set LBA flag" >> ${logFile}
        parted /dev/${actionDevice} --script set 1 lba on
        isFlagSetLBA=$(parted /dev/${actionDevice} --script print | grep -c 'fat32.*lba')
        if [ ${isFlagSetLBA} -eq 0 ]; then
            echo "error='failed to set LBA flag'"
            exit 1
        fi
        echo "# RaspberryPi - Bootorder" >> ${logFile}
        isBootOrderSet=$(sudo rpi-eeprom-config | grep -cx "BOOT_ORDER=0xf461")
        if [ ${isBootOrderSet} -eq 0 ]; then
            echo "# .. changeing Bootorder" >> ${logFile}
            rpi-eeprom-config --out bootconf.txt
            sed -i '/^BOOT_ORDER=/d' ./bootconf.txt && sudo sh -c 'echo "BOOT_ORDER=0xf461" >> ./bootconf.txt'
            rpi-eeprom-config --apply bootconf.txt
            rm bootconf.txt
        else
            echo "# .. Bootorder already set" >> ${logFile}
        fi

    # VM & PC
    else
        echo "# VM & PC - set BOOT/ESP flag" >> ${logFile}
        parted /dev/${actionDevice} --script set 1 boot on
        parted /dev/${actionDevice} --script set 1 esp on
        isFlagSetBOOT=$(parted /dev/${actionDevice} --script print | grep -c 'fat32.*boot')
        if [ ${isFlagSetBOOT} -eq 0 ]; then
            echo "error='failed to set BOOT flag'"
            exit 1
        fi
        isFlagSetESP=$(parted /dev/${actionDevice} --script print | grep -c 'fat32.*esp')
        if [ ${isFlagSetESP} -eq 0 ]; then
            echo "error='failed to set ESP flag'"
            exit 1
        fi
    fi

    ##########################
    # COPY SYSTEM
    echo "# SYSTEM COPY" >> ${logFile}

    # copy the boot drive
    bootPath="/boot/efi"
    bootPathEscpaed="\/boot\/efi"
    if [ "${computerType}" = "raspberrypi" ]; then
        bootPath="/boot/firmware/"
        bootPathEscpaed="\/boot\/firmware"
    fi
    rm -rf /mnt/disk_boot 2>/dev/null
    mkdir -p /mnt/disk_boot 2>/dev/null
    mount /dev/${actionDevicePartitionBase}1 /mnt/disk_boot
    if ! findmnt -n -o TARGET "/mnt/disk_boot" 2>/dev/null; then
        echo "error='boot partition not mounted'"
        exit 1
    fi
    if [ "${computerType}" = "raspberrypi" ]; then
        echo "# .. boot rsync start" >> ${logFile}
        echo "boot" > /var/cache/raspiblitz/temp/progress.txt
        rsync -axHAX --delete --info=progress2 ${bootPath} /mnt/disk_boot/ 2>&1 | stdbuf -oL tr '\r' '\n' | grep --line-buffered '%' | stdbuf -oL sed -n 's/.* \([0-9]\+\)% .*/\1%/p' >> /var/cache/raspiblitz/temp/progress.txt
        if [ $? -ne 0 ]; then
            echo "error='fail on boot copy'"
            exit 1
        fi
        echo "# OK - Boot copied" >> ${logFile}
    fi

    # copy the system drive
    echo "# .. copy system" >> ${logFile}
    rm -rf /mnt/disk_system 2>/dev/null
    mkdir -p /mnt/disk_system 2>/dev/null
    mount /dev/${actionDevicePartitionBase}2 /mnt/disk_system
    if ! findmnt -n -o TARGET "/mnt/disk_system" 2>/dev/null; then
        echo "error='system partition not mounted'"
        exit 1
    fi
    echo "# .. system rsync start" >> ${logFile}
    echo "system" > /var/cache/raspiblitz/temp/progress.txt
    rsync -axHAX --delete\
        --exclude=/dev/* \
        --exclude=/proc/* \
        --exclude=/sys/* \
        --exclude=/tmp/* \
        --exclude=/run/* \
        --exclude=/mnt/* \
        --exclude=/media/* \
        --exclude=${bootPath}/* \
        --exclude=/lost+found \
        --exclude=/var/cache/* \
        --exclude=/var/tmp/* \
        --exclude=/var/log/* \
        --info=progress2 / /mnt/disk_system/ 2>&1 | stdbuf -oL tr '\r' '\n' | grep --line-buffered '%' | stdbuf -oL sed -n 's/.* \([0-9]\+\)% .*/\1%/p' >> /var/cache/raspiblitz/temp/progress.txt
                                                 
    if [ $? -ne 0 ]; then
        echo "error='fail on system copy'"
        exit 1
    fi
    echo "# OK - System copied" >> ${logFile}

    # needed after fixes
    mkdir -p /mnt/disk_system/var/log/redis
    touch /mnt/disk_system/var/log/redis/redis-server.log
    chown redis:redis /mnt/disk_system/var/log/redis/redis-server.log
    chmod 644 /mnt/disk_system/var/log/redis/redis-server.log

    # fstab link & command.txt
    echo "# Perma mount boot & system drives" >> ${logFile}
    BOOT_UUID=$(blkid -s UUID -o value /dev/${actionDevicePartitionBase}1)
    ROOT_UUID=$(blkid -s UUID -o value /dev/${actionDevicePartitionBase}2)
    ROOT_PARTUUID=$(sudo blkid -s PARTUUID -o value /dev/${actionDevicePartitionBase}2)
    echo "# - BOOT_UUID(${BOOT_UUID})" >> ${logFile}
    echo "# - ROOT_UUID(${ROOT_UUID})" >> ${logFile}
    if [ "${computerType}" = "raspberrypi" ]; then
        echo "# - RaspberryPi - edit command.txt" >> ${logFile}
        sed -i "s|PARTUUID=[^ ]*|PARTUUID=$ROOT_PARTUUID|" /mnt/disk_boot/cmdline.txt
    fi
    cat > /mnt/disk_system/etc/fstab << EOF
# /etc/fstab: static file system information
#
# <file system>                           <mount point>  <type>  <options>                              <dump>  <pass>
UUID=${ROOT_UUID}                         /              ext4    defaults,noatime                       0       1
UUID=${BOOT_UUID}                        ${bootPath}          vfat    defaults,noatime,umask=0077           0       2
EOF

    # install EFI GRUB for VM & PC
    if [ "${computerType}" != "raspberrypi" ]; then
        echo "# EFI GRUB" >> ${logFile}
        DISK_SYSTEM="/mnt/disk_system"
        BOOT_PARTITION="/dev/${actionDevicePartitionBase}1"
        ROOT_PARTITION="/dev/${actionDevicePartitionBase}2"
        echo "# Mounting root and boot partitions..." >> ${logFile}
        umount /mnt/disk_boot 2>/dev/null
        mkdir -p $DISK_SYSTEM/boot/efi 2>/dev/null
        mount $BOOT_PARTITION $DISK_SYSTEM/boot/efi || { echo "Failed to mount boot partition"; exit 1; }
        echo "# Bind mounting system directories..." >> ${logFile}
        mount --bind /dev $DISK_SYSTEM/dev || { echo "Failed to bind /dev"; exit 1; }
        mount --bind /sys $DISK_SYSTEM/sys || { echo "Failed to bind /sys"; exit 1; }
        mount --bind /proc $DISK_SYSTEM/proc || { echo "Failed to bind /proc"; exit 1; }
        rm $DISK_SYSTEM/etc/resolv.conf
        cp /etc/resolv.conf $DISK_SYSTEM/etc/resolv.conf || { echo "Failed to copy resolv.conf"; exit 1; }
        echo "# Entering chroot and setting up GRUB..." >> ${logFile}
        chroot $DISK_SYSTEM /bin/bash <<EOF
apt-get install -y grub-efi-amd64 efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable --recheck
update-grub
EOF
        umount $DISK_SYSTEM/boot/efi
        umount $DISK_SYSTEM
    fi

    rm /var/cache/raspiblitz/temp/progress.txt
    echo "# OK - ${action} done" >> ${logFile}
    exit 0
fi

###################
# FORMAT
###################

if [ "$action" = "setup" ]; then

    echo "STARTED blitz.data.sh ${action} ..." >> ${logFile}
        
    # check that it is a valid setup type: STORAGE, DATA, SYSTEM
    actionType=$2
    if [ "${actionType}" != "STORAGE" ] && [ "${actionType}" != "DATA" ] && [ "${actionType}" != "SYSTEM" ]; then
        echo "# actionType(${actionType})"
        echo "error='setup type not supported'"
        echo "error='setup type not supported'" >> ${logFile}
        exit 1
    fi

    # check that device is set & exists & not mounted
    actionDevice=$3
    if [ ${#actionDevice} -eq 0 ]; then
        echo "error='missing device'"
        echo "error='missing device'" >> ${logFile}
        exit 1
    fi
    if ! lsblk -no NAME | grep -q "${actionDevice}$"; then
        echo "error='device not found'"
        echo "error='device not found'" >> ${logFile}
        exit 1
    fi
    if findmnt -n -o TARGET "/dev/${actionDevice}" 2>/dev/null; then
        echo "error='device is mounted'"
        echo "error='device is mounted'" >> ${logFile}
        exit 1
    fi

    # check if data should also be combined with storage
    actionCombinedData=$4
    if [ ${#actionCombinedData} -gt 0 ] &&  [ "${actionCombinedData}" != "combinedData=1" ] && [ "${actionCombinedData}" != "0" ] && [ "${actionCombinedData}" != "1" ]; then
        echo "error='combinedData(${actionCombinedData})'" >> ${logFile}
        echo "error='combinedData value not supported'"
        exit 1
    fi
    if [ "${actionCombinedData}" = "combinedData=1" ] || [ "${actionCombinedData}" = "1" ]; then
        actionCombinedData=1
    else
        actionCombinedData=0
    fi

    # check if boot should be from storage (create system partition)
    actionCreateSystemPartition=$5
    if [ ${#actionCreateSystemPartition} -gt 0 ] && [ "${actionCreateSystemPartition}" != "addSystemPartition=0" ] && [ "${actionCreateSystemPartition}" != "addSystemPartition=1" ] && [ "${actionCreateSystemPartition}" != "0" ] && [ "${actionCreateSystemPartition}" != "1" ]; then
        echo "error='addSystemPartition(${actionCreateSystemPartition})'" >> ${logFile}
        echo "error='addSystemPartition value not supported'"
        exit 1
    fi
    if [ "${actionCreateSystemPartition}" = "addSystemPartition=1" ] || [ "${actionCreateSystemPartition}" = "1" ]; then
        actionCreateSystemPartition=1
    else
        actionCreateSystemPartition=0
    fi

    # determine the partition base name
    actionDevicePartitionBase=${actionDevice}
    if [[ "${actionDevice}" =~ ^nvme ]]; then
        actionDevicePartitionBase="${actionDevice}p"
    fi

    source <(/home/admin/config.scripts/blitz.data.sh status)

    # debug info
    echo "# actionType(${actionType})"  >> ${logFile}
    echo "# actionDevice(${actionDevice})" >> ${logFile}
    echo "# actionDevicePartitionBase(${actionDevicePartitionBase})" >> ${logFile}
    echo "# actionCombinedData(${actionCombinedData})" >> ${logFile}
    echo "# actionCreateSystemPartition(${actionCreateSystemPartition})" >> ${logFile}

    ##########################
    # PARTITION & FORMAT

    # SYSTEM (single drive)
    if [ "${actionType}" = "SYSTEM" ]; then

        if [ ${systemMountedPath} = "/" ]; then

             echo "# SYSTEM -> partitioning & format because its running & mounted system" >> ${logFile}

        else

            echo "# SYSTEM partitioning" >> ${logFile}
            sfdisk --delete /dev/${actionDevice} 2>/dev/null
            wipefs -a /dev/${actionDevice} 2>/dev/null
            parted /dev/${actionDevice} --script mklabel msdos
            parted /dev/${actionDevice} --script mkpart primary fat32 1MiB 513MiB
            parted /dev/${actionDevice} --script mkpart primary ext4 541MB 100%
            wipefs -a /dev/${actionDevicePartitionBase}1 2>/dev/null
            mkfs.fat -F 32 /dev/${actionDevicePartitionBase}1
            wipefs -a /dev/${actionDevicePartitionBase}2 2>/dev/null
            mkfs -t ext4  /dev/${actionDevicePartitionBase}2

            # MAKE BOOTABLE
            echo "# MAKE BOOTABLE" >> ${logFile}

            # RASPBERRY PI
            if [ "${computerType}" = "raspberrypi" ]; then
                echo "# RaspberryPi - set LBA flag" >> ${logFile}
                parted /dev/${actionDevice} --script set 1 lba on
                isFlagSetLBA=$(parted /dev/${actionDevice} --script print | grep -c 'fat32.*lba')
                if [ ${isFlagSetLBA} -eq 0 ]; then
                    echo "error='failed to set LBA flag'"
                    exit 1
                fi
                echo "# RaspberryPi - Bootorder" >> ${logFile}
                isBootOrderSet=$(sudo rpi-eeprom-config | grep -cx "BOOT_ORDER=0xf461")
                if [ ${isBootOrderSet} -eq 0 ]; then
                    echo "# .. changeing Bootorder" >> ${logFile}
                    rpi-eeprom-config --out bootconf.txt
                    sed -i '/^BOOT_ORDER=/d' ./bootconf.txt && sudo sh -c 'echo "BOOT_ORDER=0xf461" >> ./bootconf.txt'
                    rpi-eeprom-config --apply bootconf.txt
                    rm bootconf.txt
                else
                    echo "# .. Bootorder already set" >> ${logFile}
                fi

            # VM & PC
            else
                echo "# VM & PC - set BOOT/ESP flag" >> ${logFile}
                parted /dev/${actionDevice} --script set 1 boot on
                parted /dev/${actionDevice} --script set 1 esp on
                isFlagSetBOOT=$(parted /dev/${actionDevice} --script print | grep -c 'fat32.*boot')
                if [ ${isFlagSetBOOT} -eq 0 ]; then
                    echo "error='failed to set BOOT flag'"
                    exit 1
                fi
                isFlagSetESP=$(parted /dev/${actionDevice} --script print | grep -c 'fat32.*esp')
                if [ ${isFlagSetESP} -eq 0 ]; then
                    echo "error='failed to set ESP flag'"
                    exit 1
                fi
            fi
        fi

    # STOARGE with System partition (if addSystemPartition=1)
    elif [ "${actionType}" = "STORAGE" ] && [ ${actionCreateSystemPartition} -eq 1 ]; then

        echo "# STORAGE partitioning (with boot)" >> ${logFile}
        sfdisk --delete /dev/${actionDevice} >> ${logFile}
        wipefs -a /dev/${actionDevice} >> ${logFile}
        parted /dev/${actionDevice} --script mklabel msdos >> ${logFile}
        parted /dev/${actionDevice} --script mkpart primary fat32 1MiB 513MiB >> ${logFile}
        parted /dev/${actionDevice} --script mkpart primary ext4 541MB 65GB >> ${logFile}
        parted /dev/${actionDevice} --script mkpart primary ext4 65GB 100% >> ${logFile}
        echo "# .. formating" >> ${logFile}
        wipefs -a /dev/${actionDevicePartitionBase}1 2>/dev/null >> ${logFile}
        mkfs.fat -F 32 /dev/${actionDevicePartitionBase}1 >> ${logFile}
        wipefs -a /dev/${actionDevicePartitionBase}2 2>/dev/null >> ${logFile}
        mkfs -t ext4  /dev/${actionDevicePartitionBase}2 >> ${logFile}
        wipefs -a /dev/${actionDevicePartitionBase}3 2>/dev/null >> ${logFile}
        mkfs -t ext4  /dev/${actionDevicePartitionBase}3 >> ${logFile}
        rm -rf /mnt/disk_storage 2>/dev/null
        mkdir -p /mnt/disk_storage 2>/dev/null
        mount /dev/${actionDevicePartitionBase}3 /mnt/disk_storage
        mkdir -p /mnt/disk_storage/app-storage
        if [ ${actionCombinedData} -eq 1 ]; then
            mkdir -p /mnt/disk_storage/app-data
        fi
        umount /mnt/disk_storage >> ${logFile}
        echo "storagePartition='${actionDevicePartitionBase}3'"
        echo "# storagePartition(${actionDevicePartitionBase}3)" >> ${logFile}

    # STORAGE without System partition (if addSystemPartition=0 or not set)
    elif [ "${actionType}" = "STORAGE" ] && [ ${actionCreateSystemPartition} -eq 0 ]; then
        echo "# STORAGE partitioning (no boot)" >> ${logFile}
        sfdisk --delete /dev/${actionDevice} >> ${logFile}
        wipefs -a /dev/${actionDevice} >> ${logFile}
        parted /dev/${actionDevice} --script mklabel msdos >> ${logFile}
        parted /dev/${actionDevice} --script mkpart primary ext4 1MB 100% >> ${logFile}
        echo "# .. formating" >> ${logFile}
        wipefs -a /dev/${actionDevicePartitionBase}1 >> ${logFile}
        mkfs -t ext4  /dev/${actionDevicePartitionBase}1 >> ${logFile}
        rm -rf /mnt/disk_storage 2>/dev/null
        mkdir -p /mnt/disk_storage 2>/dev/null
        mount /dev/${actionDevicePartitionBase}1 /mnt/disk_storage
        mkdir -p /mnt/disk_storage/app-storage
        if [ ${actionCombinedData} -eq 1 ]; then
            mkdir -p /mnt/disk_storage/app-data
        fi
        umount /mnt/disk_storage
        echo "storagePartition='${actionDevicePartitionBase}1'"
        echo "# storagePartition(${actionDevicePartitionBase}1)" >> ${logFile}

    # DATA (single drive)
    elif [ "${actionType}" = "DATA" ]; then
        echo "# DATA partitioning" >> ${logFile}
        sfdisk --delete /dev/${actionDevice} 2>/dev/null
        wipefs -a /dev/${actionDevice} 2>/dev/null
        parted /dev/${actionDevice} --script mklabel msdos
        parted /dev/${actionDevice} --script mkpart primary ext4 1MB 100%
        echo "# .. formating" >> ${logFile}
        wipefs -a /dev/${actionDevicePartitionBase}1 2>/dev/null
        mkfs -t ext4  /dev/${actionDevicePartitionBase}1
        rm -rf /mnt/disk_data 2>/dev/null
        mkdir -p /mnt/disk_data 2>/dev/null
        mount /dev/${actionDevicePartitionBase}1 /mnt/disk_data
        mkdir -p /mnt/disk_data/app-data
        umount /mnt/disk_data
    fi

    echo "# OK - ${action} done" >> ${logFile}
    exit 0
fi

###################
# RECOVER / CLEAN
###################

if [ "$action" = "recover" ] || [ "$action" = "clean" ]; then

    echo "STARTED blitz.data.sh ${action} ..." >> ${logFile}

    # check that it is a valid setup type: STORAGE, DATA, SYSTEM
    actionType=$2
    if [ "${actionType}" != "STORAGE" ] && [ "${actionType}" != "DATA" ] && [ "${actionType}" != "SYSTEM" ]; then
        echo "# actionType(${actionType})"
        echo "error='setup type not supported'"
        echo "error='setup type not supported'" >> ${logFile}
        exit 1
    fi

    # check that device is set & exists & not mounted
    actionDevice=$3
    if [ ${#actionDevice} -eq 0 ]; then
        echo "error='missing device'"
        echo "error='missing device'" >> ${logFile}
        exit 1
    fi
    if ! lsblk -no NAME | grep -q "${actionDevice}$"; then
        echo "error='device not found'"
        echo "error='device not found'" >> ${logFile}
        exit 1
    fi
    if findmnt -n -o TARGET "/dev/${actionDevice}" 2>/dev/null; then
        echo "error='device is mounted'"
        echo "error='device is mounted'" >> ${logFile}
        exit 1
    fi

    # check if data should also be combined with storage
    actionCombinedData=$4
    if [ ${#actionCombinedData} -gt 0 ] &&  [ "${actionCombinedData}" != "combinedData=1" ] && [ "${actionCombinedData}" != "0" ] && [ "${actionCombinedData}" != "1" ]; then
        echo "error='combinedData(${actionCombinedData})'" >> ${logFile}
        echo "error='combinedData value not supported'"
        exit 1
    fi
    if [ "${actionCombinedData}" = "combinedData=1" ] || [ "${actionCombinedData}" = "1" ]; then
        actionCombinedData=1
    else
        actionCombinedData=0
    fi

    # check if boot should be from storage
    actionCreateSystemPartition=$5
    if [ ${#actionCreateSystemPartition} -gt 0 ] && [ "${actionCreateSystemPartition}" != "addSystemPartition=0" ] && [ "${actionCreateSystemPartition}" != "addSystemPartition=1" ] && [ "${actionCreateSystemPartition}" != "0" ] && [ "${actionCreateSystemPartition}" != "1" ]; then
        echo "error='addSystemPartition(${actionCreateSystemPartition})'" >> ${logFile}
        echo "error='addSystemPartition value not supported'"
        exit 1
    fi
    if [ "${actionCreateSystemPartition}" = "addSystemPartition=1" ] || [ "${actionCreateSystemPartition}" = "1" ]; then
        actionCreateSystemPartition=1
    else
        actionCreateSystemPartition=0
    fi

    # determine the partition base name
    actionDevicePartitionBase=${actionDevice}
    if [[ "${actionDevice}" =~ ^nvme ]]; then
        actionDevicePartitionBase="${actionDevice}p"
    fi

    # debug info
    echo "# actionType(${actionType})"  >> ${logFile}
    echo "# actionDevice(${actionDevice})" >> ${logFile}
    echo "# actionDevicePartitionBase(${actionDevicePartitionBase})" >> ${logFile}
    echo "# actionCreateSystemPartition(${actionCreateSystemPartition})" >> ${logFile}
    echo "# actionCombinedData(${actionCombinedData})" >> ${logFile}

    if [ "${action}" = "clean" ]; then

        # clean means the devices exist with partitions
        # all data should get deleted only keep blockchain data

        if [ "${actionType}" = "SYSTEM" ]; then
            # system gets full wipe - same as format
            /home/admin/config.scripts/blitz.data.sh setup SYSTEM ${actionDevice}
            exit $?
        fi
        if [ "${actionType}" = "DATA" ]; then
            # data gets full wipe - same as format
            /home/admin/config.scripts/blitz.data.sh setup DATA ${actionDevice}
            exit $?
        fi
        if [ "${actionType}" = "STORAGE" ]; then
            # check first partition for storage
            mkdir -p /mnt/disk_storage 2>/dev/null
            mount /dev/${actionDevicePartitionBase}1 /mnt/disk_storage 2>/dev/null
            # check if /mnt/disk_storage/app-storage exists
            if [ ! -d "/mnt/disk_storage/app-storage" ]; then
                # multi partion layout
                unmount /mnt/disk_storage
                echo "# .. formating boot & system partition" >> ${logFile}
                echo "# - format: boot(/dev/${actionDevicePartitionBase}1)" >> ${logFile}
                wipefs -a /dev/${actionDevicePartitionBase}1 >> ${logFile}
                mkfs.fat -F 32 /dev/${actionDevicePartitionBase}1 >> ${logFile}
                echo "# - format: system(/dev/${actionDevicePartitionBase}2)" >> ${logFile}
                wipefs -a /dev/${actionDevicePartitionBase}2 >> ${logFile}
                mkfs -t ext4  /dev/${actionDevicePartitionBase}2 >> ${logFile}
                echo "# - mount: storage(/dev/${actionDevicePartitionBase}3)" >> ${logFile}
                mount /dev/${actionDevicePartitionBase}3 /mnt/disk_storage >> ${logFile}
                echo "storagePartition='${actionDevicePartitionBase}3'"
                echo "# storagePartition(${actionDevicePartitionBase}3)" >> ${logFile}
                if [ $? -ne 0 ]; then
                    echo "error='failed to mount /dev/${actionDevicePartitionBase}3'" >> ${logFile}
                    echo "error='failed to mount storage partition (1)'"
                    exit 1
                fi
                if [ ! -d "/mnt/disk_storage/app-storage" ]; then
                    echo "error='to /app-storage on /dev/${actionDevicePartitionBase}3'" >> ${logFile}
                    echo "error='failed to mount storage partition (2)'"
                    exit 1
                fi
            else
                echo "storagePartition='${actionDevicePartitionBase}1'"
                echo "# storagePartition(${actionDevicePartitionBase}1)" >> ${logFile}
            fi
            # in both setups /mnt/disk_storage/app-storage should exist
            # delete all data in /mnt/disk_storage except for /mnt/disk_storage/app-storage
            echo "# Cleaning storage partition - preserving app-storage" >> ${logFile}
            # TODO: This is not working yet .. refactor later
            find /mnt/disk_storage -maxdepth 1 -not -name "app-storage" -not -name "." -not -name ".." -exec rm -rf {} \;
            find /mnt/disk_storage/app-storage -maxdepth 1 -not -name "bitcoin" -not -name "." -not -name ".." -exec rm -rf {} \;
            find /mnt/disk_storage/app-storage/bitcoin -maxdepth 1 -not -name "blocks" -name "chainstate" -not -name "." -not -name ".." -exec rm -rf {} \;
            ls -la /mnt/disk_storage >> ${logFile}
            ls -la /mnt/disk_storage/app-storage >> ${logFile}
            ls -la /mnt/disk_storage/app-storage/bitcoin >> ${logFile}

            # Create fresh app-data directory if needed with combined data
            if [ ${actionCombinedData} -eq 1 ]; then
                mkdir -p /mnt/disk_storage/app-data
            fi
            
            # Unmount after cleaning
            umount /mnt/disk_storage
            rm -rf /mnt/disk_storage
        fi
    fi

    if [ "${action}" = "recover" ]; then

        if [ "${actionType}" = "SYSTEM" ]; then
            # system gets full wipe on recover - same as format
            /home/admin/config.scripts/blitz.data.sh setup SYSTEM ${actionDevice}
            exit $?
        fi
        if [ "${actionType}" = "DATA" ]; then
            echo "# .. data just keep as is" >> ${logFile}
        fi
        if [ "${actionType}" = "STORAGE" ]; then
            # get number of partions of device
            numPartitions=$(lsblk -no NAME /dev/${actionDevice} | grep -c "${actionDevicePartitionBase}")
            if [ ${numPartitions} -eq 3 ]; then
                echo "# .. formating boot & system partition" >> ${logFile}
                wipefs -a /dev/${actionDevicePartitionBase}1 >> ${logFile}
                mkfs.fat -F 32 /dev/${actionDevicePartitionBase}1 >> ${logFile}
                wipefs -a /dev/${actionDevicePartitionBase}2 >> ${logFile}
                mkfs -t ext4  /dev/${actionDevicePartitionBase}2 >> ${logFile}
                echo "storagePartition='${actionDevicePartitionBase}3'"
                echo "# storagePartition(${actionDevicePartitionBase}3)" >> ${logFile}
            else
                echo "storagePartition='${actionDevicePartitionBase}1'"
                echo "# storagePartition(${actionDevicePartitionBase}1)" >> ${logFile}
                echo "# .. storage has ${numPartitions} partitions - just keep as is" >> ${logFile}
            fi
        fi
    fi

    echo "# DONE - blitz.data.sh ${action} ${actionType}" >> ${logFile}
    exit 0
fi

###################
# UNABLE BOOT
###################

if [ "$1" = "kill-boot" ]; then
    
    device=$2
    if [ ${#device} -eq 0 ]; then
        echo "error='missing device'"
        exit 1
    fi

    # check that device is valid and not a partition
    isValidDevice=$(lsblk -no NAME 2>/dev/null | grep -c "^${device}")
    if [ ${isValidDevice} -eq 0 ]; then
        echo "error='device not valid'"
        exit 1
    fi

    # detect partition naming scheme
    if [[ "${device}" =~ nvme|mmcblk ]]; then
        separator="p"
    else
        separator=""
    fi

    # find boot partion of device
    bootPartition=""
    partitionNumber=""
    for partNumber in $(parted -s "/dev/${device}" print | grep "^ *[0-9]" | awk '{print $1}'); do
        partitionPath="/dev/${device}${separator}${partNumber}"
        if blkid "${partitionPath}" | grep -q "TYPE=\"vfat\"" && \
           parted "/dev/${device}" print | grep "^ *${partNumber}" | grep -q "boot\|esp\|lba"; then
            bootPartition="${device}${separator}${partNumber}"
            partitionNumber="${partNumber}"
            break
        fi
    done
    
    # fallback to first partition if no boot partition found
    if [ -z "${bootPartition}" ]; then
        bootPartition=$(lsblk -no NAME "/dev/${device}" | grep "^${device}p\?[0-9]" | head -1)
    fi

    # check if boot partition was found
    if [ -z "${bootPartition}" ]; then
        echo "error='boot partition not found'"
        exit 1
    fi

    # killing boot partition (needs to remove to also work on raspberrypi)
    echo "# killing boot partition (${bootPartition})"
    umount "/dev/${bootPartition}" 2>/dev/null
    parted --script "/dev/${device}" rm "${partitionNumber}"
    if [ $? -ne 0 ]; then
        echo "error='failed to remove boot partition'"
        exit 1
    else
        echo "# OK - boot partition removed" >> ${logFile}
        exit 0
    fi

fi

###################
# MIGRATION
###################

if [ "$1" = "migration" ] && [ "$2" = "hdd" ]; then
    action=$3

    if [ "${action}" = "menu-prepare" ]; then
        
        # give user prepare information
        dialog --title " Migrate Data to new HDD/SSD/NVMe " --yes-label "Start Migration" --no-label "Back" --yesno "\nTo migrate your RaspiBlitz data from your old HDD/SSD/NVMe to a new bigger drive, please make sure of the following:\n\n- If you run lightning make sure to have a\n  rescue backup downloaded.\n\n- Have your old drive replaced with the new one\n  or start with complete new hardware.\n\n- Have your old drive connected via USB3\n  where you may need an USB adapter and on\n  RasperryPi4 power old drive seperately.\n\nChoose 'Start Migration' if everything is setup or go back." 20 70
        if [ $? -gt 0 ]; then
            # user canceled
            exit 1
        fi

        # check if a bigger replacement drive exists
        source <(/home/admin/config.scripts/blitz.data.sh status)
        if [ ${#biggerDevice} -eq 0 ]; then
            dialog --msgbox "\nNo old drive with RaspiBlitz data found.\n\nMaybe you need to reset new bigger drive first:\nDisconnect old drive and use on terminal 'reset'.\nThen 'restart' and try again." 11 60
            exit 1
        fi

        # confirm selection
        storageDeviceNameTrunc="${storageDeviceName:0:35}"
        biggerDeviceNameTrunc="${biggerDeviceName:0:35}"
        dialog --title " Migrate Data to new HDD/SSD/NVMe " --yes-label "Continue" --no-label "Abort" --yesno "\nYou are about to migrate your RaspiBlitz data from:\n\n- ${storageSizeGB}GB ${storageDeviceNameTrunc} \n\nto:\n\n- ${biggerSizeGB}GB ${biggerDeviceNameTrunc}\n\nAll data on target drive will be deleted! Is this correct?" 17 70
        if [ $? -gt 0 ]; then
            # user canceled
            exit 1
        fi

        # set migration info to cache
        /home/admin/_cache.sh set hddMigrateDeviceFrom "${storageDevice}"
        /home/admin/_cache.sh set hddMigrateDeviceTo "${biggerDevice}"  
        /home/admin/_cache.sh set system_setup_storageBlockchainGB "0"
        /home/admin/_cache.sh set system_setup_askSystemCopy "${scenarioSystemCopy}"  

        # return 0 to indicate success and let calling script finish
        exit 0
    fi

    if [ "${action}" = "run" ]; then

        echo "### MIGRATING HDD"
        echo "# see /var/cache/raspiblitz/temp/progress.txt for progress"

        # get source hdd of migration
        hddMigrateDeviceFrom=$4
        echo "# hddMigrateDeviceFrom(${hddMigrateDeviceFrom})"
        if [ ${#hddMigrateDeviceFrom} -eq 0 ]; then
            echo "error='missing parameter'"
            exit 1
        fi

        # set source hdd of migration in cache & get latest disk info
        /home/admin/_cache.sh set hddMigrateDeviceFrom "${hddMigrateDeviceFrom}"
        source <(/home/admin/config.scripts/blitz.data.sh status -inspect)

        # check that target partion is formatted
        if [ "${storagePartition}" = "" ]; then
            echo "error='storage drive not formatted'"
            exit 1
        fi

        # check that target partion is formatted
        if [ "${combinedDataStorage}" = "1" ]; then
            dataPartition="${storagePartition}"
        fi
        if [ "${dataPartition}" = "" ]; then
            echo "error='data drive not formatted'"
            exit 1
        fi

        # get the biggest partition of the source hdd (thats the data or storage partition with data)
        sourcePartition=$(lsblk -no NAME,SIZE,TYPE | grep "${hddMigrateDeviceFrom}" | grep "part" | sort -k2 -h | tail -1 | awk '{print $1}' | sed 's/[^[:alnum:]]//g')
        if [ ${#sourcePartition} -eq 0 ]; then
            echo "error='no source partition found'"
            exit 1
        fi

        # get UUID of source partition
        sourceUUID=$(lsblk -n -o UUID "/dev/${sourcePartition}")
        if [ ${#sourceUUID} -eq 0 ]; then
            echo "error='no source partition UUID found'"
            exit 1
        fi

        # check that partition is not mounted
        if findmnt -n -o TARGET "/dev/${sourcePartition}" 2>/dev/null; then
            echo "# sourcePartition(${sourcePartition})"
            echo "# make sure the partition is not mounted" 
            echo "# sudo umount /dev/${sourcePartition}"
            echo "error='source partition is mounted'"
            exit 1
        fi

        # check partition data is not mounted
        if findmnt -n -o TARGET "/dev/${dataPartition}" 2>/dev/null; then
            echo "# dataPartition(${dataPartition})"
            echo "# make sure the partition is not mounted" 
            echo "# sudo umount /dev/${dataPartition}"
            echo "error='data partition is mounted'"
            exit 1
        fi

        # check storage is not mounted
        if findmnt -n -o TARGET "/dev/${storagePartition}" 2>/dev/null; then
            echo "# storagePartition(${storagePartition})"
            echo "# make sure the partition is not mounted" 
            echo "# sudo umount /dev/${storagePartition}"
            echo "error='storage partition is mounted'"
            exit 1
        fi

        # mount source partition
        mkdir -p /mnt/migrate_source 2>/dev/null
        echo "# mount /mnt/migrate_source -> ${sourcePartition} uuid(${sourceUUID})..."
        mount -U "${sourceUUID}" /mnt/migrate_source
        if ! findmnt -n -o TARGET "/mnt/migrate_source" 2>/dev/null; then
            echo "error='source partition not mounted uuid(${sourceUUID})'"
            exit 1
        fi

        ##############
        # SYNC STORAGE

        # mount target partition storage
        mkdir -p /mnt/migrate_storage 2>/dev/null
        echo "# mount /mnt/migrate_storage -> ${storagePartition} ..."
        mount "/dev/${storagePartition}" /mnt/migrate_storage
        if ! findmnt -n -o TARGET "/mnt/migrate_storage" 2>/dev/null; then
            echo "error='storage partition not mounted'"
            exit 1
        fi

        echo "# rsync storage from source to target ..."
        echo "chain" > /var/cache/raspiblitz/temp/progress.txt
        mkdir -p /mnt/migrate_storage/app-storage 2>/dev/null
        rsync -ah --info=progress2 /mnt/migrate_source/app-storage/ /mnt/migrate_storage/app-storage/ 2>&1 | stdbuf -oL tr '\r' '\n' | grep --line-buffered '%' | stdbuf -oL sed -n 's/.* \([0-9]\+\)% .*/\1%/p' >> /var/cache/raspiblitz/temp/progress.txt
        if [ $? -ne 0 ]; then
            echo "error='failed to rsync storage'"
            exit 1
        fi

        # old layout: bitcoin directory is still outside of app-storage
        if [ -d /mnt/migrate_source/bitcoin ] && [ ! -L /mnt/migrate_source/bitcoin ]; then
            echo "# rsync bitcoin from source to target ..."
            mkdir -p /mnt/migrate_storage/app-storage/bitcoin 2>/dev/null
            echo "bitcoin" > /var/cache/raspiblitz/temp/progress.txt
            rsync -ah --info=progress2 /mnt/migrate_source/bitcoin/ /mnt/migrate_storage/app-storage/bitcoin/ 2>&1 | stdbuf -oL tr '\r' '\n' | grep --line-buffered '%' | stdbuf -oL sed -n 's/.* \([0-9]\+\)% .*/\1%/p' >> /var/cache/raspiblitz/temp/progress.txt
            if [ $? -ne 0 ]; then
                echo "error='failed to rsync bitcoin'"
                exit 1
            fi
        fi

        # add flag to indicate that data was migrated
        touch /mnt/migrate_storage/app-storage/.migrated
        chmod 777 /mnt/migrate_storage/app-storage/.migrated

        # unmount storage partition
        umount /mnt/migrate_storage
        if [ $? -ne 0 ]; then
            echo "error='failed to unmount storage partition'"
            exit 1
        fi

        ##############
        # SYNC DATA

        # mount target partition data
        mkdir -p /mnt/migrate_data 2>/dev/null
        echo "# mount /mnt/migrate_data -> ${dataPartition} ..."
        mount "/dev/${dataPartition}" /mnt/migrate_data
        if ! findmnt -n -o TARGET "/mnt/migrate_data" 2>/dev/null; then
            echo "error='data partition not mounted'"
            exit 1
        fi

        echo "# rsync data from source to target ..."
        mkdir -p /mnt/migrate_data/app-data 2>/dev/null
        echo "data" > /var/cache/raspiblitz/temp/progress.txt
        rsync -ah --info=progress2 /mnt/migrate_source/app-data/ /mnt/migrate_data/app-data/ 2>&1 | stdbuf -oL tr '\r' '\n' | grep --line-buffered '%' | stdbuf -oL sed -n 's/.* \([0-9]\+\)% .*/\1%/p' >> /var/cache/raspiblitz/temp/progress.txt
        if [ $? -ne 0 ]; then
            echo "error='failed to rsync data'"
            exit 1
        fi

        # old layout: lnd directory is still outside of app-data
        if [ -d /mnt/migrate_source/lnd ] && [ ! -L /mnt/migrate_source/lnd ]; then
            echo "# rsync lnd from source to target ..."
            mkdir -p /mnt/migrate_data/app-data/lnd 2>/dev/null
            echo "lnd" > /var/cache/raspiblitz/temp/progress.txt
            rsync -ah --info=progress2 /mnt/migrate_source/lnd/ /mnt/migrate_data/app-data/lnd/ 2>&1 | stdbuf -oL tr '\r' '\n' | grep --line-buffered '%' | stdbuf -oL sed -n 's/.* \([0-9]\+\)% .*/\1%/p' >> /var/cache/raspiblitz/temp/progress.txt
            if [ $? -ne 0 ]; then
                echo "error='failed to rsync lnd'"
                exit 1
            fi
        else
            echo "# no old lnd directory found"
        fi

        # old layout: tor directory is still outside of app-data
        if [ -d /mnt/migrate_source/tor ] && [ ! -L /mnt/migrate_source/tor ]; then
            echo "# rsync tor from source to target ..."
            rm -f /mnt/migrate_source/tor/*.log*
            mkdir -p /mnt/migrate_data/app-data/tor 2>/dev/null
            echo "tor" > /var/cache/raspiblitz/temp/progress.txt
            rsync -ah --info=progress2 /mnt/migrate_source/tor/ /mnt/migrate_data/app-data/tor/ 2>&1 | stdbuf -oL tr '\r' '\n' | grep --line-buffered '%' | stdbuf -oL sed -n 's/.* \([0-9]\+\)% .*/\1%/p' >> /var/cache/raspiblitz/temp/progress.txt
            if [ $? -ne 0 ]; then
                echo "error='failed to rsync tor'"
                exit 1
            fi
        else
            echo "# no old tor directory found"
        fi

        # old layout: raspiblitz.conf file is still outside of app-data
        if [ -f /mnt/migrate_source/raspiblitz.conf ] && [ ! -L /mnt/migrate_source/raspiblitz.conf ]; then
            echo "# copy raspiblitz.conf from source to target ..."
            mkdir -p /mnt/migrate_data/app-data 2>/dev/null
            cp /mnt/migrate_source/raspiblitz.conf /mnt/migrate_data/app-data/raspiblitz.conf
            cp /mnt/migrate_source/.tmux.conf.local /mnt/migrate_data/app-data/.tmux.conf.local 2>/dev/null
            if [ $? -ne 0 ]; then
                echo "error='failed to rsync raspiblitz.conf'"
                exit 1
            fi
        else
            echo "# no old raspiblitz.conf file found"
        fi

        # unmount data partition
        umount /mnt/migrate_data
        if [ $? -ne 0 ]; then
            echo "error='failed to unmount data partition'"
            exit 1
        fi

        # unmount source device
        umount /mnt/migrate_source
        if [ $? -ne 0 ]; then
            echo "error='failed to unmount source partition'"
            exit 1
        fi

        # clean up
        rm -rf /mnt/migrate_source
        rm -rf /mnt/migrate_storage
        rm -rf /mnt/migrate_data
        rm -rf /var/cache/raspiblitz/temp/progress.txt

        exit 0
    fi

    echo "error='missing parameter'"
    exit 1
fi

if [ "$1" = "migration" ]; then

    echo "# blitz.data.sh migration" >> ${logFile}

    # check if all needed parameters are set
    if [ $# -lt 3 ]; then
        echo "error='missing parameters'"
        exit 1
    fi

    # check that partition exists
    if ! lsblk -no NAME | grep -q "${dataPartition}$"; then
        echo "# dataPartition(${dataPartition})"
        echo "error='partition not found'"
        exit 1
    fi

    # check that partition is not mounted
    if findmnt -n -o TARGET "/dev/${dataPartition}" 2>/dev/null; then
        echo "# dataPartition(${dataPartition})"
        echo "# make sure the partition is not mounted" 
        echo "error='partition is mounted'"
        exit 1
    fi

    onlyTestIfMigratioinPossible=0
    if [ "$4" = "-test" ]; then
        echo "# ... only testing if migration is possible"
        onlyTestIfMigratioinPossible=1
    fi

    mountPath="/mnt/temp"
    mkdir -p "${mountPath}" 2>/dev/null
    if ! mount "/dev/${name}" "${mountPath}"; then
        echo "error='cannot mount partition'"
        exit 1
    fi

    echo "error='TODO migration'"

    #####################
    # MIGRATION: UMBREL
    # if [ "$2" = "umbrel" ]; then
    #   # TODO: Detect and output Umbrel Version
    #   if [ ${onlyTestIfMigratioinPossible} -eq 1 ]; then
    #       # provide information about the versions
    #       btcVersion=$(grep "lncm/bitcoind" ${mountPath}/umbrel/app-data/bitcoin/docker-compose.yml 2>/dev/null | sed 's/.*bitcoind://' | sed 's/@.*//')
    #       clnVersion=$(grep "lncm/clightning" ${mountPath}/umbrel/app-data/core-lightning/docker-compose.yml 2>/dev/null | sed 's/.*clightning://' | sed 's/@.*//')
    #       lndVersion=$(grep "lightninglabs/lnd" ${mountPath}/umbrel/app-data/lightning/docker-compose.yml 2>/dev/null | sed 's/.*lnd://' | sed 's/@.*//')
    #       echo "btcVersion='${btcVersion}'"
    #       echo "clnVersion='${clnVersion}'"
    #       echo "lndVersion='${lndVersion}'"
    #   else
    #       echo "error='TODO migration'"
    #   fi

    #####################
    # MIGRATION: CITADEL
    #elif [ "$2" = "citadel" ]; then
    #   # TODO: Detect and output Citadel Version
    #   if [ ${onlyTestIfMigratioinPossible} -eq 1 ]; then
    #       # provide information about the versions
    #       lndVersion=$(grep "lightninglabs/lnd" ${mountPath}/citadel/docker-compose.yml 2>/dev/null | sed 's/.*lnd://' | sed 's/@.*//')
    #       echo "lndVersion='${lndVersion}'"
    #   else
    #       echo "error='TODO migration'"
    #   fi

    #####################
    # MIGRATION: MYNODE
    #elif [ "$2" = "mynode" ]; then
    #   echo "error='TODO'"
    #else
    #   echo "error='migration type not supported'"
    #fi

    # unmount partition
    umount ${mountPath}
    rm -r ${mountPath}
    exit 0
fi

#############
# UASP-fix
#############

if [ "$1" = "reset" ]; then
    source <(/home/admin/config.scripts/blitz.data.sh status)
    if [ "${storageDevice}" = "" ]; then
        echo "error='no storage device found'"
        exit 1
    fi
    # ask user to confirm
    echo "# WARNING: This will delete all data on ${storageDevice}"
    echo "# Are you really sure? (y/n)"
    read -r answer
    if [ "${answer}" != "y" ]; then
        echo "# User canceled"
        exit 1
    fi
    echo "# Are you REALLY REALLY sure? (Y/N)"
    read -r answer
    if [ "${answer}" != "Y" ]; then
        echo "# User canceled"
        exit 1
    fi
    echo "# Deleting all partitions on ${storageDevice} ..."
    apt-get install -y gdisk
    sgdisk --zap-all /dev/${storageDevice}
    echo "# DONE"
    exit 0
fi

#############
# UASP-fix
#############

if [ "$1" = "uasp-fix" ]; then

    echo "# blitz.data.sh uasp-fix"

    # optional: parameter
    onlyInfo=0
    if [ "$2" = "-info" ]; then
        echo
        onlyInfo=1
    fi

    # check is running on RaspiOS
    if [ "${computerType}" != "raspberrypi" ]; then
        echo "error='only on RaspberryPi'"
        exit 1
    fi

    # HDD Adapter UASP support --> https://www.pragmaticlinux.com/2021/03/fix-for-getting-your-ssd-working-via-usb-3-on-your-raspberry-pi/
    hddAdapter=$(lsusb | grep "SATA" | head -1 | cut -d " " -f6)
    if [ "${hddAdapter}" == "" ]; then
      hddAdapter=$(lsusb | grep "GC Protronics" | head -1 | cut -d " " -f6)
    fi
    if [ "${hddAdapter}" == "" ]; then
      hddAdapter=$(lsusb | grep "ASMedia Technology" | head -1 | cut -d " " -f6)
    fi

    # check if HDD ADAPTER is on UASP WHITELIST (tested devices)
    hddAdapterUASP=0
    if [ "${hddAdapter}" == "174c:55aa" ]; then
      # UGREEN 2.5" External USB 3.0 Hard Disk Case with UASP support
      hddAdapterUASP=1
    fi
    if [ "${hddAdapter}" == "174c:1153" ]; then
      # UGREEN 2.5" External USB 3.0 Hard Disk Case with UASP support, 2021+ version
      hddAdapterUASP=1
    fi
    if [ "${hddAdapter}" == "0825:0001" ] || [ "${hddAdapter}" == "174c:0825" ]; then
      # SupTronics 2.5" SATA HDD Shield X825 v1.5
      hddAdapterUASP=1
    fi
    if [ "${hddAdapter}" == "2109:0715" ]; then
      # ICY BOX IB-247-C31 Type-C Enclosure for 2.5inch SATA Drives
      hddAdapterUASP=1
    fi
    if [ "${hddAdapter}" == "174c:235c" ]; then
      # Cable Matters USB 3.1 Type-C Gen2 External SATA SSD Enclosure
      hddAdapterUASP=1
    fi
    if [ -f "/boot/firmware/uasp.force" ]; then
      # or when user forces UASP by flag file on sd card
      hddAdapterUASP=1
    fi

    if [ ${onlyInfo} -eq 1 ]; then
        echo "# the ID of the HDD Adapter:"
        echo "hddAdapter='${hddAdapter}'"
        echo "# if HDD Adapter supports UASP:"
        echo "hddAdapterUASP='${hddAdapterUASP}'"
        exit 0
    fi

    # https://www.pragmaticlinux.com/2021/03/fix-for-getting-your-ssd-working-via-usb-3-on-your-raspberry-pi/
    cmdlineFileExists=$(ls /boot/firmware/cmdline.txt 2>/dev/null | grep -c "cmdline.txt")
    if [ ${cmdlineFileExists} -eq 0 ]; then
        echo "error='no /boot/firmware/cmdline.txt'"
        exit 1
    elif [ ${#hddAdapter} -eq 0 ]; then
        echo "# Skipping UASP deactivation - no USB HDD Adapter found"
        echo "neededReboot=0"
    elif [ ${hddAdapterUASP} -eq 1 ]; then
        echo "# Skipping UASP deactivation - USB HDD Adapter is on UASP WHITELIST"
        echo "neededReboot=0"
    else
        echo "# UASP deactivation - because USB HDD Adapter is not on UASP WHITELIST ..."
        usbQuirkDone=$(cat /boot/firmware/cmdline.txt | grep -c "usb-storage.quirks=${hddAdapter}:u")
        if [ ${usbQuirkDone} -eq 0 ]; then
            # remove any old usb-storage.quirks
            sed -i "s/usb-storage.quirks=[^ ]* //g" /boot/firmware/cmdline.txt 2>/dev/null
            # add new usb-storage.quirks
            sed -i "s/^/usb-storage.quirks=${hddAdapter}:u /" /boot/firmware/cmdline.txt
            # go into reboot to activate new setting
            echo "# DONE deactivating UASP for ${hddAdapter}"
            echo "neededReboot=1"
        else
            echo "# Already UASP deactivated for ${hddAdapter}"
            echo "neededReboot=0"
        fi
    fi
    exit 0
fi

#############
# Expand
#############

if [ "$1" = "expand" ]; then

    echo "# blitz.data.sh expand"

    # get partition name
    partitionName=$2
    if [ ${#partitionName} -eq 0 ]; then
        echo "error='missing partition name'"
        exit 1
    fi

    # spereate device name and partition number
    partitionNumber=$(echo "${partitionName}" | grep -o '[0-9]*$')
    deviceName=$(echo "${partitionName}" | sed "s/${partitionNumber}$//")
    if [ ${#deviceName} -eq 0 ]; then
        echo "error='missing device name'"
        exit 1
    fi
    if [ ${#partitionNumber} -eq 0 ]; then
        echo "error='missing partition number'"
        exit 1
    fi

    echo "# deviceName(${deviceName})"
    echo "# partitionNumber(${partitionNumber})"

    # read partition table
    partprobe /dev/${deviceName}
    if [ $? -ne 0 ]; then
        echo "error='failed to read partition table'"
        exit 1
    fi

    # grow partition
    apt install -y --no-install-recommends cloud-guest-utils
    growpart /dev/${deviceName} ${partitionNumber}
    if [ $? -ne 0 ]; then
        echo "error='failed to grow partition'"
        exit 1
    fi

    # resize filesystem
    apt-get install -y --no-install-recommends e2fsprogs
    resize2fs /dev/${partitionName}
    if [ $? -ne 0 ]; then
        echo "error='failed to resize filesystem'"
        exit 1
    fi

    echo "# DONE check: df -h"
    exit 0
fi