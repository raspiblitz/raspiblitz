#!/bin/bash

VERSION="v14.15.4"
# get checksums from -> https://nodejs.org/dist/vx.y.z/SHASUMS256.txt (tar.xs files)
CHECKSUM_linux_arm64="b990bd99679158c3164c55a20c2a6677c3d9e9ffdfa0d4a40afe9c9b5e97a96f"
CHECKSUM_linux_armv7l="bafe4bfb22b046cdda3475d23cd6999c5ea85180c180c4bbb94014920aa7231b"
CHECKSUM_linux_x64="ed01043751f86bb534d8c70b16ab64c956af88fd35a9506b7e4a68f5b8243d8a"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install NodeJs $VERSION"
 echo "bonus.nodejs.sh [on|off]"
 exit 1
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
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