# load network
network=`sudo cat /home/admin/.network`

# load name of Blitz
name=`sudo cat /home/admin/.hostname`

### USER PI AUTOSTART (LCD Display)
localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')

# parse the actual scanned height progress from LND logs
item=0
chain="$(sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo | jq -r '.chain')"
gotData=$(sudo -u bitcoin tail -n 100 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep -c "(height")
if [ ${gotData} -gt 0 ]; then
  item=$(sudo -u bitcoin tail -n 100 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep "(height" | tail -n1 | awk '{print $10} {print $11} {print $12}' | tr -dc '0-9')  
fi

# get total number of blocks
total=$(sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo | jq -r '.blocks')

# calculate progress in percent 
percent=$(awk "BEGIN { pc=100*${item}/${total}; i=int(pc); print (pc-i<0.5)?i:i+1 }") 
if [ ${percent} -eq 100 ]; then
  # normally if 100% gets calculated, item parsed the wrong height
  percent=0
fi

infoStr=$(echo " Lightning Rescanning Blockchain ${percent}%\nplease wait - this can take some time\nssh admin@${localip}\nPassword A")
heigh=4
if [ "$USER" = "admin" ]; then
  heigh=6
  infoStr=$(echo " Lightning Rescanning Blockchain ${percent}%\nplease wait - this can take some time\nIts OK to close terminal and ssh back in later.")
fi

# check if blockchain is still syncing
isWaitingBlockchain=$( sudo -u bitcoin tail -n 2 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep "Waiting for chain backend to finish sync" -c )
if [ ${isWaitingBlockchain} -gt 0 ]; then
  infoStr=" Waiting for final Blockchain Sync\nplease wait - this can take some time"
fi

# display progress to user
sleep 1
dialog --title " ${network} / ${chain} " --backtitle "RaspiBlitz (${name})" --infobox "${infoStr}" ${heigh} 42