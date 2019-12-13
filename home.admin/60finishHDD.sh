#!/bin/bash

## get basic info
source /home/admin/raspiblitz.info

echo ""
echo "*** 60finishHDD.sh ***"

# use blitz.datadrive.sh to analyse HDD situation
source <(sudo /home/admin/config.scripts/blitz.datadrive.sh status ${network})
if [ ${#error} -gt 0 ]; then
  echo "FAIL blitz.datadrive.sh status --> ${error}"
  echo "Please report issue to the raspiblitz github."
  exit 1
fi

# check that data drive is mounted
if [ ${isMounted} -eq 0 ]; then
  echo "FAIL - HDD is not mounted."
  exit 1
fi

# check if blockchain exists
if [ ${hddGotBlockchain} -eq 0 ]; then
  echo "FAIL - HDD got no blockchain."
  exit 1
fi

###### COPY BASIC NETWORK CONFIG

echo ""
echo "*** Prepare ${network} ***"
sudo cp /home/admin/assets/${network}.conf /mnt/hdd/${network}/${network}.conf
sudo mkdir /home/admin/.${network} 2>/dev/null
sudo cp /home/admin/assets/${network}.conf /home/admin/.${network}/${network}.conf


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