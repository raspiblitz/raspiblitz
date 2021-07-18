#!/bin/bash

# 1 apt|git
# 2 apt normal|source
# 3 git normal|custom

# TODO change this, you know what to do
# function: install keys & sources

#include lib
. /home/admin/_tor.commands.sh

METHOD=$1
if [ "${METHOD}" == "onion" ]; then
  #check if tor is working, if not, plain
  SOURCES=${SOURCES_TOR_UPDATE_ONION}
else
  SOURCES=${SOURCES_TOR_UPDATE_PLAIN}
fi

prepareTorSources(){

    # Prepare for Tor service
    echo "*** INSTALL Tor REPO ***"
    echo ""

    echo "*** Install dirmngr ***"
    sudo apt install dirmngr -y
    echo ""

    echo "*** Adding KEYS deb.torproject.org ***"

    # fix for v1.6 base image https://github.com/rootzoll/raspiblitz/issues/1906#issuecomment-755299759
    # force update keys
    wget -qO- ${SOURCES}/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | sudo gpg --import
    sudo gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | sudo apt-key add -

    torKeyAvailable=$(sudo gpg --list-keys | grep -c "A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89")
    echo "torKeyAvailable=${torKeyAvailable}"
    if [ ${torKeyAvailable} -eq 0 ]; then
      wget -qO- ${SOURCES}/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | sudo gpg --import
      sudo gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | sudo apt-key add -
      echo "OK"
    else
      echo "Tor key is available"
    fi
    echo ""

    if [ ! -f "/etc/apt/sources.lit.d/tor.list" ]; then
      echo "*** Adding Tor Sources ***"
      echo "deb ${SOURCES}/torproject.org ${DISTRIBUTION} main" | sudo tee -a /etc/apt/sources.list.d/tor.list
      echo "deb-src ${SOURCES}/torproject.org ${DISTRIBUTION} main" | sudo tee -a /etc/apt/sources.list.d/tor.list
      echo "OK"
    else
      echo "Tor sources are available"
    fi
    echo ""
}


if [ "${2}" == "apt" ]; then

  if [ "${3}" == "normal" ]; then
    sudo apt update -y
    sudo apt install tor torsocks nyx obfsp4proxy
  fi

  if [ "${4}" == "source" ]; then
    # as in https://2019.www.torproject.org/docs/debian#source
    echo "# Install the dependencies"
    sudo apt update
    sudo apt install -y build-essential fakeroot devscripts
    sudo apt build-dep -y tor deb.torproject.org-keyring
    rm -rf ${USER_DIR}/download/debian-packages
    mkdir -p ${USER_DIR}/download/debian-packages
    cd ${USER_DIR}/download/debian-packages
    echo "# Building Tor from the source code ..."
    apt source tor
    cd tor-*
    debuild -rfakeroot -uc -us
    cd ..
    echo "# Stopping the tor.service before updating"
    sudo systemctl stop tor
    echo "# Update ..."
    sudo dpkg -i tor_*.deb
    echo "# Starting the tor.service "
    sudo systemctl start tor
    echo "# Installed $(tor --version)"
    if [ $(systemctl status lnd | grep -c "active (running)") -gt 0 ];then
      echo "# LND needs to restart"
      sudo systemctl restart lnd
      sleep 10
      lncli unlock
    fi

fi

if [ "${2}" == "git" ]; then

  # https://github.com/micahflee/onionshare/blob/v2.3.1/build-source.sh
  if [ "${3}" == "custom" ]; then
    display_usage() {
      echo "Usage: $0 [tag]"
    }
    if [ $# -lt 1 ]
    then
      display_usage
      exit 1
    fi
    # Input validation
    TAG=$1
    if [ "${TAG:0:1}" != "v" ]
    then
      echo "Tag must start with 'v' character"
      exit 1
    fi
    VERSION=${TAG:1}
    # Make sure tag exists
    git tag | grep "^$TAG\$"
    if [ $? -ne 0 ]
    then
      echo "Tag does not exist"
      exit 1
    fi
  fi

  if [ "${3}" == "normal" ]||[ "${3}" == "custom" ]; then
    sudo apt-get install git build-essential automake libevent-dev libssl-dev zlib1g-dev
    rm -rf ${USER_DIR}/download/debian-packages
    mkdir -p ${USER_DIR}/download/debian-packages
    cd ${USER_DIR}/download/debian-packages/
    #git clone https://git.torproject.org/tor.git
    git clone https://github.com/torproject/tor/
    cd tor
    if [ "${3}" == "custom" ]; then
      git checkout $TAG
    fi
    sudo bash autogen.sh
    #CPPFLAGS="-I/usr/local/include" LDFLAGS="-L/usr/local/lib" \ ./configure
    sudo bash configure --with-libevent-dir=/usr/local
    sudo make
    sudo make install
  fi

fi
