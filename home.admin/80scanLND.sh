#!/bin/bash

source /home/admin/_version.info
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

source <(sudo /home/admin/config.scripts/blitz.statusscan.sh)

adminStr="ssh admin@${localIP} ->Password A"
if [ "$USER" == "admin" ]; then
  adminStr="Use CTRL+c to EXIT to Terminal"
fi

if [ ${bitcoinActive} -eq 0 ]; then

  ####################
  # On Bitcoin Error
  ####################

  height=6
  width=42
  title="Blockchain Error"
  infoStr="The ${network}d service is not running."
  if [ "$USER" == "admin" ]; then
    infoStr="${infoStr}\n${bitcoinError}"
  fi

elif [ ${lndActive} -eq 0 ]; then

  ####################
  # On LND Error
  ####################

  height=6
  width=42
  title="Lightning Error"
  infoStr="The lnd service is not running."
  if [ "$USER" == "admin" ]; then
    infoStr="${infoStr}\n${lndError}"
  fi

else

  ####################
  # Sync Progress
  ####################

  # basic dialog info
  height=6
  width=42
  title="Node is Syncing"

  # format progress values
  if [ ${#syncProgress} -lt 6 ]; then
    syncProgress=" ${syncProgress}"
  fi
  if [ ${#scanProgress} -lt 6 ]; then
    scanProgress=" ${scanProgress}"
  fi

  infoStr=" Blockchain Progress : ${syncProgress} %\n Lightning Progress  : ${scanProgress} %\n Please wait - this can take some time"

fi

# display info to user
dialog --title " ${title} " --backtitle "RaspiBlitz ${codeVersion} ${hostname} / ${network} / ${chain} / ${tempCelsius}°C" --infobox "${infoStr}\n ${adminStr}" ${height} ${width}