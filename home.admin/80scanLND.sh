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
  title="Blockchain Warning"
  infoStr=" The ${network}d service is not running.\n Login for more details:"
  if [ "$USER" == "admin" ]; then
    echo ""
    echo "*********************************"
    echo "* The ${network}d service is not running."
    echo "*********************************"
    echo ${bitcoinError}
    echo "Use following command to debug:"
    echo "/home/admin/XXdebugLogs.sh"
    echo ""
    exit 1
  fi

elif [ ${lndActive} -eq 0 ]; then

  ####################
  # On LND Error
  ####################

  height=5
  width=42
  title="Lightning Warning"
  infoStr=" The lnd service is not running.\n Login for more details:"
  if [ "$USER" == "admin" ]; then
    echo ""
    echo "*********************************"
    echo "* The lnd service is not running."
    echo "*********************************"
    echo ${lndError}
    echo "Use following command to debug:"
    echo "/home/admin/XXdebugLogs.sh"
    echo ""
    exit 1
  fi

else

  ####################
  # Sync Progress
  ####################

  # basic dialog info
  height=6
  width=42
  title="Node is Syncing (${scriptRuntime})"

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