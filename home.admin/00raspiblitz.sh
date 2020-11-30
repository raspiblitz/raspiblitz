#!/bin/bash
echo "Starting the main menu ..."

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# use blitz.datadrive.sh to analyse HDD situation
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
if [ ${#error} -gt 0 ]; then
  echo "# FAIL blitz.datadrive.sh status --> ${error}"
  echo "# Please report issue to the raspiblitz github."
  exit 1
fi

# check if HDD is connected
if [ ${isMounted} -eq 0 ] && [ ${#hddCandidate} -eq 0 ]; then
    echo "***********************************************************"
    echo "WARNING: NO HDD FOUND -> Shutdown, connect HDD and restart."
    echo "***********************************************************"
    vagrant=$(df | grep -c "/vagrant")
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
    exit
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
recoveredInfoExists=$(sudo ls /home/admin/raspiblitz.recover.info 2>/dev/null | grep -c '.info')
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
    while :
    do
      
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
    
          echo "!! DETECTED NEED FOR RE-INDEX in debug.log ... starting repair options."          
          sudo sed -i "s/^state=.*/state=repair/g" /home/admin/raspiblitz.info
          sleep 3

          whiptail --title "RaspiBlitz - Repair Script" --yes-button "DELETE+REPAIR" --no-button "Ignore" --yesno "Your blockchain data needs to be repaired.
This can be due to power problems or a failing HDD.
For more info see: https://raspiblitz.org -> FAQ

Before RaspiBlitz can offer you repair options the old
corrupted blockchain needs to be deleted while your LND
funds and channel stay safe (just expect some off-time).

How do you want to continue?
" 13 65
          if [ $? -eq 0 ]; then
            #delete+repair
            clear
            /home/admin/XXcleanHDD.sh -blockchain -force
            /home/admin/98repairBlockchain.sh
            /home/admin/00raspiblitz.sh
            exit
          else
            # ignore - just delete blockchain logfile
            clear
          fi

        fi

        # let 80scanLND script to the info to use
        /home/admin/80scanLND.sh
        if [ $? -gt 0 ]; then
          echo "${network} error: ${clienterror}"
          exit 0
        fi

      else
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
      fi
      sleep 5
    done
}

if [ ${#setupStep} -eq 0 ]; then
  echo "WARN: no setup step found in raspiblitz.info"
  setupStep=0
fi
if [ ${setupStep} -eq 0 ]; then

  # check data from boostrap
  # TODO: when olddata --> CLEAN OR MANUAL-UPDATE-INFO
  if [ "${state}" = "olddata" ]; then

    # old data setup
    BACKTITLE="RaspiBlitz - Manual Update"
    TITLE="⚡ Found old RaspiBlitz Data on HDD ⚡"
    MENU="\n         ATTENTION: OLD DATA COULD CONTAIN FUNDS\n"
    OPTIONS+=(MANUAL "read how to recover your old funds")
    HEIGHT=11

  else
    isRaspbian=$(cat /etc/os-release 2>/dev/null | grep -c 'Raspbian')
    if [ ${isRaspbian} -gt 0 ]; then
      # show hardware test
      /home/admin/05hardwareTest.sh

      # start setup
      BACKTITLE="RaspiBlitz - Setup"
      TITLE="⚡ Welcome to your RaspiBlitz ⚡"
      MENU="\nChoose how you want to setup your RaspiBlitz: \n "
      OPTIONS+=(BITCOIN "Setup BITCOIN and Lightning (DEFAULT)" \
                LITECOIN "Setup LITECOIN and Lightning (EXPERIMENTAL)" \
                MIGRATION "Upload a Migration File from old RaspiBlitz" )
      HEIGHT=12
    else
      # start setup
      BACKTITLE="RaspiBlitz - Setup"
      TITLE="⚡ Welcome to your RaspiBlitz ⚡"
      MENU="\nStart to setup your RaspiBlitz: \n "
      OPTIONS+=(BITCOIN "Setup BITCOIN and Lightning" \
                MIGRATION "Upload a Migration File from old RaspiBlitz")
      HEIGHT=11
    fi
  fi

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

  # check if there is a channel.backup to activate
  gotSCB=$(ls /home/admin/channel.backup 2>/dev/null | grep -c 'channel.backup')
  if [ ${gotSCB} -eq 1 ]; then

    echo "*** channel.backup Recovery ***"
    lncli --chain=${network} restorechanbackup --multi_file=/home/admin/channel.backup 2>/home/admin/.error.tmp
    error=`cat /home/admin/.error.tmp`
    rm /home/admin/.error.tmp 2>/dev/null

    if [ ${#error} -gt 0 ]; then

      # output error message
      echo ""
      echo "!!! FAIL !!! SOMETHING WENT WRONG:"
      echo "${error}"

      # check if its possible to give background info on the error
      notMachtingSeed=$(echo $error | grep -c 'unable to unpack chan backup')
      if [ ${notMachtingSeed} -gt 0 ]; then
        echo "--> ERROR BACKGROUND:"
        echo "The WORD SEED is not matching the channel.backup file."
        echo "Either there was an error in the word seed list or"
        echo "or the channel.backup file is from another RaspiBlitz."
        echo 
      fi

      # basic info on error
      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      echo 
      echo "You can try after full setup to restore channel.backup file again with:"
      echo "lncli --chain=${network} restorechanbackup --multi_file=/home/admin/channel.backup"
      echo
      echo "Press ENTER to continue for now ..."
      read key
    else
      mv /home/admin/channel.backup /home/admin/channel.backup.done
      dialog --title " OK channel.backup IMPORT " --msgbox "
LND accepted the channel.backup file you uploaded. 
It will now take around a hour until you can see,
if LND was able to recover funds from your channels.
     " 9 56
    fi
  
  fi

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
              sudo rm -f ${defaultZipPath}/raspiblitz-*.tar.gz 2>/dev/null
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
