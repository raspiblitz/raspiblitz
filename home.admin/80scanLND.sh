#!/bin/bash

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

source <(sudo /home/admin/config.scripts/blitz.statusscan.sh)

height=6
width=52

#infoStr=" Waiting for Blockchain Sync\n Progress: ${syncProgress}% \n Please wait - this can take some time.\n ssh admin@${localIP} -> Password A"
infoStr=" Node is Syncing\n Blockchain Progress : ${scanProgress}%\n Lightning Progress  : ${scanProgress}%\n Please wait - this can take some time\n ssh admin@${localIP} ->Password A"

# display progress to user
temp=$(echo "scale=1; $(cat /sys/class/thermal/thermal_zone0/temp)/1000" | bc)
dialog --title " ${network} / ${chain} " --backtitle "RaspiBlitz (${hostname}) CPU: ${temp}°C" --infobox "${infoStr}" ${height} ${width}