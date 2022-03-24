#!/usr/bin/env bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "Manage RaspiBlitz Web UI"
  echo "blitz.web.ui.sh on [?GITHUBUSER] [?REPO] [?BRANCH]"
  echo "blitz.web.ui.sh update"
  echo "blitz.web.ui.sh off"
  exit 0
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='run as root'"
  exit 1
fi

DEFAULT_GITHUB_USER="cstenglein"
DEFAULT_GITHUB_REPO="raspiblitz-web"
DEFAULT_GITHUB_BRANCH="master"

###################
# ON / INSTALL
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ "$2" != "" ]; then
    DEFAULT_GITHUB_USER="$2"
  fi

  if [ "$3" != "" ]; then
    DEFAULT_GITHUB_REPO="$3"
  fi

  if [ "$4" != "" ]; then
    DEFAULT_GITHUB_BRANCH="$4"
  fi

  echo "# INSTALL WebUI"
  rm -r /root/blitz_web 2>/dev/null
  cd /root
  # git clone https://github.com/cstenglein/raspiblitz-web.git /home/admin/blitz_web
  git clone https://github.com/${DEFAULT_GITHUB_USER}/${DEFAULT_GITHUB_REPO}.git /root/blitz_web
  cd blitz_web
  git checkout ${DEFAULT_GITHUB_BRANCH}

  echo "# Compile WebUI"
  /home/admin/config.scripts/bonus.nodejs.sh on
  source <(/home/admin/config.scripts/bonus.nodejs.sh info)
  npm install --global yarn
  ${NODEPATH}/yarn config set --home enableTelemetry 0
  ${NODEPATH}/yarn install
  ${NODEPATH}/yarn build:production

  rm -r /var/www/public/* 2>/dev/null
  cp -r /root/blitz_web/build/* /var/www/public
  chown www-data:www-data -R /var/www/public

  # install info
  echo "# The WebUI is now available under:"
  echo "# http://[LOCAIP]"

  exit 0
fi

###################
# UPDATE
###################
if [ "$1" = "update" ]; then

  echo "# Update Web API"
  cd /root/blitz_web
  git fetch
  git pull
  source <(/home/admin/config.scripts/bonus.nodejs.sh info)
  ${NODEPATH}/yarn install
  ${NODEPATH}/yarn build
  sudo rm -r /var/www/public/* 2>/dev/null
  sudo cp -r /root/blitz_web/build/* /var/www/public
  sudo chown www-data:www-data -R /var/www/public
  echo "# blitzapi updates and restarted"
  exit 0

fi

###################
# OFF / UNINSTALL
###################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# UNINSTALL WebUI"
  sudo rm -r /root/blitz_web 2>/dev/null
  sudo rm -r /var/www/public/* 2>/dev/null
  exit 0
fi





