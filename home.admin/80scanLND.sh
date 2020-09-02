#!/bin/bash

source /home/admin/_version.info
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

# all system/service info gets detected by blitz.statusscan.sh
source <(sudo /home/admin/config.scripts/blitz.statusscan.sh)
source <(sudo /home/admin/config.scripts/internet.sh status)

# when admin and no other error found run LND setup check 
if [ "$USER" == "admin" ] && [ ${#lndErrorFull} -eq 0 ]; then
  lndErrorFull=$(sudo /home/admin/config.scripts/lnd.check.sh basic-setup | grep "err=" | tail -1)
fi

# set follow up info different for LCD and ADMIN
adminStr="ssh admin@${localip} ->Password A"
if [ "$USER" == "admin" ]; then
  adminStr="Use CTRL+c to EXIT to Terminal"
fi

# bitcoin errors always first
if [ ${bitcoinActive} -eq 0 ] || [ ${#bitcoinErrorFull} -gt 0 ] || [ "${1}" == "blockchain-error" ]; then

  ####################
  # Copy Blockchain Source Mode
  # https://github.com/rootzoll/raspiblitz/issues/1081
  ####################

  if [ "${state}" = "copysource" ]; then
    l1="Copy Blockchain Source Modus\n"
    l2="May needs restart node when done.\n"
    l3="Restart from Terminal: restart"
    dialog --backtitle "RaspiBlitz ${codeVersion} (${state}) ${localIP}" --infobox "$l1$l2$l3" 5 45
    sleep 3
    exit 1
  fi

  ####################
  # On Bitcoin Error
  ####################

  height=6
  width=43
  title="Blockchain Info"

  if [ ${#bitcoinErrorShort} -eq 0 ]; then
    bitcoinErrorShort="Initial Startup - Please Wait"
  fi

  if [ "$USER" != "admin" ]; then

    if [ ${uptime} -gt 600 ]; then
      if [ ${uptime} -gt 1000 ] || [ ${#bitcoinErrorFull} -gt 0 ] || [ "${1}" == "blockchain-error" ]; then
        infoStr=" The ${network}d service is NOT RUNNING!\n ${bitcoinErrorShort}\n Login for more details & options:"
      else
        infoStr=" The ${network}d service is running:\n ${bitcoinErrorShort}\n Login with SSH for more details:"
      fi
    else
      infoStr=" The ${network}d service is starting:\n ${bitcoinErrorShort}\n Login with SSH for more details:"
    fi

  else

    # output when user login in as admin and bitcoind is not running

    if [ ${uptime} -gt 1000 ] || [ ${#bitcoinErrorFull} -gt 0 ] || [ "${bitcoinErrorShort}" == "Error found in Logs" ] || [ "${1}" == "blockchain-error" ]; then

      clear
      echo ""
      echo "*****************************************"
      echo "* The ${network}d service is not running."
      echo "*****************************************"
      echo "If you just started some config/setup, this might be OK."
      echo
      if [ ${startcountBlockchain} -gt 1 ]; then
        echo "${startcountBlockchain} RESTARTS DETECTED - ${network}d might be in a error loop"
        cat /home/admin/systemd.blockchain.log | grep "ERROR" | tail -n -1
        echo
      fi
      if [ ${#bitcoinErrorFull} -gt 0 ]; then
        echo "More Error Detail:"
        echo ${bitcoinErrorFull}
        echo
      fi

      echo "POSSIBLE OPTIONS:"
      source <(/home/admin/config.scripts/network.txindex.sh status)
      if [ "${txindex}" == "1" ]; then
        echo "-> Use command 'repair' and then choose 'DELETE-INDEX' to try rebuilding transaction index."
      fi
      echo "-> Use command 'repair' and then choose 'RESET-CHAIN' to try downloading new blockchain."
      echo "-> Use command 'debug' for more log output you can use for getting support."
      echo "-> Use command 'menu' to open main menu."
      echo "-> Have you tried to turn it off and on again? Use command 'restart'"
      echo ""
      exit 1

    else
      infoStr=" The ${network}d service is starting:\n ${bitcoinErrorShort}\n Please wait up to 10min ..."
    fi

  fi

# LND errors second
elif [ ${lndActive} -eq 0 ] || [ ${#lndErrorFull} -gt 0 ] || [ "${1}" == "lightning-error" ]; then

  ####################
  # On LND Error
  ####################

  height=6
  width=43
  title="Lightning Info"
  if [ ${uptime} -gt 600 ] || [ "${1}" == "lightning-error" ]; then
    if [ ${#lndErrorShort} -gt 0 ]; then
       height=6
      lndErrorShort=" ${lndErrorShort}\n"
    fi
    if [ ${lndActive} -eq 0 ]; then
      infoStr=" The LND service is not running.\n${lndErrorShort} Login for more details:"
    else
      infoStr=" The LND service is running with error.\n${lndErrorShort} Login for more details:"
    fi
    if [ "$USER" == "admin" ]; then
      clear
      echo ""
      echo "****************************************"
      if [ ${lndActive} -eq 0 ]; then
        echo "* The LND service is not running."
      else
        echo "* The LND service is running with error."
      fi
      echo "****************************************"
      echo "If you just started some config/setup, this might be OK."
      echo
      if [ ${startcountLightning} -gt 1 ]; then
        echo "${startcountLightning} RESTARTS DETECTED - LND might be in a error loop"
        cat /home/admin/systemd.lightning.log | grep "ERROR" | tail -n -1
      fi
      sudo journalctl -u lnd -b --no-pager -n14 | grep "lnd\["
      sudo /home/admin/config.scripts/lnd.check.sh basic-setup | grep "err="
      if [ ${#lndErrorFull} -gt 0 ]; then
        echo "More Error Detail:"
        echo ${lndErrorFull}
      fi
      echo
      echo "-> Use command 'repair' and then choose 'BACKUP-LND' to make a just in case backup."
      echo "-> Use command 'debug' for more log output you can use for getting support."
      echo "-> Use command 'menu' to open main menu."
      echo "-> Have you tried to turn it off and on again? Use command 'restart'"
      echo ""
      exit 1
    else
      source <(sudo /home/admin/config.scripts/lnd.check.sh basic-setup)
      if [ ${wallet} -eq 0 ] || [ ${macaroon} -eq 0 ] || [ ${config} -eq 0 ] || [ ${tls} -eq 0 ]; then
        infoStr=" The LND service needs RE-SETUP.\n Login with SSH to continue:"
      fi
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
       infoStr="${infoStr} Browser: http://${localip}:3000\n PasswordB=login / PasswordC=unlock"
    else
       infoStr="${infoStr} Please use SSH to unlock:"
    fi
    if [ ${startcountLightning} -gt 1 ]; then
        width=45
        height=$((height+3))
        infoStr=" LIGHTNING RESTARTED - login for details\n${infoStr}"
        adminStr="${adminStr}\n or choose 'INFO' in main menu\n or type 'raspiblitz' on terminal"
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

  # formatting BLOCKCHAIN SYNC PROGRESS
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


  # formatting LIGHTNING SCAN PROGRESS  
  if [ ${#scanProgress} -eq 0 ]; then

    # in case of LND RPC is not ready yet
    if [ ${scanTimestamp} -eq -2 ]; then

      scanProgress="prepare sync"

    # in case LND restarting >2  
    elif [ ${startcountLightning} -gt 2 ]; then

      scanProgress="${startcountLightning} restarts"
      actionString="Login with SSH for more details:"

      # check if a specific error can be identified for restarts
      lndSetupErrorCount=$(sudo /home/admin/config.scripts/lnd.check.sh basic-setup | grep -c "err=")
      if [ ${lndSetupErrorCount} -gt 0 ]; then
        scanProgress="possible error"
      fi

    # unkown cases
    else
      scanProgress="waiting"
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
