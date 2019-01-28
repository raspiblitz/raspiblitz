#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "script to run re-index if the blockchain (in case of repair)"
 echo "run to start or monitor re-index progress"
 exit 1
fi

# check and load raspiblitz config
# to know which network is running
source /mnt/hdd/raspiblitz.conf 2>/dev/null
if [ ${#network} -eq 0 ]; then
 echo "FAIL - missing /mnt/hdd/raspiblitz.conf"
 exit 1
fi

# load raspiblitz.info to know if reindex is already running
source /home/admin/raspiblitz.info 2>/dev/null
if [ ${#state} -eq 0 ]; then
 echo "FAIL - missing /home/admin/raspiblitz.info"
 exit 1
fi

# if re-index is not running, start ...
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
while [ ${finished} -eq 0 ]
  do
  clear
  echo "*************************"
  echo "REINDEXING BLOCKCHAIN"
  echo "*************************"
  echo "THIS CAN TAKE SOME LONG TIME"
  echo "If you dont see any progress after 24h press X to stop."

  #TODO: detect and display progress
  #TODO: determine when finished and then finished=1

done

# trigger reboot when finished
echo "*************************"
echo "Re-Index finished"
echo "Starting reboot ..."
echo "*************************"
# clean logs (to prevent a false reindex detection)
sudo rm /mnt/hdd/${network}/debug.log
# reboot
sudo shutdown -r now