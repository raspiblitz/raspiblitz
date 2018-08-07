#!/bin/sh
echo ""

# load network
network=`cat .network`

echo "*** Checking HDD ***"
mountOK=$(df | grep -c /mnt/hdd)
if [ ${mountOK} -eq 1 ]; then
  # HDD is mounted
  if [ -d "/mnt/hdd/${network}" ]; then
    # HDD has content - continue 
    echo "OK - HDD is ready."

   ###### LINK HDD
   echo ""
   echo "*** Prepare ${network} ***"
   sudo killall -u bitcoin
   sleep 5
   sudo rm -r /home/bitcoin/.${network}
   sleep 2
   if [ -d /home/bitcoin/.${network} ]; then
     echo "FAIL - /home/bitcoin/.${network} exists and cannot be removed!"
     exit 1
   fi
   sudo cp /home/admin/assets/${network}.conf /mnt/hdd/${network}/${network}.conf
   sudo mkdir /home/admin/.${network}
   sudo cp /home/admin/assets/${network}.conf /home/admin/.${network}/${network}.conf
   sudo ln -s /mnt/hdd/${network} /home/bitcoin/.${network}
   sudo mkdir /mnt/hdd/lnd
   sudo chown -R bitcoin:bitcoin /mnt/hdd/lnd
   sudo chown -R bitcoin:bitcoin /mnt/hdd/${network}
   sudo ln -s /mnt/hdd/lnd /home/bitcoin/.lnd
   sudo chown -R bitcoin:bitcoin /home/bitcoin/.${network}
   sudo chown -R bitcoin:bitcoin /home/bitcoin/.lnd
   echo "OK - ${network} setup ready"

   ###### START NETWORK SERVICE
   echo ""
   echo "*** Start ${network} ***"
   echo "This can take a while .."
   sudo cp /home/admin/assets/${network}d.service /etc/systemd/system/${network}d.service
   sudo chmod +x /etc/systemd/system/${network}d.service
   sudo systemctl daemon-reload
   sudo systemctl enable ${network}d.service
   sudo systemctl start ${network}d.service
   echo "Giving ${network}d service 180 seconds to init - please wait ..."	
   sleep 180
   echo "OK - ${network}d started"
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