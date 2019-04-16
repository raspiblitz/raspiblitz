#!/bin/bash

# load raspiblitz config data
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
source /home/admin/_version.info

clear

# get latest release verison from GitHub
sudo curl -s -X GET https://raw.githubusercontent.com/rootzoll/raspiblitz/master/home.admin/_version.info > /home/admin/.version.tmp
gitHubVersionMain=$(cut -d"=" -f2 /home/admin/.version.tmp | cut -d'"' -f2 | cut -d"." -f1 | egrep "^[0-9]")
gitHubVersionSub=$(cut -d"=" -f2 /home/admin/.version.tmp | cut -d'"' -f2 | cut -d"." -f1 | egrep "^[0-9]")
sudo shred /home/admin/.version.tmp
sudo rm /home/admin/.version.tmp 2>/dev/null

# check valid version info
if [ ${#gitHubVersionMain} -eq 0 ] || [ ${#gitHubVersionSub} -eq 0 ]; then
  echo "FAIL: Was not able to get latest release Version from GitHub."
  echo "PRESS ENTER to continue."
  read key
  exit 1
fi

# get local version
localVersionMain=$(cut -d"=" -f2 /home/admin/_version.info | cut -d'"' -f2 | cut -d"." -f1 | egrep "^[0-9]")
localVersionSub=$(cut -d"=" -f2 /home/admin/_version.info | cut -d'"' -f2 | cut -d"." -f1 | egrep "^[0-9]")

echo "local  version: ${gitHubVersionMain}.${gitHubVersionSub}"
echo "github version: ${localVersionMain}.${localVersionSub}"

# compare versions
newerVersionAvailable=0
if [ ${gitHubVersionMain} -gt ${localVersionMain} ]; then
  echo "Main version is higher ..."
  newerVersionAvailable=1
else
  if [ ${gitHubVersionMain} -lt ${localVersionMain} ]; then
    echo "Strange that GutHub main version is lower then local - you maybe using a early release."
  elif [ ${gitHubVersionSub} -gt ${localVersionSub} ]; then
  echo "Sub version is higher ..."
  newerVersionAvailable=1
  fi
fi

# give feedback on version number
if [ ${newerVersionAvailable} -eq 0 ]; then
  echo "You have the latest version running."
else
  echo "New Version available on the RaspiBlitz Repo."
fi






