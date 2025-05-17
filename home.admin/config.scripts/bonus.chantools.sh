#!/bin/bash

# Channel Tools install script

# see https://github.com/guggero/chantools/releases

lndVersion=$(lncli -v | cut -d " " -f 3 | cut -d"." -f2)
if [ $lndVersion -gt 15 ]; then
  pinnedVersion="0.13.7"
else
  echo "# LND is not installed or is an outdated version (v0.15.x or lower)"
  lncli -v
  exit 1
fi

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "Channel Tools install script"
 echo "/home/admin/config.scripts/bonus.chantools.sh on|off|menu"
 echo "Installs the version $pinnedVersion by default."
 exit 1
fi

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " Channel Tools ${pinnedVersion} " --msgbox "\n
Channel Tools is a command line tool to rescue locked funds.\n\n
On terminal use command 'chantools' and follow instructions.\n\n
Usage: https://github.com/guggero/chantools/blob/master/README.md
" 11 75
  clear
  exit 0
fi

# install
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  downloadDir="/home/admin/download"  # edit your download directory
  PGPpkeys="https://keybase.io/guggero/pgp_keys.asc"
  PGPcheck="F4FC70F07310028424EFC20A8E4256593F177720"

  echo "Detect CPU architecture ..."
  isARM=$(uname -m | grep -c 'arm')
  isAARCH64=$(uname -m | grep -c 'aarch64')
  isX86_64=$(uname -m | grep -c 'x86_64')
  if [ ${isARM} -eq 0 ] && [ ${isAARCH64} -eq 0 ] && [ ${isX86_64} -eq 0 ] ; then
    echo "# FAIL #"
    echo "# Can only build on arm, aarch64 or x86_64 not on:"
    uname -m
    exit 1
  else
    echo "# OK running on $(uname -m) architecture."
  fi

  cd "${downloadDir}"

  # extract the SHA256 hash from the manifest file for the corresponding platform
  sudo -u admin wget -N https://github.com/guggero/chantools/releases/download/v${pinnedVersion}/manifest-v${pinnedVersion}.txt

  # get the SHA256 for the corresponding platform from manifest file
  if [ ${isARM} -eq 1 ] ; then
    OSversion="armv7"
  elif [ ${isAARCH64} -eq 1 ] ; then
    OSversion="arm64"
  elif [ ${isX86_64} -eq 1 ] ; then
    OSversion="amd64"
  fi
  SHA256=$(grep -i "linux-$OSversion" manifest-v$pinnedVersion.txt | cut -d " " -f1)
  echo
  echo "# Channel Tools v${pinnedVersion} for ${OSversion}"
  echo "# SHA256 hash: $SHA256"
  echo

  # get binary
  binaryName="chantools-linux-${OSversion}-v${pinnedVersion}.tar.gz"
  sudo -u admin wget -N https://github.com/guggero/chantools/releases/download/v${pinnedVersion}/${binaryName}

  # check binary was not manipulated (checksum test)
  sudo -u admin wget -N https://github.com/guggero/chantools/releases/download/v${pinnedVersion}/manifest-v${pinnedVersion}.txt
  sudo -u admin wget --no-check-certificate -N -O "${downloadDir}/pgp_keys.asc" ${PGPpkeys}
  binaryChecksum=$(sha256sum ${binaryName} | cut -d " " -f1)
  if [ "${binaryChecksum}" != "${SHA256}" ]; then
    echo "# FAIL # Downloaded Channel Tools BINARY not matching SHA256 checksum: ${SHA256}"
    exit 1
  fi

  # check gpg finger print
  gpg --show-keys ./pgp_keys.asc
  fingerprint=$(sudo gpg --show-keys "${downloadDir}/pgp_keys.asc" 2>/dev/null | grep "${PGPcheck}" -c)
  if [ ${fingerprint} -lt 1 ]; then
    echo
    echo "# BUILD WARNING --> Channel Tools PGP author not as expected"
    echo "# Should contain PGP: ${PGPcheck}"
    echo "# PRESS ENTER to TAKE THE RISK if you think all is OK"
    read key
  fi
  gpg --import ./pgp_keys.asc
  sleep 3
  sudo -u admin wget -N https://github.com/guggero/chantools/releases/download/v${pinnedVersion}/manifest-v${pinnedVersion}.sig

  echo "# running: gpg --verify manifest-v${pinnedVersion}.sig manifest-v${pinnedVersion}.txt"
  verifyResult=$(LANG=en_US.utf8; gpg --verify manifest-v${pinnedVersion}.sig manifest-v${pinnedVersion}.txt 2>&1)
  echo "# verifyResult(${verifyResult})"
  goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
  echo "# goodSignature(${goodSignature})"
  correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${GPGcheck}" -c)
  echo "# correctKey(${correctKey})"
  if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
    echo
    echo "# BUILD FAILED --> Channel Tools PGP Verify not OK / signature(${goodSignature}) verify(${correctKey})"
    exit 1
  fi

  # install
  sudo -u admin tar -xzf ${binaryName}
  sudo install -m 0755 -o root -g root -t /usr/local/bin/ chantools-linux-${OSversion}-v${pinnedVersion}/*
  sleep 3
  installed=$(sudo -u bitcoin chantools --version)
  if [ ${#installed} -eq 0 ]; then
    echo
    echo "# BUILD FAILED --> Was not able to install Channel Tools"
    exit 1
  fi
  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set chantools "on"

  echo
  echo "Installed ${installed}"
  echo "
# Channel Tools is a command line tool.
# Type: 'sudo su - bitcoin' in the command line to switch to the bitcoin user.
# Then see 'chantools' for the options.
# Usage: https://github.com/guggero/chantools/blob/master/README.md
"
  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set chantools "off"

  echo "# REMOVING Channel Tools"
  sudo rm -rf /home/admin/download/chantools*
  sudo rm -rf /usr/local/bin/chantools*
  echo "# OK, chantools is removed."
  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
exit 1