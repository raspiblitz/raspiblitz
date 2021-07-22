#!/bin/bash

# Portions of this file was source from TorBox, an easy to use anonymizing router based on Raspberry Pi.
#
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
# This file is a library for the TorBox menu.
# It contains functions which are used in several scripts.
# Hopefully, this way the scripts stay short and clear.
#
# SYNTAX
# . config.scripts/tor.functions.lib
#
##### SET VARIABLES ######
#
#Set the the variables for the menu
MENU_WIDTH=80
MENU_WIDTH_REDUX=60
MENU_HEIGHT_15=15
MENU_HEIGHT_20=20
MENU_HEIGHT_25=25

#Colors
NOCOLOR='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
AMBER='\033[0;33m'
WHITE='\033[1;37m'
YELLOW='\033[1;93m'

#Connectivity check
CHECK_URL1="http://debian.org"
PING_SERVER="debian.org"

DISTRIBUTION=$(lsb_release -sc)

SOURCES_DEB_SECURITY_ONION="http://5ajw6aqf3ep7sijnscdzw77t7xq4xjpsy335yb2wiwgouo7yfxtjlmid.onion/"
SOURCES_DEB_UPDATE_ONION="http://2s4yqjx5ul6okpp3f2gaunr2syex5jgbfpfvhxxbbjwnrsvbk5v3qbid.onion/"
SOURCES_DEB_SECURITY_PLAIN="https://deb.debian.org/"
SOURCES_DEB_UPDATE_PLAIN="https://deb.debian.org/"

SOURCES_TOR_UPDATE_ONION="http://apow7mjfryruh65chtdydfmqfpj5btws7nbocgtaovhvezgccyjazpqd.onion/"
SOURCES_TOR_UPDATE_PLAIN="https://deb.torproject.org/"

#Other variables
DEFAULT_CONTROL_PORT=9051
DEFAULT_SOCKS_PORT=9050
OWNER_TOR_CONF_DIR="bitcoin"
OWNER_TOR_DATA_DIR="debian-tor"
USER="admin"
ROOT_TORRC="/etc/tor"
TORRC="${ROOT_TORRC}/torrc"
ROOT_DATA_DIR="/var/lib" #"/mnt/hdd"
DATA_DIR="${ROOT_DATA_DIR}/tor"
SERVICES_DATA_DIR="${DATA_DIR}/services"
USER_DIR="/home/${USER}"
SCRIPTS_DIR="${USER_DIR}/config.scripts"
ONION_SERVICE_SCRIPT="${SCRIPTS_DIR}/tor.onion-service.sh"
INFO="${ROOT_DATA_DIR}/raspiblitz.info"
CONF="${ROOT_DATA_DIR}/raspiblitz.conf"

source ${INFO}
source ${CONF}

##############################
######## FUNCTIONS ###########

set_owner_permission(){
  sudo chown -R ${OWNER_TOR_DATA_DIR}:${OWNER_TOR_DATA_DIR} ${DATA_DIR}
  sudo chown ${OWNER_TOR_CONF_DIR}:${OWNER_TOR_CONF_DIR} ${TORRC}
  sudo chmod 700 ${DATA_DIR}
  sudo chmod 644 ${TORRC}
}

# check_tor()
# Used predefined variables: RED, NOCOLOR
# This function checks the status on https://check.torproject.org/
check_tor()
{
clear
echo -e "${RED}[+] Checking connectivity to the Tor network - please wait...${NOCOLOR}"
TOR_SERVICE=$(curl --socks5 localhost:9050 --socks5-hostname localhost:9050 -m 5 -s https://check.torproject.org/ | cat | grep -m 1 Congratulations | xargs)
TOR_SERVICE=$(cut -d "." -f1 <<< $TOR_SERVICE)

if [ "$TOR_SERVICE" = "Congratulations" ]; then
  TOR_STATUS="Tor is working"
else
  TOR_STATUS=""
fi
clear
}

# finish()
# Used predefined variables: MENU_HEIGHT_25 MENU_WIDTH
# This function displays, if we have a working connection to the Tor network
finish()
{
  check_tor
  if [ "$TOR_STATUS" = "Tor is working" ]; then
    whiptail --title "Tor - INFO (scroll down!)" --textbox --scrolltext text/finish-ok-text $MENU_HEIGHT_25 $MENU_WIDTH
  else
    whiptail --title "Tor - INFO (scroll down!)" --textbox --scrolltext text/finish-fail-text $MENU_HEIGHT_25 $MENU_WIDTH
  fi
}

# online_check()
# Syntax online_check <source_script>
# Used predefined variables: RED, NOCOLOR, MENU_HEIGHT_15 MENU_WIDTH
# This function checks the internet connection and exits to <source_script> if none.
online_check()
{
  clear
  echo -e "${RED}[+] Checking internet connectivity - please wait...${NOCOLOR}"
  JUMPTO=$1
  clear
  OCHECK=$(curl -m 5 -s $CHECK_URL1)
  if [ $? -gt 0 ]; then
    whiptail --title "Tor - INFO" --msgbox "\n\nIt seems that your Tor is not properly connected to the internet! For this operation, TorBox has to properly connected with the internet!" $MENU_HEIGHT_15 $MENU_WIDTH
    trap "bash $JUMPTO; exit 0" EXIT
    exit 0
  fi
}

# erase_logs()
# Used predefined variables: RED, NOCOLOR
# This function flushes all LOG-files in /var/log and ~/.bash_history.
erase_logs()
{
  echo -e "${RED}[+] Erasing ALL LOG-files...${NOCOLOR}"
  for logs in `sudo find /var/log -type f`; do
  	echo -e "${RED}[+]${NOCOLOR} Erasing $logs"
  	sudo rm $logs
  	sleep 1
  done
  echo -e "${RED}[+]${NOCOLOR} Erasing .bash_history"
  (sudo rm ../.bash_history) 2> /dev/null
  history -c
}

# restarting_tor(<source script>)
# This function reload tor by default or forces to restart
# Nyxnor: Why this name restart when it reload by default? I dont know a better name.
restarting_tor()
{
  clear
  SOURCE_SCRIPT=$1
  ACTION=$2
  set_owner_permission
  if [ "${ACTION}" == "force" ]; then
    echo -e "${RED}[+] Restarting tor!${NOCOLOR}"
    sudo systemctl restart tor@default &
    echo -e "${RED}[+] DONE! Checking progress - please be patient!${NOCOLOR}"
    echo -e "    Starting Anonymizing overlay network for TCP..."
    echo -e "    At the end, you should see \"Bootstrapped 100% (done): Done\"."
  elif [ "${ACTION}" == "" ]; then
    echo -e "${RED}[+] Reloading tor!${NOCOLOR}"
    sudo pkill -sighup tor &
    echo -e "${RED}[+] DONE! Checking progress - please be patient!${NOCOLOR}"
    echo -e "   Received reload signal (hup). Reloading config and resetting internal state!"
  fi
  echo -e "    You can leave the progress report with CTRL-C."
  trap "bash $SOURCE_SCRIPT; exit 0" SIGINT
  sudo journalctl -fu tor@default
}

# connecting_to_VPN()
# Used predefined variables: RED, WHITE, NOCOLOR, MENU_HEIGHT_15, MENU_WIDTH_REDUX
# This function connects the TorBox to a VPN
connecting_to_VPN()
{
  clear
  readarray -t ovpnlist < <(ls -1X ../openvpn/*.ovpn | sed "s/..\/openvpn\///" | sed "s/.ovpn//")
  if [ "${ovpnlist[0]}" = "" ] ; then
    whiptail --title "TorBox - INFO" --textbox text/no_tun0-text $MENU_HEIGHT_15 $MENU_WIDTH_REDUX
    trap "bash 96torMainMenu.sh; exit 0" EXIT
    exit 0
  fi
  ovpnlist_anzahl=${#ovpnlist[*]}
  anzahl_loops=$(( $ovpnlist_anzahl - 1 ))
  menu_content=""
  for (( i=0; i<=$anzahl_loops; i++ ))
  do
    menu_item=$(( $i + 1 ))
    menu_content="$menu_content${RED}$menu_item${NOCOLOR} - ${ovpnlist[$i]}\n"
  done
  clear
  echo -e "${WHITE}Choose an OpenVPN configuration:${NOCOLOR}"
  echo ""
  echo -e "$menu_content"
  echo ""
  read -r -p $'\e[1;37mWhich OpenVPN configuration (number) would you like to use? -> \e[0m'
  echo
  if [[ $REPLY =~ ^[1234567890]$ ]] ; then
    CHOICE_OVPN=$(( $REPLY - 1 ))
    clear
    echo -e "${RED}[+] Connecting OpenVPN server...${NOCOLOR}"
    echo ""
    ovpn_file=../openvpn/${ovpnlist[$CHOICE_OVPN]}.ovpn
    sudo sed -i "s/^dev tun.*/dev tun0/" ${ovpn_file}
    sudo openvpn --daemon --config ../openvpn/${ovpnlist[$CHOICE_OVPN]}.ovpn
    echo ""
    echo -e "${RED}[+] Please wait, we need 15 second to configure the interface...${NOCOLOR}"
    sleep 15
  else
    sudo /sbin/iptables-restore < /etc/iptables.ipv4.nat
    trap "bash 96torMainMenu.sh; exit 0" EXIT
    exit 0
  fi
}


# number_of_bridges()
# How many OBFS4 bridges do we have? readarray reads into an array beginning with index 0
# Following variables can be used:
# $configured_bridges_deactivated -> An array with all deactivated OBFS4 bridges
# $configured_bridges_activated -> An array with all activated OBFS4 bridges
# $number_configured_bridges_deactivated -> Number of deactivated bridges
# $number_configured_bridges_activated -> Number of activated bridges
# $number_configured_bridges_total -> Total number of bridges
number_of_bridges()
{
  readarray -t configured_bridges_deactivated < <(grep "^#Bridge obfs4 " ${TORRC})
  readarray -t configured_bridges_activated < <(grep "^Bridge obfs4 " ${TORRC})
  if [ ${#configured_bridges_deactivated[0]} = 0 ]; then
    number_configured_bridges_deactivated=0
  else
    number_configured_bridges_deactivated=${#configured_bridges_deactivated[*]}
  fi
  if [ ${#configured_bridges_activated[0]} = 0 ]; then
    number_configured_bridges_activated=0
  else
    number_configured_bridges_activated=${#configured_bridges_activated[*]}
  fi
  number_configured_bridges_total=$(( $number_configured_bridges_deactivated + $number_configured_bridges_activated ))
}

bridge_mode()
{
  # Is the bridge mode already turned on?
  MODE_BRIDGES=$(grep "^UseBridges" ${TORRC})

  # OBFS4STRING represents the status of the Meek-Azure bridging mode
  MODE_OBFS4=$(grep -o "^Bridge obfs4 " ${TORRC} | head -1)
  if [ "$MODE_OBFS4" = "Bridge obfs4 " ]; then
      OBFS4STRING="ON!"
      OBFS4STRINGb="Disable"
      BRIDGESTRING="/ OBFS4 ON!"
  else
      OBFS4STRING="OFF"
      OBFS4STRINGb="Enable"
  fi

  # MEEKSTRING represents the status of the Meek-Azure bridging mode
  MODE_MEEK=$(grep -o "^Bridge meek_lite " ${TORRC} | head -1)
  if [ "$MODE_MEEK" = "Bridge meek_lite " ]; then
      MEEKSTRING="ON!"
      MEEKSTRINGb="Disable"
      BRIDGESTRING="/ MEEK-AZURE ON!"
  else
      MEEKSTRING="OFF"
      MEEKSTRINGb="Enable"
  fi

  # SNOWSTRING represents the status of the Snowflake bridging mode
  MODE_SNOW=$(grep -o "^Bridge snowflake " ${TORRC} | head -1)
  if [ "$MODE_SNOW" = "Bridge snowflake " ]; then
      SNOWSTRING="ON!"
      SNOWSTRINGb="Disable"
      BRIDGESTRING="/ SNOWFLAKE ON!"
  else
      SNOWSTRING="OFF"
      SNOWSTRINGb="Enable"
  fi

  if [ "${BRIDGESTRING}" = "" ]; then
    BRIDGESTRING="/ Bridge mode OFF!"
    BRIDGESTRINGb="Enable"
  else
    BRIDGESTRINGb="Disable"
  fi
}


# list_all_obfs4_bridges()
# List all OBFS4 bridges
list_all_obfs4_bridges()
{
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
    trap "bash 96torBridgesMenu; exit 0" SIGINT
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
    trap "bash 96torBridgesMenu; exit 0" SIGINT
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
}

activate_default_lines_bridges(){
  sudo sed -i "s/^#UseBridges/UseBridges/g" ${TORRC}
  sudo sed -i "s/^#UpdateBridgesFromAuthority/UpdateBridgesFromAuthority/g" ${TORRC}
}

deactivate_default_lines_bridges(){
  sudo sed -i "s/^UseBridges/#UseBridges/g" ${TORRC}
  sudo sed -i "s/^UpdateBridgesFromAuthority/#UpdateBridgesFromAuthority/g" ${TORRC}
}

deactivate_meek_bridges(){
  deactivate_default_lines_bridges
  sudo sed -i "s/^ClientTransportPlugin meek_lite,obfs4/#ClientTransportPlugin meek_lite,obfs4/g" ${TORRC}
  sudo sed -i "s/^Bridge meek_lite /#Bridge meek_lite /g" ${TORRC}
}

deactivate_snowflake_bridges(){
  deactivate_default_lines_bridges
  sudo sed -i "s/^ClientTransportPlugin snowflake/#ClientTransportPlugin snowflake/g" ${TORRC}
  sudo sed -i "s/^Bridge snowflake /#Bridge snowflake /g" ${TORRC}
}

# deactivate_obfs4_bridges()
# Dectivates OBFS4 if the number of activated obfs4 bridge entries in torrc is 0
deactivate_obfs4_bridges(){
  deactivate_default_lines_bridges
  sudo sed -i "s/^ClientTransportPlugin meek_lite,obfs4/#ClientTransportPlugin meek_lite,obfs4/g" ${TORRC}
  sudo sed -i "s/^Bridge obfs4 /#Bridge obfs4 /g" ${TORRC}
}

# activate_obfs4_bridges(<source script>)
# Activates OBFS4 if the number of activated obfs4 bridge entries in torrc is >0
activate_obfs4_bridges()
{
  SOURCE_SCRIPT=$1
  number_of_bridges
  if [ $number_configured_bridges_activated -gt 0 ]; then
    deactivating_bridge_relay
    deactivate_meek_bridges 1
    deactivate_snowflake_bridges 1
    sudo sed -i "s/^#ClientTransportPlugin meek_lite,obfs4/ClientTransportPlugin meek_lite,obfs4/g" ${TORRC}
  else
    deactivate_obfs4_bridges
  fi
  INPUT=$(cat text/reload-tor-bridges-text)
  if (whiptail --title "Tor - INFO" --defaultno --no-button "NO - DON'T RELOAD" --yes-button "YES - RELOAD" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
    restarting_tor $SOURCE_SCRIPT
  else
    deactivate_obfs4_bridges
  fi
}

# activate_meek_bridges(<source script>)
activate_meek_bridges()
{
  SOURCE_SCRIPT=$1
  deactivating_bridge_relay
  deactivate_obfs4_bridges 1
  deactivate_snowflake_bridges 1
  sudo sed -i "s/^#ClientTransportPlugin meek_lite,obfs4/ClientTransportPlugin meek_lite,obfs4/g" ${TORRC}
  sudo sed -i "s/^#Bridge meek_lite /Bridge meek_lite /g" ${TORRC}
  INPUT=$(cat text/reload-tor-bridges-text)
  if (whiptail --title "TorBox - INFO" --defaultno --no-button "NO - DON'T RELOAD" --yes-button "YES - RELOAD" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
    restarting_tor $SOURCE_SCRIPT
  else
    deactivate_meek_bridges
  fi
}

# activate_snowflake_bridges(<source script>)
activate_snowflake_bridges(){
  SOURCE_SCRIPT=$1
  deactivating_bridge_relay
  deactivate_obfs4_bridges 1
  deactivate_meek_bridges 1
  sudo sed -i "s/^#ClientTransportPlugin snowflake/ClientTransportPlugin snowflake/g" ${TORRC}
  sudo sed -i "s/^#Bridge snowflake /Bridge snowflake /g" ${TORRC}
  INPUT=$(cat text/reload-tor-bridges-text)
  if (whiptail --title "Tor - INFO" --defaultno --no-button "NO - DON'T RELOAD" --yes-button "YES - RELOAD" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
    restarting_tor $SOURCE_SCRIPT
  else
    deactivate_snowflake_bridges
  fi
}

deactivate_all_bridges(){
  SOURCE_SCRIPT=$1
  DELETE=$2
  deactivate_obfs4_bridges
  deactivate_meek_bridges
  deactivate_snowflake_bridges
  if [ ${DELETE} == "delete" ]; then
    sudo sed -i "/^#Bridge obfs4 /d" ${TORRC}
  fi
  INPUT=$(cat text/reload-tor-bridges-text)
  if (whiptail --title "Tor - INFO" --defaultno --no-button "NO - DON'T RELOAD" --yes-button "YES - RELOAD" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
    restarting_tor $SOURCE_SCRIPT
  fi
}

# insert_canonical_bridges_to_torrc <TORRC>
insert_canonical_bridges_to_torrc(){

  TORRC_SOURCE="${1}"

  # remove_all_bridges
  sudo sed -i "/^UseBridges/d" ${TORRC_SOURCE}
  sudo sed -i "/^#UseBridges/d" ${TORRC_SOURCE}
  sudo sed -i "/^UpdateBridgesFromAuthority/d" ${TORRC_SOURCE}
  sudo sed -i "/^#UpdateBridgesFromAuthority/d" ${TORRC_SOURCE}
  sudo sed -i "/^ClientTransportPlugin meek_lite,obfs4/d" ${TORRC_SOURCE}
  sudo sed -i "/^#ClientTransportPlugin meek_lite,obfs4/d" ${TORRC_SOURCE}
  sudo sed -i "/^ClientTransportPlugin snowflake /d" ${TORRC_SOURCE}
  sudo sed -i "/^#ClientTransportPlugin snowflake /d" ${TORRC_SOURCE}
  sudo sed -i "/^Bridge obfs4 /d" ${TORRC_SOURCE}
  sudo sed -i "/^#Bridge obfs4 /d" ${TORRC_SOURCE}
  sudo sed -i "/^Bridge meek_lite /d" ${TORRC_SOURCE}
  sudo sed -i "/^#Bridge meek_lite /d" ${TORRC_SOURCE}
  sudo sed -i "/^Bridge snowflake /d" ${TORRC_SOURCE}
  sudo sed -i "/^#Bridge snowflake /d" ${TORRC_SOURCE}

  # insert_canonical_bridges_to_torrc
  sudo cat ${TORRC_SOURCE} ${TORRC} > ${TORRC_SOURCE}.tmp
  sudo mv ${TORRC_SOURCE}.tmp ${TORRC_SOURCE}

}
