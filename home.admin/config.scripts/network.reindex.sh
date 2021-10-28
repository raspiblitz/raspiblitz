#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "script to run re-index if the blockchain (in case of repair)"
 echo "run to start or monitor re-index progress"
 exit 1
fi

# check and load raspiblitz config
# to know which network is running
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# if re-index is not running, start ...
source <(/home/admin/config.scripts/blitz.cache.sh get state)
if [ "${state}" != "reindex" ]; then

  # stop services
  echo "making sure services are not running .."
  sudo systemctl stop lnd 2>/dev/null
  sudo systemctl stop ${network}d 2>/dev/null

  # starting reindex
  echo "starting re-index ..."
  sudo -u bitcoin /usr/local/bin/${network}d -daemon -reindex -conf=/home/bitcoin/.${network}/${network}.conf -datadir=/home/bitcoin/.${network}

  # set reindex flag in raspiblitz.info (gets deleted after (final) reboot)
  sudo sed -i "s/^state=.*/state=reindex/g" /home/admin/raspiblitz.info

fi

# while loop to wait to finish
finished=0
progress=0
while [ ${finished} -eq 0 ]
  do
  clear
  echo "*************************"
  echo "REINDEXING BLOCKCHAIN"
  echo "*************************"
  date
  echo "THIS CAN TAKE SOME VERY LONG TIME"
  echo "See Raspiblitz FAQ: https://github.com/rootzoll/raspiblitz"
  echo "On question: My blockchain data is corrupted - what can I do?"
  echo "If you dont see any progress after 24h keep X pressed to stop."

  # get blockchain sync progress
  blockchaininfo=$(sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo)
  progress=$(echo "${blockchaininfo}" | jq -r '.verificationprogress')
  #progress=$(echo "${progress}*100" | bc)
  progress=$(echo $progress | awk '{printf( "%.2f%%", 100 * $1)}')
  inprogress="$(echo "${blockchaininfo}" | jq -r '.initialblockdownload')"
  if [ "${inprogress}" = "false" ]; then
    finished=1
  fi

  echo ""
  echo "RUNNING: ${inprogress}"
  echo "PROGRESS: ${progress}"
  echo ""

  echo "You can close terminal while reindex is running.."
  echo "But you have to login again to check if ready."

  # wait 2 seconds for key input
  read -n 1 -t 2 keyPressed

  # check if user wants to abort monitor
  if [ "${keyPressed}" = "x" ]; then
    echo "stopped by user ..."
    break
  fi

done


# trigger reboot when finished
echo "*************************"
if [ ${finished} -eq 0 ]; then
  echo "Re-Index CANCELED"
else 
  echo "Re-Index finished"
fi
echo "Starting reboot ..."
echo "*************************"
# stop bitcoind
sudo -u bitcoin ${network}-cli stop
sleep 4
# clean logs (to prevent a false reindex detection)
sudo rm /mnt/hdd/${network}/debug.log 2>/dev/null
# reboot
sudo /home/admin/config.scripts/blitz.shutdown.sh reboot