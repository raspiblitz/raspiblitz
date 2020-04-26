#!/bin/bash

# This is for developing on your RaspiBlitz.
# THIS IS NOT THE REGULAR UPDATE MECHANISM
# and can lead to dirty state of your scripts.
# IF YOU WANT TO UPDATE YOUR RASPIBLITZ:
# https://github.com/rootzoll/raspiblitz/blob/master/FAQ.md#how-to-update-my-raspiblitz-after-version-098

cd /home/admin/raspiblitz
source /mnt/hdd/raspiblitz.conf 2>/dev/null

# gather info
activeGitHubUser=$(sudo -u admin cat /home/admin/raspiblitz/.git/config | grep "url = " | cut -d "=" -f2 | cut -d "/" -f4)
activeBranch=$(git branch | grep \* | cut -d ' ' -f2)

# if parameter is "info" just give back basic info about sync 
if [ "$1" == "info" ]; then
  echo "activeGitHubUser='${activeGitHubUser}'"
  echo "activeBranch='${activeBranch}'"
  exit 1
fi

# change branch if set as parameter
clean=0
wantedBranch="$1"
wantedGitHubUser="$2"
if [ "${wantedBranch}" = "-clean" ]; then
  clean=1
  wantedBranch="$2"
  wantedRepo="$3"
fi

# set to another GutHub repo as origin
if [ ${#wantedGitHubUser} -gt 0 ]; then
  echo "# your active GitHubUser is: ${activeGitHubUser}"
  echo "# your wanted GitHubUser is: ${wantedGitHubUser}"
  if [ "${activeGitHubUser}" = "${wantedGitHubUser}" ]; then
    echo "# OK"
  else

    echo "# checking repo exists .."
    repoExists=$(curl -s https://api.github.com/repos/${wantedGitHubUser}/raspiblitz | jq -r '.name' | grep -c 'raspiblitz')
    if [ ${repoExists} -eq 0 ]; then
      echo "error='repo not found'"
      exit 1
    fi

    echo "# try changing github origin .."
    git remote set-url origin https://github.com/${wantedGitHubUser}/raspiblitz.git
    activeGitHubUser=$(sudo -u admin cat /home/admin/raspiblitz/.git/config | grep "url = " | cut -d "=" -f2 | cut -d "/" -f4)
  fi
fi

if [ ${#wantedBranch} -gt 0 ]; then
  echo "# your active branch is: ${activeBranch}"
  echo "# your wanted branch is: ${wantedBranch}"
  if [ "${wantedBranch}" = "${activeBranch}" ]; then
    echo "# OK"
  else

    echo "# checking branch exists .."
    branchExists=$(curl -s https://api.github.com/repos/${activeGitHubUser}/raspiblitz/branches/${wantedBranch} | jq -r '.name' | grep -c '${wantedBranch}')
    if [ ${branchExists} -eq 0 ]; then
      echo "error='branch not found'"
      exit 1
    fi

    echo "# try changing branch .."
    git checkout ${wantedBranch}
    activeBranch=$(git branch | grep \* | cut -d ' ' -f2)
  fi
else
  echo ""
  echo "USAGE-INFO: ./XXsyncScripts.sh '[BRANCHNAME]'"
fi

origin=$(git remote -v | grep 'origin' | tail -n1)
checkSumBlitzTUIBefore=$(find /home/admin/raspiblitz/home.admin/BlitzTUI -type f -exec md5sum {} \; | md5sum)

echo "# *** SYNCING SHELL SCRIPTS WITH GITHUB ***"
echo "# This is for developing on your RaspiBlitz."
echo "# THIS IS NOT THE REGULAR UPDATE MECHANISM"
echo "# and can lead to dirty state of your scripts."
echo "# REPO ----> ${origin}"
echo "# BRANCH --> ${activeBranch}"
echo "# ******************************************"
git pull 1>&2
cd ..
if [ ${clean} -eq 1 ]; then
  echo "# Cleaning scripts & assets/config.scripts"
  rm *.sh
  rm -r assets
  mkdir assets
  rm -r config.scripts
  mkdir config.scripts
else
  echo "# ******************************************"
  echo "# NOT cleaning/deleting old files"
  echo "# use parameter '-clean' if you want that next time"
  echo "# ******************************************"
fi

echo "# COPYING from GIT-Directory to /home/admin/"
sudo -u admin cp -r -f /home/admin/raspiblitz/home.admin/*.* /home/admin
echo "# .."
sudo -u admin cp -r -f /home/admin/raspiblitz/home.admin/assets/*.* /home/admin/assets
echo "# .."
sudo -u admin chmod +x /home/admin/*.sh
echo "# .."
sudo -u admin chmod +x /home/admin/*.py
echo "# .."
sudo -u admin chmod +x /home/admin/config.scripts/*.sh
echo "# .."
sudo -u admin chmod +x /home/admin/config.scripts/*.py
echo "# ******************************************"
if [ "${touchscreen}" = "1" ]; then
  echo "# Checking if the content of BlitzTUI changed .."
  checkSumBlitzTUIAfter=$(find /home/admin/raspiblitz/home.admin/BlitzTUI -type f -exec md5sum {} \; | md5sum)
  echo "# checkSumBlitzTUIBefore = ${checkSumBlitzTUIBefore}"
  echo "# checkSumBlitzTUIAfter  = ${checkSumBlitzTUIAfter}"
  if [ "${checkSumBlitzTUIBefore}" = "${checkSumBlitzTUIAfter}" ]; then
    echo "# BlitzTUI did not changed."
  else
    echo "# BlitzTUI changed --> UPDATING TOUCHSCREEN INSTALL ..."
    sudo ./config.scripts/blitz.touchscreen.sh update
  fi
fi
echo "# ******************************************"
echo "# OK - shell scripts and assests are synced"
echo "# Reboot recommended"