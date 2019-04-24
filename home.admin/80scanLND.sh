#!/bin/bash

source /home/admin/_version.info
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

# all system/service info gets detected by blitz.statusscan.sh
source <(sudo /home/admin/config.scripts/blitz.statusscan.sh)

# set follow up info different for LCD and ADMIN
adminStr="ssh admin@${localIP} ->Password A"
if [ "$USER" == "admin" ]; then
  adminStr="Use CTRL+c to EXIT to Terminal"
fi

# bitcoin errors always first
if [ ${bitcoinActive} -eq 0 ] || [ ${#bitcoinErrorFull} -gt 0 ] || [ "${1}" == "blockchain-error" ]; then

  ####################
  # On Bitcoin Error
  ####################

  height=5
  width=43
  title="Blockchain Info"
  if [ ${uptime} -gt 600 ] || [ "${1}" == "blockchain-error" ]; then
    infoStr=" The ${network}d service is not running.\n Login for more details:"
    if [ "$USER" == "admin" ]; then
      clear
      echo ""
      echo "*****************************************"
      echo "* The ${network}d service is not running."
      echo "*****************************************"
      echo "If you just started some config/setup, this might be OK."
      echo
      if [ ${startcountBlockchain} -gt 1 ]; then
        echo "${startcountBlockchain} RESTARTS DETECTED - ${network}d might be in a error loop"
        cat /home/admin/systemd.blockchain.log | grep "ERROR" | tail -n -2
        echo
      fi
      if [ ${#bitcoinErrorFull} -gt 0 ]; then
        echo "More Error Detail:"
        echo ${bitcoinErrorFull}
        echo
      fi
      echo "-> Use following command to debug: /home/admin/XXdebugLogs.sh"
      echo "-> To force Main Menu run: /home/admin/00mainMenu.sh"
      echo "-> To try restart: sudo shutdown -r now"
      echo ""
    fi
  else
    height=6
    if [ ${#bitcoinErrorShort} -eq 0 ]; then
      bitcoinErrorShort="Initial Startup - Please Wait"
    fi
    infoStr=" The ${network}d service is starting:\n ${bitcoinErrorShort}\n Login with SSH for more details:"
    if [ "$USER" == "admin" ]; then
      infoStr=" The ${network}d service is starting:\n ${bitcoinErrorShort}\n Please wait up to 5min ..."
    fi
  fi

# LND errors second
elif [ ${lndActive} -eq 0 ] || [ ${#lndErrorFull} -gt 0 ] || [ "${1}" == "lightning-error" ]; then

  ####################
  # On LND Error
  ####################

  height=5
  width=43
  title="Lightning Info"
  if [ ${uptime} -gt 600 ] || [ "${1}" == "lightning-error" ]; then
    infoStr=" The LND service is not running.\n Login for more details:"
    if [ "$USER" == "admin" ]; then
      clear
      echo ""
      echo "*********************************"
      echo "* The LND service is not running."
      echo "*********************************"
      echo "If you just started some config/setup, this might be OK."
      echo
      if [ ${startcountLightning} -gt 1 ]; then
        echo "${startcountLightning} RESTARTS DETECTED - ${network}d might be in a error loop"
        cat /home/admin/systemd.lightning.log | grep "ERROR" | tail -n -2
        echo
      fi
      if [ ${#lndErrorFull} -gt 0 ]; then
        echo "More Error Detail:"
        echo ${lndErrorFull}
        echo
      fi
      echo "-> Use following command to debug: /home/admin/XXdebugLogs.sh"
      echo "-> To force Main Menu run: /home/admin/00mainMenu.sh"
      echo "-> To try restart: sudo shutdown -r now"
      echo ""
      exit 1
    fi
  else
    infoStr=" The LND service is starting.\n Login for more details:"
    if [ "$USER" == "admin" ]; then
      infoStr=" The LND service is starting.\n Please wait up to 5min ..."
    fi
  fi

# if LND wallet is locked
elif [ ${walletLocked} -gt 0 ]; then
  
  height=5
  width=43

  if [ "${autoUnlock}" = "on" ]; then
    title="Auto Unlock"
    infoStr=" Waiting for Wallet Auto-Unlock.\n Please wait up to 5min ..."
  else
    title="Action Required"
    infoStr=" LND WALLET IS LOCKED !!!\n"
    if [ "${rtlWebinterface}" = "on" ]; then
       height=6
       infoStr="${infoStr} Browser: http://${localIP}:3000\n PasswordB=login / PasswordC=unlock"
    else
       infoStr="${infoStr} Please use SSH to unlock:"
    fi
    if [ ${startcountLightning} -gt 1 ]; then
        width=45
        height=$((height+1))
        infoStr=" LIGHTNING RESTARTED - login for details\n${infoStr}"
    fi
  fi

else

  ####################
  # Sync Progress
  ####################

  # basic dialog info
  height=6
  width=43
  title="Node is Syncing (${scriptRuntime})"
  actionString="Please wait - this can take some time"

  # formatting progress values
  if [ ${#syncProgress} -eq 0 ]; then
    if [ ${startcountBlockchain} -lt 2 ]; then
      syncProgress="waiting"
    else
      syncProgress="${startcountBlockchain} restarts"
      actionString="Login with SSH for more details:"
    fi
  elif [ ${#syncProgress} -lt 6 ]; then
    syncProgress=" ${syncProgress} %"
  else
    syncProgress="${syncProgress} %"
  fi
  if [ ${#scanProgress} -eq 0 ]; then
    if [ ${startcountLightning} -lt 2 ]; then
      scanProgress="waiting"
    else
      scanProgress="${startcountLightning} restarts"
      actionString="Login with SSH for more details:"
    fi
  elif [ ${#scanProgress} -lt 6 ]; then
    scanProgress=" ${scanProgress} %"
  else
    scanProgress="${scanProgress} %"
  fi

  # setting info string
  infoStr=" Blockchain Progress : ${syncProgress}\n Lightning Progress  : ${scanProgress}\n ${actionString}"

fi

# display info to user
dialog --title " ${title} " --backtitle "RaspiBlitz ${codeVersion} ${hostname} / ${network} / ${chain} / ${tempCelsius}°C" --infobox "${infoStr}\n ${adminStr}" ${height} ${width}