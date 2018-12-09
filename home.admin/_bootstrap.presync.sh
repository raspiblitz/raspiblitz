#!/bin/bash

# LOGFILE - store debug logs of bootstrap
# resets on every start
logFile="/home/admin/raspiblitz.log"

# INFOFILE - state data from bootstrap
# used by display and later setup steps
infoFile="/home/admin/raspiblitz.info"

#echo "presync: waiting 2 secs" >> $logFile
#sleep 2

# just in case an old presync did not shutdown properly
#sudo systemctl stop bitcoind.service 2>/dev/null
#sudo systemctl disable bitcoind.service 2>/dev/null

echo "presync: bitcoind" >> $logFile
#sudo cp /home/admin/assets/bitcoin.conf /mnt/hdd/bitcoin/bitcoin.conf
#sudo cp /home/admin/assets/bitcoind.service /etc/systemd/system/bitcoind.service
#sudo chmod +x /etc/systemd/system/bitcoind.service
#sudo ln -s /mnt/hdd/bitcoin /home/bitcoin/.bitcoin
#echo "presync: starting services" >> $logFile
#sudo systemctl daemon-reload
#sudo systemctl enable bitcoind.service
#sudo systemctl start bitcoind.service
sudo chown -R bitcoin:bitcoin /mnt/hdd/bitcoin
sudo -u bitcoin /usr/local/bin/bitcoind -daemon -conf=/home/admin/assets/bitcoin.conf -pid=/mnt/hdd/bitcoin/bitcoind.pid
echo "presync: started" >> $logFile
  
# update info file
echo "state=presync" > $infoFile
sudo sed -i "s/^message=.*/message='running pre-sync'/g" ${infoFile}
