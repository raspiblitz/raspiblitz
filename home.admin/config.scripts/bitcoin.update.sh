#!/bin/bash

# based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_30_bitcoin.md#installation

# set version (change if update is available)
# https://bitcoincore.org/en/download/
bitcoinVersion="0.19.0.1"

# needed to check code signing
laanwjPGP="01EA5486DE18A882D4C2684590C8019E36C2E964"

echo "Detecting CPU architecture ..."
isARM=$(uname -m | grep -c 'arm')
isAARCH64=$(uname -m | grep -c 'aarch64')
isX86_64=$(uname -m | grep -c 'x86_64')
if [ ${isARM} -eq 0 ] && [ ${isAARCH64} -eq 0 ] && [ ${isX86_64} -eq 0 ] ; then
  echo "!!! FAIL !!!"
  echo "Can only build on ARM, aarch64, x86_64 or i386 not on:"
  uname -m
  exit 1
else
 echo "OK running on $(uname -m) architecture."
fi

echo "Checking if LND is up to date"
lndInstalled=$(lnd --version | grep v0.8.1 -c)
if [ ${lndInstalled} -eq 1 ]; then
  echo "ok, LND v0.8.1-beta is installed"
else
  echo""
  echo "LND version lower than v0.8.1 is incompatible with bitcoin v0.19"
  echo "Update LND first"
  echo "Find the update script here: https://github.com/openoms/raspiblitz-extras#lnd-update-to-v081-beta"
  exit 1
fi

echo ""
echo "*** PREPARING BITCOIN ***"

# prepare directories
sudo rm -rf /home/admin/download 2>/dev/null
sudo -u admin mkdir /home/admin/download 2>/dev/null
cd /home/admin/download

# download, check and import signer key
sudo -u admin wget https://bitcoin.org/laanwj-releases.asc
if [ ! -f "./laanwj-releases.asc" ]
then
  echo "!!! FAIL !!! Download laanwj-releases.asc not success."
  exit 1
fi
gpg ./laanwj-releases.asc
fingerprint=$(gpg ./laanwj-releases.asc 2>/dev/null | grep "${laanwjPGP}" -c)
if [ ${fingerprint} -lt 1 ]; then
  echo ""
  echo "!!! BUILD WARNING --> Bitcoin PGP author not as expected"
  echo "Should contain laanwjPGP: ${laanwjPGP}"
  echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
  read key
fi
gpg --import ./laanwj-releases.asc

# download signed binary sha256 hash sum file and check
sudo -u admin wget https://bitcoin.org/bin/bitcoin-core-${bitcoinVersion}/SHA256SUMS.asc
verifyResult=$(gpg --verify SHA256SUMS.asc 2>&1)
goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "goodSignature(${goodSignature})"
correctKey=$(echo ${verifyResult} |  grep "using RSA key ${laanwjPGP: -16}" -c)
echo "correctKey(${correctKey})"
if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> LND PGP Verify not OK / signatute(${goodSignature}) verify(${correctKey})"
  exit 1
else
  echo ""
  echo "****************************************"
  echo "OK --> BITCOIN MANIFEST IS CORRECT"
  echo "****************************************"
  echo ""
fi

# get the sha256 value for the corresponding platform from signed hash sum file
if [ ${isARM} -eq 1 ] ; then
  bitcoinOSversion="arm-linux-gnueabihf"
fi
if [ ${isAARCH64} -eq 1 ] ; then
  bitcoinOSversion="aarch64-linux-gnu"
fi
if [ ${isX86_64} -eq 1 ] ; then
  bitcoinOSversion="x86_64-linux-gnu"
fi
bitcoinSHA256=$(grep -i "$bitcoinOSversion" SHA256SUMS.asc | cut -d " " -f1)

echo ""
echo "*** BITCOIN v${bitcoinVersion} for ${bitcoinOSversion} ***"

# download resources
binaryName="bitcoin-${bitcoinVersion}-${bitcoinOSversion}.tar.gz"
sudo -u admin wget https://bitcoin.org/bin/bitcoin-core-${bitcoinVersion}/${binaryName}
if [ ! -f "./${binaryName}" ]
then
    echo "!!! FAIL !!! Download BITCOIN BINARY not success."
    exit 1
fi

# check binary checksum test
binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
if [ "${binaryChecksum}" != "${bitcoinSHA256}" ]; then
  echo "!!! FAIL !!! Downloaded BITCOIN BINARY not matching SHA256 checksum: ${bitcoinSHA256}"
  exit 1
else
  echo ""
  echo "****************************************"
  echo "OK --> VERIFIED BITCOIN CHECKSUM CORRECT"
  echo "****************************************"
  echo ""
fi

echo "Stopping bitcoind and lnd"
sudo systemctl stop lnd
sudo systemctl stop bitcoind


# install
sudo -u admin tar -xvf ${binaryName}
sudo install -m 0755 -o root -g root -t /usr/local/bin/ bitcoin-${bitcoinVersion}/bin/*
sleep 3
installed=$(sudo -u admin bitcoind --version | grep "${bitcoinVersion}" -c)
if [ ${installed} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> Was not able to install bitcoind version(${bitcoinVersion})"
  exit 1
fi

sudo systemctl start bitcoind
sleep 2

echo ""
echo "Installed $(sudo -u admin bitcoind --version | grep version)"
echo ""

sudo systemctl start lnd
sleep 10

echo "Unlock lnd with the Password C"
lncli unlock