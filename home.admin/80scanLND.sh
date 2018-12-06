source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf 2>/dev/null

### USER PI AUTOSTART (LCD Display)
localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

# parse the actual scanned height progress from LND logs
item=0
blockchaininfo=$(sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo)
chain="$(echo "${blockchaininfo}" | jq -r '.chain')"

## TRY to get the actual progress height of scanning

# 1) First try the "Rescanned through block" - it seems to happen if it restarts
item=$(sudo -u bitcoin tail -n 100 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep "Rescanned through block" | tail -n1 | cut -d ']' -f2 | cut -d '(' -f2 | tr -dc '0-9')

# 2) Second try the "Caught up to height" - thats the usual on first scan start
if [ ${#item} -eq 0 ]; then
  item=$(sudo -u bitcoin tail -n 100 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep "Caught up to height" | tail -n1 | cut -d ']' -f2 | tr -dc '0-9')
fi

# TODO next fallback try later here if necessary
if [ ${#item} -eq 0 ]; then
  item="?" 
fi

# get total number of blocks
total=$(echo "${blockchaininfo}" | jq -r '.blocks')
# put scanstate
scanstate="${item}/${total}"

# get blockchain sync progress
progress="$(echo "${blockchaininfo}" | jq -r '.verificationprogress')"

# check if blockchain is still syncing
heigh=6
width=44
isInitialChainSync=$(echo "${blockchaininfo}" | grep 'initialblockdownload' | grep "true" -c)
isWaitingBlockchain=$( sudo -u bitcoin tail -n 2 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep "Waiting for chain backend to finish sync" -c )
if [ ${isWaitingBlockchain} -gt 0 ]; then
  isInitialChainSync=1
fi
if [ ${isInitialChainSync} -gt 0 ]; then
  heigh=7
  infoStr=" Waiting for final Blockchain Sync\n Progress: ${progress}\n Please wait - this can take some time.\n ssh admin@${localip}\n Password A"
  if [ "$USER" = "admin" ]; then
    heigh=6
    width=53
    infoStr=$(echo " Waiting for final Blockchain Sync\n Progress: ${progress}\n Please wait - this can take some long time.\n Its OK to close terminal and ssh back in later.")
  fi
else
  heigh=7
  infoStr=$(echo " Lightning Rescanning Blockchain\n Progress: ${scanstate}\n Please wait - this can take some time\n ssh admin@${localip}\n Password A")
  if [ "$USER" = "admin" ]; then
    heigh=6
    width=53
    infoStr=$(echo " Lightning Rescanning Blockchain\n Progress: ${scanstate}\n Please wait - this can take some long time.\n Its OK to close terminal and ssh back in later.")
  fi
fi

# display progress to user
sleep 3
dialog --title " ${network} / ${chain} " --backtitle "RaspiBlitz (${name})" --infobox "${infoStr}" ${heigh} ${width}