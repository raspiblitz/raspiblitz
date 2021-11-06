#!/usr/bin/env sh

# set version, check: https://golang.org/dl/
goVersion="1.17.3"
downloadFolder="/home/admin/download"

case "$1" in

  1|on) # switch on
    . /etc/profile # get Go vars - needed if there was no log-out since Go installed
    printf "Check Framework: Go\n"
    if go version | grep -q "go" ; then
      printf "\nVersion of Go requested already installed.\n"
      go version
      printf "\n"
    else
      architecture="$(uname -m)"
      case "${architecture}" in
        arm*) goOSversion="armv6l";;
        aarch64) goOSversion="arm64";;
        x86_64) goOSversion="amd64";;
        *) printf %s"Not available for architecture=${architecture}\n"; exit 1
      esac
      printf %s"*** Installing Go v${goVersion} for ${goOSversion} \n***"
      wget https://dl.google.com/go/go${goVersion}.linux-${goOSversion}.tar.gz -P ${downloadFolder}
      if [ ! -f "${downloadFolder}/go${goVersion}.linux-${goOSversion}.tar.gz" ]; then
        printf "!!! FAIL !!! Download failed.\n"
        rm -fv go${goVersion}.linux-${goOSversion}.tar.gz*
        exit 1
      fi
      sudo tar -C /usr/local -xzf ${downloadFolder}/go${goVersion}.linux-${goOSversion}.tar.gz
      rm -fv ${downloadFolder}/go${goVersion}.linux-${goOSversion}.tar.gz*
      sudo mkdir -v /usr/local/gocode
      sudo chmod -v 777 /usr/local/gocode
      export GOROOT=/usr/local/go
      export PATH=$PATH:$GOROOT/bin
      export GOPATH=/usr/local/gocode
      export PATH=$PATH:$GOPATH/bin
      sudo grep -q "GOROOT=" /etc/profile || { printf "\nGOROOT=/usr/local/go\nPATH=\$PATH:\$GOROOT/bin/\nGOPATH=/usr/local/gocode\nPATH=\$PATH:\$GOPATH/bin/\n\n" | sudo tee -a /etc/profile; }
      go env -w GOPATH=/usr/local/gocode # set GOPATH https://github.com/golang/go/wiki/SettingGOPATH
      go version | grep -q "go" || { printf "FAIL: Unable to install Go\n"; exit 1; }
      printf %s"\nInstalled $(go version 2>/dev/null)\n\n"
    fi
  ;;

  0|off) # switch off
    printf "*** REMOVING GO ***\n"
    sudo rm -rf /usr/local/go /usr/local/gocode
    printf "OK Go removed.\n"
  ;;

  *) printf "Config script to install or remove Go\n./bonus.go.sh [on|off]\n"; exit 1

esac