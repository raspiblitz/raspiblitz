#!/bin/sh
echo ""

# CHECK WHAT IS ALREADY WORKING
# check list from top down - so ./10setupBlitz.sh
# and re-enters the setup process at the correct spot
# in case it got interrupted

# check if lightning is running
lndRunning=$(systemctl status lnd.service | grep -c running)
if [ ${lndRunning} -eq 1 ]; then

  chain=$(bitcoin-cli -datadir=/home/bitcoin/.bitcoin getblockchaininfo | jq -r '.chain')
  locked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/bitcoin/${chain}net/lnd.log | grep -c unlock)
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
bitcoinRunning=$(systemctl status bitcoind.service | grep -c running)
if [ ${bitcoinRunning} -eq 1 ]; then
  echo "OK - Bitcoind is running"
  echo "Next step run Lightning"
  ./70initLND.sh
  exit 1
fi

# check if HDD is mounted
mountOK=$(df | grep -c /mnt/hdd)
if [ ${mountOK} -eq 1 ]; then

  # if there are signs of blockchain data
  if [ -d "/mnt/hdd/bitcoin" ]; then
    echo "UNKOWN STATE"
    echo "It seems that something went wrong during sync/download/copy of the blockchain."
    echo "Maybe try --> ./60finishHDD.sh"
    exit 1
  fi

  # HDD is empty - ask how to get Blockchain
  _temp="./download/dialog.$$"
  dialog --clear --beep --backtitle "RaspiBlitz" --title "Getting the Blockchain" \
  --menu "You need a copy of the Blockchan - you have 3 options:" 13 75 4 \
  1 "DOWNLOAD --> TESTNET + MAINNET thru torrent (RECOMMENDED 8h)" \
  2 "COPY     --> TESTNET + MAINNET from another HDD (TRICKY 3h)" \
  3 "SYNC     --> JUST TESTNET thru Bitoin Network (FALLBACK)" 2>$_temp
  opt=${?}
  clear
  if [ $opt != 0 ]; then rm $_temp; exit; fi
  menuitem=`cat $_temp`
  rm $_temp
  case $menuitem in
          3)
              ./50syncHDD.sh
              ;;
          1)
              ./50downloadHDD.sh
              ;;
          2)
              ./50copyHDD.sh
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
