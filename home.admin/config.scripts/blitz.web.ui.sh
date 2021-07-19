#!/usr/bin/env bash

# TODO: Later use for default install (when no github parameters are given) a precompiled version
# that comes with the repo so that the user does not need to install node
# use fro that then: yarn build:production & yarn licenses generate-disclaimer

# TODO: Put WebUI into / base directory of nginx and let the index.html of the webUI handle
# the Tor detection or build it directly into the WebUI

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
  source <(/home/admin/config.scripts/bonus.nodejs.sh info)
  sudo npm install --global yarn
  ${NODEPATH}/yarn install
  ${NODEPATH}/yarn build

  sudo rm -r /var/www/public/* 2>/dev/null
  sudo cp -r /home/admin/blitz_web/build/* /var/www/public
  sudo chown www-data:www-data -R /var/www/public

  exit 1
fi

###################
# OFF / UNINSTALL
###################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# UNINSTALL WebUI"
  sudo rm -r /home/admin/blitz_web 2>/dev/null
  sudo rm -r /var/www/public/* 2>/dev/null
  exit 0
fi





