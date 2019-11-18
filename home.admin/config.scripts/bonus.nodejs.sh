#!/bin/bash

# command info
if [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to install NodeJs"
 echo "bonus.nodejs.sh"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# add default value to raspi config if needed
if [ ${#nodeJS} -eq 0 ]; then
  echo "nodeJS=off" >> /mnt/hdd/raspiblitz.conf
fi

# check if nodeJS was installed
nodeJSInstalled=$(node -v | grep -c "v1.")
if [ ${nodeJSInstalled} -eq 0 ]; then

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
else
    echo "nodeJS is already installed"
fi

# setting value in raspi blitz config
sudo sed -i "s/^nodeJS=.*/nodeJS=on/g" /mnt/hdd/raspiblitz.conf
echo "Installed nodeJS $(node -v)"
exit 0

