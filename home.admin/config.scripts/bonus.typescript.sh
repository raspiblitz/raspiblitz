#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to install typescript"
 echo "bonus.typescript.sh [on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^typescript=" /mnt/hdd/raspiblitz.conf; then
  echo "typescript=off" | tee -a  /mnt/hdd/raspiblitz.conf
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  # check if typescript was installed
  typescriptInstalled=$(tsc -v 2>/dev/null | grep -c "Version ")
  if ! [ ${typescriptInstalled} -eq 0 ]; then
    echo "nodeJS is already installed"
  else
    # install nodeJS
    /home/admin/config.scripts/bonus.nodejs.sh on
    # determine nodeJS VERSION and DISTRO
    echo "Detect CPU architecture ..."
    isARM=$(uname -m | grep -c 'arm')
    isAARCH64=$(uname -m | grep -c 'aarch64')
    isX86_64=$(uname -m | grep -c 'x86_64')
    VERSION="v12.16.3"

    if [ ${isARM} -eq 1 ] ; then
      DISTRO="linux-armv7l"
    elif [ ${isAARCH64} -eq 1 ] ; then
      DISTRO="linux-arm64"
    elif [ ${isX86_64} -eq 1 ] ; then
      DISTRO="linux-x64"
    elif [ ${#DISTRO} -eq 0 ]; then
      echo "FAIL: Was not able to determine architecture"
      exit 1
    fi

    # install
	npm install typescript -g
    sudo ln -sf /usr/local/lib/nodejs/node-$VERSION-$DISTRO/bin/tsc /usr/bin/tsc 
    sudo ln -sf /usr/local/lib/nodejs/node-$VERSION-$DISTRO/bin/tsserver /usr/bin/tsserver
  
    # check if nodeJS was installed
    typescriptInstalled=$(tsc -v | grep -c "Version ")
    if [ ${typescriptInstalled} -eq 0 ]; then
      echo "FAIL - Was not able to install typescript"
      echo "ABORT - typescript install"
      exit 1
    fi
  fi
  # setting value in raspi blitz config
  sudo sed -i "s/^typescript=.*/typescript=on/g" /mnt/hdd/raspiblitz.conf
  echo "Installed typescript $(node -v)"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  # setting value in raspiblitz config
  sudo sed -i "s/^typescript=.*/typescript=off/g" /mnt/hdd/raspiblitz.conf
  echo "*** REMOVING typescript ***"
  npm uninstall typescript -g
  echo "OK typescript removed."
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
