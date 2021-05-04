#!/bin/bash
echo "For debug logs CTRL+C and: tail -n1000 -f raspiblitz.log"
echo "or call the command 'debug' to see bigger report."
echo "Starting SSH user interface ..."

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# check if raspiblitz.info exists
systemInfoExists=$(ls ${infoFile} | grep -c "${infoFile}")
if [ "${systemInfoExists}" != "1" ]; then
  echo "systemInfoExists(${systemInfoExists})"
  echo "FAIL: ${infoFile} does not exist .. which it should at this point."
  echo "Check logs & bootstrap.service for errors and report to devs."
  exit 1
fi

# get system state information raspiblitz.info
source ${infoFile}

# check that basic system phase/state information is available
if [ "${setupPhase}" == "" ] || [ "${state}" == "" ]; then
  echo "setupPhase(${setupPhase}) state(${state})"
  echo "FAIL: ${infoFile} does not contain important state information."
  echo "Check logs & bootstrap.service for errors and report to devs."
  exit 1
fi

#####################################
# REDIRECT: Main Menu
#####################################

# if setup is done & state is ready .. jump to main menu
if [ "${setupPhase}" == "done" ] || [ "${state}" == "ready" ]; then
  # push user to main menu
  /home/admin/00mainMenu.sh
  exit 0
fi

#####################################
# SSH MENU LOOP
#####################################

# prepare status file
# TODO: this is to be replaced and unified together with raspiblitz.info
# when we move to a background monitoring thread & redis for WebUI with v1.8
sudo touch /var/cache/raspiblitz/raspiblitz.status
sudo chown admin:admin /var/cache/raspiblitz/raspiblitz.status
sudo chmod 740 /var/cache/raspiblitz/raspiblitz.status

exitMenuLoop=0
while [ ${exitMenuLoop} -eq 0 ]
do

  #####################################
  # MAIN SSH MENU
  #####################################

  # if setup is done & state is ready .. jump to main menu
  if [ "${setupPhase}" == "done" ] && [ "${state}" == "ready" ]; then
    # push user to main menu
    /home/admin/00mainMenu.sh
    # use the exit code from main menu as signal if menu loop should exited
    # 0 = continue loop / everything else = break loop and exit to terminal
    exitMenuLoop=$?
    if [ "${exitMenuLoop}" != "0" ]; then break; fi
  fi

  #####################################
  # SETUP SSH MENU
  #####################################

  # if setup is done & state is ready .. jump to main menu
  if [ "${setupPhase}" != "done" ] && [ "${state}" == "waitsetup" ]; then
    # push user to main menu
    /home/admin/setup.scripts/setupDialogControl.sh
    # use the exit code from setup menu as signal if menu loop should exited
    # 0 = continue loop / everything else = break loop and exit to terminal
    exitMenuLoop=$?
    if [ "${exitMenuLoop}" != "0" ]; then break; fi
  fi

  #####################################
  # Access fresh system info

  # refresh system state information
  source ${infoFile}

  # gather fresh status scan and store results in memory
  sudo /home/admin/config.scripts/blitz.statusscan.sh > /var/cache/raspiblitz/raspiblitz.status
  source /var/cache/raspiblitz/raspiblitz.status

  #####################################
  # DURING SETUP: Handle System States 
  #####################################

  if [ "${setupPhase}" != "done" ]; then

    echo "# DURING SETUP: Handle System States "

    # check if HDD is connected
    if [ "${isMounted}" == "0" ] && [ ${#hddCandidate} -eq 0 ]; then
      echo "***********************************************************"
      echo "WARNING: NO HDD FOUND -> Shutdown, connect HDD and restart."
      echo "***********************************************************"
      if [ ${vagrant} -gt 0 ]; then
        echo "To connect a HDD data disk to your VagrantVM:"
        echo "- shutdown VM with command: off"
        echo "- open your VirtualBox GUI and select RaspiBlitzVM"
        echo "- change the 'mass storage' settings"
        echo "- add a second 'Primary Slave' drive to the already existing controller"
        echo "- close VirtualBox GUI and run: vagrant up & vagrant ssh"
        echo "***********************************************************"
        echo "You can either create a new dynamic VDI with around 900GB or download"
        echo "a VDI with a presynced blockchain to speed up setup. If you dont have 900GB"
        echo "space on your laptop you can store the VDI file on an external drive."
        echo "***********************************************************"
      fi
    fi

  fi

  #####################################
  # ALWAYS: Handle System States 
  #####################################

  ############################
  # LND Wallet Unlock

  echo "walletLocked(${walletLocked})"
  if [ "${walletLocked}" == "1" ]; then
    /home/admin/config.scripts/lnd.unlock.sh
  fi

  #####################################
  # AFTER SETUP: Handle System States 
  #####################################

  if [ "${setupPhase}" == "done" ]; then

    echo "# AFTER SETUP: Handle System States "

  fi

  # debug wait
  echo "uptime(${uptime})"
  sleep 3

done
echo "# mainmenu signaled exit code '${exitMenuLoop}' --> exit to terminal"
echo "***********************************"
echo "* RaspiBlitz Commandline"
echo "* Here be dragons .. have fun :)"
echo "***********************************"
if [ "${setupPhase}" == "done" ]
  echo "Bitcoin command line options: bitcoin-cli help"
  echo "LND command line options: lncli -h"
fi
echo "Back to menus use command: raspiblitz"
echo
exit 0

################# TODO: MOVE PARTS BELOW TO APROPIATE NEW PLACE

# check if HDD is from another fullnode OS and offer migration
if [ "${hddGotMigrationData}" != "" ] && [ "${hddGotMigrationData}" != "none" ]; then
  nodenameUpperCase=$(echo "${hddGotMigrationData}" | tr "[a-z]" "[A-Z]")
  whiptail --title " ${nodenameUpperCase} --> RASPIBLITZ " --yes-button "Start Migration" --no-button "Ignore" --yesno "RaspiBlitz found data from ${nodenameUpperCase}

You can migrate your blockchain & LND data (funds & channels) over to RaspiBlitz.

Please make sure to have your ${nodenameUpperCase} seed words & static channel backup file (just in case). Also any data of additional apps you had installed on ${nodenameUpperCase} might get lost.

Do you want to start migration to RaspiBlitz now?
      " 16 58
  if [ $? -eq 0 ]; then
    err=""
    echo "**************************************************"
    echo "MIGRATION FROM ${nodenameUpperCase} TO RASPIBLITZ"
    echo "**************************************************"
    echo "- started ..."
    source <(sudo /home/admin/config.scripts/blitz.migration.sh migration-${hddGotMigrationData})
    if [ "${err}" != "" ]; then
      echo "MIGRATION FAILED: ${err}"
      echo "Format data disk on laptop & recover funds with fresh sd card using seed words + static channel backup."
      exit 1
    fi

    # if free space is lower than 100GB (100000000) delete backup files
    if [ "${hddDataFreeKB}" != "" ] && [ ${hddDataFreeKB} -lt 407051412 ]; then
      echo "- free space of data disk is low ... deleting 'backup_migration'"
      sudo rm -R /mnt/hdd/backup_migration
    else
      echo "- old data of ${nodenameUpperCase} can be found in '/mnt/hdd/backup_migration'"
    fi
    sleep 3

    # kick into reboot
    echo "******************************************************"
    echo "OK MIGRATION --> will now reboot and update/recover"
    echo "******************************************************"
    sudo shutdown -h -r now
    sleep 100
    exit 0
	else
    echo "******************************************************"
    echo "MIGRATION SKIPPED ... starting fresh RaspiBlitz Setup"
    echo "******************************************************"
    sleep 6
  fi
fi

# check data from _bootstrap.sh that was running on device setup
bootstrapInfoExists=$(ls $infoFile | grep -c '.info')
if [ ${bootstrapInfoExists} -eq 0 ]; then
  echo "***********************************************************"
  echo "WARNING: NO raspiblitz.info FOUND -> bootstrap not running?"
  echo "***********************************************************"
  exit
fi

# load the data from the info file (will get produced on every startup)
source ${infoFile}

if [ "${state}" = "recovering" ]; then
  echo "***********************************************************"
  echo "WARNING: bootstrap still updating - close SSH, login later"
  echo "To monitor progress --> tail -n1000 -f raspiblitz.log"
  echo "***********************************************************"
  exit
fi

if [ "${state}" = "copysource" ]; then
  echo "***********************************************************"
  echo "INFO: You lost connection during copying the blockchain"
  echo "You have the following options:"
  echo "a) continue/check progress with command: sourcemode"
  echo "b) return to normal mode with command: restart"
  echo "***********************************************************"
  exit
fi

# check if copy blockchain over LAN to this RaspiBlitz was running
source <(/home/admin/config.scripts/blitz.copyblockchain.sh status)
if [ "${copyInProgress}" = "1" ]; then
  echo "Detected interrupted COPY blochain process ..."
  /home/admin/50copyHDD.sh
  exit
fi

# signal that after bootstrap recover user dialog is needed
recoveredInfoExists=$(sudo ls /home/admin/recover.flag 2>/dev/null | grep -c '.flag')
if [ ${recoveredInfoExists} -gt 0 ]; then
  echo "System recovered - needs final user settings"
  /home/admin/20recoverDialog.sh 
  exit 1
fi

# signal that a reindex was triggered
if [ "${state}" = "reindex" ]; then
  echo "Re-Index in progress ... start monitoring:"
  /home/admin/config.scripts/network.reindex.sh
  exit 1
fi

# singal that copstation is running
if [ "${state}" = "copystation" ]; then
  echo "Copy Station is Runnning ..."
  echo "reboot to return to normal"
  sudo /home/admin/XXcopyStation.sh
  exit
fi

# if state=ready -> setup is done or started
if [ "${state}" = "ready" ]; then
  configExists=$(ls ${configFile} | grep -c '.conf')
  if [ ${configExists} -eq 1 ]; then
    echo "loading config data"
    source ${configFile}
  else
    echo "setup still in progress - setupStep(${setupStep})"
  fi
fi

## default menu settings
# to fit the main menu without scrolling: 
HEIGHT=13
WIDTH=64
CHOICE_HEIGHT=6
BACKTITLE="RaspiBlitz"
TITLE=""
MENU="Choose one of the following options:"
OPTIONS=()

# check if RTL web interface is installed
runningRTL=$(sudo ls /etc/systemd/system/RTL.service 2>/dev/null | grep -c 'RTL.service')

# function to use later
waitUntilChainNetworkIsReady()
{
    source ${configFile}
    echo "checking ${network}d - please wait .."
    echo "can take longer if device was off or first time"

    # check for error on network
    sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo 1>/dev/null 2>error.tmp
    clienterror=`cat error.tmp`
    rm error.tmp

    # check for missing blockchain data
    if [ "${network}" = "bitcoin" ]; then
      if [ "${chain}" = "main" ]; then
          minSize=210000000000
      else
          minSize=27000000000
      fi
    elif [ "${network}" = "litecoin" ]; then
      if [ "${chain}" = "main" ]; then
          minSize=20000000000
      else
          minSize=27000000000
      fi
    else
      minSize=210000000000000
    fi
    isSyncing=$(sudo ls -la /mnt/hdd/${network}/blocks/.selfsync 2>/dev/null | grep -c '.selfsync')
    blockchainsize=$(sudo du -shbc /mnt/hdd/${network}/ 2>/dev/null | head -n1 | awk '{print $1;}')
    if [ ${#blockchainsize} -gt 0 ]; then
        if [ ${blockchainsize} -lt ${minSize} ]; then
          if [ ${isSyncing} -eq 0 ]; then
            echo "blockchainsize(${blockchainsize})"
            echo "Missing Blockchain Data (<${minSize}) ..."
            clienterror="missing blockchain"
            sleep 3
          fi
        fi
    fi

    if [ ${#clienterror} -gt 0 ]; then
        #echo "clienterror(${clienterror})"

        # analyse LOGS for possible reindex
        reindex=$(sudo cat /mnt/hdd/${network}/debug.log 2>/dev/null | grep -c 'Please restart with -reindex or -reindex-chainstate to recover')
        if [ ${reindex} -gt 0 ]; then
          # dismiss if its just a date thing
          futureBlock=$(sudo tail /mnt/hdd/${network}/debug.log 2>/dev/null | grep "Please restart with -reindex or -reindex-chainstate to recover" | grep -c "block database contains a block which appears to be from the future")
          if [ ${futureBlock} -gt 0 ]; then
            blockchainBroken=0
            echo "-> Ignore reindex - its just a future block"
          fi
          if [ ${isSyncing} -gt 0 ]; then
            reindex=0
          fi
        fi
        if [ ${reindex} -gt 0 ] || [ "${clienterror}" = "missing blockchain" ]; then
    
          if [ ${reindex} -gt 0 ]; then
            echo "!! DETECTED NEED FOR RE-INDEX in debug.log ... starting repair options."          
            sudo sed -i "s/^state=.*/state=repair/g" /home/admin/raspiblitz.info
            sleep 3
          fi

          whiptail --title "Blockchain not Complete" --yes-button "DELETE+REPAIR" --no-button "Continue Sync" --yesno "Your blockchain data is not complete (yet).

You can try to sync the chain further but if your stuck
this can be due to power problems or a failing HDD.
For more info see: https://raspiblitz.org -> FAQ

If you choose to DELETE+REPAIR the old blockchain gets
deleted but your Lightning funds & channel not be touched.

How do you want to continue?
" 15 65
          if [ $? -eq 0 ]; then
            #delete+repair
            clear
            echo "***********************************************************"
            echo "DELETE+REPAIR blockchain ..."
            echo "***********************************************************"
            /home/admin/XXcleanHDD.sh -blockchain -force
            /home/admin/98repairBlockchain.sh
            /home/admin/00raspiblitz.sh
            exit
          else
            # ignore - just delete blockchain logfile
            clear
            echo "***********************************************************"
            echo "CONTINUE SYNC blockchain ..."
            echo "***********************************************************"
          fi

        fi

        # let 80scanLND script to the info to use
        /home/admin/80scanLND.sh
        if [ $? -gt 0 ]; then
          echo "${network} error: ${clienterror}"
          exit 0
        fi
    fi

    while :
    do
      
      locked=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net getinfo 2>&1 | grep -c unlock)
      if [ ${locked} -gt 0 ]; then
          uptime=$(awk '{printf("%d\n",$1 + 0.5)}' /proc/uptime)
          if [ "${autoUnlock}" == "on" ] && [ ${uptime} -lt 300 ]; then
            # give autounlock 5 min after startup to react
            sleep 1
          else
            # check how many times LND was restarted
            source <(sudo /home/admin/config.scripts/blitz.statusscan.sh)
            if [ ${startcountLightning} -lt 4 ]; then
              /home/admin/config.scripts/lnd.unlock.sh
              echo "Starting up Wallet ... (10sec)"
              sleep 5
              sleep 5
              echo "please wait ... update to next screen can be slow"
            else
              /home/admin/80scanLND.sh lightning-error
              sudo rm /home/admin/systemd.lightning.log
              echo "(exit after too much restarts/unlocks - restart to try again)"
              exit 0
            fi
          fi
      fi
      lndSynced=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net getinfo 2>/dev/null | jq -r '.synced_to_chain' | grep -c true)
      if [ ${lndSynced} -eq 0 ]; then
          /home/admin/80scanLND.sh
          if [ $? -gt 0 ]; then
            exit 0
          fi
      else
          # everything is ready - return from loop
          return
      fi
      sleep 5
    done
}

if [ ${#setupStep} -eq 0 ]; then
  echo "WARN: no setup step found in raspiblitz.info"
  setupStep=0
fi
if [ ${setupStep} -eq 0 ]; then


  # start setup
  BACKTITLE="RaspiBlitz - Setup"
  TITLE="⚡ Welcome to your RaspiBlitz ⚡"
  MENU="\nChoose how you want to setup your RaspiBlitz: \n "
  OPTIONS+=(BITCOIN "Setup BITCOIN and Lightning (DEFAULT)" \
            LITECOIN "Setup LITECOIN and Lightning (EXPERIMENTAL)" \
            MIGRATION "Upload a Migration File from old RaspiBlitz" )
  HEIGHT=12

elif [ ${setupStep} -lt 100 ]; then

  # continue setup
  BACKTITLE="${hostname} / ${network} / ${chain}"
  TITLE="⚡ Welcome to your RaspiBlitz ⚡"
  MENU="\nThe setup process is not finished yet: \n "
  OPTIONS+=(CONTINUE "Continue Setup of your RaspiBlitz")
  HEIGHT=10

else

  # check if LND needs re-setup
  source <(sudo /home/admin/config.scripts/lnd.check.sh basic-setup)
  if [ "${wallet}" == "0" ] || [ "${macaroon}" == "0" ] || [ "${config}" == "0" ] || [ "${tls}" == "0" ]; then
      echo "WARN: LND needs re-setup"
      /home/admin/70initLND.sh
      exit 0
  fi

  # wait all is synced and ready
  waitUntilChainNetworkIsReady



  # check if DNS is working (if not it will trigger dialog)
  sudo /home/admin/config.scripts/internet.dns.sh test

  #forward to main menu
  /home/admin/00mainMenu.sh
  exit 0

fi

CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

clear
case $CHOICE in
        CLOSE)
            exit 1;
            ;;
        BITCOIN)
            # set network info
            sed -i "s/^network=.*/network=bitcoin/g" ${infoFile}
            sed -i "s/^chain=.*/chain=main/g" ${infoFile}
            ###### OPTIMIZE IF RAM >1GB
            kbSizeRAM=$(cat /proc/meminfo | grep "MemTotal" | sed 's/[^0-9]*//g')
            if [ ${kbSizeRAM} -gt 1500000 ]; then
              echo "Detected RAM >1GB --> optimizing ${network}.conf"
              sudo sed -i "s/^dbcache=.*/dbcache=512/g" /home/admin/assets/bitcoin.conf
              sudo sed -i "s/^maxmempool=.*/maxmempool=300/g" /home/admin/assets/bitcoin.conf
            fi
            /home/admin/10setupBlitz.sh
            exit 1;
            ;;
        LITECOIN)
            /home/admin/config.scripts/blitz.litecoin.sh on
            /home/admin/10setupBlitz.sh
            exit 1;
            ;;
        MANUAL)
            echo "************************************************************************************"
            echo "PLEASE go to RaspiBlitz FAQ:"
            echo "https://github.com/rootzoll/raspiblitz"
            echo "And check: How can I recover my coins from a failing RaspiBlitz?"
            echo "************************************************************************************"
            exit 0
            ;; 
        MIGRATION)
            sudo /home/admin/config.scripts/blitz.migration.sh "import-gui"
            # on error clean & repeat
            if [ "$?" = "1" ]; then
              echo
              echo "# clean and unmount for next try"
              sudo umount /mnt/hdd 2>/dev/null
              sudo umount /mnt/storage 2>/dev/null
              sudo umount /mnt/temp 2>/dev/null
              sleep 2
              /home/admin/00raspiblitz.sh
            fi
            exit 0
            ;;
        CONTINUE)
            /home/admin/10setupBlitz.sh
            exit 1;
            ;;
esac
