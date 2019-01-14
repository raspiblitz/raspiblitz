#!/bin/bash

# This is for developing on your RaspiBlitz.
# THIS IS NOT THE REGULAR UPDATE MECHANISM
# and can lead to dirty state of your scripts.
# IF YOU WANT TO UPDATE YOUR RASPIBLITZ:
# https://github.com/rootzoll/raspiblitz/blob/master/FAQ.md#how-to-update-my-raspiblitz-after-version-098

cd /home/admin/raspiblitz

# change branch if set as parameter
wantedBranch="$1"
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
echo "*** SYCING SHELL SCRIPTS WITH GITHUB ***"
echo "This is for developing on your RaspiBlitz."
echo "THIS IS NOT THE REGULAR UPDATE MECHANISM"
echo "and can lead to dirty state of your scripts."
echo "REPO ----> ${origin}"
echo "BRANCH --> ${activeBranch}"
echo "******************************************"
git pull
cd ..
rm *.sh
rm -r assets
sudo -u admin cp /home/admin/raspiblitz/home.admin/*.* /home/admin
sudo -u admin chmod +x *.sh
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/assets /home/admin/
sudo -u admin cp -r /home/admin/raspiblitz/home.admin/config.scripts /home/admin/
sudo -u admin chmod +x /home/admin/config.scripts/*.sh
echo "******************************************"
echo "OK - shell scripts and assests are synced"
echo "Reboot recommended"
echo ""