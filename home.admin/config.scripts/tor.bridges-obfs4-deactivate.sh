#!/bin/bash


# This file is part of TorBox, an easy to use anonymizing router based on Raspberry Pi.
# Copyright (C) 2021 Patrick Truffer
# Contact: anonym@torbox.ch
#
# Copyright (C) 2021 The RaspiBlitz developers
# Github:  https://github.com/rootzoll/raspiblitz
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
# This file deactivates already configured bridges in /etc/tor/torrc.
#
# SYNTAX
# ./tor.bridges-obfs4-deactivate.sh
#
#
###########################
######## FUNCTIONS ########

# include lib
. /home/admin/config.scripts/tor.functions.lib

###### SET VARIABLES ######

SOURCE_SCRIPT="${USER_DIR}/config.scripts/tor.bridges-obfs4-deactivate.sh"

#Other variables
i=0

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

if [ $number_configured_bridges_activated = 0 ]; then
  #clear
  echo -e "${WHITE}[!] There are no activated OBFS4 bridges. ${NOCOLOR}"
  echo -e "${RED}[+] You may use the menu entry \"Activate configured OBFS4 bridges...\". ${NOCOLOR}"
  sleep 3
  exit 0
else
  #clear

  # BASIC MENU INFO
  HEIGHT=10 # add 6 to CHOICE_HEIGHT + MENU lines
  WIDTH=80
  BACKTITLE="Raspiblitz ${BRIDGESTRING}"
  TITLE="Tor - BRIDGE DEACTIVATION MENU"
  MENU=""    # adds lines to HEIGHT
  OPTIONS=() # adds lines to HEIGHt + CHOICE_HEIGHT
  OPTIONS+=(ALL "Deactivate ALL configured bridges")
  OPTIONS+=(OFFLINE "Deactivate only bridges, which are not longer ONLINE")
  OPTIONS+=(SELECTED "Deactivate only selected bridges")
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
    deactivate_obfs4_bridges
    restarting_tor ${SOURCE_SCRIPT}
    exit 0
  ;;

  OFFLINE)
    clear
    echo -e "${RED}[+] Checking connectivity to the bridge database - please wait...${NOCOLOR}"
    OCHECK=$(curl -m 6 -s https://onionoo.torproject.org)
    if [ $? == 0 ]; then OCHECK="0"; else OCHECK="1"; fi
    if [ $OCHECK == 0 ]; then
      echo -e "${WHITE}[+] OK - we are connected with the bridge database${NOCOLOR}"
      echo " "
      echo -e "${RED}[+] Checking for bridges to deactivate - please wait...${NOCOLOR}"
      trap "bash ${SOURCE_SCRIPT}; exit 0" SIGINT
      j=0
      while [ $i -lt $number_configured_bridges_activated ]
      do
        bridge_address=$(cut -d ' ' -f2- <<< ${configured_bridges_activated[$i]})
        bridge_hash=$(cut -d ' ' -f3 <<< $bridge_address)
        bridge_status=$(${USER_DIR}/config.scripts/tor.bridges-check.py -f $bridge_hash)
        if [ $bridge_status == 0 ] || [ $bridge_status == 2 ]; then
          j=$(($j + 1))
          echo -e "${RED}[+] Deactivating bridge with the hash $bridge_hash${NOCOLOR}"
          #This is necessary to work with special characters in sed
          ORIGINAL_STR="Bridge $bridge_address"
          ORIGINAL_STR="$(<<< "$ORIGINAL_STR" sed -e 's`[][\\/.*^$]`\\&`g')"
          ORIGINAL_STR="^$ORIGINAL_STR"
          REPLACEMENT_STR="#Bridge $bridge_address"
          REPLACEMENT_STR="$(<<< "$REPLACEMENT_STR" sed -e 's`[][\\/.*^$]`\\&`g')"
          sudo sed -i "s/${ORIGINAL_STR}/${REPLACEMENT_STR}/g" ${TORRC}
        fi
        i=$(( $i + 1 ))
      done
      if [ $j = 0 ]; then
        echo " "
        echo -e "${WHITE}[!] All checked OBFS4 do exist and are online -> nothing to deactivate!${NOCOLOR}"
        sleep 5
        clear
      else
        echo " "
        read -n 1 -s -r -p "Press any key to continue"
        clear
        number_of_bridges
        if [ $number_configured_bridges_activated = 0 ]; then
          deactivate_obfs4_bridges
          restarting_tor ${SOURCE_SCRIPT}
        else
          activate_obfs4_bridges ${SOURCE_SCRIPT}
          exit 0
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
    INPUT=$(cat ${USER_DIR}/text/deactivate-selected-bridges-text)
    if (whiptail --title "Tor - INFO" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
      number_to_be_deactivated=$(whiptail --title "Tor - INFO" --inputbox "\n\nWhich bridge number(s) do you like to deactivate? Put in all bridge numbers separated by a comma (for example 1,2,3,10)" $MENU_HEIGHT_25 $MENU_WIDTH_REDUX 3>&1 1>&2 2>&3)
      number_to_be_deactivated=$(cut -f1- -d ',' --output-delimiter=' ' <<< $number_to_be_deactivated)
      deactivate_number=$(cut -d ' ' -f1 <<< $number_to_be_deactivated)
      number_configured_bridges_activated=$(( $number_configured_bridges_deactivated + $number_configured_bridges_activated ))
      clear
      echo -e "${RED}[+] Checking for bridges to deactivate - please wait...${NOCOLOR}"
      j=0
      while [[ "$deactivate_number" != " " && $deactivate_number -gt 0 && $deactivate_number -gt $number_configured_bridges_deactivated && $deactivate_number -le $number_configured_bridges_activated ]]
      do
        i=$(( $deactivate_number - $number_configured_bridges_deactivated - 1 ))
        bridge_address=$(cut -d ' ' -f2- <<< ${configured_bridges_activated[$i]})
        # Row below is not necessary?
        # bridge_hash=$(cut -d ' ' -f3 <<< $bridge_address)
        j=$(($j + 1))
        echo -e "${RED}[+] Dectivating bridge number $deactivate_number${NOCOLOR}"
        #This is necessary to work with special characters in sed
        ORIGINAL_STR="Bridge $bridge_address"
        ORIGINAL_STR="$(<<< "$ORIGINAL_STR" sed -e 's`[][\\/.*^$]`\\&`g')"
        ORIGINAL_STR="^$ORIGINAL_STR"
        REPLACEMENT_STR="#Bridge $bridge_address"
        REPLACEMENT_STR="$(<<< "$REPLACEMENT_STR" sed -e 's`[][\\/.*^$]`\\&`g')"
        sudo sed -i "s/${ORIGINAL_STR}/${REPLACEMENT_STR}/g" ${TORRC}
        if [ "$deactivate_number" = "$number_to_be_deactivated" ]; then
          deactivate_number=0
        else
          number_to_be_deactivated=$(cut -d ' ' -f2- <<< $number_to_be_deactivated)
          deactivate_number=$(cut -d ' ' -f1 <<< $number_to_be_deactivated)
        fi
      done
      echo " "
      read -n 1 -s -r -p "Press any key to continue"
      clear
      number_of_bridges
      if [ $number_configured_bridges_activated = 0 ]; then
        deactivate_obfs4_bridges
        clear
        restarting_tor ${SOURCE_SCRIPT}
      else
        if [ $j -gt 0 ]; then
          activate_obfs4_bridges
          exit 0
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
fi

bash ${SOURCE_SCRIPT}
exit 0
