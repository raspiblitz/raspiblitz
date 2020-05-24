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

  # get network info
  localip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  toraddress=$(sudo cat /mnt/hdd/tor/RTL/hostname 2>/dev/null)

  if [ "${runBehindTor}" = "on" ] && [ ${#toraddress} -gt 0 ]; then
    # Info with TOR
    /home/admin/config.scripts/blitz.lcd.sh qr "${toraddress}"
    whiptail --title " Ride The Lightning (RTL) " --msgbox "Open the following URL in your local web browser:
http://${localip}:3000
Use your Password B to login.\n
Hidden Service address for TOR Browser (QR see LCD):\n${toraddress}
" 12 67
    /home/admin/config.scripts/blitz.lcd.sh hide
  else
    # Info without TOR
    whiptail --title " Ride The Lightning (RTL) " --msgbox "Open the following URL in your local web browser:
http://${localip}:3000
Use your Password B to login.\n
Activate TOR to access the web interface from outside your local network.
" 12 57
  fi
  echo "please wait ..."
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

    # create rtl user
    sudo adduser --disabled-password --gecos "" rtl

    echo "*** make sure rtl is member of lndadmin ***"
    sudo /usr/sbin/usermod --append --groups lndadmin rtl

    echo "*** make sure symlink to central app-data directory exists ***"
    if ! [[ -L "/home/rtl/.lnd" ]]; then
      sudo rm -rf "/home/rtl/.lnd"                          # not a symlink.. delete it silently
      sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/rtl/.lnd"  # and create symlink
    fi

    # download source code and set to tag release
    echo "*** Get the RTL Source Code ***"
    rm -rf /home/admin/RTL 2>/dev/null
    sudo -u rtl rm -rf /home/rtl/RTL 2>/dev/null
    sudo -u rtl git clone https://github.com/ShahanaFarooqui/RTL.git /home/rtl/RTL
    cd /home/rtl/RTL
    sudo -u rtl git reset --hard v0.7.0
    # from https://github.com/Ride-The-Lightning/RTL/commits/master
    # git checkout 917feebfa4fb583360c140e817c266649307ef72
    if [ -d "/home/rtl/RTL" ]; then
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
    sudo -u rtl npm install --only=prod
    cd ..
    # check if node_modules exist now
    if [ -d "/home/rtl/RTL/node_modules" ]; then
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

    # prepare RTL-Config.json file
    echo "*** RTL.conf ***"
    # change of config: https://github.com/Ride-The-Lightning/RTL/tree/v0.6.4
    sudo cp /home/rtl/RTL/sample-RTL-Config.json /home/admin/RTL-Config.json
    sudo chown admin:admin /home/admin/RTL-Config.json
    sudo chmod 600 /home/admin/RTL-Config.json || exit 1
    PASSWORD_B=$(sudo cat /mnt/hdd/${network}/${network}.conf | grep rpcpassword | cut -c 13-)
    # modify sample-RTL-Config.json and save in RTL-Config.json
    sudo node > /home/admin/RTL-Config.json <<EOF
//Read data
var data = require('/home/rtl/RTL/sample-RTL-Config.json');
//Manipulate data
data.nodes[0].lnNode = '$hostname'
data.nodes[0].Authentication.macaroonPath = '/home/rtl/.lnd/data/chain/${network}/${chain}net/';
data.nodes[0].Authentication.configPath = '/home/rtl/.lnd/lnd.conf';
data.multiPass = '$PASSWORD_B';
data.nodes[0].Settings.userPersona = 'OPERATOR'
data.nodes[0].Settings.channelBackupPath = '/home/rtl/RTL-SCB-backup-$hostname'
//Output data
console.log(JSON.stringify(data, null, 2));
EOF
    sudo rm -f /home/rtl/RTL/RTL-Config.json
    sudo mv /home/admin/RTL-Config.json /home/rtl/RTL/
    sudo chown rtl:rtl /home/rtl/RTL/RTL-Config.json
    echo ""

    # open firewall
    echo "*** Updating Firewall ***"
    sudo ufw allow 3000 comment 'RTL'
    echo ""

    # install service
    echo "*** Install RTL systemd for ${network} on ${chain} ***"
    cat > /home/admin/RTL.service <<EOF
# Systemd unit for RTL
# /etc/systemd/system/RTL.service

[Unit]
Description=RTL daemon
Wants=lnd.service
After=lnd.service

[Service]
ExecStart=/usr/bin/node /home/rtl/RTL/rtl --lndir /home/rtl/.lnd/data/chain/bitcoin/mainnet
User=rtl
Restart=always
TimeoutSec=120
RestartSec=30
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /home/admin/RTL.service /etc/systemd/system/RTL.service 
    sudo sed -i "s|chain/bitcoin/mainnet|chain/${network}/${chain}net|" /etc/systemd/system/RTL.service
    sudo chown root:root /etc/systemd/system/RTL.service
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
    sudo rm -rf /home/rtl/RTL
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
