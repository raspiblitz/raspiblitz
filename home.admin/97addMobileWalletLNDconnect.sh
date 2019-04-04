#!/bin/bash

# get service port from argument
servicePort="10009"
if [ $# -gt 0 ]; then
  if [ "$1" == "RPC" ]; then
    echo "running RPC mode"
    servicePort="10009"
  fi
  if [ "$1" == "REST" ]; then
    echo "running REST mode"
    servicePort="8080"
  fi
fi

# load raspiblitz config data
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# export go vars (if needed)
if [ ${#GOROOT} -eq 0 ]; then
  export GOROOT=/usr/local/go
  export PATH=$PATH:$GOROOT/bin
fi
if [ ${#GOPATH} -eq 0 ]; then
  export GOPATH=/usr/local/gocode
  export PATH=$PATH:$GOPATH/bin
fi

# make sure go is installed
goVersion="1.11"
echo "### Check Framework: GO ###"
goInstalled=$(go version 2>/dev/null | grep -c 'go')
if [ ${goInstalled} -eq 0 ];then
  echo "---> Installing GO"
  wget https://storage.googleapis.com/golang/go${goVersion}.linux-armv6l.tar.gz
  sudo tar -C /usr/local -xzf go${goVersion}.linux-armv6l.tar.gz
  sudo rm *.gz
  sudo mkdir /usr/local/gocode
  sudo chmod 777 /usr/local/gocode
  goInstalled=$(go version 2>/dev/null | grep -c 'go')
fi
if [ ${goInstalled} -eq 0 ];then
  echo "FAIL: Was not able to install GO (needed to run LndConnect)"
  sleep 4
  exit 1
fi

correctGoVersion=$(go version | grep -c "go${goVersion}")
if [ ${correctGoVersion} -eq 0 ]; then
  echo "WARNING: You work with a untested version of GO - should be ${goVersion} .. trying to continue"
  go version
  sleep 6
  echo ""
fi

# make sure qrcode-encoder in installed
echo "*** Setup ***"
echo ""
echo "Installing lndconnect. Please wait..."
echo ""
echo "Getting github.com/LN-Zap/lndconnect (please wait - can take several minutes) ..."
go get -d github.com/LN-Zap/lndconnect
cd $GOPATH/src/github.com/LN-Zap/lndconnect
echo ""
echo "Building github.com/LN-Zap/lndconnect ..."
make
cd
sleep 3

# default host to local IP and port
local=1
host=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
port="${servicePort}"

# change host to dynDNS if set
if [ ${#dynDomain} -gt 0 ]; then
  local=0
  host="${dynDomain}"
  echo "port ${servicePort} forwarding from dynDomain ${host}"
fi

# check if local service port is forwarded
if [ ${#sshtunnel} -gt 0 ]; then
  isForwarded=$(echo ${sshtunnel} | grep -c "${servicePort}<")
  if [ ${isForwarded} -gt 0 ]; then
    local=0
    host=$(echo $sshtunnel | cut -d '@' -f2 | cut -d ' ' -f1)
    if [ "${servicePort}" == "10009" ]; then
      port=$(echo $sshtunnel | awk '{split($0,a,"10009<"); print a[2]}' | cut -d ' ' -f1 | sed 's/[^0-9]//g')
    elif [ "${servicePort}" == "8080" ]; then
      port=$(echo $sshtunnel | awk '{split($0,a,"8080<"); print a[2]}' | cut -d ' ' -f1 | sed 's/[^0-9]//g')
    fi
    echo "port ${servicePort} forwarding from port ${port} from server ${host}"
  else
    echo "port ${servicePort} is not part of the ssh forwarding - keep default port ${servicePort}"
  fi
fi

echo "******************************"
echo "Connect Zap Mobile Wallet"
echo "******************************"
echo ""
echo "GETTING THE APP"
echo "At the moment this app is in closed beta testing and the source code has not been published yet."
echo "1. Install the app 'TestFlight' from Apple Appstore. Open it and agree to all terms of services."
echo "2. Open on your iOS device https://github.com/LN-Zap/zap-iOS and follow 'Download the Alpha'"
echo ""
echo "*** PAIRING STEP 1 ***"
if [ ${local} -eq 1 ]; then 
  echo "Once you have the app is running make sure you are on the same local network (WLAN same as LAN)."
fi
echo "During Setup of the Zap app you should get to the 'Connect Remote-Node' screen."
echo ""
echo "---> Click on Scan"
echo "Make the this terminal as big as possible - fullscreen would be best."
echo "Then PRESS ENTER here in the terminal to generare the QR code and scan it with the app."
read key

clear
echo "*** PAIRING STEP 2 : Click on Scan (make whole QR code fill camera) ***"

lndconnect --host=${host} --port=${port}
echo "(To shrink QR code: CTRL- or CMD-) Press ENTER when finished."
read key

clear
echo "If it's not working - check issues on GitHub:"
echo "https://github.com/LN-Zap/lndconnect/issues"
echo ""