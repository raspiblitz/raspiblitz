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

# is bitcoind running
bitcoinRunning=$(systemctl status ${network}d.service 2>/dev/null | grep -c running)
echo "bitcoinActive=${bitcoinRunning}"

if [ ${bitcoinRunning} -eq 1 ]; then

  # get blockchain info
  blockchaininfo=$(sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo 2>/mnt/hdd/temp/.bitcoind.error)

  # check if error on request
  bitcoinError=$(cat /mnt/hdd/temp/.bitcoind.error 2>/dev/null)
  rm /mnt/hdd/temp/.bitcoind.error 2>/dev/null
  if [ ${#bitcoinError} -gt 0 ]; then
    echo "bitcoinErrorFull='${bitcoinError}'"
    echo "bitcoinErrorShort='${clienterror/error*:/}'"
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
fi

# is LND running
lndRunning=$(systemctl status lnd.service 2>/dev/null | grep -c running)

# TODO: check how long running ... try to find out if problem on starting

echo "lndActive=${lndRunning}"

if [ ${lndRunning} -eq 1 ]; then

  # get LND info
  lndinfo=$(sudo -u bitcoin lncli getinfo 2>/mnt/hdd/temp/.lnd.error)

  # check if error on request
  lndErrorFull=$(cat /mnt/hdd/temp/.lnd.error 2>/dev/null)
  rm /mnt/hdd/temp/.lnd.error 2>/dev/null
  if [ ${#lndError} -gt 0 ]; then
    echo "lndErrorFull='${lndErrorFull}'"
    echo "lndErrorShort=''"
  else
    
    # synced to chain
    syncedToChain=$(echo ${lndinfo} | jq -r '.synced_to_chain' | grep -c 'true')
    echo "syncedToChain=${syncedToChain}"

    # lnd scan progress
    scanTimestamp=$(echo ${lndinfo} | jq -r '.best_header_timestamp')
    echo "scanTimestamp=${scanTimestamp}"
    if [ ${#scanTimestamp} -gt 0 ]; then
      scanDate=$(date -d @${scanTimestamp})
      echo "scanDate='${scanDate}'"

      # calculate LND scan progress by seconds since Genesisblock
      genesisTimestamp=1230940800
      nowTimestamp=$(date +%s)
      totalSeconds=$(echo "${nowTimestamp}-${genesisTimestamp}" | bc)
      scannedSeconds=$(echo "${scanTimestamp}-${genesisTimestamp}" | bc)
      scanProgress=$(echo "scale=2; $scannedSeconds*100/$totalSeconds" | bc)
      echo "scanProgress=${scanProgress}"
    fi
    
  fi

fi

# check if online if problem with other stuff 

# info on scan run time
endTime=$(date +%s)
runTime=$(echo "${endTime}-${startTime}" | bc)
echo "scriptRuntime=${runTime}"


