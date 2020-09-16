#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install or uninstall lndmanage"
 echo "bonus.lndmanage.sh [on|off|menu]"
 exit 1
fi

# set version of LND manage to install
# https://github.com/bitromortac/lndmanage/releases
lndmanageVersion="0.11.0"
pgpKeyDownload="https://github.com/bitromortac.gpg"
gpgFingerprint="0453B9F5071261A40FDB34181965063FC13BEBE2"

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^lndmanage=" /mnt/hdd/raspiblitz.conf; then
  echo "lndmanage=off" >> /mnt/hdd/raspiblitz.conf
fi

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " Info lndmanage " --msgbox "\n\
Usage: https://github.com/bitromortac/lndmanage/blob/master/README.md or
lndmanage --help.\n
To start type: 'manage' in the command line.
" 9 75
  exit 0
fi

# install
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  directoryExists=$(sudo ls /home/admin/lndmanage 2>/dev/null | wc -l)
  if [ ${directoryExists} -gt 0 ]; then
    echo "# FAIL - LNDMANAGE already installed"
    sleep 3
    exit 1
  fi
  
  echo "*** INSTALL LNDMANAGE ***"

  # prepare directory
  mkdir /home/admin/lndmanage 2>/dev/null
  sudo chown admin:admin /home/admin/lndmanage

  echo "# downloading files ..."
  cd /home/admin/lndmanage
  sudo -u admin wget -N https://github.com/bitromortac/lndmanage/releases/download/v${lndmanageVersion}/lndmanage-${lndmanageVersion}-py3-none-any.whl
  sudo -u admin wget -N https://github.com/bitromortac/lndmanage/releases/download/v${lndmanageVersion}/lndmanage-${lndmanageVersion}-py3-none-any.whl.asc
  sudo -u admin wget -N ${pgpKeyDownload} -O sigingkey.gpg

  echo "# checking signing keys ..."
  gpg --import sigingkey.gpg
  verifyResult=$(gpg --verify lndmanage-${lndmanageVersion}-py3-none-any.whl.asc 2>&1)
  goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
  correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${gpgFingerprint}" -c)
  echo "goodSignature='${goodSignature}'"
  echo "correctKey='${correctKey}'"
  if [ ${goodSignature} -gt 0 ] && [ ${correctKey} -gt 0 ]; then
    echo "# OK signature is valid"
  else
    echo "error='unvalid signature'"
    sudo rm -rf /home/admin/lndmanage
    sleep 5
    exit 1
  fi

  echo "# installing ..."
  python3 -m venv venv
  source /home/admin/lndmanage/venv/bin/activate
  python3 -m pip install lndmanage-0.11.0-py3-none-any.whl

  # get build dependencies
  # python3 -m pip install --upgrade pip wheel setuptools
  # install lndmanage
  # python3 -m pip install lndmanage==0.11.0

  # check if install was successfull
  if [ $(python3 -m pip list | grep -c "lndmanage") -eq 0 ]; then
    echo
    echo "#!! FAIL --> Was not able to install LNDMANAGE"
    echo "#!! Maybe because of internet network issues - try again later."
    sudo rm -rf /home/admin/lndmanage
    sleep 5
    exit 1
  fi

  # setting value in raspi blitz config
  sudo sed -i "s/^lndmanage=.*/lndmanage=on/g" /mnt/hdd/raspiblitz.conf
  echo "#######################################################################"
  echo "# OK install done"
  echo "#######################################################################"
  echo "# To start type: 'manage' in the command line."
  echo "# To exit the venv - type 'deactivate' and press ENTER"
  echo "# usage: https://github.com/bitromortac/lndmanage/blob/master/README.md"
  echo "# usage: lndmanage --help"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  sudo sed -i "s/^lndmanage=.*/lndmanage=off/g" /mnt/hdd/raspiblitz.conf
  
  echo "*** REMOVING LNDMANAGE ***"
  sudo rm -rf /home/admin/lndmanage
  echo "# OK, lndmanage is removed."
  exit 0

fi

echo "FAIL - Unknown Parameter $1"
exit 1
