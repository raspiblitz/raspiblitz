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
# This file activate or deactivate Meek-Azure to circumvent censorship.
# Following variables can be used:
# $SNOWSTRING -> represents the status of the Snowflake bridging mode
# $MEEKSTRING -> represents the status of the Meek-Azure bridging mode
#
#
# SYNTAX
# ./tor.bridges-meek-azure.sh <MEEKSTRING> <SNOWSTRING>
#
# <MEEKSTRING> <SNOWSTRING> give the status of Snowflake and Meek-Azure.
#
# Possible values for <MEEKSTRING> <SNOWSTRING>: "ON!" or "OFF".
#
#
#
###########################
######## FUNCTIONS ########

#include lib
. /home/admin/_tor.commands.sh

##### SET VARIABLES ######

SOURCE_SCRIPT="${USER_DIR}/config.scripts/tor.bridges-meek-azure.sh"

#Other variables
MEEKSTRING=$1
SNOWSTRING=$2
i=0

######## PREPARATIONS ########
###########################

if [ "$MEEKSTRING" = "OFF" ]; then
	clear
	trap "bash ${SOURCE_SCRIPT}; exit 0" SIGINT
	echo -e "${WHITE}[!] Let's first check, if MEEK-AZURE could work for you!${NOCOLOR}"
	readarray -t configured_meekazure_deactivated < <(grep "^#Bridge meek_lite " ${TORRC})
	if [ ${#configured_meekazure_deactivated[0]} = 0 ]; then
		echo " "
		echo -e "${WHITE}[!] There is no MEEK-AZURE configured! Did you change /etc/tor/torrc ?${NOCOLOR}"
		echo -e "${WHITE}[!] We cannot activate MEEK-AZURE! Contact anonym@torbox.ch for help!${NOCOLOR}"
		read -n 1 -s -r -p "Press any key to continue"
		exit 1
	else
		number_configured_meekazure_deactivated=${#configured_meekazure_deactivated[*]}
	fi
	echo " "
	echo -e "${RED}[+] Checking connectivity to the bridge database - please wait...${NOCOLOR}"
	#-m 6 must not be lower, otherwise it looks like there is no connection!
	OCHECK=$(curl -m 6 -s https://onionoo.torproject.org)
	if [ $? == 0 ]; then
		echo -e "${WHITE}[+] OK - we are connected with the bridge database${NOCOLOR}"
		echo -e "${RED}[+] Checking next the MEEK-AZURE SERVER${NOCOLOR}"
		echo -e "${RED}[+] You can only use MEEK-AZURE, if the server is ONLINE!${NOCOLOR}"
		sleep 2
		echo " "
		while [ $i -lt $number_configured_meekazure_deactivated ]
		do
			bridge_address=$(cut -d ' ' -f3,4 <<< ${configured_meekazure_deactivated[$i]})
			bridge_hash=$(cut -d ' ' -f2 <<< $bridge_address)
			bridge_status=$(${USER_DIR}/config.scripts/tor.bridges-check.py -f $bridge_hash)
			if [ $bridge_status == 1 ]; then bridge_status_txt="${GREEN}- ONLINE${NOCOLOR}"
		elif [ $bridge_status == 0 ]; then bridge_status_txt="${RED}- OFFLINE${NOCOLOR}"
	elif [ $bridge_status == 2 ]; then bridge_status_txt="- DOESN'T EXIST" ; fi
			i=$(( $i + 1 ))
			bridge_address="$i : $bridge_address $bridge_status_txt"
			echo -e $bridge_address
		done
		if [ $bridge_status == 0 ] || [ $bridge_status == 2 ]; then
			echo " "
			echo -e "${WHITE}[!] SORRY! - the SNOWFLAKE SERVER seems to be OFFLINE!${NOCOLOR}"
			echo -e "${RED}[+] We try to use it anyway, but most likely it will not work :(${NOCOLOR}"
		fi
		echo " "
		read -n 1 -s -r -p "Press any key to continue"
	else
		echo -e "${WHITE}[!] SORRY! - no connection with the bridge database!${NOCOLOR}"
		echo -e "${RED}[+] We cannot check the MEEK-AZURE SERVER - we try to use it anyway!${NOCOLOR}"
		echo " "
		read -n 1 -s -r -p "Press any key to continue"
	fi
	clear
	INPUT=$(cat text/activate-meek-azure-text)
	if (whiptail --title "Tor - INFO (scroll down!)" --scrolltext --defaultno --no-button "NO" --yes-button "YES" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
		clear
		activate_meek_bridges ${SOURCE_SCRIPT}
		clear
	fi
else
	if [ "$MEEKSTRING" = "ON!" ]; then
		INPUT=$(cat text/deactivate-meek-azure-text)
		if (whiptail --title "Tor - INFO" --defaultno --no-button "NO" --yes-button "YES" --yesno "$INPUT" $MENU_HEIGHT_15 $MENU_WIDTH_REDUX); then
            deactivate_meek_bridges
			restarting_tor ${SOURCE_SCRIPT}
		fi
	fi
fi
