#!/bin/bash

# This is for developing on your RaspiBlitz.
# THIS IS NOT THE REGULAR UPDATE MECHANISM
# and can lead to dirty state of your scripts.
# IF YOU WANT TO UPDATE YOUR RASPIBLITZ:
# https://github.com/rootzoll/raspiblitz/blob/dev/FAQ.md#how-to-update-my-raspiblitz-after-version-098

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "FOR DEVELOPMENT USE ONLY!"
  echo "RaspiBlitz Sync Scripts"
  echo "blitz.github.sh info"
  echo "blitz.github.sh [-run|-install|-justinstall] branch [repo]"
  exit 1
fi

source /mnt/hdd/raspiblitz.conf 2>/dev/null

cd /home/admin/raspiblitz

# gather info
activeGitHubUser=$(sudo -u admin cat /home/admin/raspiblitz/.git/config 2>/dev/null | grep "url = " | cut -d "=" -f2 | cut -d "/" -f4)
activeBranch=$(git branch 2>/dev/null | grep \* | cut -d ' ' -f2)
commitHashLong=$(git log -n1 --format=format:"%H")
commitHashShort=${commitHashLong:0:7}

# if parameter is "info" just give back basic info about sync
if [ "$1" == "info" ]; then

  echo "activeGitHubUser='${activeGitHubUser}'"
  echo "activeBranch='${activeBranch}'"
  echo "commitHashLong='${commitHashLong}'"
  echo "commitHashShort='${commitHashShort}'"
  exit 1
fi

# change branch if set as parameter
vagrant=0
clean=0
install=0
wantedBranch="$1"
wantedGitHubUser="$2"
if [ "${wantedBranch}" = "-run" ]; then
  # "-run" its just used by "patch" command and will ignore all further parameter
  wantedBranch="${activeBranch}"
  wantedGitHubUser="${activeGitHubUser}"
  # detect if running in vagrant VM
  vagrant=$(df | grep -c "/vagrant")
  if [ "$2" = "git" ]; then 
    echo "# forcing github over vagrant sync"
    vagrant=0
  fi
fi
if [ "${wantedBranch}" = "-install" ]; then
  install=1
  wantedBranch="$2"
  wantedGitHubUser="$3"
fi
if [ "${wantedBranch}" = "-justinstall" ]; then
  clean=1
  install=1
  wantedBranch=""
  wantedGitHubUser=""
fi

# set to another GutHub repo as origin
if [ ${#wantedGitHubUser} -gt 0 ] && [ ${vagrant} -eq 0 ]; then
  echo "# your active GitHubUser is: ${activeGitHubUser}"
  echo "# your wanted GitHubUser is: ${wantedGitHubUser}"
  if [ "${activeGitHubUser}" = "${wantedGitHubUser}" ]; then
    echo "# OK"
  else

    echo "# checking repo exists .."
    repoExists=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s https://api.github.com/repos/${wantedGitHubUser}/raspiblitz | jq -r '.name' | grep -c 'raspiblitz')
    if [ ${repoExists} -eq 0 ]; then
      echo "error='repo not found'"
      exit 1
    fi

    echo "# try changing github origin .."
    git remote set-url origin https://github.com/${wantedGitHubUser}/raspiblitz.git
    activeGitHubUser=$(sudo -u admin cat /home/admin/raspiblitz/.git/config | grep "url = " | cut -d "=" -f2 | cut -d "/" -f4)
  fi
fi

if [ ${#wantedBranch} -gt 0 ] && [ ${vagrant} -eq 0 ]; then
  echo "# your active branch is: ${activeBranch}"
  echo "# your wanted branch is: ${wantedBranch}"
  if [ "${wantedBranch}" = "${activeBranch}" ]; then
    echo "# OK"
  else

    # always clean & install fresh on branch change
    clean=1
    install=1

    echo "# checking if branch is locally available"
    localBranch=$(git branch | grep -c "${wantedBranch}")
    if [ ${localBranch} -eq 0 ]; then
      echo "# checking branch exists .."
      branchExists=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s https://api.github.com/repos/${activeGitHubUser}/raspiblitz/branches/${wantedBranch} | jq -r '.name' | grep -c ${wantedBranch})
      if [ ${branchExists} -eq 0 ]; then
        echo "error='branch not found'"
        exit 1
      fi
      echo "# checkout/changing branch .."
      git fetch
      git checkout -b ${wantedBranch} origin/${wantedBranch}
    else
      echo "# changing branch .."
      git checkout ${wantedBranch}
    fi

    activeBranch=$(git branch | grep \* | cut -d ' ' -f2)
  fi
fi

checkSumBlitzPyBefore=$(find /home/admin/raspiblitz/home.admin/BlitzPy -type f -exec md5sum {} \; | md5sum)
checkSumBlitzTUIBefore=$(find /home/admin/raspiblitz/home.admin/BlitzTUI -type f -exec md5sum {} \; | md5sum)

if [ ${vagrant} -eq 0 ]; then
  origin=$(git remote -v | grep 'origin' | tail -n1)
  echo "# *** SYNCING RASPIBLITZ CODE WITH GITHUB ***"
  echo "# This is for developing on your RaspiBlitz."
  echo "# THIS IS NOT THE REGULAR UPDATE MECHANISM"
  echo "# and can lead to dirty state of your scripts."
  echo "# REPO ----> ${origin}"
  echo "# BRANCH --> ${activeBranch}"
  echo "# ******************************************"
  git config pull.rebase true
  git pull 1>&2
  cd ..
else
  cd ..
  echo "# --> VAGRANT IS ACTIVE"
  echo "# *** SYNCING RASPIBLITZ CODE WITH VAGRANT LINKED DIRECTORY ***"
  echo "# This is for developing on your RaspiBlitz with a VM."
  echo "# - delete /home/admin/raspiblitz"
  sudo rm -r /home/admin/raspiblitz
  sudo mkdir /home/admin/raspiblitz
  echo "# - copy from vagrant new raspiblitz files (ignore hidden dirs)"
  sudo cp -R /vagrant/* /home/admin/raspiblitz
  echo "# - set admin as owner of files"
  sudo chown admin:admin -R /home/admin/raspiblitz
fi

echo "# COPYING from GIT-Directory to /home/admin/"
echo "# - basic admin files"
sudo rm -f *.sh
sudo -u admin cp /home/admin/raspiblitz/home.admin/.tmux.conf /home/admin
sudo -u admin cp /home/admin/raspiblitz/home.admin/*.* /home/admin 2>/dev/null
sudo -u admin chmod 755 *.sh
echo "# - asset directory"
sudo rm -rf assets
sudo -u admin cp -R /home/admin/raspiblitz/home.admin/assets /home/admin/assets
echo "# - config.scripts directory"
sudo rm -rf /home/admin/config.scripts
sudo -u admin cp -R /home/admin/raspiblitz/home.admin/config.scripts /home/admin/config.scripts 
sudo -u admin chmod 755 /home/admin/config.scripts/*.sh
sudo -u admin chmod 755 /home/admin/config.scripts/*.py
echo "# - setup.scripts directory"
sudo rm -rf /home/admin/setup.scripts
sudo -u admin cp -R /home/admin/raspiblitz/home.admin/setup.scripts /home/admin/setup.scripts
sudo -u admin chmod 755 /home/admin/setup.scripts/*.sh
sudo -u admin chmod 755 /home/admin/config.scripts/*.py
echo "# ******************************************"

echo "# Checking if the content of BlitzPy changed .."
checkSumBlitzPyAfter=$(find /home/admin/raspiblitz/home.admin/BlitzPy -type f -exec md5sum {} \; | md5sum)
echo "# checkSumBlitzPyBefore = ${checkSumBlitzPyBefore}"
echo "# checkSumBlitzPyAfter  = ${checkSumBlitzPyAfter}"
if [ "${checkSumBlitzPyBefore}" = "${checkSumBlitzPyAfter}" ] && [ ${install} -eq 0 ]; then
  echo "# BlitzPy did not changed."
else
  blitzpy_wheel=$(ls -trR /home/admin/raspiblitz/home.admin/BlitzPy/dist | grep -E ".*any.whl" | tail -n 1)
  blitzpy_version=$(echo ${blitzpy_wheel} | grep -oE "([0-9]\.[0-9]\.[0-9])")
  echo "# BlitzPy changed --> UPDATING to Version ${blitzpy_version}"
  sudo pip config set global.break-system-packages true
  sudo -H /usr/bin/python -m pip install "/home/admin/raspiblitz/home.admin/BlitzPy/dist/${blitzpy_wheel}" >/dev/null 2>&1
fi

if [ "${touchscreen}" = "1" ]; then
  echo "# Checking if the content of BlitzTUI changed .."
  checkSumBlitzTUIAfter=$(find /home/admin/raspiblitz/home.admin/BlitzTUI -type f -exec md5sum {} \; | md5sum)
  echo "# checkSumBlitzTUIBefore = ${checkSumBlitzTUIBefore}"
  echo "# checkSumBlitzTUIAfter  = ${checkSumBlitzTUIAfter}"
  if [ "${checkSumBlitzTUIBefore}" = "${checkSumBlitzTUIAfter}" ] && [ ${install} -eq 0 ] && [ ${clean} -eq 0 ]; then
    echo "# BlitzTUI did not changed."
  else
    echo "# BlitzTUI changed --> UPDATING TOUCHSCREEN INSTALL ..."
    sudo /home/admin/config.scripts/blitz.touchscreen.sh update
  fi
fi
echo "# ******************************************"
echo "# OK - shell scripts and assets are synced"
echo "# Reboot recommended"
