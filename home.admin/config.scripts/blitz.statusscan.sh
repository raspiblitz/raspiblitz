#!/bin/bash

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "# script to scan the state of the system after setup"
 exit 1
fi

# measure time of scan
startTime=$(date +%s)

# macke sure temp folder on HDD is available and fro all usable
sudo mkdir /mnt/hdd/temp 2>/dev/null
sudo chmod 777 -R /mnt/hdd/temp 2>/dev/null

# localIP
localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
echo "localIP='${localip}'"

# temp
tempC=$(echo "scale=1; $(cat /sys/class/thermal/thermal_zone0/temp)/1000" | bc)
echo "tempCelsius='${tempC}'"

# uptime in seconds
uptime=$(awk '{printf("%d\n",$1 + 0.5)}' /proc/uptime)
echo "uptime=${uptime}"

# count restarts of bitcoind/litecoind
startcountBlockchain=$(cat systemd.blockchain.log 2>/dev/null | grep -c "STARTED")
echo "startcountBlockchain=${startcountBlockchain}"

# is bitcoind running
bitcoinRunning=$(systemctl status ${network}d.service 2>/dev/null | grep -c running)
echo "bitcoinActive=${bitcoinRunning}"

if [ ${bitcoinRunning} -eq 1 ]; then

  # get blockchain info
  sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo 1>/mnt/hdd/temp/.bitcoind.out 2>/mnt/hdd/temp/.bitcoind.error
  # check if error on request
  blockchaininfo=$(cat /mnt/hdd/temp/.bitcoind.out 2>/dev/null)
  bitcoinError=$(cat /mnt/hdd/temp/.bitcoind.error 2>/dev/null)
  #rm /mnt/hdd/temp/.bitcoind.error 2>/dev/null
  if [ ${#bitcoinError} -gt 0 ]; then
    bitcoinErrorShort=$(echo ${bitcoinError/error*:/} | sed 's/[^a-zA-Z0-9 ]//g')
    echo "bitcoinErrorShort='${bitcoinErrorShort}'"
    bitcoinErrorFull=$(echo ${bitcoinError} | tr -d "'")
    echo "bitcoinErrorFull='${bitcoinErrorFull}'"
  else

    ##############################
    # Get data from blockchaininfo
    ##############################

    # get total number of blocks
    total=$(echo ${blockchaininfo} | jq -r '.blocks')
    echo "blockchainHeight=${total}"
    
    # is initial sync of blockchain
    initialSync=$(echo ${blockchaininfo} | jq -r '.initialblockdownload' | grep -c 'true')
    echo "initialSync=${initialSync}"

    # get blockchain sync progress
    syncProgress="$(echo ${blockchaininfo} | jq -r '.verificationprogress')"
    syncProgress=$(echo $syncProgress | awk '{printf( "%.2f%%", 100 * $1)}' | tr '%' ' ' | tr -s " ")
    echo "syncProgress=${syncProgress}"

  fi
else

  # find out why Bitcoin not running

  pathAdd=""
  if [ "${chain}" = "test" ]; then
    pathAdd="/testnet3"
  fi

  #### POSSIBLE/SOFT PROBLEMS
  # place here in future analysis

  #### HARD PROBLEMS

  # LOW DISK SPACE
  lowDiskSpace=$(sudo tail -n 100 /mnt/hdd/${network}${pathAdd}/debug.log | grep -c "Error: Disk space is low!")
  if [ ${lowDiskSpace} -gt 0 ]; then
    bitcoinErrorShort="HDD DISK SPACE LOW"
    bitcoinErrorFull="HDD DISK SPACE LOW - check what data you can delete on HDD and restart"
  fi

  #### GENERIC ERROR FIND

  # if still no error identified - search logs for genereic error
  if [ ${#bitcoinErrorShort} -eq 0 ]; then
    bitcoinErrorFull=$(sudo tail -n 100 /mnt/hdd/${network}${pathAdd}/debug.log | grep -c "Error:" | tail -1 | tr -d "'")
    if [ ${#bitcoinErrorFull} -gt 0 ]; then
      bitcoinErrorShort="Error found in Logs"
    fi
  fi
   
  # output error if found
  if [ ${#bitcoinErrorShort} -gt 0 ]; then
    echo "bitcoinErrorShort='${bitcoinErrorShort}'"
    echo "bitcoinErrorFull='${bitcoinErrorFull}'"
    /home/admin/config.scripts/blitz.systemd.sh log blockchain "ERROR: ${bitcoinErrorShort}"
  fi

fi

# count restarts of bitcoind/litecoind
startcountLightning=$(cat systemd.lightning.log 2>/dev/null | grep -c "STARTED")
echo "startcountLightning=${startcountLightning}"

# is LND running
lndRunning=$(systemctl status lnd.service 2>/dev/null | grep -c running)
echo "lndActive=${lndRunning}"

if [ ${lndRunning} -eq 1 ]; then

  # get LND info
  lndinfo=$(sudo -u bitcoin lncli getinfo 2>/mnt/hdd/temp/.lnd.error)

  # check if error on request
  lndErrorFull=$(cat /mnt/hdd/temp/.lnd.error 2>/dev/null)
  lndErrorShort=''
  #rm /mnt/hdd/temp/.lnd.error 2>/dev/null

  if [ ${#lndErrorFull} -gt 0 ]; then

    # scan error for walletLocked as common error
    locked=$(echo ${lndErrorFull} | grep -c 'Wallet is encrypted')
    if [ ${locked} -gt 0 ]; then
      echo "walletLocked=1"
    else
      echo "walletLocked=0"

      # if not locked error - then 
      echo "lndErrorShort='Unkown Error - see logs'"
      lndErrorFull=$(echo ${lndErrorFull} | sed 's/[^a-zA-Z0-9 ]//g')
      echo "lndErrorFull='${lndErrorFull}'"
      /home/admin/config.scripts/blitz.systemd.sh log lightning "ERROR: ${lndErrorFull}"
    fi

  else
    
    # check if wallet is locked
    locked=$(echo ${lndinfo} | grep -c unlock)
    if [ ${locked} -gt 0 ]; then
      echo "walletLocked=1"
    else
      echo "walletLocked=0"
    fi

    # synced to chain
    syncedToChain=$(echo ${lndinfo} | jq -r '.synced_to_chain' | grep -c 'true')
    echo "syncedToChain=${syncedToChain}"

    # lnd scan progress
    scanTimestamp=$(echo ${lndinfo} | jq -r '.best_header_timestamp')
    if [ ${#scanTimestamp} -gt 0 ]; then
      echo "scanTimestamp=${scanTimestamp}"
      scanDate=$(date -d @${scanTimestamp})
      echo "scanDate='${scanDate}'"

      # calculate LND scan progress by seconds since Genesisblock
      genesisTimestamp=1230940800
      nowTimestamp=$(date +%s)
      totalSeconds=$(echo "${nowTimestamp}-${genesisTimestamp}" | bc)
      scannedSeconds=$(echo "${scanTimestamp}-${genesisTimestamp}" | bc)
      scanProgress=$(echo "scale=2; $scannedSeconds*100/$totalSeconds" | bc)
      echo "scanProgress=${scanProgress}"
    else
      echo "# was not able to parse 'best_header_timestamp' from: lncli getinfo"
      echo "scanTimestamp=-1"
    fi
    
  fi

fi

# check if online if problem with other stuff 

# info on scan run time
endTime=$(date +%s)
runTime=$(echo "${endTime}-${startTime}" | bc)
echo "scriptRuntime=${runTime}"