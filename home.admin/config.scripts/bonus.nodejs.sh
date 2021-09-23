#!/bin/bash

# consider installing with apt when updated next
# https://github.com/nodesource/distributions/blob/master/README.md#installation-instructions

VERSION="v14.17.6"
# get checksums from -> https://nodejs.org/dist/vx.y.z/SHASUMS256.txt (tar.xs files)
CHECKSUM_linux_arm64="9c4f3a651e03cd9b5bddd33a80e8be6a6eb15e518513e410bb0852a658699156"
CHECKSUM_linux_armv7l="09ad804c7354ebaded407d0ce64e72e534801fc435be084af3e5b16b1a9c96d0"
CHECKSUM_linux_x64="3bbe4faf356738d88b45be222bf5e858330541ff16bd0d4cfad36540c331461b"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install NodeJs $VERSION"
 echo "bonus.nodejs.sh [on|off|info]"
 exit 1
fi

 # determine nodeJS VERSION and DISTRO
isARM=$(uname -m | grep -c 'arm')
isAARCH64=$(uname -m | grep -c 'aarch64')
isX86_64=$(uname -m | grep -c 'x86_64')
if [ ${isARM} -eq 1 ] ; then
  DISTRO="linux-armv7l"
  CHECKSUM="${CHECKSUM_linux_armv7l}"
elif [ ${isAARCH64} -eq 1 ] ; then
  DISTRO="linux-arm64"
  CHECKSUM="${CHECKSUM_linux_arm64}"
elif [ ${isX86_64} -eq 1 ] ; then
  DISTRO="linux-x64"
  CHECKSUM="${CHECKSUM_linux_x64}"
elif [ ${#DISTRO} -eq 0 ]; then
  echo "# FAIL: Was not able to determine architecture"
  exit 1
fi

# info
if [ "$1" = "info" ]; then
  echo "NODEVERSION='${VERSION}'"
  echo "NODEDISTRO='${DISTRO}'"
  echo "NODEPATH='/usr/local/lib/nodejs/node-$VERSION-$DISTRO/bin'"
  exit 0
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  # check if nodeJS was installed
  nodeJSInstalled=$(node -v 2>/dev/null | grep -c "v1.")
  if ! [ ${nodeJSInstalled} -eq 0 ]; then
    echo "nodeJS is already installed"
  else

    # install latest nodejs
    # https://github.com/nodejs/help/wiki/Installation
    echo "*** Install NodeJS $VERSION-$DISTRO ***"
    echo "VERSION: ${VERSION}"
    echo "DISTRO: ${DISTRO}"
    echo "CHECKSUM: ${CHECKSUM}"
    echo ""

    # download
    cd /home/admin/download
    wget https://nodejs.org/dist/$VERSION/node-$VERSION-$DISTRO.tar.xz
    # checksum
    isChecksumValid=$(sha256sum node-$VERSION-$DISTRO.tar.xz | grep -c "${CHECKSUM}")
    if [ ${isChecksumValid} -eq 0 ]; then
      echo "FAIL: The checksum of node-$VERSION-$DISTRO.tar.xz is NOT ${CHECKSUM}"
      rm -f node-$VERSION-$DISTRO.tar.xz*
      exit 1
    fi
    echo "OK CHECKSUM of nodeJS is OK"
    sleep 3
    # install
    sudo mkdir -p /usr/local/lib/nodejs
    sudo tar -xJvf node-$VERSION-$DISTRO.tar.xz -C /usr/local/lib/nodejs
    rm -f node-$VERSION-$DISTRO.tar.xz* 
    export PATH=/usr/local/lib/nodejs/node-$VERSION-$DISTRO/bin:$PATH
    sudo ln -sf /usr/local/lib/nodejs/node-$VERSION-$DISTRO/bin/node /usr/bin/node
    sudo ln -sf /usr/local/lib/nodejs/node-$VERSION-$DISTRO/bin/npm /usr/bin/npm
    sudo ln -sf /usr/local/lib/nodejs/node-$VERSION-$DISTRO/bin/npx /usr/bin/npx
    # add to PATH permanently
    sudo bash -c "echo 'PATH=\$PATH:/usr/local/lib/nodejs/node-${VERSION}-${DISTRO}/bin/' >> /etc/profile"
    echo ""
  
    # check if nodeJS was installed
    nodeJSInstalled=$(node -v | grep -c "v1.")
    if [ ${nodeJSInstalled} -eq 0 ]; then
      echo "FAIL - Was not able to install nodeJS"
      echo "ABORT - nodeJs install"
      exit 1
    fi
  fi

  npm7installed=$(npm -v 2>/dev/null | grep -c "7.")
  if [ ${npm7installed} -eq 0 ]; then
    # needed for RTL
    # https://github.blog/2021-02-02-npm-7-is-now-generally-available/
    echo "# Update npm to v7"
    sudo npm install --global npm@7
  fi

  echo "Installed nodeJS $(node -v)"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  # setting value in raspiblitz config
  echo "*** REMOVING NODEJS ***"
  sudo rm -rf /usr/local/lib/nodejs
  echo "OK NodeJS removed."
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1