#!/bin/bash

# This file is part of TorBox, an easy to use anonymizing router based on Raspberry Pi.
# Copyright (C) 2021 Patrick Truffer
# Contact: anonym@torbox.ch
# Website: https://www.torbox.ch
# Github:  https://github.com/radio24/TorBox
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
# This file displays the bridges menu and executes all relevant scripts.
#
# SYNTAX
# ./96torBridgesMenu.sh
#

###########################
######## FUNCTIONS ########

# include lib
. /home/admin/config.scripts/tor.functions.lib

SOURCE_SCRIPT="${USER_DIR}/96torBridgesMenu"

#Other variables
i=0
j=0

# This function imports the configuration and makes some preparations
read_config(){

  bridge_mode

  # number_of_bridges()
  # How many OBFS4 bridges do we have? readarray reads into an array beginning with index 0
  # Following variables can be used:
  # $configured_bridges_deactivated -> An array with all deactivated OBFS4 bridges
  # $configured_bridges_activated -> An array with all activated OBFS4 bridges
  # $number_configured_bridges_deactivated -> Number of deactivated bridges
  # $number_configured_bridges_activated -> Number of activated bridges
  # $number_configured_bridges_total -> Total number of bridges
  number_of_bridges
}

######## PREPARATIONS ########
read_config

###### DISPLAY THE MENU ######
clear

# BASIC MENU INFO
HEIGHT=17 # add 6 to CHOICE_HEIGHT + MENU lines
WIDTH=75
BACKTITLE="Raspiblitz ${BRIDGESTRING}"
TITLE=" Tor Bridges "
MENU=""    # adds lines to HEIGHT
OPTIONS=() # adds lines to HEIGHt + CHOICE_HEIGHT
OPTIONS+=(========== "=[Informational]=====================================================")
OPTIONS+=(README "Bridges and Pluggable Transports - READ ME FIRST!")
OPTIONS+=(========== "=[OBFS4]============================================================")
OPTIONS+=(ACTIVATE "Activate configured bridges")
OPTIONS+=(DEACTIVATE "Deactivate configured bridges")
OPTIONS+=(ADD "Add additional bridges")
OPTIONS+=(REMOVE "Remove configured bridges")
OPTIONS+=(LIST "List all "${number_configured_bridges_total}" bridges and their status")
OPTIONS+=(========== "=[Other bridges types]===============================================")
OPTIONS+=(SNOWFLAKE ${SNOWSTRINGb}" snowflake bridges")
OPTIONS+=(MEEK_AZURE ${MEEKSTRINGb}" meek-azure bridges")

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

  # Informational
  README)
    INPUT=$(cat ${USER_DIR}/text/help-bridges-text)
    if (whiptail --title "Tor - INFO (scroll down!)" --msgbox --scrolltext "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
      clear
    fi
  ;;

  ACTIVATE)
    if [ "$MODE_MEEK" = "Bridge meek_lite " ] || [ "$MODE_SNOW" = "Bridge snowflake " ]; then
      whiptail --title "Tor - INFO" --textbox ${USER_DIR}/text/no_meek-snow-please-text $MENU_HEIGHT_15 $MENU_WIDTH_REDUX
    fi
    if [ $number_configured_bridges_total = 0 ]; then
      INPUT=$(cat ${USER_DIR}/text/add-bridges-first-text)
      if (whiptail --title "Tor - INFO" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
        sudo bash ${USER_DIR}/config.scripts/tor.bridges-obfs4-add.sh "$MODE_BRIDGES" 0
      else
        deactivate_obfs4_bridges
        trap "bash ${USER_DIR}/96torBridgesMenu.sh; exit 0" EXIT
        exit 0
      fi
    fi
    if [ "$MODE_BRIDGES" != "UseBridges 1" ]; then
      INPUT=$(cat ${USER_DIR}/text/activate-bridges-text)
      if (whiptail --title "Tor - INFO" --defaultno --no-button "NO" --yes-button "YES" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
        sudo bash ${USER_DIR}/config.scripts/tor.bridges-obfs4-activate.sh
      else
        trap "bash ${USER_DIR}/96torBridgesMenu.sh; exit 0" EXIT
        exit 0
      fi
    else
      sudo bash ${USER_DIR}/config.scripts/tor.bridges-obfs4-activate.sh
    fi
    read_config
  ;;

  DEACTIVATE)
    if [ $number_configured_bridges_total = 0 ]; then
      clear
      echo -e "${WHITE}[!] There are no configured OBFS4 bridges -> nothing to deactivate!${NOCOLOR}"
      sleep 5
    else
      if [ "$MODE_OBFS4" != "Bridge obfs4 " ]; then
        clear
        echo -e "${WHITE}[!] No OBFS4 bridges are activated!${NOCOLOR}"
        echo -e "${RED}[+] If you want to use OBFS4 bridges, you have to activate them first.${NOCOLOR}"
        sleep 5
      else
        INPUT=$(cat ${USER_DIR}/text/deactivate-bridges-text)
        if (whiptail --title "Tor - INFO" --defaultno --no-button "NO" --yes-button "YES" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
          sudo bash ${USER_DIR}/config.scripts/tor.bridges-obfs4-deactivate.sh
          read_config
        fi
      fi
    fi
  ;;

  ADD)
    if [ "$MODE_MEEK" = "Bridge meek_lite " ] || [ "$MODE_SNOW" = "Bridge snowflake " ]; then
      whiptail --title "Tor - INFO" --textbox ${USER_DIR}/text/no_meek-snow-please-text $MENU_HEIGHT_15 $MENU_WIDTH_REDUX
    fi
    sudo bash ${USER_DIR}/config.scripts/tor.bridges-obfs4-add.sh "$MODE_BRIDGES" 1
    read_config
  ;;

  REMOVE)
    if [ $number_configured_bridges_total = 0 ]; then
      clear
      echo -e "${WHITE}[!] There are no configured OBFS4 bridges -> nothing to remove!${NOCOLOR}"
      sleep 5
    else
      whiptail --title "Tor - INFO" --textbox ${USER_DIR}/text/remove-bridges-text $MENU_HEIGHT_25 $MENU_WIDTH
      sudo bash ${USER_DIR}/config.scripts/tor.bridges-obfs4-remove.sh "$MODE_BRIDGES"
      read_config
    fi
  ;;

  LIST)
    clear
    echo -e "${RED}[+] Checking connectivity to the bridge database - please wait...${NOCOLOR}"
    #-m 6 must not be lower, otherwise it looks like there is no connection!
    OCHECK=$(curl -m 6 -s https://onionoo.torproject.org)
    if [ $? == 0 ]; then
      OCHECK="0"
      echo -e "${WHITE}[+] OK - we are connected with the bridge database${NOCOLOR}"
      sleep 2
    else
      OCHECK="1"
      echo -e "${WHITE}[!] SORRY! - no connection with the bridge database${NOCOLOR}"
      sleep 2
    fi
    number_of_bridges
    if [ $number_configured_bridges_deactivated -gt 0 ]; then
      echo " "
      echo " "
      echo -e "${RED}[+] DEACTIVATED BRIDGES${NOCOLOR}"
      echo -e "${RED}[+] Format: <Number>: <IP>:<Port> <Fingerprint> <- STATUS>${NOCOLOR}"
      echo -e "${RED}[+] Would you like to have more information on a specific bridge?${NOCOLOR}"
      echo -e "${RED}[+] Go to https://metrics.torproject.org/rs.html and search for the fingerprint${NOCOLOR}"
      echo " "
      trap "bash ${USER_DIR}/96torBridgesMenu.sh; exit 0" SIGINT
      while [ $i -lt $number_configured_bridges_deactivated ]
      do
          bridge_address=$(cut -d ' ' -f3,4 <<< ${configured_bridges_deactivated[$i]})
          if [ $OCHECK == 0 ]; then
            bridge_hash=$(cut -d ' ' -f2 <<< $bridge_address)
            bridge_status=$(${USER_DIR}/config.scripts/tor.bridges-check.py -f $bridge_hash)
            if [ $bridge_status == 1 ]; then bridge_status="${GREEN}- ONLINE${NOCOLOR}"
            elif [ $bridge_status == 0 ]; then bridge_status="${RED}- OFFLINE${NOCOLOR}"
            elif [ $bridge_status == 2 ]; then bridge_status="- DOESN'T EXIST" ; fi
          else bridge_status=" "
          fi
          i=$(( $i + 1 ))
          bridge_address="$i : $bridge_address $bridge_status"
          echo -e $bridge_address
      done
    fi
    if [ $number_configured_bridges_activated -gt 0 ]; then
      echo " "
      echo " "
      echo -e "${RED}[+] ACTIVATED BRIDGES${NOCOLOR}"
      echo -e "${RED}[+] Format: <Number>: <IP>:<Port> <Fingerprint> <- STATUS>${NOCOLOR}"
      echo -e "${RED}[+] Would you like to have more information on a specific bridge?${NOCOLOR}"
      echo -e "${RED}[+] Go to https://metrics.torproject.org/rs.html and search for the fingerprint${NOCOLOR}"
      echo " "
      trap "bash ${USER_DIR}/96torBridgesMenu.sh; exit 0" SIGINT
      j=0
      while [ $j -lt $number_configured_bridges_activated ]
      do
          bridge_address=$(cut -d ' ' -f3,4 <<< ${configured_bridges_activated[$j]})
          if [ $OCHECK == 0 ]; then
            bridge_hash=$(cut -d ' ' -f2 <<< $bridge_address)
            bridge_status=$(${USER_DIR}/config.scripts/tor.bridges-check.py -f $bridge_hash)
            if [ $bridge_status == 1 ]; then bridge_status="${GREEN}- ONLINE${NOCOLOR}"
            elif [ $bridge_status == 0 ]; then bridge_status="${RED}- OFFLINE${NOCOLOR}"
            elif [ $bridge_status == 2 ]; then bridge_status="- DOESN'T EXIST" ; fi
          else bridge_status=" "
          fi
          j=$(( $j + 1 ))
          n=$(( $i + $j ))
          bridge_address="${WHITE}$n : $bridge_address${NOCOLOR} $bridge_status"
          echo -e "$bridge_address"
      done
    fi
    if [ $number_configured_bridges_total = 0 ]; then
      echo " "
      echo " "
      echo -e "${WHITE}[!] SORRY! - there are no configured OBFS4 bridges!${NOCOLOR}"
    fi
    echo " "
    read -n 1 -s -r -p "Press any key to continue"
  ;;

  # Other pb bridges types
  SNOWFLAKE)
    if [ "$MODE_MEEK" = "Bridge meek_lite " ] || [ "$MODE_OBFS4" = "Bridge obfs4 " ]; then
      whiptail --title "Tor - INFO" --textbox ${USER_DIR}/text/no_meek-please-text $MENU_HEIGHT_15 $MENU_WIDTH_REDUX
    fi
    sudo bash ${USER_DIR}/config.scripts/tor.bridges-snowflake.sh $SNOWSTRING $MEEKSTRING
    read_config
  ;;

  MEEK_AZURE)
    if [ "$MODE_OBFS4" = "Bridge obfs4 " ] || [ "$MODE_SNOW" = "Bridge snowflake " ]; then
      whiptail --title "Tor - INFO" --textbox ${USER_DIR}/text/no_snow-please-text $MENU_HEIGHT_15 $MENU_WIDTH_REDUX
    fi
    sudo bash ${USER_DIR}/config.scripts/tor.bridges-meek-azure.sh $MEEKSTRING $SNOWSTRING
    read_config
  ;;

  # Fake option and non listed
  ==========)
  ;;

  *)
    exit 0

esac

bash ${USER_DIR}/96torBridgesMenu.sh