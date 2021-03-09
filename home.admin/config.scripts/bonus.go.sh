#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install Go"
 echo "bonus.go.sh [on|off]"
 exit 1
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  # set version, check: https://github.com/golang/go/releases 
  goVersion="1.13.3"

  # get cpu architecture
  isARM=$(uname -m | grep -c 'arm')
  isAARCH64=$(uname -m | grep -c 'aarch64')
  isX86_64=$(uname -m | grep -c 'x86_64')

  # make sure go is installed

  # get Go vars - needed if there was no log-out since Go installed
  source /etc/profile

  echo "Check Framework: Go"
  goInstalled=$(go version 2>/dev/null | grep -c 'go')
  if [ ${goInstalled} -eq 0 ];then
    if [ ${isARM} -eq 1 ] ; then
      goOSversion="armv6l"
    fi
    if [ ${isAARCH64} -eq 1 ] ; then
      goOSversion="arm64"
    fi
    if [ ${isX86_64} -eq 1 ] ; then
      goOSversion="amd64"
    fi 

    echo "*** Installing Go v${goVersion} for ${goOSversion} ***"

    # wget https://storage.googleapis.com/golang/go${goVersion}.linux-${goOSversion}.tar.gz
    cd /home/admin/download
    wget https://dl.google.com/go/go${goVersion}.linux-${goOSversion}.tar.gz
    if [ ! -f "./go${goVersion}.linux-${goOSversion}.tar.gz" ]
    then
        echo "!!! FAIL !!! Download not success."
        rm -f go${goVersion}.linux-${goOSversion}.tar.gz*
        exit 1
    fi
    sudo tar -C /usr/local -xzf go${goVersion}.linux-${goOSversion}.tar.gz
    rm -f go${goVersion}.linux-${goOSversion}.tar.gz*
    sudo mkdir /usr/local/gocode
    sudo chmod 777 /usr/local/gocode
    export GOROOT=/usr/local/go
    export PATH=$PATH:$GOROOT/bin
    export GOPATH=/usr/local/gocode
    export PATH=$PATH:$GOPATH/bin
    if [ $(cat /etc/profile | grep -c "GOROOT=") -eq 0 ]; then
      sudo bash -c "echo 'GOROOT=/usr/local/go' >> /etc/profile"
      sudo bash -c "echo 'PATH=\$PATH:\$GOROOT/bin/' >> /etc/profile"
      sudo bash -c "echo 'GOPATH=/usr/local/gocode' >> /etc/profile"   
      sudo bash -c "echo 'PATH=\$PATH:\$GOPATH/bin/' >> /etc/profile"
    fi

    # set GOPATH https://github.com/golang/go/wiki/SettingGOPATH
    go env -w GOPATH=/usr/local/gocode
    
    goInstalled=$(go version 2>/dev/null | grep -c 'go')
  fi
  if [ ${goInstalled} -eq 0 ];then
    echo "FAIL: Was not able to install Go"
    sleep 4
    exit 1
  fi

  correctGoVersion=$(go version | grep -c "go${goVersion}")
  if [ ${correctGoVersion} -eq 0 ]; then
    echo "WARNING: You work with an untested version of GO - should be ${goVersion} .. trying to continue"
    go version
    sleep 3
    echo ""
  fi

  # setting value in raspi blitz config
  echo ""
  echo "Installed $(go version)"
  echo ""
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  # setting value in raspiblitz config
  echo "*** REMOVING GO ***"
  sudo rm -rf /usr/local/go
  sudo rm -rf /usr/local/gocode
  echo "OK Go removed."
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1