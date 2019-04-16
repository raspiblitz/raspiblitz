#!/bin/bash

source /home/admin/_version.info
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

source <(sudo /home/admin/config.scripts/blitz.statusscan.sh)

height=6
width=42

#infoStr=" Waiting for Blockchain Sync\n Progress: ${syncProgress}% \n Please wait - this can take some time.\n ssh admin@${localIP} -> Password A"
title="Node is Syncing"
if [ ${#syncProgress} -lt 6 ]; then
  syncProgress=" ${syncProgress}"
fi
if [ ${#scanProgress} -lt 6 ]; then
  scanProgress=" ${scanProgress}"
fi

infoStr=" Blockchain Progress : ${syncProgress} %\n Lightning Progress  : ${scanProgress} %\n Please wait - this can take some time"
adminStr="ssh admin@${localIP} ->Password A"
if [ "$USER" == "admin" ]; then
  adminStr="Use CTRL+c to EXIT to Terminal"
fi

# display progress to user
dialog --title " ${title} " --backtitle "RaspiBlitz ${codeVersion} ${hostname} / ${network} / ${chain} / ${tempCelsius}°C" --infobox "${infoStr}\n ${adminStr}" ${height} ${width}