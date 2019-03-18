#!/bin/bash

# CHECK WHAT IS ALREADY WORKING
# check list from top down - so ./10setupBlitz.sh
# and re-enters the setup process at the correct spot
# in case it got interrupted
echo "checking setup script"

# INFOFILE on SD - state data from bootstrap & setup
infoFile="/home/admin/raspiblitz.info"
source ${infoFile}

echo "network(${network})"
echo "chain(${chain})"
echo "setupStep(${setupStep})"

if [ ${#network} -eq 0 ]; then
  echo "FAIL: Something is wrong. There is no value for network in ${infoFile}."
  echo "Should be at least default value. EXIT"
  exit 1
fi

# if no setup step in info file init with 0
if [ ${#setupStep} -eq 0 ];then
  echo "Init setupStep=0"
  echo "setupStep=0" >> ${infoFile}
  setupStep=0
fi

# if setup if ready --> REBOOT
if [ ${setupStep} -gt 89 ];then
  echo "FINISH by setupstep(${setupStep})"
  sleep 3
  sudo ./90finishSetup.sh
  sudo ./95finalSetup.sh
  exit 0
fi

# check if lightning is running
lndRunning=$(systemctl status lnd.service 2>/dev/null | grep -c running)
if [ ${lndRunning} -eq 1 ]; then
  
  echo "LND is running ..."
  sleep 1

  # check if LND wallet exists and if locked
  walletExists=$(sudo ls /mnt/hdd/lnd/data/chain/${network}/${chain}net/wallet.db 2>/dev/null | grep wallet.db -c)
  locked=0
  # only when a wallet exists - it can be locked
  if [ ${walletExists} -eq 1 ];then
    echo "lnd wallet exists ... checking if locked"
    sleep 2
    locked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log 2>/dev/null | grep -c unlock)
  fi
  if [ ${locked} -gt 0 ]; then
    # LND wallet is locked
    ./AAunlockLND.sh
    ./10setupBlitz.sh
    exit 0
  fi

  # check if blockchain still syncing (during sync sometimes CLI returns with error at this point)
  chainInfo=$(sudo -u bitcoin ${network}-cli getblockchaininfo 2>/dev/null | grep 'initialblockdownload')
  chainSyncing=1
  if [ ${#chainInfo} -gt 0 ];then
    echo "check chaininfo" 
    chainSyncing=$(echo "${chainInfo}" | grep "true" -c)
  else 
    echo "chaininfo is zero" 
  fi
  if [ ${chainSyncing} -eq 1 ]; then
    echo "Sync Chain ..."
    sleep 3
    ./70initLND.sh
    exit 0
  fi

  # check if lnd is scanning blockchain
  lndInfo=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} getinfo | grep "synced_to_chain")
  lndSyncing=1
  if [ ${#lndInfo} -gt 0 ];then
    lndSyncing=$(echo "${chainInfo}" | grep "false" -c)
  fi
  if [ ${lndSyncing} -eq 1 ]; then
    echo "Sync LND ..." 
    sleep 3
    ./70initLND.sh
    exit 0
  fi

  # if unlocked, blockchain synced and LND synced to chain .. finisch Setup
  echo "FINSIH ... "
  sleep 3
  sudo ./90finishSetup.sh
  sudo ./95finalSetup.sh
  exit 0

fi #end - when lighting is running

# check if bitcoin is running
bitcoinRunning=$(systemctl status ${network}d.service 2>/dev/null | grep -c running)
if [ ${bitcoinRunning} -eq 0 ]; then
  # double check
  seconds=120
  if [ ${setupStep} -lt 60 ]; then
    seconds=10
  fi
  dialog --pause "  Double checking for ${network}d - please wait .." 8 58 ${seconds}
  bitcoinRunning=$(${network}-cli getblockchaininfo | grep "initialblockdownload" -c)
else
  echo "${network} is running"  
fi
if [ ${bitcoinRunning} -eq 1 ]; then
  echo "OK - ${network}d is running"
  echo "Next step run Lightning"
  ./70initLND.sh
  exit 1
else
 echo "${network} still not running"  
fi #end - when bitcoin is running

# check if HDD is auto-mounted
mountOK=$( sudo cat /etc/fstab | grep -c '/mnt/hdd' )
if [ ${mountOK} -eq 1 ]; then
  
  # FAILSAFE: check if raspiblitz.conf is available
  configExists=$(ls /mnt/hdd/raspiblitz.conf | grep -c '.conf')
  if [ ${configExists} -eq 0 ]; then
    echo ""
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "FAIL: /mnt/hdd/raspiblitz.conf should exists at this point, but not found!"
    echo "Please report to: https://github.com/rootzoll/raspiblitz/issues/293"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "Press ENTER to EXIT."
    read key
    exit 1
  fi

  # are there any signs of blockchain data and activity
  # setup running with admin user, but has no permission to read /mnt/hdd/bitcoin/blocks/, sudo needed
  blockchainDataExists=$(sudo ls /mnt/hdd/${network}/blocks/blk00000.dat 2>/dev/null | grep -c '.dat')
  configExists=$(sudo ls /mnt/hdd/${network}/${network}.conf | grep -c '.conf')

  if [ ${blockchainDataExists} -eq 1 ]; then
    if [ ${configExists} -eq 1 ]; then
      ./XXdebugLogs.sh
      echo "UNKOWN STATE - there is blockain data config, but blockchain service is not running"
      echo "It seems that something went wrong during sync/download/copy of the blockchain."
      echo "Or something with the config is not correct."
      echo "Sometimes a reboot helps --> sudo shutdown -r now"
      exit 1
    else 
      echo "Got mounted blockchain, but no config and running service yet --> finish HDD"
      ./60finishHDD.sh
      exit 1
    fi
  fi

  # check if there is torrent data to continue
  torrentProgressExists=$(sudo ls /mnt/hdd/ 2>/dev/null | grep "torrent" -c)
  if [ ${torrentProgressExists} -eq 1 ]; then
    # check if there is a running screen session to return to
    noScreenSession=$(screen -ls | grep -c "No Sockets found")
    if [ ${noScreenSession} -eq 0 ]; then 
      echo "found torrent data .. resuming"
      ./50torrentHDD.sh
      exit 1
    fi
  fi

  # check if there is ftp data to continue
  downloadProgressExists=$(sudo ls /mnt/hdd/ 2>/dev/null | grep "download" -c)
  if [ ${downloadProgressExists} -eq 1 ]; then
    # check if there is a running screen session to return to
    noScreenSession=$(screen -ls | grep -c "No Sockets found")
    if [ ${noScreenSession} -eq 0 ]; then 
      echo "found download in data .. resuming"
      ./50downloadHDD.sh
      exit 1
    fi
  fi

  # HDD is empty - get Blockchain

  #Bitcoin
  if [ ${network} = "bitcoin" ]; then
    echo "Bitcoin Options"
    menuitem=$(dialog --clear --beep --backtitle "RaspiBlitz" --title "Getting the Blockchain" \
    --menu "You need a copy of the Bitcoin Blockchain - you have 5 options:" 13 75 5 \
    T "TORRENT  --> MAINNET + TESTNET thru Torrent (DEFAULT)" \
    C "COPY     --> BLOCKCHAINDATA from another node with SCP" \
    N "CLONE    --> BLOCKCHAINDATA from 2nd HDD (extra cable)"\
    S "SYNC     --> MAINNET thru Bitcoin Network (ULTRA SLOW)" 2>&1 >/dev/tty)

  # Litecoin
  elif [ ${network} = "litecoin" ]; then
    echo "Litecoin Options"
    menuitem=$(dialog --clear --beep --backtitle "RaspiBlitz" --title "Getting the Blockchain" \
    --menu "You need a copy of the Litecoin Blockchain - you have 3 options:" 13 75 4 \
    T "TORRENT  --> MAINNET thru Torrent (DEFAULT)" \
    S "SYNC     --> MAINNET thru Litecoin Network (FALLBACK+SLOW)" 2>&1 >/dev/tty)

  # error
  else
    echo "FAIL Unkown network(${network})"
    exit 1
   fi

  # set SetupState
  sudo sed -i "s/^setupStep=.*/setupStep=50/g" ${infoFile}

  clear
  case $menuitem in
          T)
              /home/admin/50torrentHDD.sh
              ;;
          C)
              /home/admin/50copyHDD.sh
              ;;
          N)
              /home/admin/50cloneHDD.sh
              ;;              
          S)
              /home/admin/50syncHDD.sh
              ;;
  esac
  exit 1

fi # end HDD is already auto-mountes


# the HDD is not auto-mounted --> very early stage of setup

# if the script is called for the first time
if [ ${setupStep} -eq 0 ]; then

  # run initial user dialog
  ./20setupDialog.sh

  # set SetupState
  sudo sed -i "s/^setupStep=.*/setupStep=20/g" ${infoFile}

fi

# the HDD is already ext4 formated and called blockchain
formatExt4OK=$(lsblk -o UUID,NAME,FSTYPE,SIZE,LABEL,MODEL | grep BLOCKCHAIN | grep -c ext4)
if [ ${formatExt4OK} -eq 1 ]; then
  echo "HDD was already initialized/prepared"
  echo "Now needs to be mounted"
  ./40addHDD.sh
  exit 1
fi

# the HDD had no init yet
echo "init HDD ..."
./30initHDD.sh
exit 1
