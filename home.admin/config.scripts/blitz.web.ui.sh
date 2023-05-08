#!/usr/bin/env bash

# main repo: https://github.com/cstenglein/raspiblitz-web

# NORMALLY user/repo/version will be defined by calling script - see build_sdcard.sh
# the following is just a fallback to try during development if script given branch does not exist
FALLACK_BRANCH="master"

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

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='run as root'"
  exit 1
fi

###################
# INFO
###################
if [ "$1" = "info" ]; then

  # check if installed
  cd /home/blitzapi/blitz_web
  if [ "$?" != "0" ]; then
    echo "installed=0"
    exit 1
  fi
  echo "installed=1"

  # get github origin repo from repo directory with git command
  origin=$(sudo -u blitzapi git config --get remote.origin.url)
  echo "repo='${origin}'"

  # get github branch from repo directory with git command 
  branch=$(sudo -u blitzapi git rev-parse --abbrev-ref HEAD)
  echo "branch='${branch}'"

  # get github commit from repo directory with git command
  commit=$(sudo -u blitzapi git rev-parse HEAD)
  echo "commit='${commit}'"

  exit 0
fi

###################
# ON / INSTALL
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ "$2" == "DEFAULT" ]; then
    echo "# getting default user/repo from build_sdcard.sh"
    sudo cp /home/admin/raspiblitz/build_sdcard.sh /home/admin/build_sdcard.sh
    sudo chmod +x /home/admin/build_sdcard.sh 2>/dev/null
    source <(sudo /home/admin/build_sdcard.sh -EXPORT)
    GITHUB_USER="${defaultWEBUIuser}"
    GITHUB_REPO="${defaultWEBUIrepo}"
    GITHUB_BRANCH="${githubBranch}"
    GITHUB_COMMITORTAG=""
  else
    # get parameters
    GITHUB_USER=$2
    GITHUB_REPO=$3
    GITHUB_BRANCH=$4
    GITHUB_COMMITORTAG=$5
  fi

  # check & output info
  echo "# GITHUB_USER(${GITHUB_USER})"
  if [ "${GITHUB_USER}" == "" ]; then
    echo "# FAIL: No GITHUB_USER provided"
    exit 1
  fi
  echo "GITHUB_REPO(${GITHUB_REPO})"
  if [ "${GITHUB_REPO}" == "" ]; then
    echo "# FAIL: No GITHUB_REPO provided"
    exit 1
  fi
  echo "GITHUB_BRANCH(${GITHUB_BRANCH})"
  if [ "${GITHUB_BRANCH}" == "" ]; then
    echo "# FAIL: No GITHUB_BRANCH provided"
    exit 1
  fi
  echo "GITHUB_COMMITORTAG(${GITHUB_COMMITORTAG})"
  if [ "${GITHUB_COMMITORTAG}" == "" ]; then
    echo "# INFO: No GITHUB_COMMITORTAG provided .. will use latest code on branch"
  fi

  # check if given branch exits on that github user/repo
  branchExists=$(curl --header "X-GitHub-Api-Version:2022-11-28" -s "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/branches/${GITHUB_BRANCH}" | grep -c "\"name\": \"${GITHUB_BRANCH}\"")
  if [ ${branchExists} -lt 1 ]; then
    echo
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "# WARNING! The given WebUI repo is not available:"
    echo "# user(${GITHUB_USER}) repo(${GITHUB_REPO}) branch(${GITHUB_BRANCH})"
    echo "# WORKING WITH FALLBACK REPO - USE JUST FOR DEVELOPMENT - DONT USE IN PRODUCTION"
    echo "# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo
    sleep 10
    GITHUB_BRANCH="${FALLACK_BRANCH}"
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
  rm -r /root/blitz_web 2>/dev/null
  rm -r /root/${GITHUB_REPO} 2>/dev/null
  rm -r /home/blitzapi/blitz_web 2>/dev/null
  rm -r /home/blitzapi/${GITHUB_REPO} 2>/dev/null
  
  cd /home/blitzapi || exit 1
   echo "# clone github: ${GITHUB_USER}/${GITHUB_REPO}"
  if ! git clone https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git; then
    echo "error='git clone failed'"
    exit 1
  fi
  mv /home/blitzapi/${GITHUB_REPO} /home/blitzapi/blitz_web
  cd blitz_web || exit 1
  echo "# checkout branch: ${GITHUB_BRANCH}"
  if ! git checkout ${GITHUB_BRANCH}; then
    echo "error='git checkout failed'"
    exit 1
  fi
  if [ "${GITHUB_COMMITORTAG}" != "" ]; then
    echo "# setting code to tag/commit: ${GITHUB_COMMITORTAG}"
    if ! git reset --hard ${GITHUB_COMMITORTAG}; then
      echo "error='git reset failed'"
      exit 1
    fi
  else
    echo "# using lastest code in branch"
  fi

  echo "# Compile WebUI"
  /home/admin/config.scripts/bonus.nodejs.sh on
  source <(/home/admin/config.scripts/bonus.nodejs.sh info)
  if ! npm install --global yarn; then
    echo "error='install yarn failed'"
    exit 1
  fi
  ${NODEPATH}/yarn config set --home enableTelemetry 0
  if ! ${NODEPATH}/yarn install; then
    echo "error='yarn install failed'"
    exit 1
  fi
  if ! ${NODEPATH}/yarn build; then
    echo "error='yarn build failed'"
    exit 1
  fi

  rm -r /var/www/public/* 2>/dev/null
  cp -r /home/blitzapi/blitz_web/build/* /var/www/public
  chown www-data:www-data -R /var/www/public

  # install info
  localIP=$(hostname -I | awk '{print $1}')
  echo "# The WebUI is now available under:"
  echo "# http://${localIP}"

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
    git reset --hard origin/${currentBranch}
    newCommit=$(git rev-parse HEAD)
    if [ "${oldCommit}" != "${newCommit}" ]; then
      source <(/home/admin/config.scripts/bonus.nodejs.sh info)
      ${NODEPATH}/yarn install
      ${NODEPATH}/yarn build
      sudo rm -r /var/www/public/* 2>/dev/null
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
  sudo rm -r /root/blitz_web 2>/dev/null
  sudo rm -r /home/blitzapi/blitz_web 2>/dev/null
  sudo rm -r /var/www/public/* 2>/dev/null
  exit 0
fi
