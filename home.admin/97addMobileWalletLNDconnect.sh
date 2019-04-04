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
localIP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
host="${localIP}"
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

# write qr code data to an image
lndconnect --host=${host} --port=${port} --image

# display qr code image on LCD
./XXdisplayLCD.sh lndconnect-qr.png

# show pairing info dialog
msg=""
if [ ${local} -eq 1 ]; then 
  msg="Make sure you are on the same local network.\n(WLAN same as LAN - use WIFI not cell network on phone).\n\n"
fi
msg="${msg}When you start the App choose to connect to your own node.\n(DIY / Remote-Node / lndconnect)\n\nClick on the 'Scan QR' button. Scan the QR on the LCD and <continue> or <show QR code> to see it in this window."
whiptail --backtitle "Connecting Mobile Wallet" \
	 --title "Pairing by QR code" \
	 --yes-button "continue" \
	 --no-button "show QR code" \
	 --yesno "${msg}" 20 65
if [ $? -eq 1 ]; then
  lndconnect --host=${host} --port=${port}
  echo "(To shrink QR code: OSX->CMD- / LINUX-> CTRL-) Press ENTER when finished."
  read key
fi

# clean up
./XXdisplayQRlcd_hide.sh
shred lndconnect-qr.png 2> /dev/null
rm -f lndconnect-qr.png 2> /dev/null
shred qr.txt 2> /dev/null
rm -f qr.txt 2> /dev/null

echo "------------------------------"
echo "If the connection was not working:"
if [ ${#dynDomain} -gt 0 ]; then
  echo "- Make sure that your router is forwarding port ${port} to the Raspiblitz with IP ${localIP}"
fi
if [ ${local} -eq 1 ]; then
  echo "- Check that your WIFI devices can talk to the LAN devices on your router (deactivate IP isolation or guest mode)."
fi
echo "- check issues: https://github.com/LN-Zap/lndconnect/issues"
echo "- check issues: https://github.com/rootzoll/raspiblitz/issues"
echo ""