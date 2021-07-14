#!/bin/bash

# 1 apt|git
# 2 apt normal|source
# 3 git normal|custom

# TODO change this, you know what to do
# function: install keys & sources
prepareTorSources(){

    # Prepare for TOR service
    echo "*** INSTALL TOR REPO ***"
    echo ""

    echo "*** Install dirmngr ***"
    sudo apt install dirmngr -y
    echo ""

    echo "*** Adding KEYS deb.torproject.org ***"

    # fix for v1.6 base image https://github.com/rootzoll/raspiblitz/issues/1906#issuecomment-755299759
    # force update keys
    wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | sudo gpg --import
    sudo gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | sudo apt-key add -

    torKeyAvailable=$(sudo gpg --list-keys | grep -c "A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89")
    echo "torKeyAvailable=${torKeyAvailable}"
    if [ ${torKeyAvailable} -eq 0 ]; then
      wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | sudo gpg --import
      sudo gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | sudo apt-key add -
      echo "OK"
    else
      echo "TOR key is available"
    fi
    echo ""

    echo "*** Adding Tor Sources to sources.list ***"
    torSourceListAvailable=$(sudo cat /etc/apt/sources.list | grep -c 'https://deb.torproject.org/torproject.org')
    echo "torSourceListAvailable=${torSourceListAvailable}"
    if [ ${torSourceListAvailable} -eq 0 ]; then
      echo "Adding TOR sources ..."
      if [ "${baseImage}" = "raspbian" ] || [ "${baseImage}" = "armbian" ] || [ "${baseImage}" = "dietpi" ]; then
        echo "deb https://deb.torproject.org/torproject.org buster main" | sudo tee -a /etc/apt/sources.list
        echo "deb-src https://deb.torproject.org/torproject.org buster main" | sudo tee -a /etc/apt/sources.list
      elif [ "${baseImage}" = "ubuntu" ]; then
        echo "deb https://deb.torproject.org/torproject.org focal main" | sudo tee -a /etc/apt/sources.list
        echo "deb-src https://deb.torproject.org/torproject.org focal main" | sudo tee -a /etc/apt/sources.list
      fi
      echo "OK"
    else
      echo "TOR sources are available"
    fi
    echo ""
}


if [ "${1}" == "apt" ]; then

  if [ "${2}" == "normal" ]; then
    sudo apt update -y
    sudo apt install tor torsocks nyx obfsp4proxy
  fi

  if [ "${2}" == "source" ]; then
    # as in https://2019.www.torproject.org/docs/debian#source
    echo "# Install the dependencies"
    sudo apt update
    sudo apt install -y build-essential fakeroot devscripts
    sudo apt build-dep -y tor deb.torproject.org-keyring
    rm -rf /home/admin/download/debian-packages
    mkdir -p /home/admin/download/debian-packages
    cd /home/admin/download/debian-packages
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

if [ "${1}" == "git" ]; then

  # https://github.com/micahflee/onionshare/blob/v2.3.1/build-source.sh
  if [ "${1}" == "custom" ]; then
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

  if [ "${2}" == "normal" ]||[ "${1}" == "custom" ]; then
    sudo apt-get install git build-essential automake libevent-dev libssl-dev zlib1g-dev
    rm -rf /home/admin/download/debian-packages
    mkdir -p /home/admin/download/debian-packages
    cd /home/admin/download/debian-packages/
    #git clone https://git.torproject.org/tor.git
    git clone https://github.com/torproject/tor/
    cd tor
    if [ "${2}" == "custom" ]; then
      git checkout $TAG
    fi
    sudo bash autogen.sh
    #CPPFLAGS="-I/usr/local/include" LDFLAGS="-L/usr/local/lib" \ ./configure
    sudo bash configure --with-libevent-dir=/usr/local
    sudo make
    sudo make install
  fi

fi
