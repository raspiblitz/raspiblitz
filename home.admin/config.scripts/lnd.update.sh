#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "Interim optional LND updates between RaspiBlitz releases."
 echo "lnd.update.sh [info|secure|reckless]"
 echo "info -> get actual state and possible actions"
 echo "secure -> only do recommended updates by RaspiBlitz team"
 echo "  binary will be checked by signature and checksum"
 echo "reckless -> if you just want to update to the latest release"
 echo "  published on LND GitHub releases (RC or final) without any"
 echo "  testing or security checks."
 exit 1
fi

# 1. parameter [info|secure|reckless]
mode="$1"

# RECOMMENDED UPDATE BY RASPIBLITZ TEAM

lndUpdateVersion="0.10.0-beta"
lndUpdateComment="Some optional apps might not work with this update. You will not be able to downgrade after LND database migration."

# GATHER DATA

# detect CPU architecture & fitting download link
cpuArchitecture=""
if [ $(uname -m | grep -c 'arm') -eq 1 ] ; then
  cpuArchitecture="armv7"
fi
if [ $(uname -m | grep -c 'aarch64') -eq 1 ] ; then
  cpuArchitecture="arm64"
fi
if [ $(uname -m | grep -c 'x86_64') -eq 1 ] ; then
  cpuArchitecture="amd64"
fi
if [ $(uname -m | grep -c 'i386\|i486\|i586\|i686\|i786') -eq 1 ] ; then
  cpuArchitecture="386"
fi

# installed LND version
lndInstalledVersion=$(sudo -u bitcoin lncli --network=mainnet --chain=bitcoin  getinfo | jq -r ".version" | cut -d " " -f1)
lndInstalledVersionMajor=$(echo "${lndInstalledVersion}" | cut -d "-" -f1 | cut -d "." -f1)
lndInstalledVersionMain=$(echo "${lndInstalledVersion}" | cut -d "-" -f1 | cut -d "." -f2)
lndInstalledVersionMinor=$(echo "${lndInstalledVersion}" | cut -d "-" -f1 | cut -d "." -f3)

# test if the installed version already the secure/recommended update version
lndUpdateInstalled=$(echo "${lndInstalledVersion}" | grep -c "lndUpdateVersion")

# get latest release from LND GitHub releases
gitHubLatestReleaseJSON="$(curl -s https://api.github.com/repos/lightningnetwork/lnd/releases | jq '.[0]')"
lndLatestVersion=$(echo "${gitHubLatestReleaseJSON}" | jq -r '.tag_name')
lndLatestDownload=$(echo "${gitHubLatestReleaseJSON}" | grep "browser_download_url" | grep "linux-${cpuArchitecture}" | cut -d '"' -f4)

# INFO
if [ "${mode}" = "info" ]; then

  echo "# basic data"
  echo "cpuArchitecture='${cpuArchitecture}'"
  echo "lndInstalledVersion='${lndInstalledVersion}'"
  echo "lndInstalledVersionMajor='${lndInstalledVersionMajor}'"
  echo "lndInstalledVersionMain='${lndInstalledVersionMain}'"
  echo "lndInstalledVersionMinor='${lndInstalledVersionMinor}'"

  echo "# the secure/recommended update option"
  echo "lndUpdateInstalled='${lndUpdateInstalled}'"
  echo "lndUpdateVersion='${lndUpdateVersion}'"
  echo "lndUpdateComment='${lndUpdateComment}'"

  echo "# reckless update option (latest LND release from GitHub)"
  echo "lndLatestVersion='${lndLatestVersion}'"
  echo "lndLatestDownload='${lndLatestDownload}'"


# SECURE
elif [ "${mode}" = "secure" ]; then

  echo "# lnd.update.sh secure"

  # check for optional second parameter: forced update version
  # --> only does the secure update if its the given version
  # this is needed for recovery/update. 
  fixedUpdateVersion="$2"
  if [ ${#fixedUpdateVersion} -gt 0 ]; then
    echo "# checking for fixed version update: askedFor(${fixedUpdateVersion}) available(${lndUpdateVersion})"
    if [ "${fixedUpdateVersion}" != "${lndUpdateVersion}" ]; then
      echo "warn='required update version does not match'"
      echo "# this is normal when the recovery script of a new RaspiBlitz version checks for an old update - just ignore"
      exit 1
    else
      echo "# OK - update version is matching"
    fi
  fi

  echo "# TODO install secure"

# RECKLESS
# this mode is just for people running test and development nodes - its not recommended
# for production nodes. In a update/recovery scenario it will not install a fixed version
# it will always pick the latest release from the github
elif [ "${mode}" = "reckless" ]; then

  echo "# TODO install reckless"

# NOT KNOWN PARAMETER
else
  echo "error='parameter not known'"
fi
