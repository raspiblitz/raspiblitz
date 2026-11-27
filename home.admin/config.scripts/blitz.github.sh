#!/bin/bash

# This is for developing on your RaspiBlitz.
# THIS IS NOT THE REGULAR UPDATE MECHANISM
# and can lead to dirty state of your scripts.

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "FOR DEVELOPMENT USE ONLY!"
  echo "RaspiBlitz Sync Scripts"
  echo "blitz.github.sh info"
  echo "blitz.github.sh [-run|-install|-justinstall] branch [repo]"
  exit 1
fi

source /mnt/hdd/app-data/raspiblitz.conf 2>/dev/null

cd /home/admin/raspiblitz || exit 1

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
clean=0
install=0
wantedBranch="$1"
wantedGitHubUser="$2"
if [ "${wantedBranch}" = "-run" ]; then
  # "-run" its just used by "patch" command and will ignore all further parameter
  wantedBranch="${activeBranch}"
  wantedGitHubUser="${activeGitHubUser}"
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
if [ ${#wantedGitHubUser} -gt 0 ]; then
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

if [ ${#wantedBranch} -gt 0 ]; then
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

origin=$(git remote -v | grep 'origin' | tail -n1)
echo "# *** SYNCING RASPIBLITZ CODE WITH GITHUB ***"
echo "# This is for developing on your RaspiBlitz."
echo "# THIS IS NOT THE REGULAR UPDATE MECHANISM"
echo "# and can lead to dirty state of your scripts."
echo "# REPO ----> ${origin}"
echo "# BRANCH --> ${activeBranch}"
echo "# ******************************************"
git config pull.rebase true
if [ $? -eq 0 ]; then
  echo "# OK - git config pull.rebase true"
else
  echo "# FAIL - git config pull.rebase true"
  exit 1
fi
if [[ ${activeBranch} != pr* ]]; then
  git pull 1>&2
  if [ $? -eq 0 ]; then
    echo "# OK - git pull"
  else
    echo "# FAIL - git pull"
    exit 1
  fi
else
  echo "# SKIP - git pull on PR-Branches"
fi
cd /home/admin || exit 1
checkout=/home/admin/raspiblitz/home.admin
stage=$(sudo -u admin mktemp -d /home/admin/.raspiblitz-patch-XXXXXXXX) || exit 1
trap 'sudo -u admin rm -rf -- "$stage"' EXIT
# Prepare permissions before rsync stages replacement files on the target.
# Existing scripts remain callable if a transfer is interrupted.
for dir in assets config.scripts setup.scripts; do
  sudo -u admin cp -a -- "$checkout/$dir" "$stage/" || exit 1
done
sudo -u admin chmod 755 -- "$stage"/config.scripts/*.sh "$stage"/config.scripts/*.py "$stage"/setup.scripts/*.sh || exit 1
echo "# COPYING from GIT-Directory to /home/admin/"
echo "# - basic admin files"
sudo -u admin mkdir "$stage/basic" || exit 1
sudo -u admin cp "$checkout/.tmux.conf" "$stage/basic/" || exit 1
sudo -u admin find "$checkout" -maxdepth 1 -type f \
  -name '*.*' ! -name '.*' -exec cp -t "$stage/basic/" -- {} + || exit 1
sudo -u admin chmod 755 -- "$stage"/basic/*.sh || exit 1
# Do not apply the staging directory mode or timestamps to admin's home.
sudo -u admin rsync -ctp --delay-updates -- "$stage/basic/.tmux.conf" "$stage"/basic/* /home/admin/ || exit 1
for script in *.sh; do
  if [ ! -f "/home/admin/raspiblitz/home.admin/$script" ]; then
    sudo rm -f -- "$script" || exit 1
  fi
done
for dir in assets config.scripts setup.scripts; do
  echo "# - $dir directory"
  # Python services may own their generated bytecode directories.
  sudo -u admin rsync -crltp --delay-updates --delete-delay --exclude='__pycache__/' -- "$stage/$dir/" "/home/admin/$dir/" || exit 1
done
echo "# ******************************************"
echo "# OK - shell scripts and assets are synced"
echo "# Reboot recommended"
