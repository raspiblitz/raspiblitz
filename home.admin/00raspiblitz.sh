#!/bin/bash

#######################################
# SSH USER INTERFACE
# gets called when user logins per SSH
# or calls 'raspiblitz' on the terminal
#######################################
echo "Starting SSH user interface ... (please wait)"

# CONFIGFILE - configuration of RaspiBlitz
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"
source ${infoFile}

# check that basic system phase/state information is available
if [ -z "${setupPhase}" ] || [ -z "${state}" ]; then
  echo "setupPhase(${setupPhase}) state(${state})"
  echo "FAIL: ${infoFile} does not exist or missing state."
  echo "Check logs & bootstrap.service for errors and report to devs."
  exit 1
fi

# special state: copysource
if [ "${state}" = "stop" ]; then
  echo "***********************************************************"
  echo "Stop signal detectecd - OK ready for manual provision."
  echo "If your ready for shutdown use the following command:"
  echo "release --> for an official release"
  echo "release -quick --> during development"
  if [ "${vm}" = "1" ]; then
    echo "REMOVE AUDIO DEVICE from VM before next boot up."
  fi
  echo "***********************************************************"
  exit
# special state: copysource
elif [ "${state}" = "copysource" ]; then
  echo "***********************************************************"
  echo "INFO: You lost connection during copying the blockchain"
  echo "You have the following options:"
  echo "a) continue/check progress with command: sourcemode"
  echo "b) return to normal mode with command: restart"
  echo "***********************************************************"
  exit
fi

# special state: copytarget
source <(/home/admin/config.scripts/blitz.copychain.sh status)
if [ "${copyInProgress}" = "1" ]; then
  echo "Detected interrupted COPY blockchain process ..."
  /home/admin/config.scripts/blitz.copychain.sh target
  exit
fi

#####################################
# SSH MENU LOOP
# this loop runs until user exits or
# an error drops user to terminal
#####################################

# listen to CTRL-c & CTRL-z to break loop
quit() {
  echo "SIGINT or SIGTERM received, exiting..."
  kill -9 $$
}
trap quit INT TERM

echo "# start ssh menu loop"
# put some values on higher scan rate for 10 minute
for key in ln_default_ready ln_default_locked btc_default_synced; do
  /home/admin/_cache.sh focus $key 2 600 >/dev/null
done

echo "# starting ssh menu loop ... "
exitMenuLoop=0
doneIBD=0
while [ ${exitMenuLoop} -eq 0 ]; do
  #####################################
  # Access fresh system info on every loop

  # refresh system state information
  source <(/home/admin/_cache.sh get \
    systemscan_runtime state setupPhase btc_default_synced \
    ln_default_sync_chain ln_default_locked ln_default_ready \
    ln_default_sync_initial_done message network chain \
    lightning internet_localip)

  # background.scan is not ready yet
  if [ -z "${systemscan_runtime}" ]; then
    echo "# background.scan not ready yet ... (please wait)"
    sleep 4
    continue
  fi

  #####################################
  # ALWAYS: Handle System States
  #####################################

  ############################
  # Wallet Unlock

  if [ "${state}" == "ready" ] && [ "${setupPhase}" == "done" ] && [ "${ln_default_locked}" == "1" ]; then
    # unlock lnd
    if [ "${lightning}" == "lnd" ]; then
      /home/admin/config.scripts/lnd.unlock.sh
    # unlock c-lightning
    elif [ "${lightning}" == "cl" ]; then
      /home/admin/config.scripts/cl.hsmtool.sh unlock ${chain}net
      sleep 5
    fi
  fi

  #####################################
  # SETUP MENU
  #####################################

  # when is needed & bootstrap process signals that it waits for user dialog
  if [ "${setupPhase}" != "done" ] && [ "${state}" == "waitsetup" ]; then
    # push user to main menu
    echo "# controlSetupDialog.sh"
    /home/admin/setup.scripts/controlSetupDialog.sh
    # use the exit code from setup menu as signal if menu loop should exited
    # 0 = continue loop / everything else = break loop and exit to terminal
    exitMenuLoop=$?
    if [ "${exitMenuLoop}" != "0" ]; then break; fi
  fi

  #####################################
  # SETUP DONE DIALOGS
  #####################################

  # when is needed & bootstrap process signals that it waits for user dialog
  if [ "${setupPhase}" != "done" ] && [ "${state}" == "waitfinal" ]; then
    # push to final setup gui dialogs
    #echo "# controlFinalDialog.sh"
    /home/admin/setup.scripts/controlFinalDialog.sh
    # exit because controller will reboot at the end
    exit 0
  fi

  # exit loop/script in case if system shutting down
  if [ "${state}" == "reboot" ] || [ "${state}" == "shutdown" ]; then
    dialog --pause "  Prepare ${state} ..." 8 58 4
    clear
    echo "***********************************************************"
    echo "RaspiBlitz going to ${state}"
    echo "***********************************************************"
    if [ "${state}" == "reboot" ]; then
      echo "SSH again into system with:"
      echo "ssh admin@${internet_localip}"
      echo "Use your password A"
      echo "***********************************************************"
    fi
    sleep 10
    exit 0
  fi

  #####################################
  # MAKE SURE BLOCKCHAIN/LN IS SYNC
  #####################################
  if [ "${setupPhase}" == "done" ] && [ "${state}" == "ready" ]; then
    if [ "${btc_default_synced}" != "1" ] || [ "${ln_default_ready}" == "0" ] || [ "${ln_default_sync_chain}" == "0" ] || [ "${ln_default_sync_initial_done}" == "0" ]; then
      /home/admin/setup.scripts/eventBlockchainSync.sh ssh
      sleep 3
      continue
    fi
  fi

  #####################################
  # SCB ACTIVATION
  #####################################

  # when setup is done & state is ready .. check for SCB activation
  if [ "${setupPhase}" == "done" ] && [ "${state}" == "ready" ]; then

    # check if there is a channel.backup to activate
    gotSCB=$(ls /home/admin/channel.backup 2>/dev/null | grep -c 'channel.backup')
    if [ "${gotSCB}" == "1" ]; then
      clear
      echo
      echo "*** channel.backup Recovery ***"
      echo "Running ... (please wait)"
      lncli --chain=${network} restorechanbackup --multi_file=/home/admin/channel.backup 2>/home/admin/.error.tmp
      error=$(cat /home/admin/.error.tmp)
      rm /home/admin/.error.tmp 2>/dev/null

      if [ ${#error} -gt 0 ]; then
        # output error message
        echo ""
        echo "# FAIL # SOMETHING WENT WRONG:"
        echo "${error}"

        # check if its possible to give background info on the error
        notMatchingSeed=$(echo $error | grep -c 'unable to unpack chan backup')
        if [ ${notMatchingSeed} -gt 0 ]; then
          echo "--> ERROR BACKGROUND:"
          echo "The WORD SEED is not matching the channel.backup file."
          echo "Either there was an error in the word seed list or"
          echo "or the channel.backup file is from another RaspiBlitz."
          echo
        fi

        # basic info on error
        echo "#################"
        echo "To try upload of channel.backup again:"
        echo "MAINMENU > REPAIR > REPAIR-LND > RETRYSCB"
        echo
        echo "Press ENTER to continue for now ..."
        rm /home/admin/channel.backup
        read key
      else
        rm /home/admin/channel.backup
        dialog --title " OK Static-Channel-Backup IMPORT " --msgbox "
LND accepted the channel.backup file you uploaded.
It can now take up to an hour until you can see,
if LND was able to recover funds from your channels.

If you dont see any pending on-chain incoming funds
within the next hour or you still missing funds, you
can always retry the upload again under:
MAINMENU > REPAIR > REPAIR-LND > RETRYSCB
" 14 58
      fi
    fi
  fi

  #####################################
  # MAIN MENU or BLOCKCHAIN SYNC
  #####################################

  # when setup is done & state is ready .. jump to main menu
  if [ "${setupPhase}" == "done" ] && [ "${state}" == "ready" ]; then
    # MAIN MENU
    # remove higher scan rate on values
    for key in ln_default_locked btc_default_synced; do
      /home/admin/_cache.sh focus $key -1
    done
    echo "# 00mainMenu.sh"
    /home/admin/00mainMenu.sh
    # use the exit code from main menu as signal if menu loop should exited
    # 0 = continue loop / everything else = break loop and exit to terminal
    exitMenuLoop=$?
    [ "${exitMenuLoop}" != "0" ] && break
  fi

  #####################################
  # DURING SETUP: Handle System States
  #####################################

  if [ "${setupPhase}" != "done" ]; then

    #echo "# DURING SETUP: Handle System State (${state})"

    # for all critical errors (admin info & exit)
    if [ "${state}" == "error" ] || [ "${state}" == "errorHDD" ]; then
      clear
      echo "###########################################################"
      echo "# /home/admin/raspiblitz.log"
      cat /home/admin/raspiblitz.log
      if [ "${state}" == "errorHDD" ]; then
        # print some debug detail info on HDD/SSD error
        echo "###########################################################"
        echo "# blitz.datadrive.sh status"
        sudo /home/admin/config.scripts/blitz.datadrive.sh status
      fi
      if [ "${message}" == "_provision.setup.sh fail" ]; then
        echo "# /home/admin/raspiblitz.provision-setup.log"
        cat /home/admin/raspiblitz.provision-setup.log
      fi
      echo "***********************************************************"
      echo "ERROR - please report to development team"
      echo "***********************************************************"
      echo "state(${state}) message(${message})"
      echo "https://github.com/rootzoll/raspiblitz#support"
      echo "command to shutdown --> off"
      exit 1
    elif [ "${state}" == "" ]; then
      echo "state(${state}) message(${message})"
    else
        # every other state just push as event to SSH frontend
        /home/admin/setup.scripts/eventInfoWait.sh "${state}" "${message}"
    fi
  fi
done

echo "# menu loop received exit code ${exitMenuLoop} --> exit to terminal"
echo
echo "               -==@@@====@===--       --===@====@@@==-                "
echo "            -@@=====-----=-===@@=====@@=====-----=====@@-       -==@- "
echo "            -@@------==---------@@@@@=--------==------@@-  --=@@@@=   "
echo "             @@=------======-----@@@-----======------=@@=@@===@@=     "
echo "             =@@=---------=======@@@=======-----===@@@==-  =@@-       "
echo "          -=@@==@@=----------=@@@@@@@@@=----==@@@==--   -=@@-         "
echo "        -@@@=----=@@===--====@@@@@@@@@@@@@@@@=--      -=@@@@=         "
echo "       =@@=--------@@@@@@@@@@@@@@@@@@@@@=--         -@@=---=@@-       "
echo "     -@@=-------=@@@=====@@@@@@@@@@=--            =@@=-------@@@      "
echo "    =@@=-------=@@====@@@@@@@@==-              -=@@@@=--------=@@-    "
echo "   =@@---------@@==@@@@@@==-                 -=@@@=@@@---------=@@    "
echo "  -@@=--------=@@@@@@=-                    -@@@@@@@@@@=---------=@@   "
echo "  @@=-------@@@@@@@@@=-                  =@@@===@@@@=@@@@--------@@-  "
echo " -@@=------@@====@@@=@@@=-            -=@@@======@@====@@@-------=@@  "
echo " -@@------@@@====@@@====@@@=-         =@@@======@@@=====@@=------=@@  "
echo " -@@------=@@====@@@@@=====@@@=-        -=@@@=@@@@@@===@@@=------=@@  "
echo " -@@-------@@@=@@@@@@@@@@@@@@@=-           -=@@@@@@@@=@@@=-------=@@  "
echo "  @@=-------=@@@@@@@@@@@@@@@=                 -=@@@=@@@@=--------@@=  "
echo "  -@@--------=@@======@@@@-                    -=@@@@@@=--------=@@   "
echo "   =@@--------@@@===@@@=-                 --=@@@@@@=@@@--------=@@-   "
echo "    =@@--------@@@@@@=-               -==@@@@@=====@@@--------=@@-    "
echo "     =@@=-------@@@=             -==@@@@@@@=====@@@@=--------=@@-     "
echo "      -@@=----=@@-          -==@@@@@@@@@@@@@@@@@==---------=@@=       "
echo "        =@@==@@-       -==@@@@@=========@@@@@=-----------=@@@-        "
echo "         -@@=-    --=@@@==-=@@@@@@@@@@@@@=-------------=@@=-          "
echo "       -@@=  --=@@@==----------=======-------------==@@@=             "
echo "     -@@=-==@==-=@@@===------------------------==@@@@=                "
echo "   =@@@@==-        -==@@@@@======----======@@@@@=--                   "
echo " =@@=--                 --===@@@@@@@@@@@===--                         "
echo
echo "***********************************"
echo "* RaspiBlitz Commandline"
echo "* Here be dragons .. have fun :)"
echo "***********************************"
if [ "${setupPhase}" == "done" ]; then
  echo "Bitcoin command line options: ${network}-cli help"
  [ "${lightning}" == "lnd" ] && echo "LND command line options: lncli -h"
  [ "${lightning}" == "cl" ] && echo "Core Lightning command line options: lightning-cli help"
else
  echo "Your setup is not finished."
  echo "For setup logs: cat raspiblitz.log"
  echo "or call the command 'debug' to see bigger report."
fi
echo "Blitz command line options: blitzhelp"
echo "Back to menus use command: raspiblitz"
echo
exit 0
