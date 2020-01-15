#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to install NodeJs"
 echo "bonus.nodejs.sh"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if ! grep -Eq "^nodeJS=" /mnt/hdd/raspiblitz.conf; then
  echo "nodeJS=off" >> /mnt/hdd/raspiblitz.conf
fi

# check if nodeJS was installed
nodeJSInstalled=$(node -v 2>/dev/null | grep -c "v1.")
if ! [ ${nodeJSInstalled} -eq 0 ]; then
    echo "nodeJS is already installed"
else
    # determine nodeJS VERSION and DISTRO
    echo "Detect CPU architecture ..."
    isARM=$(uname -m | grep -c 'arm')
    isAARCH64=$(uname -m | grep -c 'aarch64')
    isX86_64=$(uname -m | grep -c 'x86_64')
    isX86_32=$(uname -m | grep -c 'i386\|i486\|i586\|i686\|i786')
    VERSION="v12.14.1"
 
    # get checksums from -> https://nodejs.org/dist/vx.y.z/SHASUMS256.txt
    # https://nodejs.org/dist/v12.14.1/SHASUMS256.txt
    if [ ${isARM} -eq 1 ] ; then
    DISTRO="linux-armv7l"
    CHECKSUM="ed4e625c84b877905eda4f356c8b4183c642e5ee6d59513d6329674ec23df234"
    fi
    if [ ${isAARCH64} -eq 1 ] ; then
    DISTRO="linux-arm64"
    CHECKSUM="6cd28a5e6340f596aec8dbfd6720f444f011e6b9018622290a60dbd17f9baff6"
    fi
    if [ ${isX86_64} -eq 1 ] ; then
    DISTRO="linux-x64"
    CHECKSUM="07cfcaa0aa9d0fcb6e99725408d9e0b07be03b844701588e3ab5dbc395b98e1b"
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
    sudo bash -c "echo 'PATH=\$PATH:/usr/local/lib/nodejs/node-\$VERSION-\$DISTRO/bin/' >> /etc/profile"
    echo ""

    # check if nodeJS was installed
    nodeJSInstalled=$(node -v | grep -c "v1.")
    if [ ${nodeJSInstalled} -eq 0 ]; then
    echo "FAIL - Was not able to install nodeJS"
    echo "ABORT - nodeJs install"
    exit 1
    fi
fi

# setting value in raspi blitz config
sudo sed -i "s/^nodeJS=.*/nodeJS=on/g" /mnt/hdd/raspiblitz.conf
echo "Installed nodeJS $(node -v)"
exit 0

