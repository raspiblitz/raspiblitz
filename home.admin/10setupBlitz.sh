#!/bin/sh
echo ""

# load network
network=`cat .network`

# check chain
chain="test"
isMainChain=$(sudo cat /mnt/hdd/${network}/${network}.conf 2>/dev/null | grep "#testnet=1" -c)
if [ ${isMainChain} -gt 0 ];then
  chain="main"
fi

# get setup progress
setupStep=$(sudo -u admin cat /home/admin/.setup)
if [ ${#setupStep} -eq 0 ];then
  setupStep=0
fi

# if setup if ready --> REBOOT
if [ ${setupStep} -gt 89 ];then
  echo "FINISH by setupstep(${setupStep})"
  sleep 3
  ./90finishSetup.sh
  exit 0
fi

# CHECK WHAT IS ALREADY WORKING
# check list from top down - so ./10setupBlitz.sh
# and re-enters the setup process at the correct spot
# in case it got interrupted

# check if lightning is running
lndRunning=$(systemctl status lnd.service 2>/dev/null | grep -c running)
if [ ${lndRunning} -eq 1 ]; then
  
  echo "LND is running ..."
  sleep 1

  # check if LND is locked
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
    chainSyncing=$(echo "${chainInfo}" | grep "true" -c)
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
  ./90finishSetup.sh
  exit 0

fi

# check if bitcoin is running
bitcoinRunning=$(systemctl status ${network}d.service 2>/dev/null | grep -c running)
if [ ${bitcoinRunning} -eq 0 ]; then
  # double check
  bitcoinRunning=$(${network}-cli getblockchaininfo | grep "initialblockdownload" -c)
fi
if [ ${bitcoinRunning} -eq 1 ]; then
  echo "OK - ${network}d is running"
  echo "Next step run Lightning"
  ./70initLND.sh
  exit 1
fi

# check if HDD is mounted
mountOK=$( df | grep -c /mnt/hdd )
if [ ${mountOK} -eq 1 ]; then
  
  # are there any signs of blockchain data
  if [ -d "/mnt/hdd/${network}" ]; then

    echo "TAIL Chain Network Log"
    sudo tail /mnt/hdd/${network}/debug.log
    echo ""

    echo "UNKOWN STATE - there is blockain data folder, but blockchaind is not running"
    echo "It seems that something went wrong during sync/download/copy of the blockchain."
    echo "Or something with the config is not correct."
    echo "Sometimes a reboot helps --> sudo shutdown -r now"

    exit 1
  fi

  # check if there is a download to continue
  downloadProgressExists=$(sudo ls /home/admin/.Download.out 2>/dev/null | grep ".Download.out" -c)
  if [ ${downloadProgressExists} -eq 1 ]; then
    echo "found download in progress .."
    ./50downloadHDD.sh
    exit 1
  fi

  # HDD is empty - ask how to get Blockchain

  #Bitcoin
  if [ ${network} = "bitcoin" ]; then
    echo "Bitcoin Options"
    menuitem=$(dialog --clear --beep --backtitle "RaspiBlitz" --title "Getting the Blockchain" \
    --menu "You need a copy of the Bitcoin Blockchain - you have 3 options:" 13 75 4 \
    T "TORRENT  --> TESTNET + MAINNET thru Torrent (DEFAULT)" \
    D "DOWNLOAD --> TESTNET + MAINNET per FTP (FALLBACK)" \
    C "COPY     --> TESTNET + MAINNET from another HDD (TRICKY+FAST)" \
    S "SYNC     --> JUST TESTNET thru Bitoin Network (FALLBACK+SLOW)" 2>&1 >/dev/tty)

  # Litecoin
  elif [ ${network} = "litecoin" ]; then
    echo "Litecoin Options"
    menuitem=$(dialog --clear --beep --backtitle "RaspiBlitz" --title "Getting the Blockchain" \
    --menu "You need a copy of the Litecoin Blockchain - you have 3 options:" 13 75 4 \
    T "TORRENT  --> MAINNET thru Torrent (DEFAULT)" \
    D "DOWNLOAD --> MAINNET per FTP (FALLBACK)" \
    C "COPY     --> MAINNET from another HDD (TRICKY+FAST)" \
    S "SYNC     --> MAINNET thru Litecoin Network (FALLBACK+SLOW)" 2>&1 >/dev/tty)

  # error
  else
    echo "FAIL Unkown network(${network})"
    exit 1
   fi

  # set SetupState
  echo "50" > /home/admin/.setup

  clear
  case $menuitem in
          T)
              ./50torrentHDD.sh
              ;;
          C)
              ./50copyHDD.sh
              ;;
          S)
              ./50syncHDD.sh
              ;;
          D)
              ./50downloadHDD.sh
              ;;
  esac
  exit 1

fi


# the HDD is not mounted --> very early stage of setup

# if the script is called for the first time
if [ ! -f "home/admin/.setup" ]; then

  # run initial user dialog
  ./20initDialog.sh

  # set SetupState to 10
  echo "20" > /home/admin/.setup

  # update system
  echo ""
  echo "*** Update System ***"
  sudo apt-mark hold raspberrypi-bootloader
  sudo apt-get update
  sudo apt-get upgrade -f -y --allow-change-held-packages
  echo "OK - System is now up to date"
fi

# the HDD is already ext4 formated and called blockchain
formatExt4OK=$(lsblk -o UUID,NAME,FSTYPE,SIZE,LABEL,MODEL | grep BLOCKCHAIN | grep -c ext4)
if [ ${formatExt4OK} -eq 1 ]; then
  echo "HDD was already inited or prepared"
  echo "Now needs to be mounted"
  ./40addHDD.sh
  exit 1
fi

# the HDD had no init yet
echo "HDD needs init"
./30initHDD.sh
exit 1
