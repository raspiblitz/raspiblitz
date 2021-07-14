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
# This file removes already configured bridges in /etc/tor/torrc.
#
# SYNTAX
# ./tor.bridges-obfs4-remove-old.sh <bridge mode>
#
# <show when zero bridges> -> defines if a message is shown or not if no bridges are configured in /etc/tor/torrc.
#
# <bridge mode>: "UseBridges 1" for bridge mode on; everything else = bridge mode off
#
###### SET VARIABLES ######

SOURCE_SCRIPT="config.scripts/tor.obfs4-remove-old.sh"

#Other variables
MODE_BRIDGES=$1
number_bridges=0
i=0

###########################
######## FUNCTIONS ########

# include lib
#. /home/admin/config.scripts/tor.functions.lib
. /home/admin/raspi-tor/config.scripts/tor.functions.lib

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

clear

# BASIC MENU INFO
HEIGHT=10 # add 6 to CHOICE_HEIGHT + MENU lines
WIDTH=80
BACKTITLE="Raspiblitz ${BRIDGESTRING}"
TITLE="Tor - BRIDGE REMOVAL MENU"
MENU=""    # adds lines to HEIGHT
OPTIONS=() # adds lines to HEIGHt + CHOICE_HEIGHT
OPTIONS+=(ALL "Remove ALL configured OBFS4 bridges and directly connect tor")
OPTIONS+=(DEPRECATED "Remove only OBFS4 bridges, which do not exist anymore")
OPTIONS+=(SELECTED "Remove only selected OBFS4 bridges")
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
  INPUT=$(cat text/delete-all-bridges-text)
  if (whiptail --title "Tor - INFO" --defaultno --no-button "DON'T CHANGE" --yes-button "REMOVE ALL BRIDGES" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
      sudo cp ${TORRC} ${BAK}
      deactivate_obfs4_bridges
      clear
      ${SOURCE_SCRIPT}
  fi
  exit 0
;;

DEPRECATED)
  clear
  echo -e "${RED}[+] Checking connectivity to the bridge database - please wait...${NOCOLOR}"
  OCHECK=$(curl -m 6 -s https://onionoo.torproject.org)
  if [ $? == 0 ]; then OCHECK="0"; else OCHECK="1"; fi
  if [ $OCHECK == 0 ]; then
    echo -e "${WHITE}[+] OK - we are connected with the bridge database${NOCOLOR}"
    echo " "
    echo -e "${RED}[+] Checking for bridges to remove - please wait...${NOCOLOR}"
    sudo cp ${TORRC} ${BAK}
    trap "bash ${SOURCE_SCRIPT}; exit 0" SIGINT
    j=0
    while [ $i -lt $number_configured_bridges_deactivated ]
    do
      bridge_address=$(cut -d ' ' -f2- <<< ${configured_bridges_deactivated[$i]})
      bridge_hash=$(cut -d ' ' -f3 <<< $bridge_address)
      bridge_status=$(./config.scripts/tor.bridges-check.py -f $bridge_hash)
      if [ $bridge_status == 2 ]; then
        j=$(($j + 1))
        echo -e "${RED}[+] Removing bridge with the hash $bridge_hash${NOCOLOR}"
        #This is necessary to work with special characters in sed
        ORIGINAL_STR="${configured_bridges_deactivated[$i]}"
        ORIGINAL_STR="$(<<< "$ORIGINAL_STR" sed -e 's`[][\\/.*^$]`\\&`g')"
        ORIGINAL_STR="^$ORIGINAL_STR"
        sudo grep -v "${ORIGINAL_STR}" ${TORRC} > ${TMP}; sudo mv ${TMP} ${TORRC}
      fi
      i=$(( $i + 1 ))
    done
    i=0
    while [ $i -lt $number_configured_bridges_activated ]
    do
      bridge_address=$(cut -d ' ' -f2- <<< ${configured_bridges_activated[$i]})
      bridge_hash=$(cut -d ' ' -f3 <<< $bridge_address)
      bridge_status=$(./config.scripts/tor.bridges-check.py -f $bridge_hash)
      if [ $bridge_status == 2 ]; then
        j=$(($j + 1))
        echo -e "${RED}[+] Removing bridge with the hash $bridge_hash${NOCOLOR}"
        #This is necessary to work with special characters in sed
        ORIGINAL_STR="${configured_bridges_activated[$i]}"
        ORIGINAL_STR="$(<<< "$ORIGINAL_STR" sed -e 's`[][\\/.*^$]`\\&`g')"
        ORIGINAL_STR="^$ORIGINAL_STR"
        sudo grep -v "${ORIGINAL_STR}" ${TORRC} > ${TMP}; sudo mv ${TMP} ${TORRC}
      fi
      i=$(( $i + 1 ))
    done
    if [ $j = 0 ]; then
      echo " "
      echo -e "${WHITE}[!] All checked OBFS4 do exist -> nothing to remove!${NOCOLOR}"
      sleep 5
      clear
    else
      echo " "
      read -n 1 -s -r -p "Press any key to continue"
      clear
      number_of_bridges
      if [ $MODE_BRIDGES = "UseBridges 1" ]; then
        if [ $number_configured_bridges_activated = 0 ]; then
          deactivate_obfs4_bridges
          restarting_tor ${SOURCE_SCRIPT}
        else
          restarting_tor ${SOURCE_SCRIPT}
        fi
      fi
    fi
  else
    echo -e "${WHITE}[+] OH NO! - no connection to the bridge database :( ${NOCOLOR}"
    echo -e "${WHITE}[+] Can't fetch the status of the bridges - ABORTING :( ${NOCOLOR}"
    sleep 5
    clear
  fi
  exit 0
;;


SELECTED)
  INPUT=$(cat text/delete-selected-bridges-text)
  if (whiptail --title "Tor - INFO" --defaultno --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
    number_to_be_deleted=$(whiptail --title "Tor - INFO" --inputbox "\n\nWhich bridge number(s) do you like to remove? Put in all bridge numbers separated by a comma (for example 1,2,3,10)" $MENU_HEIGHT_25 $MENU_WIDTH_REDUX 3>&1 1>&2 2>&3)
    number_to_be_deleted=$(cut -f1- -d ',' --output-delimiter=' ' <<< $number_to_be_deleted)
    delete_number=$(cut -d ' ' -f1 <<< $number_to_be_deleted)
    clear
    echo -e "${RED}[+] Checking for bridges to remove - please wait...${NOCOLOR}"
    sudo cp ${TORRC} ${BAK}
    j=0
    while [[ "$delete_number" != " " && $delete_number -gt 0 && $delete_number -le $number_configured_bridges_total ]]
    do
      if [ $delete_number -gt $number_configured_bridges_deactivated ]; then
        echo -e "${RED}[+] Removing bridge number $delete_number${NOCOLOR}"
        j=$(($j + 1))
        i=$(( $delete_number - $number_configured_bridges_deactivated - 1 ))
        #This is necessary to work with special characters
        ORIGINAL_STR="${configured_bridges_activated[$i]}"
        ORIGINAL_STR="$(<<< "$ORIGINAL_STR" sed -e 's`[][\\/.*^$]`\\&`g')"
        ORIGINAL_STR="^$ORIGINAL_STR"
        sudo grep -v "${ORIGINAL_STR}" ${TORRC} > ${TMP}; sudo mv ${TMP} ${TORRC}
      else
        echo -e "${RED}[+] Removing bridge number $delete_number${NOCOLOR}"
        j=$(($j + 1))
        i=$(( $delete_number - 1 ))
        #This is necessary to work with special characters
        ORIGINAL_STR="${configured_bridges_deactivated[$i]}"
        ORIGINAL_STR="$(<<< "$ORIGINAL_STR" sed -e 's`[][\\/.*^$]`\\&`g')"
        ORIGINAL_STR="^$ORIGINAL_STR"
        sudo grep -v "${ORIGINAL_STR}" ${TORRC} > ${TMP}; sudo mv ${TMP} ${TORRC}
      fi
      if [ "$delete_number" = "$number_to_be_deleted" ]; then
        delete_number=0
      else
        number_to_be_deleted=$(cut -d ' ' -f2- <<< $number_to_be_deleted)
        delete_number=$(cut -d ' ' -f1 <<< $number_to_be_deleted)
      fi
    done
    number_of_bridges
    if [ $j = 0 ]; then
      echo " "
      echo -e "${WHITE}[!] We had nothing to remove! Did we?${NOCOLOR}"
      sleep 5
      clear
    else
      echo " "
      read -n 1 -s -r -p "Press any key to continue"
      clear
      number_of_bridges
      if [ $MODE_BRIDGES = "UseBridges 1" ]; then
        if [ $number_configured_bridges_activated = 0 ]; then
          deactivate_obfs4_bridges
          restarting_tor ${SOURCE_SCRIPT}
        else
          restarting_tor ${SOURCE_SCRIPT}
        fi
      fi
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

bash ${SOURCE_SCRIPT}
exit 0
