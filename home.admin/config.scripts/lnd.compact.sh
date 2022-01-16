#!/bin/bash

if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "# script to compact the LND channel.db"
  echo "# lnd.compact.sh <interactive>"
  exit 1
fi

# basic info
echo "###########################################"
echo "# lnd.compact.sh"


# check if HDD/SSD has enough space to run compaction (at least again the size as the channel.db at the moment)
channelDBsizeKB=$(sudo ls -l --block-size=K /mnt/hdd/lnd/data/graph/mainnet/channel.db | cut -d " " -f5 | tr -dc '0-9')
echo "# channelDBsizeKB(${channelDBsizeKB})"
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status)
echo "# hddDataFreeKB(${hddDataFreeKB})"
if [ "${channelDBsizeKB}" != "" ] && [ "${hddDataFreeKB}" != "" ] && [ ${hddDataFreeKB} -lt ${channelDBsizeKB} ]; then
  echo "error='HDD/SSD free space is too low to run LND compact'"
  exit 1
fi

# check if interactive
if [ "$1" = interactive ];then
  channelDBsizeHumanRead=$(sudo du -h /mnt/hdd/lnd/data/graph/mainnet/channel.db | awk '{print $1}')
  whiptail --title " Compact LND database? " \
	--yes-button "Yes" \
	--no-button "No" \
	--yesno "The current LND channel.db size: $channelDBsizeHumanRead
If compacting the database the first time it can take a long time, but can reduce the size a lot.\n
Do you want to compact the LND database now?" 11 60
	if [ "$?" != "0" ]; then
    # no
	  exit 1
	fi
fi

echo "###########################################"
echo "# Start compacting ...."
echo "# Can monitor the background process in a new window with:"
echo "# tail -f /home/admin/lnd.db.bolt.auto-compact.log"
echo

echo "# Stop LND"
sudo systemctl stop lnd

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

  # give up after 60 tries (10 minutes)
  if [ ${counter} -gt 60 ]; then
      echo
      echo "# FAIL: Takes too long ... giving up on --> Waiting for LND to start"
      echo "# SEE LOG: ---------------------------------------------------------"
      cat /home/admin/lnd.db.bolt.auto-compact.log
      sleep 10
      exit 1
  fi
done

counter=0
while [ $(sudo -u bitcoin lncli state | grep -c "WAITING_TO_START") -gt 0 ]; do
  echo
  echo "# Compacting channel.db, this can take a long time"
  echo "# Checking again in a minute (${counter})"
  echo
  counter=$((counter+1))
  sleep 60
  # give up after 60 tries (1 hour)
  if [ ${counter} -gt 60 ]; then
      echo "# FAIL: Takes too long ... giving up on --> Compacting channel.db"
      echo "# SEE LOG: ---------------------------------------------------------"
      cat /home/admin/lnd.db.bolt.auto-compact.log
      sleep 10
      exit 1
  fi
done

echo "# LND state:"
sudo -u bitcoin lncli state

sudo -u bitcoin pkill lnd 2>/dev/null

echo
echo "# Finished compacting."
echo "# Showing logs:"
cat /home/admin/lnd.db.bolt.auto-compact.log
echo
channelDBsize=$(sudo du -h /mnt/hdd/lnd/data/graph/mainnet/channel.db | awk '{print $1}')
echo "# The current channel.db size: $channelDBsize"
echo "# Exiting. Now can start LND again."

exit 0
