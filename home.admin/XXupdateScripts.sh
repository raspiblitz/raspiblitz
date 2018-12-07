#!/bin/bash

cd /home/admin/raspiblitz

# change branch if set as parameter
wantedBranch=$1
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
fi

echo ""
echo "*** UPDATING SHELL SCRIPTS FROM GITHUB ***"
echo "justincase, not the final upadte mechanism"
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
echo "OK - shell scripts and assests are up to date"
echo "Reboot recommended"
echo ""
