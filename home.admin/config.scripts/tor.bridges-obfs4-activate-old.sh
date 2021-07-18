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
# This file activates already configured bridges in /etc/tor/torrc.
#
# SYNTAX
# ./bridges_activate_old
#
#
###### SET VARIABLES ######

SOURCE_SCRIPT="config.scripts/tor.bridges-obfs4-activate.sh"

#Other variables
i=0

###########################
######## FUNCTIONS ########

# include lib
. /home/admin/_tor.commands.sh

######## PREPARATIONS ########
#
# number_of_bridges()
# How many OBFS4 bridges do we have? readarray reads into an array beginning with index 0
# Following variables can be used:
# $configured_bridges_deactivated -> An array with all deactivated OBFS4 bridges
# $configured_bridges_activated -> An array with all activated OBFS4 bridges
# $number_configured_bridges_deactivated -> Number of deactivated bridges
# $number_configured_bridges_activated -> Number of activated bridges
# $number_configured_bridges_total -> Total number of bridges
number_of_bridges

###########################

if [ $number_configured_bridges_deactivated = 0 ]; then
  clear
  echo -e "${WHITE}[!] There are no deactivated OBFS4 bridges. ${NOCOLOR}"
  echo -e "${RED}[+] You may use the menu entry \"Deactivate OBFS4...\". ${NOCOLOR}"
  sleep 5
  exit 0
else
  clear

  # BASIC MENU INFO
  HEIGHT=10 # add 6 to CHOICE_HEIGHT + MENU lines
  WIDTH=80
  BACKTITLE="Raspiblitz ${BRIDGESTRING}"
  TITLE="Tor - BRIDGE ACTIVATION MENU"
  MENU=""    # adds lines to HEIGHT
  OPTIONS=() # adds lines to HEIGHt + CHOICE_HEIGHT
  OPTIONS+=(ALL "Activate ALL configured bridges")
  OPTIONS+=(ONLINE "Activate only bridges, which are ONLINE")
  OPTIONS+=(SELECTED "Add OBFS4 bridges manually")
  OPTIONS+=(LIST "List all "$number_configured_bridges_total" OBFS4 bridges")

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

  ALL)
    sudo sed -i "s/^#Bridge obfs4 /Bridge obfs4 /g" ${TORRC}
    activate_obfs4_bridges
    exit 0
  ;;

  ONLINE)
    clear
    echo -e "${RED}[+] Checking connectivity to the bridge database - please wait...${NOCOLOR}"
    OCHECK=$(curl -m 6 -s https://onionoo.torproject.org)
    if [ $? == 0 ]; then OCHECK="0"; else OCHECK="1"; fi
    if [ $OCHECK == 0 ]; then
      echo -e "${WHITE}[+] OK - we are connected with the bridge database${NOCOLOR}"
      echo " "
      echo -e "${RED}[+] Checking for bridges to activate - please wait...${NOCOLOR}"
      trap "bash ${SOURCE_SCRIPT}; exit 0" SIGINT
      while [ $i -lt $number_configured_bridges_deactivated ]
      do
        bridge_address=$(cut -d ' ' -f2- <<< ${configured_bridges_deactivated[$i]})
        bridge_hash=$(cut -d ' ' -f3 <<< $bridge_address)
        bridge_status=$(./config.scripts/tor.bridges-check.py -f $bridge_hash)
        j=0
        if [ $bridge_status == 1 ]; then
          j=$(($i + 1))
          echo -e "${GREEN}[+] Activating bridge number $j${NOCOLOR}"
          #This is necessary to work with special characters in sed
          ORIGINAL_STR="#Bridge $bridge_address"
          ORIGINAL_STR="$(<<< "$ORIGINAL_STR" sed -e 's`[][\\/.*^$]`\\&`g')"
          ORIGINAL_STR="^$ORIGINAL_STR"
          REPLACEMENT_STR="Bridge $bridge_address"
          REPLACEMENT_STR="$(<<< "$REPLACEMENT_STR" sed -e 's`[][\\/.*^$]`\\&`g')"
          sudo sed -i "s/${ORIGINAL_STR}/${REPLACEMENT_STR}/g" ${TORRC}
        fi
        i=$(( $i + 1 ))
      done
      echo " "
      read -n 1 -s -r -p "Press any key to continue"
      clear
      if [ $j -gt 0 ]; then
        activate_obfs4_bridges
        exit 0
      else
        echo ""
        echo -e "${WHITE}[!] There are no usable OBFS4 bridges :(  ${NOCOLOR}"
        echo -e "${RED}[+] Please add some new OBFS4 bridges first! ${NOCOLOR}"
        sleep 5
        clear
      fi
    else
      echo ""
      echo -e "${WHITE}[!] OH NO! - no connection to the bridge database :( ${NOCOLOR}"
      echo -e "${WHITE}[!] Can't fetch the status of the bridges - ABORTING :( ${NOCOLOR}"
      sleep 5
      clear
    fi
    exit 0
  ;;

  SELECTED)
    INPUT=$(cat text/activate-selected-bridges-text)
    if (whiptail --title "Tor - INFO" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
      number_to_be_activated=$(whiptail --title "Tor - INFO" --inputbox "\n\nWhich bridge number(s) do you like to activate? Put in all bridge numbers separated by a comma (for example 1,2,3,10)" $MENU_HEIGHT_15 $MENU_WIDTH_REDUX 3>&1 1>&2 2>&3)
      number_to_be_activated=$(cut -f1- -d ',' --output-delimiter=' ' <<< $number_to_be_activated)
      activate_number=$(cut -d ' ' -f1 <<< $number_to_be_activated)
      clear
      echo -e "${RED}[+] Checking for bridges to activate - please wait...${NOCOLOR}"
      j=0
      while [[ "$activate_number" != " " && $activate_number -gt 0 && $activate_number -le $number_configured_bridges_deactivated ]]
      do
        i=$(( $activate_number - 1 ))
        bridge_address=$(cut -d ' ' -f2- <<< ${configured_bridges_deactivated[$i]})
        # Row below is not necessary?
        # bridge_hash=$(cut -d ' ' -f3 <<< $bridge_address)
        j=$(($i + 1))
        echo -e "${RED}[+] Activating bridge number $j${NOCOLOR}"
        #This is necessary to work with special characters in sed
        ORIGINAL_STR="#Bridge $bridge_address"
        ORIGINAL_STR="$(<<< "$ORIGINAL_STR" sed -e 's`[][\\/.*^$]`\\&`g')"
        ORIGINAL_STR="^$ORIGINAL_STR"
        REPLACEMENT_STR="Bridge $bridge_address"
        REPLACEMENT_STR="$(<<< "$REPLACEMENT_STR" sed -e 's`[][\\/.*^$]`\\&`g')"
        sudo sed -i "s/${ORIGINAL_STR}/${REPLACEMENT_STR}/g" ${TORRC}
        if [ "$activate_number" = "$number_to_be_activated" ]; then
          activate_number=0
        else
          number_to_be_activated=$(cut -d ' ' -f2- <<< $number_to_be_activated)
          activate_number=$(cut -d ' ' -f1 <<< $number_to_be_activated)
        fi
      done
      echo " "
      read -n 1 -s -r -p "Press any key to continue"
      clear
      if [ $j -gt 0 ]; then
        activate_obfs4_bridges
        exit 0
      fi
    fi
  ;;

  LIST)
    list_all_obfs4_bridges
  ;;

  *)
    clear
    exit 0

  esac

sleep 5
  bash ${SOURCE_SCRIPT}
  exit 0
fi
