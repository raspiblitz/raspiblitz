#!/bin/bash

# consider installing with apt when updated next
# https://github.com/nodesource/distributions/blob/master/README.md#installation-instructions

VERSION="v18.12.0"

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
elif [ ${isAARCH64} -eq 1 ] ; then
  DISTRO="linux-arm64"
elif [ ${isX86_64} -eq 1 ] ; then
  DISTRO="linux-x64"
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
  if [ "$(node -v)" = "${VERSION}" ]; then
    echo "nodeJS $VERSION is already installed"
  else
    # install latest nodejs
    # https://github.com/nodejs/help/wiki/Installation
    echo "*** Install NodeJS $VERSION-$DISTRO ***"
    echo "VERSION: ${VERSION}"
    echo "DISTRO: ${DISTRO}"
    echo

    # download
    cd /home/admin/download || exit 1
    wget -O node-$VERSION-$DISTRO.tar.xz https://nodejs.org/dist/$VERSION/node-$VERSION-$DISTRO.tar.xz
    # checksum
    wget -O SHASUMS256.txt https://nodejs.org/dist/$VERSION/SHASUMS256.txt
    if ! sha256sum -c SHASUMS256.txt --ignore-missing; then
      echo "FAIL: The checksum of node-$VERSION-$DISTRO.tar.xz is not found in the SHASUMS256.txt"
      rm -f node-$VERSION-$DISTRO.tar.xz*
      exit 1
    fi
    echo "OK the checkdum of nodeJS is OK"
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
    echo

    # check if nodeJS was installed
    if node -v; then
      echo "Installed nodeJS $(node -v)"
    else
      echo "FAIL - Was not able to install nodeJS"
      echo "ABORT - nodeJs install"
      exit 1
    fi
  fi

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
