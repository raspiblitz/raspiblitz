#!/bin/bash

# This file is part of TorBox, an easy to use anonymizing router based on Raspberry Pi.
# Copyright (C) 2021 Patrick Truffer
# Contact: anonym@torbox.ch
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it is useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# DESCRIPTION
# This file add automatically or manually bridges to /etc/tor/torrc.
#
# SYNTAX
# ./bridges_add_old <bridge mode> <standalone>
#
# <bridge mode>: "UseBridges 1" for bridge mode on; everything else = bridge mode off
# <standalone>: 0 - bridges_add_old was executed as part of the activation process, when no bridges were found
#               1 - bridges_add_old was directly executed
#
###### SET VARIABLES ######

SOURCE_SCRIPT="config.scripts/tor.obfs4-add-old.sh"

#Other variables
MODE_BRIDGES=$1
STANDALONE=$2
number_bridges=0
i=0

###########################
######## FUNCTIONS ########

# include lib
. /home/admin/config.scripts/tor.functions.lib

###########################

clear

# BASIC MENU INFO
HEIGHT=8 # add 6 to CHOICE_HEIGHT + MENU lines
WIDTH=80
BACKTITLE="Raspiblitz ${BRIDGESTRING}"
TITLE="Tor - BRIDGES ADDITION MENU"
MENU=""    # adds lines to HEIGHT
OPTIONS=() # adds lines to HEIGHt + CHOICE_HEIGHT
OPTIONS+=(AUTOMATICALLY "Add 1 OBFS4 bridge automatically (1 bridge every 24 hours)")
OPTIONS+=(MANUALLY "Add OBFS4 bridges manually")

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

  AUTOMATICALLY)
    clear
    echo -e "${RED}[+] Checking connectivity to the bridge database - please wait...${NOCOLOR}"
    #-m 6 must not be lower, otherwise it looks like there is no connection!
    OCHECK=$(curl -m 6 -s https://bridges.torproject.org)
    if [ $? == 0 ]; then
      echo -e "${WHITE}[+] OK - we are connected with the bridge database${NOCOLOR}"
      sleep 3
      clear
      whiptail --title "Tor - INFO" --textbox text/add-bridges-automatically-text $MENU_HEIGHT_15 $MENU_WIDTH
      clear
      echo -e "${RED}[+] Fetching a bridge... this may take some time, please wait!${NOCOLOR}"
      trap "bash ${SOURCE_SCRIPT} $MODE_BRIDGES $STANDALONE; exit 0" SIGINT
      bridge_address=$(sudo python3 config.scripts/tor.bridges-get.py)
      if grep -q "$bridge_address" $TORRC ; then
        echo -e "${WHITE}[!] This bridge is already added!${NOCOLOR}"
        echo -e "${RED}[+] Sorry, I didn't found a new valid bridge! Please, try again later or add bridges manually!${NOCOLOR}"
        echo " "
        read -n 1 -s -r -p "Press any key to continue"
        clear
      else
        if [ "$MODE_BRIDGES" = "UseBridges 1" ]; then
          bridge_address="$(<<< "$bridge_address" sed -e 's`obfs4`Bridge obfs4`g')"
          bridge_address=$(echo -e "$bridge_address\n")
        else
          bridge_address="$(<<< "$bridge_address" sed -e 's`obfs4`#Bridge obfs4`g')"
          bridge_address=$(echo -e "$bridge_address\n")
        fi
        echo ""
        echo -e "${RED}[+] Found a valid bridge!${NOCOLOR}"
        echo -e "${RED}[+] Saved a valid bridge!${NOCOLOR}"
        sudo echo $bridge_address >> $TORRC
        sleep 5
        clear
        if [ $STANDALONE = 1 ]; then
          activate_obfs4_bridges
          exit 0
        fi
      fi
    else
      clear
      echo -e "${WHITE}[!] SORRY! - no connection with the bridge database! Please, try again later!${NOCOLOR}"
      echo " "
      read -n 1 -s -r -p "Press any key to continue"
      clear
    fi
  ;;

  MANUALLY)
    clear
    whiptail --title "Tor - INFO" --textbox text/add-bridges-manually-text $MENU_HEIGHT_25 $MENU_WIDTH
    number_bridges=$(whiptail --title "Tor - INFO" --inputbox "\n\nHow many bridges do you like to add?" $MENU_HEIGHT_15 $MENU_WIDTH_REDUX 3>&1 1>&2 2>&3)
    if [ $number_bridges > 0 ]; then
      i=1
      while [ $i -le $number_bridges ]
      do
        bridge_address=$(whiptail --title "Tor - INFO" --inputbox "\n\nInsert one bridge (something like:\nobfs4 xxx.xxx.xxx.xxx.:xxxx cert=abcd.. iat-mode=0)" $MENU_HEIGHT_15 $MENU_WIDTH_REDUX 3>&1 1>&2 2>&3)
        bridge_address="$(<<< "$bridge_address" sed -e 's/[[:blank:]]*$//')"
        if grep -q "$bridge_address" $TORRC ; then
          echo -e "${WHITE}[!] Bridge number $i is already added!${NOCOLOR}"
          sleep 3
          i=$(( $i+1 ))
        else
          if [ "$MODE_BRIDGES" = "UseBridges 1" ]; then
            bridge_address="Bridge $bridge_address"
          else
            bridge_address="#Bridge $bridge_address"
          fi
          echo -e "${RED}[+] Saved bridge number $i!${NOCOLOR}"
          sudo echo $bridge_address >> $TORRC
          i=$(( $i+1 ))
        fi
      done
      sleep 5
      clear
      if [ $STANDALONE = 1 ]; then
        activate_obfs4_bridges
        exit 0
      fi
    else
      exit 0
    fi
  ;;

  *)
    clear
    exit 0

esac

bash ${SOURCE_SCRIPT}
exit 0
