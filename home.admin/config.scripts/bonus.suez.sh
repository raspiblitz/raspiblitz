#!/bin/bash

# https://github.com/prusnak/suez/commits/master
# reactivate PGP verification if the pinned / last commit is signed
SUEZVERSION="d055a1f8b4a81488c72f60da9b51b0f0932c5146"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "config script to install, update or uninstall Suez"
  echo "bonus.suez.sh [on|off|menu|update]"
  echo "installs the version $SUEZVERSION by default"
  exit 1
fi

PGPsigner="prusnak"
PGPpubkeyLink="https://rusnak.io/public/pgp.txt"
PGPpubkeyFingerprint="91F3B339B9A02A3D"

source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then
  dialog --title " Info Suez" --msgbox "
Suez is a command line tool.
Type: 'suez' to visualize the channels of the default ln instance
Readme: https://github.com/prusnak/suez#readme
" 10 75
  exit 0
fi

# install
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "# INSTALL SUEZ"

  cd /home/bitcoin || exit 1

  # poetry
  sudo pip3 config set global.break-system-packages true
  sudo pip3 install --upgrade pip
  sudo pip3 install poetry

  # download source code
  sudo -u bitcoin git clone https://github.com/prusnak/suez.git
  cd suez || exit 1
  sudo -u bitcoin git reset --hard $SUEZVERSION
#  sudo -u bitcoin /home/admin/config.scripts/blitz.git-verify.sh \
#    "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1
  sudo -u bitcoin poetry install

  # make sure default virtaulenv is used
  sudo apt-get remove -y python3-virtualenv 2>/dev/null
  sudo pip uninstall -y virtualenv 2>/dev/null
  sudo apt-get install -y python3-virtualenv

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set suez "on"

  echo "# To use the alias in /home/admin/_aliases:"
  echo "source /home/admin/_aliases"
  echo "# Type: 'suez' for the default channel visualization for LND"
  echo "# Type: 'suez --help' in the command line to see the usage options."
  echo "# Readme: https://github.com/prusnak/suez#readme"

  exit 0
fi

# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "# REMOVING SUEZ"
  sudo rm -rf /home/bitcoin/suez
  echo "# OK, Suez is removed."

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set suez "off"

  exit 0
fi

# update
if [ "$1" = "update" ]; then
  echo "# UPDATE SUEZ"
  cd /home/bitcoin || exit 1
  # dependency
  sudo pip3 config set global.break-system-packages true
  sudo pip3 install --upgrade pip
  sudo pip3 install poetry
  # download source code
  if [ -d suez ]; then
    sudo -u bitcoin git clone https://github.com/prusnak/suez.git
  fi
  cd suez || exit 1
  sudo -u bitcoin git pull
#  sudo -u bitcoin /home/admin/config.scripts/blitz.git-verify.sh \
#    "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1
  sudo -u bitcoin poetry install
  echo "# Updated to the latest in https://github.com/prusnak/suez/commits/master"

  # make sure default virtaulenv is used
  sudo apt-get remove -y python3-virtualenv 2>/dev/null
  sudo pip uninstall -y virtualenv 2>/dev/null
  sudo apt-get install -y python3-virtualenv

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
