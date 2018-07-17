# parse the actual scanned height progress from LND logs
item=0
chain="$(bitcoin-cli -datadir=/home/bitcoin/.bitcoin getblockchaininfo | jq -r '.chain')"
gotData=$(sudo tail -n 100 /mnt/hdd/lnd/logs/bitcoin/${chain}net/lnd.log | grep -c height)
if [ ${gotData} -gt 0 ]; then
  item=$(sudo tail -n 100 /mnt/hdd/lnd/logs/bitcoin/${chain}net/lnd.log | grep height | tail -n1 | awk '{print $9} {print $10} {print $11} {print $12}' | tr -dc '0-9')  
fi

# get total number of blocks
total=$(bitcoin-cli -datadir=/home/bitcoin/.bitcoin getblockchaininfo | jq -r '.blocks')

# calculate progress in percent 
percent=$(awk "BEGIN { pc=100*${item}/${total}; i=int(pc); print (pc-i<0.5)?i:i+1 }") 
if [ ${percent} -e 100 ]; then
  # normally if 100% gets calculated, item parsed the wrong height
  percent=0
fi

# display progress to user
dialog --backtitle "RaspiBlitz" --infobox " Lightning Rescanning Blockchain $percent%\nplease wait - this can take some time" 4 42
