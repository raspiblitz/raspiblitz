#!/bin/bash

# consider installing with apt when updated next
# https://github.com/nodesource/distributions/blob/master/README.md#installation-instructions

VERSION="v18.5.0"
# get checksums from -> https://nodejs.org/dist/vx.y.z/SHASUMS256.txt (tar.xs files)
CHECKSUM_linux_arm64="cb16406a059882928de74359c20eb1daa272efcb8160495ea02c9a162f3ce33c"
CHECKSUM_linux_armv7l="ed31d680a918437e4ca0b9137af03d96b0b984048eac456f9611fe110df9eaf8"
CHECKSUM_linux_x64="3a64a0d2f86831d56fbfd9b59f61fe84f639d24772c5eaba0bfac23219a6d74d"

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
  nodeJSInstalled=$(node -v 2>/dev/null | grep -c "$VERSION")
  if ! [ ${nodeJSInstalled} -eq 0 ]; then
    echo "nodeJS $VERSION is already installed"
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
