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
# This file activates or deactivates Snowflake to circumvent censorship.
# Following variables can be used:
#
# SYNTAX
# ./tor.bridges-snowflake.sh <SNOWSTRING> <MEEKSTRING>
#
# <SNOWSTRING> <MEEKSTRING> give the status of Snowflake and Meek-Azure.
#
# Possible values for <SNOWSTRING> <MEEKSTRING>: "ON!" or "OFF".
#
#

###########################
######## FUNCTIONS ########

#include lib
. /home/admin/config.scripts/tor.functions.lib

##### SET VARIABLES ######

SOURCE_SCRIPT="${USER_DIR}/config.scripts/tor.bridges-snowflake.sh"

#Other variables
SNOWSTRING=$1
MEEKSTRING=$2
i=0

######## PREPARATIONS ########
###########################

if [ "$SNOWSTRING" = "OFF" ]; then
	clear
	trap "bash ${SOURCE_SCRIPT}; exit 0" SIGINT
	echo -e "${WHITE}[!] Let's first check, if SNOWFLAKE could work for you!${NOCOLOR}"
	readarray -t configured_snowflake_deactivated < <(grep "^#Bridge snowflake " ${TORRC})
	if [ ${#configured_snowflake_deactivated[0]} = 0 ]; then
		echo " "
		echo -e "${WHITE}[!] There is no SNOWFLAKE configured! Did you change /etc/tor/torrc ?${NOCOLOR}"
		echo -e "${WHITE}[!] We cannot activate SNOWFLAKE! Contact anonym@torbox.ch for help!${NOCOLOR}"
		read -n 1 -s -r -p "Press any key to continue"
		exit 1
	else
		number_configured_snowflake_deactivated=${#configured_snowflake_deactivated[*]}
	fi
	echo " "
	echo -e "${RED}[+] Checking connectivity to the bridge database - please wait...${NOCOLOR}"
	#-m 6 must not be lower, otherwise it looks like there is no connection!
	OCHECK=$(curl -m 6 -s https://onionoo.torproject.org)
	if [ $? == 0 ]; then
		echo -e "${WHITE}[+] OK - we are connected with the bridge database${NOCOLOR}"
		echo -e "${RED}[+] Checking next the SNOWFLAKE SERVER${NOCOLOR}"
		echo -e "${RED}[+] You can only use SNOWFLAKE, if the server is ONLINE!${NOCOLOR}"
		sleep 2
		echo " "
		while [ $i -lt $number_configured_snowflake_deactivated ]
		do
			bridge_address=$(cut -d ' ' -f3,4 <<< ${configured_snowflake_deactivated[$i]})
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
		echo -e "${RED}[+] We cannot check the SNOWFLAKE SERVER - we try to use it anyway!${NOCOLOR}"
		echo " "
		read -n 1 -s -r -p "Press any key to continue"
	fi
	clear
	INPUT=$(cat ${USER_DIR}/text/activate-snowflake-text)
	if (whiptail --title "Tor - INFO (scroll down!)" --scrolltext --defaultno --no-button "NO" --yes-button "YES" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
		clear
		activate_snowflake_bridges ${SOURCE_SCRIPT}
		clear
	fi
else
	if [ "$SNOWSTRING" = "ON!" ]; then
		INPUT=$(cat ${USER_DIR}/text/deactivate-snowflake-text)
		if (whiptail --title "Tor - INFO" --defaultno --no-button "NO" --yes-button "YES" --yesno "$INPUT" $MENU_HEIGHT_15 $MENU_WIDTH_REDUX); then
			clear
	    	activate_snowflake_bridges ${SOURCE_SCRIPT}
		fi
	fi
fi
