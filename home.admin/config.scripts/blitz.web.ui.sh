#!/usr/bin/env bash

# TODO: Later use for default install (when no github parameters are given) a precompiled version
# that comes with the repo so that the user does not need to install node
# use fro that then: yarn build:production & yarn licenses generate-disclaimer

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "Manage RaspiBlitz Web UI"
  echo "blitz.web.ui.sh on [?GITHUBUSER] [?REPO] [?BRANCH]"
  echo "blitz.web.ui.sh off"
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
  sudo rm -r /home/admin/blitz_web 2>/dev/null
  cd /home/admin
  # git clone https://github.com/cstenglein/raspiblitz-web.git /home/admin/blitz_web
  git clone https://github.com/${DEFAULT_GITHUB_USER}/${DEFAULT_GITHUB_REPO}.git /home/admin/blitz_web
  cd blitz_web
  git checkout ${DEFAULT_GITHUB_BRANCH}

  echo "# Compile WebUI"
  /home/admin/config.scripts/bonus.nodejs.sh on
  sudo npm install --global yarn #FAIL: yarn comand not available afterwards (test with fresh sd card image) 
  /usr/local/lib/nodejs/node-v14.15.4-linux-arm64/bin/yarn install
  /usr/local/lib/nodejs/node-v14.15.4-linux-arm64/bin/yarn build

  sudo rm -r /var/www/public/ui 2>/dev/null
  sudo cp -r /home/admin/blitz_web/build /var/www/public/ui
  sudo chown www-data:www-data -r /var/www/public/ui

  exit 1
fi

###################
# OFF / UNINSTALL
###################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# UNINSTALL WebUI"

  echo "TODO: Implement"
  exit 0
fi





