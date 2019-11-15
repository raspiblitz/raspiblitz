#!/bin/bash

# This is for developing on your RaspiBlitz.
# THIS IS NOT THE REGULAR UPDATE MECHANISM
# and can lead to dirty state of your scripts.
# IF YOU WANT TO UPDATE YOUR RASPIBLITZ:
# https://github.com/rootzoll/raspiblitz/blob/master/FAQ.md#how-to-update-my-raspiblitz-after-version-098

cd /home/admin/raspiblitz

# change branch if set as parameter
clean=0
wantedBranch="$1"
if [ "${wantedBranch}" = "-clean" ]; then
  clean=1
  wantedBranch="$2"
fi
if [ "$2" = "-clean" ]; then
  clean=1
fi

activeBranch=$(git branch | grep \* | cut -d ' ' -f2)
if [ ${#wantedBranch} -gt 0 ]; then
  echo "your wanted branch is: ${wantedBranch}"
  echo "your active branch is: ${activeBranch}"
  if [ "${wantedBranch}" = "${activeBranch}" ]; then
    echo "OK"
  else
    echo "try changing branch .."
    git checkout ${wantedBranch}
    activeBranch=$(git branch | grep \* | cut -d ' ' -f2)
  fi
else
  echo ""
  echo "USAGE-INFO: ./XXsyncScripts.sh '[BRANCHNAME]'"
fi

origin=$(git remote -v | grep 'origin' | tail -n1)

echo ""
echo "*** SYNCING SHELL SCRIPTS WITH GITHUB ***"
echo "This is for developing on your RaspiBlitz."
echo "THIS IS NOT THE REGULAR UPDATE MECHANISM"
echo "and can lead to dirty state of your scripts."
echo "REPO ----> ${origin}"
echo "BRANCH --> ${activeBranch}"
echo "******************************************"
git pull
cd ..
if [ ${clean} -eq 1 ]; then
  echo "Cleaning scripts & assets/config.scripts"
  rm *.sh
  rm -r assets
  mkdir assets
  rm -r config.scripts
  mkdir config.scripts
else
  echo "******************************************"
  echo "NOT cleaning/deleting old files"
  echo "use parameter '-clean' if you want that next time"
  echo "******************************************"
fi
echo "COPYING from GIT-Directory to /home/admin/ .."
sudo -u admin cp -r -f /home/admin/raspiblitz/home.admin/*.* /home/admin
sudo -u admin cp -r -f /home/admin/raspiblitz/home.admin/assets/*.* /home/admin/assets
sudo -u admin chmod +x /home/admin/*.sh
sudo -u admin chmod +x /home/admin/*.py
sudo -u admin chmod +x /home/admin/config.scripts/*.sh
sudo -u admin chmod +x /home/admin/config.scripts/*.py
echo "******************************************"
echo "OK - shell scripts and assests are synced"
echo "Reboot recommended"
echo ""
