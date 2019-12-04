#!/bin/bash

# set version, check: https://github.com/golang/go/releases 
goVersion="1.13.3"

# export go vars (if needed)
#if [ ${#GOROOT} -eq 0 ]; then
#  export GOROOT=/usr/local/go
#  export PATH=$PATH:$GOROOT/bin
#fi
#if [ ${#GOPATH} -eq 0 ]; then
#  export GOPATH=/usr/local/gocode
#  export PATH=$PATH:$GOPATH/bin
#fi

# get cpu architecture
isARM=$(uname -m | grep -c 'arm')
isAARCH64=$(uname -m | grep -c 'aarch64')
isX86_64=$(uname -m | grep -c 'x86_64')
isX86_32=$(uname -m | grep -c 'i386\|i486\|i586\|i686\|i786')

# make sure go is installed
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
  if [ ${isX86_32} -eq 1 ] ; then
    goOSversion="386"
  fi 

  echo "*** Installing Go v${goVersion} for ${goOSversion} ***"

  # wget https://storage.googleapis.com/golang/go${goVersion}.linux-${goOSversion}.tar.gz
  wget https://dl.google.com/go/go${goVersion}.linux-${goOSversion}.tar.gz
  if [ ! -f "./go${goVersion}.linux-${goOSversion}.tar.gz" ]
  then
      echo "!!! FAIL !!! Download not success."
      exit 1
  fi
  sudo tar -C /usr/local -xzf go${goVersion}.linux-${goOSversion}.tar.gz
  sudo rm *.gz
  sudo mkdir /usr/local/gocode
  sudo chmod 777 /usr/local/gocode
  export GOROOT=/usr/local/go
  export PATH=$PATH:$GOROOT/bin
  export GOPATH=/usr/local/gocode
  export PATH=$PATH:$GOPATH/bin
  sudo bash -c "echo 'GOROOT=/usr/local/go' >> /etc/profile"
  sudo bash -c "echo 'PATH=\$PATH:\$GOROOT/bin/' >> /etc/profile"
  sudo bash -c "echo 'GOPATH=/usr/local/gocode' >> /etc/profile"   
  sudo bash -c "echo 'PATH=\$PATH:\$GOPATH/bin/' >> /etc/profile"
  #export PATH=$PATH:/home/admin/go/bin/
  #sudo bash -c "echo 'PATH=\$PATH:/home/admin/go/bin/' >> /etc/profile"
  #echo "export GOPATH=$HOME/go" >> .profile
  
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

echo ""
echo "Installed $(go version)"
echo ""
