#!/bin/bash

# This script runs on every start calles by boostrap.service
# It makes sure that the system is configured like the
# default values or as in the config.
# For more details see background_raspiblitzSettings.md

# LOGFILE - store debug logs of bootstrap
# resets on every start
logFile="/home/admin/raspiblitz.log"

# INFOFILE - state data from bootstrap
# used by display and later setup steps
infoFile="/home/admin/raspiblitz.info"

echo "presync: waiting 2 secs" >> $logFile
sleep 2

echo "presync: copying files" >> $logFile
sudo cp /home/admin/assets/bitcoin.conf /mnt/hdd/bitcoin/bitcoin.conf
sudo cp /home/admin/assets/bitcoind.service /etc/systemd/system/bitcoind.service
sudo chmod +x /etc/systemd/system/bitcoind.service
sudo ln -s /mnt/hdd/bitcoin /home/bitcoin/.bitcoin
echo "presync: starting services" >> $logFile
sudo systemctl daemon-reload
sudo systemctl enable bitcoind.service
sudo systemctl start bitcoind.service
echo "presync: started" >> $logFile
  
# update info file
echo "state=presync" > $infoFile
echo "message='started pre-sync'" >> $infoFile
echo "device=${hddDeviceName}" >> $infoFile
