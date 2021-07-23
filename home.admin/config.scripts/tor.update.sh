#!/bin/bash

# 1 apt|git
# 2 apt normal|source
# 3 git normal|custom

# TODO change this, you know what to do
# this is wrong, need to finish this ASAP
# function: install keys & sources

#include lib
. /home/admin/config.scripts/tor.functions.lib

# Release Page of the Unofficial Tor repositories on GitHub
TORURL="https://github.com/torproject/tor/releases"

METHOD=$1
if [ "${METHOD}" == "onion" ]; then
  #check if tor is working, if not, plain
  SOURCES=${SOURCES_TOR_UPDATE_ONION}
else
  SOURCES=${SOURCES_TOR_UPDATE_PLAIN}
fi

# this makes sense to be used if the onion service changes domain.
prepareTorSources(){

    # Prepare for Tor service
    echo "*** INSTALL Tor REPO ***"
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

    if [ ! -f "/etc/apt/sources.list.d/tor.list" ]; then
      echo "*** Adding Tor Sources ***"
      echo "deb [arch=arm64] ${SOURCES}/torproject.org ${DISTRIBUTION} main" | sudo tee -a /etc/apt/sources.list.d/tor.list
      echo "deb-src [arch=arm64] ${SOURCES}/torproject.org ${DISTRIBUTION} main" | sudo tee -a /etc/apt/sources.list.d/tor.list
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

  # Select, compile and install Tor
  if [ "$SELECT_TOR" = "--select-tor" ] ; then
    clear
    echo -e "${RED}[+]         Fetching possible tor versions... ${NOCOLOR}"
    readarray -t torversion_datesorted < <(curl --silent $TORURL | grep "/torproject/tor/releases/tag/" | sed -e "s/<a href=\"\/torproject\/tor\/releases\/tag\/tor-//g" | sed -e "s/\">//g")

    #How many tor version did we fetch?
    if [ ${#torversion_datesorted[0]} = 0 ]; then number_torversion=0
    else
      number_torversion=${#torversion_datesorted[*]}

      #The fetched tor versions are sorted by dates, but we need it sorted by version
      IFS=$'\n' torversion_versionsorted=($(sort -r <<< "${torversion_datesorted[*]}")); unset IFS

      #We will build a new array with only the relevant tor versions
      while [ $i -lt $number_torversion ]
      do
        if [ $n = 0 ] ; then
          torversion_versionsorted_new[0]=${torversion_versionsorted[0]}
          covered_version=$(cut -d '.' -f1-3 <<< ${torversion_versionsorted[0]})
          i=$(( $i + 1 ))
          n=$(( $n + 1 ))
        else
          actual_version=$(cut -d '.' -f1-3 <<< ${torversion_versionsorted[$i]})
          if [ "$actual_version" == "$covered_version" ] ; then i=$(( $i + 1 ))
          else
            torversion_versionsorted_new[$n]=${torversion_versionsorted[$i]}
            covered_version=$actual_version
            i=$(( $i + 1 ))
            n=$(( $n + 1 ))
          fi
        fi
      done
      number_torversion=$n

      #Display and chose a tor version
      clear
      echo -e "${WHITE}Choose a tor version (alpha versions are not recommended!):${NOCOLOR}"
      echo ""
      for (( i=0; i<$number_torversion; i++ ))
      do
        menuitem=$(( $i + 1 ))
        echo -e "${RED}$menuitem${NOCOLOR} - ${torversion_versionsorted_new[$i]}"
      done
      echo ""
      read -r -p $'\e[1;37mWhich tor version (number) would you like to use? -> \e[0m'
      echo
      if [[ $REPLY =~ ^[1234567890]$ ]] ; then
        CHOICE_TOR=$(( $REPLY - 1 ))
      else number_torversion=0 ; fi

      #Download and install
      clear
      echo -e "${RED}[+]         Download the selected tor version...... ${NOCOLOR}"
      version_string="$(<<< ${torversion_versionsorted_new[$CHOICE_TOR]} sed -e 's/ //g')"
      download_tor_url="https://github.com/torproject/tor/archive/refs/tags/tor-$version_string.tar.gz"
      filename="tor-$version_string.tar.gz"
      mkdir ~/debian-packages; cd ~/debian-packages
      wget $download_tor_url
      clear
      if [ $? -eq 0 ] ; then
        echo -e "${RED}[+]         Sucessfully downloaded the selected tor version... ${NOCOLOR}"
        tar xzf $filename
        cd `ls -d */`
        #The following packages are needed
        sudo apt-get -y install automake libevent-dev libssl-dev asciidoc-base
        echo -e "${RED}[+]         Installing additianal packages... ${NOCOLOR}"
        clear
        echo -e "${RED}[+]         Starting configuring, compiling and installing... ${NOCOLOR}"
        ./autogen.sh
        ./configure
        make
        sudo make install
        cd
        sudo rm -r ~/debian-packages
      else number_torversion=0 ; fi
    fi
    if [ $number_torversion = 0 ] ; then
      echo -e "${WHITE}[!]         Something didn't go as expected!${NOCOLOR}"
      echo -e "${WHITE}[!]         I will try to install the latest stable version.${NOCOLOR}"
    fi
  else number_torversion=0 ; fi

  # Compile and install the latest stable Tor version
  if [ $number_torversion = 0 ] ; then
    mkdir ~/debian-packages; cd ~/debian-packages
    apt source tor
    sudo apt-get -y install fakeroot devscripts
    #sudo apt-get -y install tor deb.torproject.org-keyring
    #sudo apt-get -y upgrade tor deb.torproject.org-keyring
    sudo apt-get -y build-dep tor deb.torproject.org-keyring
    cd tor-*
    sudo debuild -rfakeroot -uc -us
    cd ..
    sudo dpkg -i tor_*.deb
    cd
    sudo rm -r ~/debian-packages
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
