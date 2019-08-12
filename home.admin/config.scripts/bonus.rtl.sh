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

    # determine nodeJS VERSION and DISTRO
    echo "Detect CPU architecture ..."
    isARM=$(uname -m | grep -c 'arm')
    isAARCH64=$(uname -m | grep -c 'aarch64')
    isX86_64=$(uname -m | grep -c 'x86_64')
    isX86_32=$(uname -m | grep -c 'i386\|i486\|i586\|i686\|i786')
    VERSION="v10.16.0"
    # get checksums from -> https://nodejs.org/dist/vx.y.z/SHASUMS256.txt
    if [ ${isARM} -eq 1 ] ; then
      DISTRO="linux-armv7l"
      CHECKSUM="3a3710722a1ce49b4c72c4af3155041cce3c4f632260ec8533be3fc7fd23f92c"
    fi
    if [ ${isAARCH64} -eq 1 ] ; then
      DISTRO="linux-arm64"
      CHECKSUM="ae2e74ab2f5dbff96bf0b7d8457004bf3538233916f8834740bbe2d5a35442e5"
    fi
    if [ ${isX86_64} -eq 1 ] ; then
      DISTRO="linux-x64"
      CHECKSUM="1827f5b99084740234de0c506f4dd2202a696ed60f76059696747c34339b9d48"
    fi
    if [ ${isX86_32} -eq 1 ] ; then
      echo "FAIL: No X86 32bit build available - will abort setup"
      exit 1
    fi
    if [ ${#DISTRO} -eq 0 ]; then
      echo "FAIL: Was not able to determine architecture"
      exit 1
    fi
    echo "VERSION: ${VERSION}"
    echo "DISTRO: ${DISTRO}"
    echo "CHECKSUM: ${CHECKSUM}"
    echo ""

    # install latest nodejs
    # https://github.com/nodejs/help/wiki/Installation
    echo "*** Install NodeJS $VERSION-$DISTRO ***"
    
    # download
    wget https://nodejs.org/dist/$VERSION/node-$VERSION-$DISTRO.tar.xz

    # checksum
    isChecksumValid=$(sha256sum node-$VERSION-$DISTRO.tar.xz | grep -c "${CHECKSUM}")
    if [ ${isChecksumValid} -eq 0 ]; then
      echo "FAIL: The checksum of node-$VERSION-$DISTRO.tar.xz is NOT ${CHECKSUM}"
      exit 1
    fi
    echo "OK CHECKSUM of nodeJS is OK"
    sleep 3

    # install
    sudo mkdir -p /usr/local/lib/nodejs
    sudo tar -xJvf node-$VERSION-$DISTRO.tar.xz -C /usr/local/lib/nodejs 
    export PATH=/usr/local/lib/nodejs/node-$VERSION-$DISTRO/bin:$PATH
    sudo ln -s /usr/local/lib/nodejs/node-$VERSION-$DISTRO/bin/node /usr/bin/node
    sudo ln -s /usr/local/lib/nodejs/node-$VERSION-$DISTRO/bin/npm /usr/bin/npm
    sudo ln -s /usr/local/lib/nodejs/node-$VERSION-$DISTRO/bin/npx /usr/bin/npx
    echo ""

    # check if nodeJS was installed
    nodeJSInstalled=$(node -v | grep -c "v1.")
    if [ ${nodeJSInstalled} -eq 0 ]; then
      echo "FAIL - Was not able to install nodeJS"
      echo "ABORT - RTL install"
      exit 1
    fi

    # download source code and set to tag release
    echo "*** Get the RTL Source Code ***"
    rm -r /home/admin/RTL 2>/dev/null
    git clone https://github.com/ShahanaFarooqui/RTL.git /home/admin/RTL
    cd /home/admin/RTL
    git reset --hard v0.4.2
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
