#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to switch WebGUI RideTheLightning on or off"
 echo "bonus.rtl.sh [on|off]"
 exit 1
fi

# check and load raspiblitz config
# to know which network is running
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then
 echo "FAIL - missing /mnt/hdd/raspiblitz.conf"
 exit 1
fi

# add default value to raspi config if needed
if [ ${#rtlWebinterface} -eq 0 ]; then
  echo "rtlWebinterface=off" >> /mnt/hdd/raspiblitz.conf
fi

# stop services
echo "making sure services are not running"
sudo systemctl stop RTL 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL RTL ***"

  isInstalled=$(sudo ls /etc/systemd/system/RTL.service 2>/dev/null | grep -c 'RTL.service')
  if [ ${isInstalled} -eq 0 ]; then

    # check and install NodeJS
    /home/admin/config.scripts/bonus.nodejs.sh

    # download source code and set to tag release
    echo "*** Get the RTL Source Code ***"
    rm -r /home/admin/RTL 2>/dev/null
    git clone https://github.com/ShahanaFarooqui/RTL.git /home/admin/RTL
    cd /home/admin/RTL
    git reset --hard v0.5.4
    # check if node_modles exists now
    if [ -d "/home/admin/RTL" ]; then
     echo "OK - RTL code copy looks good"
    else
      echo "FAIL - code copy did not run correctly"
      echo "ABORT - RTL install"
      exit 1
    fi
    echo ""
    

    # install
    echo "*** Run: npm install ***"
    export NG_CLI_ANALYTICS=false
    npm install
    cd ..
    # check if node_modles exists now
    if [ -d "/home/admin/RTL/node_modules" ]; then
     echo "OK - RTL install looks good"
    else
      echo "FAIL - npm install did not run correctly"
      echo "ABORT - RTL install"
      exit 1
    fi
    echo ""

    # prepare RTL.conf file
    echo "*** RTL.conf ***"
    cp ./RTL/sample-RTL.conf ./RTL/RTL.conf
    sudo sed -i "s/^macroonPath=.*/macroonPath=\/mnt\/hdd\/lnd\/data\/chain\/${network}\/${chain}net/g" ./RTL/RTL.conf
    sudo sed -i "s/^lndConfigPath=.*/lndConfigPath=\/mnt\/hdd\/lnd\/lnd.conf/g" ./RTL/RTL.conf
    sudo sed -i "s/^nodeAuthType=.*/nodeAuthType=DEFAULT/g" ./RTL/RTL.conf
    sudo sed -i "s/^rtlPass=.*/rtlPass=/g" ./RTL/RTL.conf
    echo ""

    # open firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow 3000
    sudo ufw --force enable
    echo ""

    # install service
    echo "*** Install RTL systemd for ${network} on ${chain} ***"
    sudo cp /home/admin/assets/RTL.service /etc/systemd/system/RTL.service
    sudo sed -i "s|chain/bitcoin/mainnet|chain/${network}/${chain}net|" /etc/systemd/system/RTL.service
    sudo systemctl enable RTL
    echo "OK - the RTL service is now enabled"

  else 
    echo "RTL already installed."
  fi
  
  # start service
  echo "Starting service"
  sudo systemctl start RTL 2>/dev/null

  # setting value in raspi blitz config
  sudo sed -i "s/^rtlWebinterface=.*/rtlWebinterface=on/g" /mnt/hdd/raspiblitz.conf

  # Hidden Service for RTL if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    isRTLTor=$(sudo cat /etc/tor/torrc 2>/dev/null | grep -c 'RTL')
    if [ ${isRTLTor} -eq 0 ]; then
      echo "
# Hidden Service for RTL
HiddenServiceDir /mnt/hdd/tor/RTL
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:3000
      " | sudo tee -a /etc/tor/torrc
  
      sudo systemctl restart tor
      sleep 2
    else
      echo "The Hidden Service is already installed"
    fi
  
    TOR_ADDRESS=$(sudo cat /mnt/hdd/tor/RTL/hostname)
    if [ -z "$TOR_ADDRESS" ]; then
      echo "Waiting for the Hidden Service"
      sleep 10
      TOR_ADDRESS=$(sudo cat /mnt/hdd/tor/RTL/hostname)
        if [ -z "$TOR_ADDRESS" ]; then
          echo " FAIL - The Hidden Service address could not be found - Tor error?"
          exit 1
        fi
    fi    
    echo ""
    echo "***"
    echo "The Tor Hidden Service address for RTL is:"
    echo "$TOR_ADDRESS"
    echo "***"
    echo "" 
  fi
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^rtlWebinterface=.*/rtlWebinterface=off/g" /mnt/hdd/raspiblitz.conf

  isInstalled=$(sudo ls /etc/systemd/system/RTL.service 2>/dev/null | grep -c 'RTL.service')
  if [ ${isInstalled} -eq 1 ]; then
    echo "*** REMOVING RTL ***"
    sudo systemctl stop RTL
    sudo systemctl disable RTL
    sudo rm /etc/systemd/system/RTL.service
    sudo rm -r /home/admin/RTL
    echo "OK RTL removed."
  else 
    echo "RTL is not installed."
  fi

  echo "needs reboot to activate new setting"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
echo "may need reboot to run normal again"
exit 1
