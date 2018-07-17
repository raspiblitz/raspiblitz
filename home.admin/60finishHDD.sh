#!/bin/sh
echo ""
echo "*** Checking HDD ***"
mountOK=$(df | grep -c /mnt/hdd)
if [ ${mountOK} -eq 1 ]; then
  # HDD is mounted
  if [ -d "/mnt/hdd/bitcoin" ]; then
    # HDD has content - continue 
    echo "OK - HDD is ready."

   ###### LINK HDD
   echo ""
   echo "*** Prepare Bitcoin ***"
   sudo cp /home/admin/assets/bitcoin.conf /mnt/hdd/bitcoin/bitcoin.conf
   sudo ln -s /mnt/hdd/bitcoin /home/bitcoin/.bitcoin
   sudo mkdir /mnt/hdd/lnd
   sudo chown -R bitcoin:bitcoin /mnt/hdd/lnd
   sudo ln -s /mnt/hdd/lnd /home/bitcoin/.lnd
   sudo chown -R bitcoin:bitcoin /home/bitcoin/.bitcoin
   sudo chown -R bitcoin:bitcoin /home/bitcoin/.lnd
   echo "OK - Bitcoin setup ready"

   ###### START BITCOIN SERVICE
   echo ""
   echo "*** Start Bitcoin ***"
   sudo systemctl enable bitcoind.service
   sudo systemctl start bitcoind.service
   echo "Giving bitcoind service 180 seconds to init - please wait ..."	
   sleep 180
   echo "OK - bitcoind started"
   sleep 2 

   # set SetupState
   echo "60" > /home/admin/.setup

   ./10setupBlitz.sh

  else
    # HDD is empty - download HDD content
    echo "FAIL - HDD is empty."
  fi
else
  # HDD is not available yet
  echo "FAIL - HDD is not mounted."
fi
