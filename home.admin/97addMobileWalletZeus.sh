#!/bin/bash

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
goInstalled=$(go version 2>/dev/null | grep -c 'go')
if [ ${goInstalled} -eq 0 ];then
  echo "### Installing GO ###"
  wget https://storage.googleapis.com/golang/go1.11.linux-armv6l.tar.gz
  sudo tar -C /usr/local -xzf go1.11.linux-armv6l.tar.gz
  sudo rm *.gz
  sudo mkdir /usr/local/gocode
  sudo chmod 777 /usr/local/gocode
  goInstalled=$(go version 2>/dev/null | grep -c 'go')
fi
if [ ${goInstalled} -eq 0 ];then
  echo "FAIL: Was not able to install GO (needed to run LndConnect)"
  exit 1
fi

# make sure qrcode-encoder in installed
clear
echo "*** Setup ***"
echo ""
echo "Installing lndconnect. Please wait..."
echo ""
echo "Getting github.com/LN-Zap/lndconnect (please wait) ..."
go get -d github.com/LN-Zap/lndconnect
cd $GOPATH/src/github.com/LN-Zap/lndconnect
echo ""
echo "Building github.com/LN-Zap/lndconnect ..."
make
cd
sleep 3

clear
echo "******************************"
echo "Connect Zeus Mobile Wallet"
echo "******************************"
echo ""
echo "GETTING THE APP"
echo "At the moment this app is in alpha stages."
echo "You can compile the code for iOS or Android but only an Android APK is currently available for downloads."
echo "Go to https://github.com/ZeusLN/zeus/releases to find the latest release."
echo ""
echo "*** STEP 1 ***"
if [ ${#dynDomain} -eq 0 ]; then
  echo "Once you have the app is running make sure you are on the same local network (WLAN same as LAN)."
fi
echo "During setup of the Zeus app you should get to the 'Settings' screen."
echo ""
echo "---> Click on the Scan lndconnect config button"
echo "Make the this terminal as big as possible - fullscreen would be best."
echo "Then PRESS ENTER here in the terminal to generare the QR code and scan it with the app."
read key

clear
echo "*** STEP 2 : Click on Scan (make whole QR code fill camera) ***"

if [ ${#dynDomain} -eq 0 ]; then
  # If you drop the -i parameter, lndconnect will use the external IP.
  lndconnect -i --port=8080
else
  # when dynamic domain is set
  lndconnect --host=${dynDomain} --port=8080
fi

echo "(To shrink QR code: OSX->CMD- / LINUX-> CTRL-) Press ENTER when finished."
read key

clear
echo "If it's not working - check issues on GitHub:"
echo "https://github.com/ZeusLN/zeus"
echo "https://github.com/LN-Zap/lndconnect/issues"
echo ""
