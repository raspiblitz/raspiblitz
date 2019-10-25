#!/bin/bash
echo ""

## get basic info
source /home/admin/raspiblitz.info

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
   sudo rm -r /home/bitcoin/.${network} 2>/dev/null
   sleep 2
   if [ -d /home/bitcoin/.${network} ]; then
     echo "FAIL - /home/bitcoin/.${network} exists and cannot be removed!"
     exit 1
   fi
   sudo cp /home/admin/assets/${network}.conf /mnt/hdd/${network}/${network}.conf
   sudo mkdir /home/admin/.${network} 2>/dev/null
   sudo cp /home/admin/assets/${network}.conf /home/admin/.${network}/${network}.conf
   sudo ln -s /mnt/hdd/${network} /home/bitcoin/.${network}
   sudo mkdir /mnt/hdd/lnd
   sudo chown -R bitcoin:bitcoin /mnt/hdd/lnd
   sudo chown -R bitcoin:bitcoin /mnt/hdd/${network}
   sudo ln -s /mnt/hdd/lnd /home/bitcoin/.lnd
   sudo chown -R bitcoin:bitcoin /home/bitcoin/.${network}
   sudo chown -R bitcoin:bitcoin /home/bitcoin/.lnd
   echo "OK - ${network} setup ready"

   ###### ACTIVATE TOR IF SET DURING SETUP
   if [ "${runBehindTor}" = "on" ]; then
     
     echo "runBehindTor --> ON"
     sudo /home/admin/config.scripts/internet.tor.sh on

     # but if IBD is allowed to be public switch off TOR just fro bitcoin 
     # until IBD is done. background service will after that switch TOR on
     if [ "${ibdBehindTor}" = "off" ]; then
       echo "ibdBehindTor --> OFF"
       sudo /home/admin/config.scripts/internet.tor.sh btcconf-off
     else
       echo "ibdBehindTor --> ON"
     fi

   else
     echo "runBehindTor --> OFF"
   fi

   ###### START NETWORK SERVICE
   echo ""
   echo "*** Start ${network} ***"
   echo "This can take a while .."
   sudo cp /home/admin/assets/${network}d.service /etc/systemd/system/${network}d.service
   #sudo chmod +x /etc/systemd/system/${network}d.service
   sudo systemctl daemon-reload
   sudo systemctl enable ${network}d.service
   sudo systemctl start ${network}d.service
   echo "Started ... wait 10 secs"	
   sleep 10

   # set SetupState
   sudo sed -i "s/^setupStep=.*/setupStep=60/g" /home/admin/raspiblitz.info

   ./10setupBlitz.sh

  else
    # HDD is empty - download HDD content
    echo "FAIL - HDD is empty."
  fi
else
  # HDD is not available yet
  echo "FAIL - HDD is not mounted."
fi