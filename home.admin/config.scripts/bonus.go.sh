#!/usr/bin/env sh

# set version, check: https://go.dev/dl/
goVersion="1.23.0"
# checksums:
amd64Checksum="905a297f19ead44780548933e0ff1a1b86e8327bb459e92f9c0012569f76f5e3"
armv6lChecksum="0efa1338e644d7f74064fa7f1016b5da7872b2df0070ea3b56e4fef63192e35b"
arm64Checksum="62788056693009bcf7020eedc778cdd1781941c6145eab7688bd087bce0f8659"

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
    echo "# Downloading https://dl.google.com/go/go${goVersion}.linux-${goOSversion}.tar.gz ..."
    wget --quiet https://dl.google.com/go/go${goVersion}.linux-${goOSversion}.tar.gz -P ${downloadFolder}
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
