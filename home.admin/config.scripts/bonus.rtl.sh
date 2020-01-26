#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to switch WebGUI RideTheLightning on or off"
 echo "bonus.rtl.sh [on|off|menu]"
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

# show info menu
if [ "$1" = "menu" ]; then
  localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  torInfo="\nActivate TOR to access the web interface from outside your local network."
  toraddress=$(sudo cat /mnt/hdd/tor/RTL/hostname 2>/dev/null)
  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    torInfo="\nHidden Service address for TOR Browser (QR see LCD):\n${toraddress}"
    /home/admin/config.scripts/blitz.lcd.sh qr "${toraddress}"
  fi
  whiptail --title " Ride The Lightning (RTL)" --msgbox "Open the following URL in your local web browser:
http://${localip}:3000
Use your Password B to login.
${torInfo}
" 12 67
  echo "please wait ..."
  /home/admin/config.scripts/blitz.lcd.sh hide
  exit 0
fi

# add default value to raspi config if needed
if ! grep -Eq "^rtlWebinterface=" /mnt/hdd/raspiblitz.conf; then
  echo "rtlWebinterface=off" >> /mnt/hdd/raspiblitz.conf
fi

# stop services
echo "making sure services are not running"
sudo systemctl stop RTL 2>/dev/null

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "*** INSTALL RTL ***"

  isInstalled=$(sudo ls /etc/systemd/system/RTL.service 2>/dev/null | grep -c 'RTL.service')
  if ! [ ${isInstalled} -eq 0 ]; then
    echo "RTL already installed."

  else
    # check and install NodeJS
    /home/admin/config.scripts/bonus.nodejs.sh

    # check for Python2 (install if missing)
    # TODO remove Python2 ASAP!
    echo "*** Check for Python2 ***"
    /usr/bin/which python2 &>/dev/null
    if ! [ $? -eq 0 ]; then
      echo "*** Install Python2 ***"
      sudo apt-get update
      sudo apt-get install -y python2
    fi

    # download source code and set to tag release
    echo "*** Get the RTL Source Code ***"
    rm -r /home/admin/RTL 2>/dev/null
    git clone https://github.com/ShahanaFarooqui/RTL.git /home/admin/RTL
    cd /home/admin/RTL
    git reset --hard v0.6.3
    # from https://github.com/Ride-The-Lightning/RTL/commits/master
    # git checkout 917feebfa4fb583360c140e817c266649307ef72
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
    npm install --only=production
    cd ..
    # check if node_modules exist now
    if [ -d "/home/admin/RTL/node_modules" ]; then
     echo "OK - RTL install looks good"
    else
      echo "FAIL - npm install did not run correctly"
      echo "ABORT - RTL install"
      exit 1
    fi
    echo ""

    # now remove Python2 again
    echo "*** Now remove Python2 again ***"
    sudo apt-get purge -y python2
    sudo apt-get autoremove -y

    # prepare RTL.conf file
    echo "*** RTL.conf ***"
    cp ./RTL/sample-RTL.conf ./RTL/RTL.conf
    chmod 600 ./RTL/RTL.conf || exit 1
    sudo sed -i "s/^macroonPath=.*/macroonPath=\/mnt\/hdd\/lnd\/data\/chain\/${network}\/${chain}net/g" ./RTL/RTL.conf
    sudo sed -i "s/^lndConfigPath=.*/lndConfigPath=\/mnt\/hdd\/lnd\/lnd.conf/g" ./RTL/RTL.conf
    sudo sed -i "s/^nodeAuthType=.*/nodeAuthType=CUSTOM/g" ./RTL/RTL.conf
    # getting ready for the phasing out of the "DEFAULT" auth type
    # will need to change blitz.setpassword.sh too
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
    sudo sed -i "s/^rtlPass=.*/rtlPass=$PASSWORD_B/g" ./RTL/RTL.conf
    echo ""

    # open firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow 3000 comment 'RTL'
    sudo ufw --force enable
    echo ""

    # install service
    echo "*** Install RTL systemd for ${network} on ${chain} ***"
    sudo cp /home/admin/assets/RTL.service /etc/systemd/system/RTL.service
    sudo sed -i "s|chain/bitcoin/mainnet|chain/${network}/${chain}net|" /etc/systemd/system/RTL.service
    sudo systemctl enable RTL
    echo "OK - the RTL service is now enabled"

  fi
  
  # setting value in raspi blitz config
  sudo sed -i "s/^rtlWebinterface=.*/rtlWebinterface=on/g" /mnt/hdd/raspiblitz.conf

  # Hidden Service for RTL if Tor is active
  if [ "${runBehindTor}" = "on" ]; then
    # correct old Hidden Service with port
    sudo sed -i "s/^HiddenServicePort 3000 127.0.0.1:3000/HiddenServicePort 80 127.0.0.1:3000/g" /etc/tor/torrc
    /home/admin/config.scripts/internet.hiddenservice.sh RTL 80 3000
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
