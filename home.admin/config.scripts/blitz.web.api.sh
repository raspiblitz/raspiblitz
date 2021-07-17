#!/usr/bin/env bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "Manage RaspiBlitz Web API"
  echo "blitz.web.api.sh on"
  echo "blitz.web.api.sh off"
  exit 1
fi

DEFAULT_GITHUB_REPO="https://github.com/fusion44/blitz_api"

###################
# ON / INSTALL
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "# INSTALL Web API"

  


  echo "TODO: Implement"
  exit 1
fi

###################
# OFF / UNINSTALL
###################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# UNINSTALL Web API"

  echo "TODO: Implement"
  exit 0
fi



