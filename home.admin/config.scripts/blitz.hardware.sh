#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "Hardware Tool Script"
 echo "blitz.hardware.sh status"
 echo "blitz.hardware.sh check [smart [disk] | select]"
 exit 1
fi

# A quick, read-only inventory for bootstrap, support reports and the menus.
if [ "$1" = "check" ]; then
    echo "Block devices (name, type, transport, size):"
    lsblk --nodeps --exclude 7 --output NAME,TYPE,TRAN,SIZE || exit 1
    if command -v lsusb >/dev/null; then
        echo "USB topology and negotiated link speeds:"
        lsusb -t
    fi
    if [[ "${2:-}" = smart || "${2:-}" = select ]]; then
        echo "Drive health (read-only SMART summary):"
        if ! command -v smartctl >/dev/null; then
            echo "smartctl is unavailable."
            exit 1
        fi
        inventory=$(lsblk --nodeps --noheadings --raw --output NAME,TYPE,TRAN) || exit 1
        disks=()
        while read -r name type transport; do
            [[ "$type" = disk && "$transport" =~ ^(sata|ata|sas|usb|nvme)$ ]] || continue
            disks+=("$name" "$transport")
        done <<< "$inventory"
        if [ "${#disks[@]}" -eq 0 ]; then
            echo "No SATA, SAS, USB or NVMe disks reported by lsblk."
            exit 1
        fi
        selected=${3:-ALL}
        if [ "$2" = select ]; then
            if ! command -v whiptail >/dev/null; then
                echo "whiptail is unavailable; use 'check smart' from the command line." >&2
                exit 1
            fi
            selected=$(whiptail --title "Drive health" --menu "Select a disk to read its SMART data" 16 65 8 \
                ALL "All listed disks" "${disks[@]}" 3>&1 1>&2 2>&3) || exit 0
        fi
        health_status=0
        found=0
        for ((i=0; i<${#disks[@]}; i+=2)); do
            name=${disks[i]}
            [[ "$selected" = ALL || "$selected" = "$name" ]] || continue
            found=1
            echo "/dev/$name"
            python3 "$(dirname "$0")/blitz.drive-health.py" "/dev/$name" "${disks[i+1]}" || health_status=1
        done
        if [ "$found" = 0 ]; then echo "Disk missing from inventory."; exit 1; fi
        exit "$health_status"
    fi
    exit 0
fi

########################
# GATHER HARDWARE INFO
#######################

# detect info about the computer
computerType="pc"
computerVersion=1

# detect generic RaspberryPi
isRaspberryPi=$(cat /proc/device-tree/model 2>/dev/null | grep -c "Raspberry Pi")
if [ ${isRaspberryPi} -gt 0 ]; then
    computerType="raspberrypi"
    computerVersion=0 #unknown
fi

# detect RaspberryPi 3
isRaspberryPi3=$(cat /proc/device-tree/model 2>/dev/null | grep -c "Raspberry Pi 3")
if [ "${isRaspberryPi3}" == "1" ]; then
    computerType="raspberrypi"
    computerVersion=3
fi

# detect RaspberryPi 4
isRaspberryPi4=$(cat /proc/device-tree/model 2>/dev/null | grep -c "Raspberry Pi 4")
if [ ${isRaspberryPi4} -gt 0 ]; then
    computerType="raspberrypi"
    computerVersion=4
fi

# detect RaspberryPi 5
isRaspberryPi5=$(cat /proc/device-tree/model 2>/dev/null | grep -c "Raspberry Pi 5")
if [ "${isRaspberryPi5}" == "1" ]; then
    computerType="raspberrypi"
    computerVersion=5
fi

# detect VM
isVM=$(grep -c 'hypervisor' /proc/cpuinfo)
if [ ${isVM} -gt 0 ]; then
    computerType="vm"
fi

# detect NVMe drive
gotNVMe=$(lsblk -o TRAN | grep -c nvme)
if [ ${gotNVMe} -gt 0 ]; then
    gotNVMe=1
fi

# detect USB drive
gotUSB=$(lsblk -o TRAN | grep -c usb)
if [ ${gotUSB} -gt 0 ]; then
    gotUSB=1
fi

# get how many RAM (in MB)
ramMB=$(awk '/MemTotal/ {printf( "%d\n", $2 / 1024 )}' /proc/meminfo)

# get how many RAM (in GB - approx)
ramGB=$(awk '/MemTotal/ {printf( "%d\n", $2 / 950000 )}' /proc/meminfo)

########################
# OUTPUT HARDWARE INFO
#######################

if [ "$1" = "status" ]; then
    echo "computerType='${computerType}'"
    echo "computerVersion=${computerVersion}"
    echo "ramMB=${ramMB}"
    echo "ramGB=${ramGB}"
    echo "gotNVMe=${gotNVMe}"
    echo "gotUSB=${gotUSB}"
fi
