#!/bin/bash

# follows https://github.com/nodesource/distributions/blob/master/README.md#manual-installation

VERSION="20"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to install NodeJs $VERSION"
  echo "bonus.nodejs.sh [on|off]"
  exit 1
fi

# switch on
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  # check if nodeJS was installed
  if node -v | grep "${VERSION}"; then
    echo "nodeJS $VERSION is already installed"
  else
    KEYRING=/usr/share/keyrings/nodesource.gpg
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key | gpg --dearmor | sudo tee "$KEYRING" >/dev/null
    # wget can also be used:
    # wget --quiet -O - https://deb.nodesource.com/gpgkey/nodesource.gpg.key | gpg --dearmor | sudo tee "$KEYRING" >/dev/null
    gpg --no-default-keyring --keyring "$KEYRING" --list-keys
    sudo chmod a+r /usr/share/keyrings/nodesource.gpg

    # Replace with the keyring above, if different
    KEYRING=/usr/share/keyrings/nodesource.gpg
    # The below command will set this correctly, but if lsb_release isn't available, you can set it manually:
    # - For Debian distributions: jessie, sid, etc...
    # - For Ubuntu distributions: xenial, bionic, etc...
    # - For Debian or Ubuntu derived distributions your best option is to use the codename corresponding to the upstream release your distribution is based off. This is an advanced scenario and unsupported if your distribution is not listed as supported per earlier in this README.
    DISTRO="$(lsb_release -s -c)"
    echo "deb [signed-by=$KEYRING] https://deb.nodesource.com/node_$VERSION.x $DISTRO main" | sudo tee /etc/apt/sources.list.d/nodesource.list
    echo "deb-src [signed-by=$KEYRING] https://deb.nodesource.com/node_$VERSION.x $DISTRO main" | sudo tee -a /etc/apt/sources.list.d/nodesource.list

    sudo apt-get update
    sudo apt-get install -y nodejs

    # check if nodeJS was installed
    if node -v; then
      echo "Installed nodeJS $(node -v)"
    else
      echo "FAIL - Was not able to install nodeJS"
      echo "ABORT - nodeJs install"
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
