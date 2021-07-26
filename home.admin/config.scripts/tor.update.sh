#!/bin/bash

#include lib
. /home/admin/config.scripts/tor.functions.lib

# URLS
TORURL="https://github.com/torproject/tor/releases"
TORURL_DL_PARTIAL="https://github.com/torproject/tor/archive/refs/tags/tor"

#Other variables
LOOP_NUMBER=0
RECOMPILE=0
i=0
n=0
UPDATE_MODE=${1}

###### DISPLAY THE MENU ######
clear

# BASIC MENU INFO
HEIGHT=13 # add 6 to CHOICE_HEIGHT + MENU lines
WIDTH=75
BACKTITLE="Raspiblitz ${BRIDGESTRING}"
TITLE=" Tor Update Methods "
MENU=""    # adds lines to HEIGHT
OPTIONS=() # adds lines to HEIGHt + CHOICE_HEIGHT
OPTIONS+=(APT_UPDATE "Update tor packages")
OPTIONS+=(APT_SOURCE "Build tor from source repo")
OPTIONS+=(GIT_SOURCE "Build tor from source git repo")

CHOICE_HEIGHT=$(("${#OPTIONS[@]}" / 3))

CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --ok-label "Select" \
                --cancel-label "Main menu" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

case $CHOICE in

  APT_UPDATE)
    sudo apt update -y
    sudo apt install $TOR_PKGS
  ;;

  APT_SOURCE)
    clear
    if [ -d ~/debian-packages ]; then sudo rm -r ~/debian-packages; fi
    mkdir ~/debian-packages; cd ~/debian-packages
    sudo apt-get -y update
    sudo apt source tor
    KERNEL_VERS=$(uname -s -r)
    TOR_VERS=$(tor --version|head -n 1|rev|cut -c2-|rev|cut -d " " -f3)
    SOURCE_VERS_NUMBER=$(ls -l|grep "^d"|grep -o "tor.*"|cut -d " " -f11-|sed s/tor-//g|sed s/.orig//g)
    clear
    if [ "$SOURCE_VERS_NUMBER" == "$TOR_VERS" ]; then
      INPUT="\nThis are the versions of your current base system:\nKernel: $KERNEL_VERS\nTor:    $TOR_VERS (newest stable version!)\n\nThere is no new stable version of Tor around!\nWould you like to recompile Tor anyway?"
      if (whiptail --defaultno --yesno "$INPUT" $MENU_HEIGHT_15 $MENU_WIDTH_REDUX); then
        RECOMPILE=1
      else
        RECOMPILE=0
      fi
    elif [ -z "$SOURCE_VERS_NUMBER" ]; then
      INPUT="\nThis are the versions of your current base system:\nKernel: $KERNEL_VERS\nTor:    $TOR_VERS\n\nHowever, something went wrong! I couldn't download the Tor package. You may try it later or manually !!"
      whiptail --title "Tor - INFO" --msgbox "$INPUT" $MENU_HEIGHT_15 $MENU_WIDTH_REDUX
      RECOMPILE=0
    else
      if [ $LOOP_NUMBER = 1 ]; then
        INPUT="\nThis are the versions of your current base system:\nKernel: $KERNEL_VERS\nTor:    $TOR_VERS\n\nWould you like to change/update to Tor version $SOURCE_VERS_NUMBER?"
        if (whiptail --defaultno --yesno "$INPUT" $MENU_HEIGHT_15 $MENU_WIDTH_REDUX); then
          RECOMPILE=1
        else
          RECOMPILE=0
        fi
      else
        RECOMPILE=1
      fi
    fi
    if [ $RECOMPILE = 1 ]; then
      clear
      echo -e "${RED}[+] Building Tor from source... ${NOCOLOR}"
      # as in https://2019.www.torproject.org/docs/debian#source
      echo "# Install the dependencies"
      sudo apt update
      sudo apt install -y build-essential fakeroot devscripts
      sudo apt build-dep -y tor deb.torproject.org-keyring
      sudo rm -rf ${USER_DIR}/download/debian-packages
      mkdir -p ${USER_DIR}/download/debian-packages
      cd ${USER_DIR}/download/debian-packages
      echo "# Building Tor from the source code ..."
      apt source tor
      cd tor-*
      debuild -rfakeroot -uc -us
      cd ..
      echo "# Stopping the tor@default.service before updating"
      sudo systemctl stop tor@default
      echo "# Update ..."
      sudo dpkg -i tor_*.deb
      cd
      sudo rm -rf ${USER_DIR}/download/debian-packages
      echo "# Starting the tor@default.service "
      sudo systemctl restart tor@default
      echo "# Installed $(tor --version)"
      sudo systemctl restart lnd
      sleep 10
      echo "# Unlock LND wallet:"
      lncli unlock
      return 1
    fi
  ;;

  GIT_SOURCE)
    # Release Page of the Unofficial Tor repositories on GitHub
    echo -e "${RED}[+] Fetching possible tor versions... ${NOCOLOR}"
    readarray -t torversion_datesorted < <(curl --silent $TORURL | grep "/torproject/tor/releases/tag/" | sed -e "s/<a href=\"\/torproject\/tor\/releases\/tag\/tor-//g" | sed -e "s/\">//g" | grep -v "-")
    #How many tor version did we fetch?
    if [ ${#torversion_datesorted[0]} = 0 ]; then number_torversion=0
    else
      number_torversion=${#torversion_datesorted[*]}

      #The fetched tor versions are sorted by dates, but we need it sorted by version
      IFS=$'\n' torversion_versionsorted=($(sort -r <<< "${torversion_datesorted[*]}")); unset IFS

      #We will build a new array with only the relevant tor versions
      while [ $i -lt $number_torversion ]; do
        if [ $n = 0 ]; then
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
      for (( i=0; i<$number_torversion; i++ )); do
        menuitem=$(( $i + 1 ))
        echo -e "${RED}$menuitem${NOCOLOR} - ${torversion_versionsorted_new[$i]}"
      done
      echo ""
      read -r -p $'\e[1;37mWhich tor version (number) would you like to use (0 = EXIT)? -> \e[0m'
      echo
      if [[ $REPLY =~ ^[1234567890]$ ]]; then
        if [ $REPLY = 0 ]; then
          number_torversion=0
          return 0
        else
          CHOICE_TOR=$(( $REPLY - 1 ))
          clear
          echo -e "${RED}[+] Install necessary packages... ${NOCOLOR}"
          sudo apt-get -y update
          sudo apt-get -y install automake libevent-dev libssl-dev asciidoc-base
          echo ""
          echo -e "${RED}[+] Download the selected tor version...... ${NOCOLOR}"
          version_string="$(<<< ${torversion_versionsorted_new[$CHOICE_TOR]} sed -e 's/ //g')"
          download_tor_url="$TORURL_DL_PARTIAL-$version_string.tar.gz"
          filename="tor-$version_string.tar.gz"
          if [ -d ~/debian-packages ] ; then sudo rm -r ~/debian-packages ; fi
          mkdir ~/debian-packages; cd ~/debian-packages
          wget $download_tor_url
          DLCHECK=$?
          clear
          if [ $DLCHECK -eq 0 ]; then
            echo -e "${RED}[+] Sucessfully downloaded the selected tor version... ${NOCOLOR}"
            tar xzf $filename
            cd `ls -d */`
            echo -e "${RED}[+] Starting configuring, compiling and installing... ${NOCOLOR}"
            ./autogen.sh
            ./configure
            make
            sudo make install
            return 1
          else number_torversion=0; fi
        fi
      else number_torversion=0; fi
    fi
    if [ $number_torversion = 0 ]; then
      echo ""
      echo -e "${WHITE}[!] Something didn't go as expected or you chose to exit!${NOCOLOR}"
      echo -e "${WHITE}[!] Try it again or chose the DEFAULT installation procedure!${NOCOLOR}"
      clear
      return 0
    fi
  ;;

  *)
    clear
    exit 0

esac