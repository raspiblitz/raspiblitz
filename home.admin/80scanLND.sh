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

  height=5
  width=42
  title="Blockchain Info"
  if [ ${uptime} -gt 300 ]; then
    infoStr=" The ${network}d service is not running.\n Login for more details:"
    if [ "$USER" == "admin" ]; then
      echo ""
      echo "*****************************************"
      echo "* The ${network}d service is not running."
      echo "*****************************************"
      echo "If you just started some config/setup, this might be OK."
      echo
      if [ ${#bitcoinError} -gt 0 ]; then
        echo "More Error Detail:"
        echo ${bitcoinError}
        echo
      fi
      echo "-> To try to start ${network}d run:"
      echo "sudo systemctl start ${network}d"
      echo "-> To force Main Menu run:"
      echo "/home/admin/00mainmenu.sh"
      echo "-> Use following command to debug:"
      echo "/home/admin/XXdebugLogs.sh"
      echo ""
      exit 1
    fi
  else
    infoStr=" The ${network}d service is starting.\n Login for more details:"
    if [ "$USER" == "admin" ]; then
      infoStr=" The ${network}d service is starting.\n Please wait up to 5min ..."
    fi
  fi

elif [ ${lndActive} -eq 0 ]; then

  ####################
  # On LND Error
  ####################

  height=5
  width=42
  title="Lightning Info"
  if [ ${uptime} -gt 300 ]; then
    infoStr=" The LND service is not running.\n Login for more details:"
    if [ "$USER" == "admin" ]; then
      echo ""
      echo "*********************************"
      echo "* The LND service is not running."
      echo "*********************************"
      echo "If you just started some config/setup, this might be OK."
      echo
      if [ ${#lndError} -gt 0 ]; then
        echo "More Error Detail:"
        echo ${lndError}
        echo
      fi
      echo "-> To try to start LND run:"
      echo "sudo systemctl start lnd"
      echo "-> To force Main Menu run:"
      echo "/home/admin/00mainmenu.sh"
      echo "-> Use following command to debug:"
      echo "/home/admin/XXdebugLogs.sh"
      echo ""
      exit 1
    fi
  else
    infoStr=" The LND service is starting.\n Login for more details:"
    if [ "$USER" == "admin" ]; then
      infoStr=" The LND service is starting.\n Please wait up to 5min ..."
    fi
  fi

else

  ####################
  # Sync Progress
  ####################

  # basic dialog info
  height=6
  width=42
  title="Node is Syncing (${scriptRuntime})"

  # formatting progress values
  if [ ${#syncProgress} -eq 0 ]; then
    syncProgress="waiting"
  elif [ ${#syncProgress} -lt 6 ]; then
    syncProgress=" ${syncProgress} %"
  else
    syncProgress="${syncProgress} %"
  fi
  if [ ${#scanProgress} -eq 0 ]; then
    scanProgress="waiting"
  elif [ ${#scanProgress} -lt 6 ]; then
    scanProgress=" ${scanProgress} %"
  else
    scanProgress="${scanProgress} %"
  fi

  # setting info string
  infoStr=" Blockchain Progress : ${syncProgress}\n Lightning Progress  : ${scanProgress}\n Please wait - this can take some time"

fi

# display info to user
dialog --title " ${title} " --backtitle "RaspiBlitz ${codeVersion} ${hostname} / ${network} / ${chain} / ${tempCelsius}°C" --infobox "${infoStr}\n ${adminStr}" ${height} ${width}