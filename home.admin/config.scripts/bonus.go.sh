#!/usr/bin/env sh

# set version, check: https://golang.org/dl/
goVersion="1.19.5"
# checksums:
amd64Checksum="36519702ae2fd573c9869461990ae550c8c0d955cd28d2827a6b159fda81ff95"
armv6lChecksum="ec14f04bdaf4a62bdcf8b55b9b6434cc27c2df7d214d0bb7076a7597283b026a"
arm64Checksum="fc0aa29c933cec8d76f5435d859aaf42249aa08c74eb2d154689ae44c08d23b3"

downloadFolder="/home/admin/download"

usage() {
  printf "Config script to install or remove Go\n"
  printf "./bonus.go.sh [on|off]\n"
  exit 1
}

case "$1" in

1 | on)          # switch on
  . /etc/profile # get Go vars - needed if there was no log-out since Go installed
  printf "# Check Framework: Go\n"
  if go version 2>/dev/null | grep -q "${goVersion}"; then
    printf "\nThe requested version of Go is already installed.\n"
    go version
    printf "\n"
  else
    goOSversion=$(dpkg --print-architecture)
    if [ ${goOSversion} = "armv6l" ]; then
      checksum=${armv6lChecksum}
    elif [ ${goOSversion} = "arm64" ]; then
      checksum=${arm64Checksum}
    elif [ ${goOSversion} = "amd64" ]; then
      checksum=${amd64Checksum}
    else
      echo "# architecture $goOSversion not supported"
      exit 1
    fi

    printf %s"\n*** Installing Go v${goVersion} for ${goOSversion} \n***"
    wget --show-progress https://dl.google.com/go/go${goVersion}.linux-${goOSversion}.tar.gz -P ${downloadFolder} > /dev/null
    if [ ! -f "${downloadFolder}/go${goVersion}.linux-${goOSversion}.tar.gz" ]; then
      printf "# FAIL # Download failed.\n"
      rm -fv go${goVersion}.linux-${goOSversion}.tar.gz*
      exit 1
    fi
    if ! echo ${checksum} ${downloadFolder}/go${goVersion}.linux-${goOSversion}.tar.gz | sha256sum -c; then
      printf "# FAIL: Download corrupted\n"
      rm -fv ${downloadFolder}/go${goVersion}.linux-${goOSversion}.tar.gz*
      exit 1
    fi

    printf "# Clean old Go version\n"
    sudo rm -rf /usr/local/go /usr/local/gocode
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
    go version | grep -q "go" || {
      printf "FAIL: Unable to install Go\n"
      exit 1
    }
    printf %s"Installed $(go version 2>/dev/null)\n\n"
  fi
  ;;

0 | off) # switch off
  printf "*** REMOVING GO ***\n"
  sudo rm -rf /usr/local/go /usr/local/gocode
  printf "# OK Go removed.\n"
  ;;

*) usage ;;

esac
