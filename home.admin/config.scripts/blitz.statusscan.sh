#!/bin/bash

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# LNTYPE is lnd | cln
if [ $# -gt 0 ];then
  LNTYPE=$1
else
  LNTYPE=lnd
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars $LNTYPE ${chain}net)

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
localip=$(hostname -I | awk '{print $1}')
echo "localIP='${localip}'"

# temp - no measurement in a VM
tempC=0
if [ -d "/sys/class/thermal/thermal_zone0/" ]; then
  tempC=$(echo "scale=1; $(cat /sys/class/thermal/thermal_zone0/temp)/1000" | bc)
  echo "tempCelsius='${tempC}'"
fi

# uptime in seconds
uptime=$(awk '{printf("%d\n",$1 + 0.5)}' /proc/uptime)
echo "uptime=${uptime}"

# get UPS info (if configured)
/home/admin/config.scripts/blitz.ups.sh status

# count restarts of bitcoind/litecoind
startcountBlockchain=$(cat /home/admin/systemd.blockchain.log 2>/dev/null | grep -c "STARTED")
echo "startcountBlockchain=${startcountBlockchain}"

# is bitcoind running
bitcoinRunning=$(systemctl status ${network}d.service 2>/dev/null | grep -c running)
echo "bitcoinActive=${bitcoinRunning}"

if [ ${bitcoinRunning} -eq 1 ]; then

  # get blockchain info
  $bitcoincli_alias getblockchaininfo 1>/mnt/hdd/temp/.bitcoind.out 2>/mnt/hdd/temp/.bitcoind.error
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

    ###################################
    # Get data from blockchain network
    ###################################

    source <(sudo -u bitcoin /home/admin/config.scripts/network.monitor.sh peer-status)
    echo "blockchainPeers=${peers}"

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
  lowDiskSpace=$(sudo tail -n 100 /mnt/hdd/${network}${pathAdd}/debug.log 2>/dev/null | grep -c "Error: Disk space is low!")
  if [ ${lowDiskSpace} -gt 0 ]; then
    bitcoinErrorShort="HDD DISK SPACE LOW"
    bitcoinErrorFull="HDD DISK SPACE LOW - check what data you can delete on HDD and restart"
  fi

  #### GENERIC ERROR FIND

  # if still no error identified - search logs for generic error (after 4min uptime)
  if [ ${#bitcoinErrorShort} -eq 0 ] && [ ${uptime} -gt 240 ]; then
    bitcoinErrorFull=$(sudo tail -n 100 /mnt/hdd/${network}${pathAdd}/debug.log 2>/dev/null | grep -c "Error:" | tail -1 | tr -d "'")
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
startcountLightning=$(cat /home/admin/systemd.lightning.log 2>/dev/null | grep -c "STARTED")
echo "startcountLightning=${startcountLightning}"

# is LND running
lndRunning=$(systemctl status ${netprefix}lnd.service 2>/dev/null | grep -c running)
echo "lndActive=${lndRunning}"

if [ ${lndRunning} -eq 1 ]; then

  # get LND info
  lndRPCReady=1
  lndinfo=$($lncli_alias getinfo 2>/mnt/hdd/temp/.lnd.error)
  
  # check if error on request
  lndErrorFull=$(cat /mnt/hdd/temp/.lnd.error 2>/dev/null)
  lndErrorShort=''
  #rm /mnt/hdd/temp/.lnd.error 2>/dev/null

  if [ ${#lndErrorFull} -gt 0 ]; then

    # flag if error could be resoled by analysis
    errorResolved=0

    ### analyse LND logs since start

    # find a the line number in logs of start of LND
    # just do this on error case to save on processing memory
    lndStartLineNumber=$(sudo cat /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log 2>/dev/null | grep -in "LTND: Active chain:" | tail -1 | cut -d ":" -f1)

    # get logs of last LND start
    lndLogsAfterStart=$(sudo tail --lines=+${lndStartLineNumber} /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log 2>/dev/null) 

    # check RPC server ready (can take some time after wallet was unlocked)
    lndRPCReady=$(echo "${lndLogsAfterStart}" | grep -c "RPCS: RPC server listening on")
    echo "lndRPCReady=${lndRPCReady}"

    # check wallet if wallet was opened (after correct password)
    lndWalletOpened=$(echo "${lndLogsAfterStart}" | grep -c "LNWL: Opened wallet")
    echo "walletOpened=${lndWalletOpened}"

    # check wallet if wallet is ready (can take some time after wallet was opened)
    lndWalletReady=$(echo "${lndLogsAfterStart}" | grep -c "LTND: LightningWallet opened")
    echo "walletReady=${lndWalletReady}"

    ### check errors

    # scan error for walletLocked as common error
    locked=$(echo ${lndErrorFull} | grep -c 'Wallet is encrypted')
    if [ ${locked} -gt 0 ]; then
      echo "walletLocked=1"
    else
      echo "walletLocked=0"

      rpcNotWorking=$(echo ${lndErrorFull} | grep -c 'connection refused')
      if [ ${rpcNotWorking} -gt 0 ]; then

        # this can happen for a long time when LND is starting fresh sync
        # on first startup - check if logs since start signaled RPC ready before
        if [ ${lndRPCReady} -eq 0 ]; then
          # nullify error - this is normal
          lndErrorFull=""
          errorResolved=1
          # oputput basic data because no error
          echo "# LND RPC is still warming up - no scan progress: prepare scan"
          echo "scanTimestamp=-2"
          echo "syncedToChain=0"
        else
          echo "# LND RPC was started - some other problem going on"
          lndErrorShort='LND RPC not responding'
          lndErrorFull=$(echo "LND RPC is not responding. LND may have problems starting up. Check logs, config files and systemd service. Org-Error: ${lndErrorFull}" | tr -d "'")
        fi   
      fi

      # if not known error and not resolved before - keep generic
      if [ ${#lndErrorShort} -eq 0 ] && [ ${errorResolved} -eq 0 ]; then
        lndErrorShort='Unkown Error - see logs'
        lndErrorFull=$(echo ${lndErrorFull} | tr -d "'")
      fi

      # write to results
      if [ ${#lndErrorFull} -gt 0 ]; then
        echo "lndErrorShort='${lndErrorShort}'"
        echo "lndErrorFull='${lndErrorFull}'"
        /home/admin/config.scripts/blitz.systemd.sh log lightning "ERROR: ${lndErrorFull}"
      fi

    fi

  else
    
    # check if wallet is locked
    locked=$(echo ${lndinfo} | grep -c unlock)
    if [ ${locked} -gt 0 ]; then
      echo "walletLocked=1"
    else
      echo "walletLocked=0"
    fi

    # number of lnd peers
    lndPeers=$(echo ${lndinfo} | jq -r '.num_peers')
    echo "lndPeers=${lndPeers}"

    # synced to chain
    syncedToChain=$(echo ${lndinfo} | jq -r '.synced_to_chain' | grep -c 'true')
    echo "syncedToChain=${syncedToChain}"

    # lnd scan progress
    scanTimestamp=$(echo ${lndinfo} | jq -r '.best_header_timestamp')
    nowTimestamp=$(date +%s)
    if [ ${#scanTimestamp} -gt 0 ] && [ ${scanTimestamp} -gt ${nowTimestamp} ]; then
      scanTimestamp=${nowTimestamp}
    fi
    if [ ${#scanTimestamp} -gt 0 ]; then
      echo "scanTimestamp=${scanTimestamp}"
      scanDate=$(date -d @${scanTimestamp} 2>/dev/null)
      echo "scanDate='${scanDate}'"
      
      # calculate LND scan progress by seconds since Genesisblock
      genesisTimestamp=1230940800

      totalSeconds=$(echo "${nowTimestamp}-${genesisTimestamp}" | bc)
      scannedSeconds=$(echo "${scanTimestamp}-${genesisTimestamp}" | bc)
      scanProgress=$(echo "scale=2; $scannedSeconds*100/$totalSeconds" | bc)
      echo "scanProgress=${scanProgress}"
    else
      echo "# was not able to parse 'best_header_timestamp' from: lncli getinfo"
      echo "scanTimestamp=-1"
    fi
    
  fi

  # output if lnd-RPC is ready
  echo "lndRPCReady=${lndRPCReady}"

fi

# is CLN running
clnRunning=$(systemctl status ${netprefix}lightningd.service 2>/dev/null | grep -c running)
echo "clnActive=${clnRunning}"
if [ ${clnRunning} -eq 1 ]; then

  clnInfo=$(${netprefix}lightning-cli getinfo)
  clnBlockHeight=$(echo "${clnInfo}" | jq -r '.blockheight' | tr -cd '[[:digit:]]')
  echo "clnBlockHeight=${clnBlockHeight}"
  echo "# TODO: cln status statistics"
fi

# touchscreen statistics
if [ "${touchscreen}" == "1" ]; then
  echo "blitzTUIActive=1"
  if [ ${#blitzTUIRestarts} -gt 0 ]; then
    echo "blitzTUIRestarts=${blitzTUIRestarts}"
  else
    echo "blitzTUIRestarts=0"
  fi
else
  echo "blitzTUIActive=0"
  echo "blitzTUIRestarts=0"
fi

# check if runnig in vagrant
vagrant=$(df | grep -c "/vagrant")
echo "vagrant=${vagrant}"

# check if online if problem with other stuff 

# info on scan run time
endTime=$(date +%s)
runTime=$(echo "${endTime}-${startTime}" | bc)
echo "scriptRuntime=${runTime}"
