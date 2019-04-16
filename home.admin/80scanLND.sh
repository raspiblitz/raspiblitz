#!/bin/bash

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

source <(sudo /home/admin/config.scripts/blitz.statusscan.sh)

height=6
width=44

#infoStr=" Waiting for Blockchain Sync\n Progress: ${syncProgress}% \n Please wait - this can take some time.\n ssh admin@${localIP}\n Password A"
infoStr=" Lightning Scanning Blockchain\n Progress: ${scanProgress}%\n Please wait - this can take some time\n ssh admin@${localIP}\n Password A"

# display progress to user
sleep 3
temp=$(echo "scale=1; $(cat /sys/class/thermal/thermal_zone0/temp)/1000" | bc)
dialog --title " ${network} / ${chain} " --backtitle "RaspiBlitz (${hostname}) CPU: ${temp}°C" --infobox "${infoStr}" ${height} ${width}