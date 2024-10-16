#!/usr/bin/env bash
# main repo: https://github.com/raspiblitz/raspiblitz-web

# NORMALLY user/repo/version will be defined by calling script - see build_sdcard.sh
# the following is just a fallback to try during development if script given branch does not exist
FALLBACK_BRANCH="master"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "Manage RaspiBlitz WebUI"
  echo "blitz.web.ui.sh info"
  echo "blitz.web.ui.sh on [GITHUBUSER] [REPO] [BRANCH] [?COMMITORTAG]"
  echo "blitz.web.ui.sh on DEFAULT"
  echo "blitz.web.ui.sh update"
  echo "blitz.web.ui.sh off"
  exit 0
fi

###################
# INFO
###################
if [ "$1" = "info" ]; then
  # check if installed
  if ! cd /home/blitzapi/blitz_web 2>/dev/null; then
    echo "installed=0"
    exit 1
  fi
  echo "installed=1"
  # get github origin repo from repo directory with git command
  echo "repo='$(sudo git config --get remote.origin.url)'"
  # get github branch from repo directory with git command
  echo "branch='$(sudo git rev-parse --abbrev-ref HEAD)'"
  # get github commit from repo directory with git command
  echo "commit='$(sudo git rev-parse HEAD)'"
  exit 0
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then
  echo "error='run as root'"
  exit 1
fi

###################
# ON / INSTALL
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  if [ "$2" == "DEFAULT" ]; then
    echo "# WEBUI: getting default user/repo from build_sdcard.sh"
    # copy build_sdcard.sh out of raspiblitz directory to not create "changes" in git
    sudo cp /home/admin/raspiblitz/build_sdcard.sh /home/admin/build_sdcard.sh
    sudo chmod +x /home/admin/build_sdcard.sh
    source <(sudo /home/admin/build_sdcard.sh -EXPORT)
    GITHUB_USER="${defaultWEBUIuser}"
    GITHUB_REPO="${defaultWEBUIrepo}"
    activeBranch=$(git -C /home/admin/raspiblitz branch --show-current)
    echo "# activeBranch detected by raspiblitz repo: ${activeBranch}"
    # use dev branch when raspiblitz repo is n dev branch
    if [[ "$activeBranch" == *"dev"* ]]; then    
      echo "# RELEASE CANDIDATE: using master branch"
      GITHUB_BRANCH="master"
    else
      GITHUB_BRANCH="release/${githubBranch}"
    fi
    GITHUB_COMMITORTAG=""
  else
    # get parameters
    GITHUB_USER=$2
    GITHUB_REPO=$3
    GITHUB_BRANCH=$4
    GITHUB_COMMITORTAG=$5
  fi

  for var in GITHUB_USER GITHUB_REPO GITHUB_BRANCH; do
    [ -z "${!var}" ] && { echo "# FAIL: No ${var} provided"; exit 1; }
  done

  echo "# GITHUB_COMMITORTAG(${GITHUB_COMMITORTAG})"
  if [ "${GITHUB_COMMITORTAG}" == "" ]; then
    echo "# INFO: No GITHUB_COMMITORTAG provided .. will use latest code on branch"
  fi

  # check if given branch exits on that github user/repo
  branchExists=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/branches/${GITHUB_BRANCH}" | grep -c "\"name\": \"${GITHUB_BRANCH}\"")
  if [ "${branchExists}" -lt 1 ]; then
    echo
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "# WARNING! The given WebUI repo is not available:"
    echo "# user(${GITHUB_USER}) repo(${GITHUB_REPO}) branch(${GITHUB_BRANCH})"
    GITHUB_BRANCH="${FALLBACK_BRANCH}"
    echo "# SO WORKING WITH FALLBACK REPO:"
    echo "# user(${GITHUB_USER}) repo(${GITHUB_REPO}) branch(${GITHUB_BRANCH})"
    echo "# USE JUST FOR DEVELOPMENT - DONT USE IN PRODUCTION"
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo
    sleep 10
  fi

  # re-check (if case its fallback)
  branchExists=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/branches/${GITHUB_BRANCH}" | grep -c "\"name\": \"${GITHUB_BRANCH}\"")
  if [ ${branchExists} -lt 1 ]; then
    echo
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "# FAIL! user(${GITHUB_USER}) repo(${GITHUB_REPO}) branch(${GITHUB_BRANCH})"
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
  fi

  echo "# INSTALL WebUI"
  # clean all source
  rm -rf /root/blitz_web /root/"${GITHUB_REPO}" /home/blitzapi/blitz_web /home/blitzapi/"${GITHUB_REPO}"
  cd /home/blitzapi || exit 1
  echo "# clone github: ${GITHUB_USER}/${GITHUB_REPO}"
  git clone https://github.com/"${GITHUB_USER}"/"${GITHUB_REPO}".git || { echo "error='git clone failed'"; exit 1; }
  mv /home/blitzapi/"${GITHUB_REPO}" /home/blitzapi/blitz_web
  cd blitz_web || exit 1
  echo "# checkout branch: ${GITHUB_BRANCH}"
  git checkout "${GITHUB_BRANCH}" || { echo "error='git checkout failed'"; exit 1; }
  if [ "${GITHUB_COMMITORTAG}" != "" ]; then
    echo "# setting code to tag/commit: ${GITHUB_COMMITORTAG}"
    if ! git reset --hard "${GITHUB_COMMITORTAG}"; then
      echo "error='git reset failed'"
      exit 1
    fi
  else
    echo "# using lastest code in branch"
  fi
  echo "# Compile WebUI"
  /home/admin/config.scripts/bonus.nodejs.sh on
  npm install || { echo "error='npm install failed'"; exit 1; }
  npm run build || { echo "error='npm run build failed'"; exit 1; }

  rm -rf /var/www/public/*
  cp -r /home/blitzapi/blitz_web/build/* /var/www/public
  chown www-data:www-data -R /var/www/public

  echo "# The WebUI is now available under:"
  echo "# http://$(hostname -I | awk '{print $1}')"
  exit 0
fi

###################
# UPDATE
###################
if [ "$1" = "update" ]; then
  webuiActive=$(sudo ls /home/blitzapi/blitz_web/README.md | grep -c "README")
  if [ "${webuiActive}" != "0" ]; then
    echo "# Update Web API"
    cd /home/blitzapi/blitz_web
    currentBranch=$(git rev-parse --abbrev-ref HEAD)
    echo "# updating local repo ..."
    oldCommit=$(git rev-parse HEAD)
    git fetch
    git reset --hard origin/"${currentBranch}"
    newCommit=$(git rev-parse HEAD)
    if [ "${oldCommit}" != "${newCommit}" ]; then
      npm install
      npm run build
      sudo rm -rf /var/www/public/*
      sudo cp -r /home/blitzapi/blitz_web/build/* /var/www/public
      sudo chown www-data:www-data -R /var/www/public
    else
      echo "# no code changes"
    fi
    echo "# BRANCH ---> ${currentBranch}"
    echo "# old commit -> ${oldCommit}"
    echo "# new commit -> ${newCommit}"
    echo "# reload WebUI in your browser"
    exit 0
  else
    echo "# webui not active"
    exit 1
  fi
fi

###################
# OFF / UNINSTALL
###################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# UNINSTALL WebUI"
  sudo rm -rf /root/blitz_web /home/blitzapi/blitz_web /var/www/public/*
  exit 0
fi