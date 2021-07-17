#!/usr/bin/env bash

# based on: https://github.com/cstenglein/raspiblitz-web

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "Manage RaspiBlitz Web UI"
  echo "blitz.web.ui.sh on"
  echo "blitz.web.ui.sh off"
  exit 1
fi

###################
# ON / INSTALL
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  echo "# INSTALL WebUI"


  echo "TODO: Implement"
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





