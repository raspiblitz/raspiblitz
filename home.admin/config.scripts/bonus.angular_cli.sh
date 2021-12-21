#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "small config script to install angular CLI"
 echo "bonus.angular_cli.sh [on|off]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  # check if angular_cli was installed
  angularcliInstalled=$(ng help 2>/dev/null | grep -c "Available Commands:")
  if ! [ ${angularcliInstalled} -eq 0 ]; then
    echo "angular/cli is already installed"
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
    echo "# try to suppress question on statistics report"
    export NG_CLI_ANALYTICS=ci
    NG_CLI_ANALYTICS=ci
    echo "# install angular CLI"
    sudo apt install -y yes
    yes | npm install -g @angular/cli
    echo "# link ng"
    sudo ln -sf /usr/local/lib/nodejs/node-$VERSION-$DISTRO/bin/ng /usr/bin/ng
    echo "# explicit turn off statistics report"
    ng analytics off

    # check if nodeJS was installed
    angularcliInstalled=$(ng help | grep -c "Available Commands:")
    if [ ${angularcliInstalled} -eq 0 ]; then
      echo "FAIL - Was not able to install angular_cli"
      echo "ABORT - angular_cli install"
      exit 1
    fi
  fi
  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set angular_cli "on"
  echo "Installed angular_cli $(node -v)"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set angular_cli "off"
  echo "*** REMOVING angular_cli ***"
  npm uninstall @angular/cli -g
  echo "OK angular_cli removed."
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
