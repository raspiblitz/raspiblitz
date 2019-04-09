#!/bin/bash

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 

### USER PI AUTOSTART (LCD Display)
localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

# parse the actual scanned height progress from LND logs
item=0
blockchaininfo=$(sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo)
chain="$(echo "${blockchaininfo}" | jq -r '.chain')"

## TRY to get the actual progress height of scanning

# 1) First try the "Rescanned through block" - it seems to happen if it restarts
item=$(sudo -u bitcoin tail -n 100 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep "Rescanned through block" | tail -n1 | cut -d ']' -f2 | cut -d '(' -f2 | tr -dc '0-9')
action="Rescanning"

# 2) Second try the "Caught up to height" - thats the usual on first scan start
if [ ${#item} -eq 0 ]; then
  item=$(sudo -u bitcoin tail -n 100 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep "Caught up to height" | tail -n1 | cut -d ']' -f2 | tr -dc '0-9')
  action="Catching-Up"
fi

# 3) Third try the "LNWL: Filtering block" - thats the usual on later starts
if [ ${#item} -eq 0 ]; then
  item=$(sudo -u bitcoin tail -n 100 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep "LNWL: Filtering block" | tail -n1 | cut -d ' ' -f7 | tr -dc '0-9')
  action="Filtering"
fi

# if no progress info
online=1
if [ ${#item} -eq 0 ]; then
  item="?" 

  # check if offline
  online=$(ping 1.0.0.1 -c 1 -W 2 | grep -c '1 received')
  if [ ${online} -eq 0 ]; then
    # re-test with other server
    online=$(ping 8.8.8.8 -c 1 -W 2 | grep -c '1 received')
  fi
  if [ ${online} -eq 0 ]; then
    # re-test with other server
    online=$(ping 208.67.222.222 -c 1 -W 2 | grep -c '1 received')
  fi

fi

# get total number of blocks
total=$(echo "${blockchaininfo}" | jq -r '.blocks')
# put scanstate
scanstate="${item}/${total}"

# get blockchain sync progress
progress="$(echo "${blockchaininfo}" | jq -r '.verificationprogress')"
#progress=$(echo "${progress}*100" | bc)
progress=$(echo $progress | awk '{printf( "%.2f%%", 100 * $1)}')

# check if blockchain is still syncing
heigh=6
width=44
isInitialChainSync=$(echo "${blockchaininfo}" | grep 'initialblockdownload' | grep "true" -c)
isWaitingBlockchain=$( sudo -u bitcoin tail -n 2 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep "Waiting for chain backend to finish sync" -c )
if [ ${isWaitingBlockchain} -gt 0 ]; then
  isInitialChainSync=1
fi
if [ ${online} -eq 0 ]; then
    heigh=7
    width=44
    infoStr=$(echo " Waiting INTERNET CONNECTION\n RaspiBlitz cannot ping 1.0.0.1\n Local IP is ${localip}\n Please check cables and router.")
elif [ ${isInitialChainSync} -gt 0 ]; then
  heigh=7
  infoStr=" Waiting for final Blockchain Sync\n Progress: ${progress} %\n Please wait - this can take some time.\n ssh admin@${localip}\n Password A"
  if [ "$USER" = "admin" ]; then
    heigh=6
    width=53
    infoStr=$(echo " Waiting for final Blockchain Sync\n Progress: ${progress} %\n Please wait - this can take some long time.\n Its OK to close terminal and ssh back in later.")
  fi
else
  heigh=7
  # check if wallet has any UTXO
  # reason see: https://github.com/lightningnetwork/lnd/issues/2326
  txlines=$(sudo -u bitcoin lncli listchaintxns 2>/dev/null | wc -l)
  # has just 4 lines if empty
  if [ ${txlines} -eq 4 ]; then
    infoStr=$(echo " Lightning ${action} Blockchain\n Progress: ${scanstate}\n re-rescan every start until funding\n ssh admin@${localip}\n Password A")
  else
    infoStr=$(echo " Lightning ${action} Blockchain\n Progress: ${scanstate}\n Please wait - this can take some time\n ssh admin@${localip}\n Password A")
    if [ "$USER" = "admin" ]; then
      heigh=6
      width=53
      infoStr=$(echo " Lightning ${action} Blockchain\n Progress: ${scanstate}\n Please wait - this can take some long time.\n Its OK to close terminal and ssh back in later.")
    fi
  fi
fi

# display progress to user
sleep 3
temp=$(echo "scale=1; $(cat /sys/class/thermal/thermal_zone0/temp)/1000" | bc)
dialog --title " ${network} / ${chain} " --backtitle "RaspiBlitz (${hostname})     CPU: ${temp}°C" --infobox "${infoStr}" ${heigh} ${width}