#!/bin/bash

whiptail --title " BOOT FROM SSD/NVME " --yes-button "NO" --no-button "YES - BOOT SSD/NVME" --yesno "Your system allows to BOOT FROM SSD/NVME - which provides better performance but is still experimental.\n\nDo you want to copy RaspiBlitz system to SSD/NVME and boot from it? (optional)" 11 65

if [ "$?" == "0" ]; then
    echo "# 1 --> No"
    exit 1
else
    echo "# 0 --> Yes"
    exit 0
fi
