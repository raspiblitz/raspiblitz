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

    # install latest nodejs
    echo "*** Install NodeJS ***"
    cd /home/admin
    curl -sL https://deb.nodesource.com/setup_11.x | sudo -E bash -
    sudo apt-get install -y nodejs
    echo ""

    # check if nodeJS was installed 
    nodeJSInstalled=$(node -v | grep -c "v11.")
    if [ nodeJSInstalled -eq 0 ]; then
      echo "FAIL - Was not able to install nodeJS 11"
      echo "ABORT - RTL install"
      exit 1
    fi

    # download source code and set to tag release
    echo "*** Get the RTL Source Code ***"
    git clone https://github.com/ShahanaFarooqui/RTL.git
    cd RTL
    git reset --hard v0.2.15
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
    echo "OK - RTL is now ACTIVE"

  else 
    echo "RTL already installed."
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^rtlWebinterface=.*/rtlWebinterface=on/g" /mnt/hdd/raspiblitz.conf

  echo "needs reboot to activate new setting"
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

echo "FAIL - Unknown Paramter $1"
echo "may needs reboot to run normal again"
exit 1