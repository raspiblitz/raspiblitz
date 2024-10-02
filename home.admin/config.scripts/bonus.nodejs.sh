#!/bin/bash

# follows https://github.com/nodesource/distributions/blob/master/README.md#manual-installation

VERSION="20"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to install Node.js $VERSION"
  echo "bonus.nodejs.sh [on|off]"
  exit 1
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  # check if Node.js was installed
  if node -v 2>/dev/null | grep "${VERSION}"; then
    echo "Node.js $VERSION is already installed"
  else
    # install prerequisites
    sudo apt-get install -y curl gnupg
    KEYRING=/usr/share/keyrings/nodesource-repo.gpg
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor | sudo tee "$KEYRING" >/dev/null
    # wget can also be used:
    # wget --quiet -O - https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor | sudo tee "$KEYRING" >/dev/null
    gpg --no-default-keyring --keyring "$KEYRING" --list-keys
    sudo chmod a+r "$KEYRING"

    echo "deb [signed-by=$KEYRING] https://deb.nodesource.com/node_$VERSION.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list

    sudo apt-get update
    sudo apt-get install -y nodejs

    # check if Node.js was installed
    if node -v; then
      echo "Installed Node.js $(node -v)"
    else
      echo "FAIL - Was not able to install Node.js"
      echo "ABORT - Node.js install"
      exit 1
    fi
  fi

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "*** REMOVING NODEJS ***"
  sudo apt remove nodejs -y
  sudo rm /etc/apt/sources.list.d/nodesource.list
  echo "OK NodeJS removed."
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
