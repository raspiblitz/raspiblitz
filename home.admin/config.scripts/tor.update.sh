#!/usr/bin/env bash

case "$1" in

  source)
    # as in https://2019.www.torproject.org/docs/debian#source
    echo "# Install the dependencies"
    sudo apt update
    sudo apt install -y build-essential fakeroot devscripts
    sudo apt build-dep -y tor deb.torproject.org-keyring
    rm -rf /home/admin/download/debian-packages
    mkdir -p /home/admin/download/debian-packages
    cd /home/admin/download/debian-packages || exit 1
    echo "# Building Tor from the source code ..."
    apt source tor
    cd tor-* || exit 1
    debuild -rfakeroot -uc -us
    cd ..
    echo "# Stopping the tor.service before updating"
    sudo systemctl stop tor
    echo "# Update ..."
    sudo dpkg -i tor_*.deb
    echo "# Starting the tor.service "
    sudo systemctl start tor
    echo "# Installed $(tor --version)"
  ;;

  *) sudo apt update -y && sudo apt upgrade -y tor

esac