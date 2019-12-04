#!/bin/bash

# LND Update Script

# Download and run this script on the RaspiBlitz:
# $ wget https://raw.githubusercontent.com/openoms/raspiblitz-extras/master/config.scripts/lnd.update.sh && bash lnd.update.sh

## based on https://github.com/Stadicus/guides/blob/master/raspibolt/raspibolt_40_lnd.md#lightning-lnd
## see LND releases: https://github.com/lightningnetwork/lnd/releases

lndVersion="0.8.1-beta"  # the version you would like to be updated
downloadDir="/home/admin/download"  # edit your download directory

# check who signed the release in https://github.com/lightningnetwork/lnd/releases
# olaoluwa
PGPpkeys="https://keybase.io/roasbeef/pgp_keys.asc"
PGPcheck="9769140D255C759B1EB77B46A96387A57CAAE94D"

# bitconner 
# PGPpkeys="https://keybase.io/bitconner/pgp_keys.asc"
# PGPcheck="9C8D61868A7C492003B2744EE7D737B67FA592C7"

# wpaulino
# PGPpkeys="https://keybase.io/wpaulino/pgp_keys.asc"
# PGPcheck="729E9D9D92C75A5FBFEEE057B5DD717BEF7CA5B1"

echo "Detect CPU architecture ..." 
isARM=$(uname -m | grep -c 'arm')
isAARCH64=$(uname -m | grep -c 'aarch64')
isX86_64=$(uname -m | grep -c 'x86_64')
isX86_32=$(uname -m | grep -c 'i386\|i486\|i586\|i686\|i786')
if [ ${isARM} -eq 0 ] && [ ${isAARCH64} -eq 0 ] && [ ${isX86_64} -eq 0 ] && [ ${isX86_32} -eq 0 ] ; then
  echo "!!! FAIL !!!"
  echo "Can only build on ARM, aarch64, x86_64 or i386 not on:"
  uname -m
  exit 1
else
 echo "OK running on $(uname -m) architecture."
fi

cd "${downloadDir}"

# extract the SHA256 hash from the manifest file for the corresponding platform
sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-v${lndVersion}.txt
if [ ${isARM} -eq 1 ] ; then
  lndOSversion="armv7"
  lndSHA256=$(grep -i "linux-$lndOSversion" manifest-v$lndVersion.txt | cut -d " " -f1)
fi
if [ ${isAARCH64} -eq 1 ] ; then
  lndOSversion="arm64"
  lndSHA256=$(grep -i "linux-$lndOSversion" manifest-v$lndVersion.txt | cut -d " " -f1)
fi
if [ ${isX86_64} -eq 1 ] ; then
  lndOSversion="amd64"
  lndSHA256=$(grep -i "linux-$lndOSversion" manifest-v$lndVersion.txt | cut -d " " -f1)
fi 
if [ ${isX86_32} -eq 1 ] ; then
  lndOSversion="386"
  lndSHA256=$(grep -i "linux-$lndOSversion" manifest-v$lndVersion.txt | cut -d " " -f1)
fi 
echo ""
echo "*** LND v${lndVersion} for ${lndOSversion} ***"
echo "SHA256 hash: $lndSHA256"
echo ""

# get LND binary
binaryName="lnd-linux-${lndOSversion}-v${lndVersion}.tar.gz"
sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/${binaryName}

# check binary was not manipulated (checksum test)
sudo -u admin wget -N https://github.com/lightningnetwork/lnd/releases/download/v${lndVersion}/manifest-v${lndVersion}.txt.sig
sudo -u admin wget -N -O "${downloadDir}/pgp_keys.asc" ${PGPpkeys}
binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
if [ "${binaryChecksum}" != "${lndSHA256}" ]; then
  echo "!!! FAIL !!! Downloaded LND BINARY not matching SHA256 checksum: ${lndSHA256}"
  exit 1
fi

# check gpg finger print
gpg ./pgp_keys.asc
fingerprint=$(sudo gpg "${downloadDir}/pgp_keys.asc" 2>/dev/null | grep "${PGPcheck}" -c)
if [ ${fingerprint} -lt 1 ]; then
  echo ""
  echo "!!! BUILD WARNING --> LND PGP author not as expected"
  echo "Should contain PGP: ${PGPcheck}"
  echo "PRESS ENTER to TAKE THE RISK if you think all is OK"
  read key
fi
gpg --import ./pgp_keys.asc
sleep 3
verifyResult=$(gpg --verify manifest-v${lndVersion}.txt.sig 2>&1)
goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "goodSignature(${goodSignature})"
correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${GPGcheck}" -c)
echo "correctKey(${correctKey})"
if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
  echo ""
  echo "!!! BUILD FAILED --> LND PGP Verify not OK / signature(${goodSignature}) verify(${correctKey})"
  exit 1
fi

sudo systemctl stop lnd

# install
sudo -u admin tar -xzf ${binaryName}
sudo install -m 0755 -o root -g root -t /usr/local/bin lnd-linux-${lndOSversion}-v${lndVersion}/*
sleep 3
installed=$(sudo -u admin lnd --version)
if [ ${#installed} -eq 0 ]; then
  echo ""
  echo "!!! BUILD FAILED --> Was not able to install LND"
  exit 1
fi

sudo systemctl start lnd

sleep 5
echo ""
echo "Installed ${installed}"

sleep 5
lncli unlock