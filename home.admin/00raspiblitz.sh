#!/bin/bash
echo "Starting the main menu ..."

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# check if HDD is connected
hddExists=$(lsblk | grep -c sda1)
if [ ${hddExists} -eq 0 ]; then

  # check if there is maybe a HDD but woth no partitions
  noPartition=$(lsblk | grep -c sda)
  if [ ${noPartition} -eq 1 ]; then
    echo "***********************************************************"
    echo "WARNING: HDD HAS NO PARTITIONS"
    echo "***********************************************************"
    echo "Press ENTER to create a Partition - or CTRL+C to abort"
    read key
    echo "Creating Partition ..."
    sudo parted -s /dev/sda mklabel msdos
    sudo parted -s /dev/sda unit s mkpart primary `sudo parted /dev/sda unit s print free | grep 'Free Space' | tail -n 1`
    echo "DONE."
    sleep 3
  else 
    echo "***********************************************************"
    echo "WARNING: NO HDD FOUND -> Shutdown, connect HDD and restart."
    echo "***********************************************************"
    exit
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

# singal that torrent is in re-download
if [ "${state}" = "retorrent" ]; then
  echo "Re-Index in progress ... start monitoring:"
  /home/admin/50torrentHDD.sh
  sudo sed -i "s/^state=.*/state=repair/g" /home/admin/raspiblitz.info
  /home/admin/00raspiblitz.sh
  exit
fi

# singal that copstation is running
if [ "${state}" = "copystation" ]; then
  echo "Copy Station is Runnning ..."
  echo "reboot to return to normal"
  sudo /home/admin/XXcopyStation.sh
  exit
fi

# if pre-sync is running - stop it - before continue
if [ "${state}" = "presync" ]; then
  # stopping the pre-sync
  echo ""
  # analyse if blockchain was detected broken by pre-sync
  blockchainBroken=$(sudo tail /mnt/hdd/bitcoin/debug.log 2>/dev/null | grep -c "Please restart with -reindex or -reindex-chainstate to recover.")
  if [ ${blockchainBroken} -eq 1 ]; then  
    # dismiss if its just a date thing
    futureBlock=$(sudo tail /mnt/hdd/bitcoin/debug.log 2>/dev/null | grep "Please restart with -reindex or -reindex-chainstate to recover." | grep -c "block database contains a block which appears to be from the future")
    if [ ${futureBlock} -gt 0 ]; then
      blockchainBroken=0
      echo "-> Ignore reindex - its just a future block"
    fi
  fi
  if [ ${blockchainBroken} -eq 1 ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "Detected corrupted blockchain on pre-sync !"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "Deleting blockchain data ..."
    echo "(needs to get downloaded fresh during setup)"
    sudo rm -f -r /mnt/hdd/bitcoin
  else
    echo "************************************"
    echo "Preparing ... pls wait (up to 1min) "
    echo "************************************"
    sudo -u root bitcoin-cli -conf=/home/admin/assets/bitcoin.conf stop 2>/dev/null
    echo "Calling presync to finish up .."
    sleep 50
  fi

  # unmount the temporary mount
  echo "Unmount HDD .."
  sudo umount -l /mnt/hdd
  sleep 3

  # update info file
  state=waitsetup
  sudo sed -i "s/^state=.*/state=waitsetup/g" $infoFile
  sudo sed -i "s/^message=.*/message='Pre-Sync Stopped'/g" $infoFile
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
      minSize=210000000000
      if [ "${network}" = "litecoin" ]; then
        minSize=20000000000
      fi
      isSyncing=$(sudo ls -la /mnt/hdd/${network}/blocks/.selfsync 2>/dev/null | grep -c '.selfsync')
      blockchainsize=$(sudo du -shbc /mnt/hdd/${network} 2>/dev/null | head -n1 | awk '{print $1;}')
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
For more info see: https://raspiblitz.com -> FAQ

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
              /home/admin/AAunlockLND.sh
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
    OPTIONS+=(MANUAL "read how to recover your old funds" \
              DELETE "erase old data, keep blockchain, reboot" )
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
                LITECOIN "Setup LITECOIN and Lightning (EXPERIMENTAL)" )
      HEIGHT=11
    else
      # start setup
      BACKTITLE="RaspiBlitz - Setup"
      TITLE="⚡ Welcome to your RaspiBlitz ⚡"
      MENU="\nStart to setup your RaspiBlitz: \n "
      OPTIONS+=(BITCOIN "Setup BITCOIN and Lightning")
      HEIGHT=10
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
  if [ ${wallet} -eq 0 ] || [ ${macaroon} -eq 0 ] || [ ${config} -eq 0 ] || [ ${tls} -eq 0 ]; then
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
            # set network info
            sed -i "s/^network=.*/network=litecoin/g" ${infoFile}
            sed -i "s/^chain=.*/chain=main/g" ${infoFile}
            ###### OPTIMIZE IF RAM >1GB
            kbSizeRAM=$(cat /proc/meminfo | grep "MemTotal" | sed 's/[^0-9]*//g')
            if [ ${kbSizeRAM} -gt 1500000 ]; then
              echo "Detected RAM >1GB --> optimizing ${network}.conf"
              sudo sed -i "s/^dbcache=.*/dbcache=512/g" /home/admin/assets/litecoin.conf
              sudo sed -i "s/^maxmempool=.*/maxmempool=300/g" /home/admin/assets/litecoin.conf
            fi
            /home/admin/10setupBlitz.sh
            exit 1;
            ;;
        CONTINUE)
            /home/admin/10setupBlitz.sh
            exit 1;
            ;;
        OFF)
            echo ""
            echo "LCD turns white when shutdown complete."
            echo "Then wait 5 seconds and disconnect power."
            echo "-----------------------------------------------"
            echo "stop lnd - please wait .."
            sudo systemctl stop lnd
            echo "stop ${network}d (1) - please wait .."
            sudo -u bitcoin ${network}-cli stop
            sleep 10
            echo "stop ${network}d (2) - please wait .."
            sudo systemctl stop ${network}d
            sleep 3
            sync
            echo "starting shutdown ..."
            sudo shutdown now
            exit 0
            ;;
        MANUAL)
            echo "************************************************************************************"
            echo "PLEASE go to RaspiBlitz FAQ:"
            echo "https://github.com/rootzoll/raspiblitz"
            echo "And check: How can I recover my coins from a failing RaspiBlitz?"
            echo "************************************************************************************"
            exit 0
            ;;
        DELETE)
            sudo /home/admin/XXcleanHDD.sh
            sudo shutdown -r now
            exit 0
            ;;   
        X)
            lncli -h
            echo "OK you now on the command line."
            echo "You can return to the main menu with the command:"
            echo "raspiblitz"
            ;;
        R)
            /home/admin/00raspiblitz.sh
            ;;
        U) # unlock
            /home/admin/AAunlockLND.sh
            /home/admin/00raspiblitz.sh
            ;;
esac
