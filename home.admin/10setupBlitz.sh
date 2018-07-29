#!/bin/sh
echo ""

# load network
network=`cat .network`

# CHECK WHAT IS ALREADY WORKING
# check list from top down - so ./10setupBlitz.sh
# and re-enters the setup process at the correct spot
# in case it got interrupted

# check if lightning is running
lndRunning=$(systemctl status lnd.service | grep -c running)
if [ ${lndRunning} -eq 1 ]; then

  chain=$(${network}-cli -datadir=/home/${network}/.${network} getblockchaininfo | jq -r '.chain')
  locked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep -c unlock)
  lndSyncing=$(sudo -u bitcoin lncli getinfo | jq -r '.synced_to_chain' | grep -c false)
  if [ ${locked} -gt 0 ]; then
    # LND wallet is locked
    ./AAunlockLND.sh
    ./10setupBlitz.sh
  elif [ ${lndSyncing} -gt 0 ]; then
    ./70initLND.sh
  else
    ./90finishSetup.sh
  fi
  exit 1
fi

# check if bitcoin is running
bitcoinRunning=$(sudo -u bitcoin ${network}-cli getblockchaininfo | grep -c blocks)
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
    echo "UNKOWN STATE"
    echo "It seems that something went wrong during sync/download/copy of the blockchain."
    echo "Maybe try --> ./60finishHDD.sh"
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
  sudo apt-get upgrade -f -y --force-yes
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
