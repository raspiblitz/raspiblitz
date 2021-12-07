#!/bin/bash

if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "# script to compact the LND channel.db"
  echo "# lnd.compact.sh <interactive>"
  exit 1
fi

channelDBsize=$(sudo du -h /mnt/hdd/lnd/data/graph/mainnet/channel.db | awk '{print $1}')
echo
echo "The current channel.db size: $channelDBsize"
echo "If compacting the database the first time it can take a long time, but reduces the size 2-3 times."
echo "Can monitor the background process in a new window with:"
echo "'tail -f /home/admin/lnd.db.bolt.auto-compact.log'"

if [ "$1" = interactive ];then
  read -p "Do you want to compact the database now (yes/no) ?" confirm && [[ $confirm == [yY]||$confirm == [yY][eE][sS] ]]||exit 1
fi

echo "# Stop LND"
sudo systemctl stop lnd

trap "exit" INT TERM ERR
trap "kill 0" EXIT

echo "# Run LND with --db.bolt.auto-compact"
sudo -u bitcoin /usr/local/bin/lnd --configfile=/home/bitcoin/.lnd/lnd.conf --db.bolt.auto-compact > /home/admin/lnd.db.bolt.auto-compact.log &

echo "# Compacting channel.db, this can take a long time"

counter=0
while [ $(sudo -u bitcoin lncli state 2>&1 | grep -c "connection refused") -gt 0 ]; do
  echo
  echo "# Waiting for LND to start "
  echo "# Checking again in 10 seconds (${counter})"
  counter=$((counter+1))
  sleep 10
done

echo "# LND state:"
sudo -u bitcoin lncli state

counter=0
while [ $(sudo -u bitcoin lncli state | grep -c "WAITING_TO_START") -gt 0 ]; do
  echo
  echo "# Compacting channel.db, this can take a long time"
  echo "# Checking again in a minute (${counter})"
  echo
  counter=$((counter+1))
  sleep 60
done

echo "# LND state:"
sudo -u bitcoin lncli state

sudo killall lnd >> /home/admin/lnd.db.bolt.auto-compact.log 2>&1

echo
echo "# Finished compacting."
echo "# Showing logs:"
cat /home/admin/lnd.db.bolt.auto-compact.log
echo
channelDBsize=$(sudo du -h /mnt/hdd/lnd/data/graph/mainnet/channel.db | awk '{print $1}')
echo "# The current channel.db size: $channelDBsize"
echo "# Exiting. Now can start LND again."

exit 0
