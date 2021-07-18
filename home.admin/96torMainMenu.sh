#!/bin/bash

# Portions of this file was sourced from TorBox, an easy to use anonymizing router based on Raspberry Pi.
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
# This file displays the main menu and executes all relevant scripts.
#
# SYNTAX
# ./96torMainMenu.sh
#
#
###### SET VARIABLES ######

SOURCE_SCRIPT="96torMainMenu.sh"

distribution=$(lsb_release -sc)

debianSourcesOnionUpdate="http://2s4yqjx5ul6okpp3f2gaunr2syex5jgbfpfvhxxbbjwnrsvbk5v3qbid.onion/"
debianSourcesOnionSecurity="http://5ajw6aqf3ep7sijnscdzw77t7xq4xjpsy335yb2wiwgouo7yfxtjlmid.onion/"
torSourcesOnionUpdate="http://apow7mjfryruh65chtdydfmqfpj5btws7nbocgtaovhvezgccyjazpqd.onion/"

debianSourcesPlainUpdate="https://deb.debian.org/"
debianSourcesPlainSecurity="https://deb.debian.org/"
torSourcesPlainUpdate="https://deb.torproject.org/"

##############################
######## FUNCTIONS ###########

# include lib
. /home/admin/_tor.commands.sh

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

# This function tests from where the Internet is coming
check_interface_with_internet()
{
echo -e "${RED}[+] Checking connectivity to the Internet - please wait...${NOCOLOR}"
IINTERFACE=""
IINTERFACE=$(sudo timeout 5 sudo route | grep -m 1 tun0 | tr -s " " | cut -d " " -f1)
if [ "$IINTERFACE" != "" ] ; then
  VPN_STATUS="VPN is up"
  IIPTABLES=""
  IIPTABLES=$(sudo iptables -t nat -L -v | grep MASQUERADE | grep tun0)
else
  VPN_STATUS=""
fi
if [ "$IINTERFACE" = "0.0.0.0" ] && [ "$IIPTABLES" != "" ] ; then FLASH_TUN0="<--" ; else
  IINTERFACE=$(sudo timeout 5 sudo route | grep -m 1 default | tr -s " " | cut -d " " -f8)
  if [ "$IINTERFACE" = "eth0" ] ; then FLASH_ETH0="<--" ; fi
  if [ "$IINTERFACE" = "eth1" ] ; then FLASH_ETH1="<--" ; fi
  if [ "$IINTERFACE" = "wlan0" ] ; then FLASH_WLAN0="<--" ; fi
  if [ "$IINTERFACE" = "wlan1" ] ; then FLASH_WLAN1="<--" ; fi
  if [ "$IINTERFACE" = "usb0" ] ; then FLASH_USB0="<--" ; fi
  if [ "$IINTERFACE" = "ppp0" ] ; then FLASH_USB0="<--" ; fi
fi
}

######## PREPARATIONS ########
clear
read_config
#check_interface_with_internet
#check_tor

# Connected to a VPN?
tun0up=$(ip link | grep tun0)
if [ "$tun0up" = "" ]; then
  VPNSTRING="OFF"
  VPNSTRINGb="Enable"
else
  VPNSTRING="ON"
  VPNSTRINGb="Disable"
fi

if [ "$TOR_STATUS" != "" ] && [ "$VPN_STATUS" != "" ] ; then TOR_STATUS="VPN is up & Tor working"
elif [ "$TOR_STATUS" != "" ] && [ "$VPN_STATUS" = "" ] ; then TOR_STATUS="         Tor is working"
elif [ "$TOR_STATUS" = "" ] && [ "$VPN_STATUS" != "" ] ; then TOR_STATUS="              VPN is up"
else TOR_STATUS=""
fi

# Is the Countermeasure against a disconnection when idle feature active?
if ps -ax | grep "[p]ing -q $PING_SERVER" ; then
  PING="ON"
  PINGb="Disable"
else
  PING="OFF"
  PINGb="Enable"
fi

vanguardsStatus=$(sudo systemctl is-active vanguards@default.service)
if [ "${vanguardsStatus}" == "active" ]; then
  VANGUARDSSTRING="ON!"
  VANGUARDSSTRINGb="Disable"
else
  VANGUARDSSTRING="OFF"
  VANGUARDSSTRINGb="Enable"
fi

if ! grep -Eq "^sshTor=" ${CONF}; then echo "sshTor=off" >> ${CONF}; fi
if [ ${#sshTor} -eq 0 ]; then sshTor="off"; fi
if [ "${sshTor}" == "on" ]; then
  SSHTORSTRINGb="Disable"
else
  SSHTORSTRINGb="Enable"
fi

torVersion=$(dpkg -s tor | grep "Version:" | cut -c10-)

HEIGHT=30 # add 6 to CHOICE_HEIGHT + MENU lines
# BASIC MENU INFO
WIDTH=80
BACKTITLE="RaspiBlitz ${BRIDGESTRING}"
TITLE="Tor - v${torVersion}"
MENU=""    # adds lines to HEIGHT
OPTIONS=() # adds lines to HEIGHT + CHOICE_HEIGHT

OPTIONS+=(============== "=[Checks]==========================================================")
OPTIONS+=(CREDENTIALS "See services credentials (address, key, QR code)")
OPTIONS+=(NYX "Terminal status monitor for tor")
OPTIONS+=(LOGS "Show the logs")
OPTIONS+=(TORRC "Edit configuration file (torrc)")
OPTIONS+=(RELOAD "Reload config and reset internal state")
OPTIONS+=(RESTART "Restart tor@default.service")
OPTIONS+=(SSH_OVER_TOR ${SSHTORSTRINGb}" SSH over Tor")
OPTIONS+=(============== "=[Countermeasure]==================================================")
OPTIONS+=(AUTH "Request client authentication for onion service")
OPTIONS+=(RENEW_ADDRESS "Request new onion address for specific onion service")
OPTIONS+=(VANGUARDS ${VANGUARDSSTRINGb}" protection against server location deanonymization")
OPTIONS+=(BRIDGES ${BRIDGESTRINGb}" Tor bridges with pluggable transport")
OPTIONS+=(SOURCES "Request APT over Tor and update packages")
OPTIONS+=(CHANGE_CIRCUIT "Request new circuit (signal NEWNYM)")
OPTIONS+=(CHANGE_GUARD "Delete all circuits and force change of the entry node")
OPTIONS+=(BYPASS_IDLE ${PINGb}" countermeaseure against idle feature")
OPTIONS+=(OVER_VPN ${VPNSTRINGb}" Tor over VPN")
OPTIONS+=(============== "=[Informational]===================================================")
OPTIONS+=(VERSION "Tor related packages version")
OPTIONS+=(ONION "Onion routing privacy and security benefits")
OPTIONS+=(DISCLAIMERS "What Tor does not provide?")
OPTIONS+=(SUPPORT_TPO "Support the Tor Project")
OPTIONS+=(SUPPORT_TORBOX "Support TorBox")

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

  # Checks
  CREDENTIALS)
    trap "bash 96torMainMenu.sh; exit 0" SIGINT
    bash 96torCredentialsMenu.sh
  ;;

  NYX)
    trap "bash 96torMainMenu.sh; exit 0" SIGINT
    sudo -u ${OWNER_TOR_DATA_DIR} nyx
  ;;


  LOGS)
      trap "bash 96torMainMenu.sh; exit 0" SIGINT
      clear
      sudo journalctl -n 40 -fu tor@default
  ;;

  TORRC)
    set_owner_permission
    if /home/admin/config.scripts/blitz.setconf.sh ${TORRC} ${OWNER_TOR_DATA_DIR}; then
      whiptail \
        --title "Restart" --yes-button "Restart" --no-button "Not now" \
        --yesno "To apply the new settings Tor needs to reload.
        Do you want to restart Tor now?" 10 55
      if [ $? -eq 0 ]; then
        restarting_tor ${SOURCE_SCRIPT}
      else
        echo "# Continue without restarting."
      fi
    else
      echo "# No change made"
    fi
    ;;

  RELOAD)
    INPUT=$(cat text/reload-tor-text)
    if (whiptail --title "TorBox - INFO" --defaultno --no-button "NO - DON'T RELOAD" --yes-button "YES - RELOAD" --yesno "$INPUT" $MENU_HEIGHT_15 $MENU_WIDTH); then
      restarting_tor ${SOURCE_SCRIPT}
    fi
  ;;

  RESTART)
    INPUT=$(cat text/restart-tor-text)
    if (whiptail --title "TorBox - INFO" --defaultno --no-button "NO - DON'T (RE)START" --yes-button "YES - (RE)START" --yesno "$INPUT" $MENU_HEIGHT_15 $MENU_WIDTH); then
      restarting_tor ${SOURCE_SCRIPT} force
    fi
  ;;

  SSH_OVER_TOR)
    if [ "${sshTor}" == "off" ] ; then
      INPUT=$(cat text/activate-ssh-over-tor-text)
      if (whiptail --title "Tor - INFO" --defaultno --no-button "NO" --yes-button "YES" --yesno "$INPUT" $MENU_HEIGHT_20 $MENU_WIDTH_REDUX); then
        ${ONION_SERVICE_SCRIPT} on ssh 22 22
        sudo sed -i "s/^sshTor=.*/sshTor=on/g" ${CONF}
      fi
    else
      INPUT=$(cat text/deactivate-ssh-over-tor-text)
      if (whiptail --title "Tor - INFO" --defaultno --no-button "NO" --yes-button "YES" --yesno "$INPUT" $MENU_HEIGHT_20 $MENU_WIDTH_REDUX  ); then
        ${ONION_SERVICE_SCRIPT} off ssh
        sudo sed -i "s/^sshTor=.*/sshTor=off/g" ${CONF}
      fi
    fi
  ;;

  # Counter measure
  CHANGE_CIRCUIT)
    sudo -u ${OWNER_TOR_DATA_DIR} tor-prompt --run 'SIGNAL NEWNYM' -i 9051
    whiptail --msgbox "Done !!! Using new circuit" 10 30
    #trap "bash 96torMainMenu.sh; exit 0" SIGINT
    #sudo bash tor.newnym.sh
  ;;

  CHANGE_GUARD)
    INPUT=$(cat text/tor-reset-text)
    if (whiptail --title "Tor - INFO" --defaultno  --yesno "$INPUT" 18 $MENU_WIDTH); then
      clear
      echo -e "${RED}[+] Stopping Tor...${NOCOLOR}"
      sudo systemctl stop tor@default
      sleep 2
      echo -e "${RED}[+] Deleting all circuits and forcing a change of the permanent entry node${NOCOLOR}"
      (sudo rm -r ${DATA_DIR}/cached-certs) 2> /dev/null
      (sudo rm -r ${DATA_DIR}/cached-consensus) 2> /dev/null
      (sudo rm -r ${DATA_DIR}/cached-descriptors) 2> /dev/null
      (sudo rm -r ${DATA_DIR}/cached-descriptors.new) 2> /dev/null
      (sudo rm -r ${DATA_DIR}/cached-microdesc-consensus) 2> /dev/null
      (sudo rm -r ${DATA_DIR}/cached-microdescs) 2> /dev/null
      (sudo rm -r ${DATA_DIR}/cached-microdescs.new) 2> /dev/null
      (sudo rm -r ${DATA_DIR}/diff-cache) 2> /dev/null
      (sudo rm -r ${DATA_DIR}/lock) 2> /dev/null
      (sudo rm -r ${DATA_DIR}/state) 2> /dev/null
      sleep 2
      echo -e "${RED}[+] Resetting Tor statistics...${NOCOLOR}"
      sudo touch ${DATA_DIR}/log/tor/notice.log
      sudo chown ${OWNER_TOR_DATA_DIR} ${DATA_DIR}/tor/notice.log
      echo -e "${RED}[+] Done!${NOCOLOR}"
      sleep 4
      sudo systemctl restart tor@default
    fi
  ;;

  SOURCES)

    isDebOnion=$(cat /etc/apt/sources.list.d/deb.list | grep "onion" -c)
    isTorOnion=$(cat /etc/apt/sources.list.d/tor.list | grep "onion" -c)
    if [ ${isDebOnion} -gt 0 ]; then
      debSourcesString="Onion"
    else
      debSourcesString="Plain"
    fi
    if [ ${isTorOnion} -gt 0 ]; then
      torSourcesString="Onion"
    else
      torSourcesString="Plain"
    fi

    CHOICE=$(whiptail --menu "Current sources: ( Deb=${debSourcesString} | Tor=${torSourcesString} )" 18 60 6 \
            "ONION_tor" "Tor sources over tor" \
            "ONION_debian" "Debian sources over tor" \
            "ONION_debian_tor" "Debian and Tor sources over tor" \
            "PLAIN_tor" "Tor sources over plainnet" \
            "PLAIN_debian" "Debian sources over plainnet" \
            "PLAIN_debian_tor" "Debian and Tor sources over plainnet" \
            3>&1 1>&2 2>&3)

    if [ "$CHOICE" == "ONION_tor" ]||[ "$CHOICE" == "ONION_debian_tor" ]; then
      sudo rm -f /etc/apt/sources.list.d/tor.list
      sudo tee /etc/apt/sources.list.d/tor.list >/dev/null <<EOF
deb [arch=arm64] tor+${torSourcesOnionUpdate}torproject.org ${distribution} main
deb-src [arch=arm64] tor+${torSourcesOnionUpdate}torproject.org ${distribution} main
EOF
    fi

    if [ "$CHOICE" == "ONION_debian" ]||[ "$CHOICE" == "ONION_debian_tor" ]; then
      sudo tee /etc/apt/sources.list.d/deb.list >/dev/null <<EOF
deb [arch=arm64] tor+${debianSourcesOnionUpdate}debian ${distribution} main
deb [arch=arm64] tor+${debianSourcesOnionUpdate}debian ${distribution}-updates main
deb [arch=arm64] tor+${debianSourcesOnionSecurity}debian-security/ ${distribution}-security main
#deb [arch=arm64] tor+${debianSourcesOnionUpdate}debian ${distribution}-backports main
EOF
    fi

    if [ "$CHOICE" == "PLAIN_tor" ] || [ "$CHOICE" == "PLAIN_debian_tor" ]; then
      sudo tee /etc/apt/sources.list.d/tor.list >/dev/null <<EOF
deb [arch=arm64] ${torSourcesPlainUpdate}torproject.org ${distribution} main
deb-src [arch=arm64] ${torSourcesPlainUpdate}torproject.org ${distribution} main
EOF
    fi

    if [ "$CHOICE" == "PLAIN_debian" ]||[ "$CHOICE" == "PLAIN_debian_tor" ]; then
      sudo tee /etc/apt/sources.list.d/deb.list >/dev/null <<EOF
deb [arch=arm64] ${debianSourcesPlainUpdate}debian ${distribution} main
deb [arch=arm64] ${debianSourcesPlainUpdate}debian ${distribution}-updates main
deb [arch=arm64] ${debianSourcesPlainSecurity}debian-security/ ${distribution}-security main
#deb [arch=arm64] ${debianSourcesPlainUpdate}debian ${distribution}-backports main
EOF
    fi

    if [ "$CHOICE" != "" ]; then
      sudo apt update -y
      echo "hi"
      if [ "$CHOICE" == "onion" ]; then
        sudo apt install -y apt-transport-tor
        sudo apt update -y
        echo "hey"
      fi
      sudo apt install -y tor torsocks nyx obfs4proxy
    fi
  ;;

  BRIDGES)
    bash 96torBridgesMenu.sh
  ;;

  OVER_VPN)
    if [ "$tun0up" = "" ] ; then
      INPUT=$(cat text/connecting-VPN-text)
      if (whiptail --title "Tor - INFO" --defaultno --no-button "NO" --yes-button "YES" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
        connecting_to_VPN
        sudo /sbin/iptables-restore < /etc/iptables.ipv4.nat
        echo ""
        echo -e "${RED}[+] It may take some time for Tor to reconnect.${NOCOLOR}"
        sleep 5
        tun0up=$(ip link | grep tun0)
      fi
    else
      INPUT=$(cat text/disconnecting-VPN-text)
      if (whiptail --title "Tor - INFO" --defaultno --no-button "NO" --yes-button "YES" --yesno "$INPUT" $MENU_HEIGHT_20 $MENU_WIDTH); then
        clear
        echo -e "${RED}[+] Disonnecting OpenVPN server...${NOCOLOR}"
        sudo killall openvpn
        echo -e "${RED}[+] Please wait, we need 15 second to configure the interface...${NOCOLOR}"
        sleep 15
        echo ""
        echo -e "${RED}[+] It may take some time for Tor to reconnect.${NOCOLOR}"
        sleep 5
        tun0up=$(ip link | grep tun0)
      fi
    fi
  ;;

  BYPASS_IDLE)
    if [ "$PING" = "OFF" ] || [ "$PING" = "" ]; then
      whiptail --title "Tor - INFO" --textbox text/ping-text-on $MENU_HEIGHT_25 $MENU_WIDTH
      ping -q $PING_SERVER >/dev/null &
      #Alternative option: screen -dm ping debian.org
      echo -e "${RED}[+] Countermeasure against a disconnect when idle feature activated!${NOCOLOR}"
      sleep 2
    fi
    if [ "$PING" = "ON" ]; then
      if (whiptail --title "Tor - INFO" --defaultno --no-button "NO" --yes-button "YES" --yesno "Would you deactivate the countermeasure against a disconnect when idle feature?" $MENU_HEIGHT_15 $MENU_WIDTH_REDUX); then
        sudo killall ping
        echo -e "${RED}[+] Countermeasure against a disconnect when idle feature deactivated!${NOCOLOR}"
        sleep 2
      fi
    fi
  ;;

  VANGUARDS)
    vanguardsStatus=$(sudo systemctl is-active vanguards@default.service)
    INPUT=$(cat text/vanguards-explanation-text)
    if (whiptail --title "Tor - INFO" --defaultno --no-button "NO" --yes-button "YES" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
      CHOICE=$(whiptail --menu "Vanguards are: ${vanguardsStatus}" 16 80 6 \
              "INSTALL" "Install Vanguards" \
              "RESTART" "Restart the service for the default instance" \
              "STOP" "Stop the service for the default instance" \
              "REMOVE" "Remove/Uninstall Vanguards" \
              3>&1 1>&2 2>&3)

      if [ "$CHOICE" == " LOGS" ]; then
        clear
        trap "bash 96torMainMenu.sh; exit 0" EXIT
        sudo journalctl -n 10 -fu vanguards@default.service
      elif [ "$CHOICE" == "INSTALL" ]; then
        clear
        ${ONION_SERVICE_SCRIPT} vanguards install
        ${ONION_SERVICE_SCRIPT} vanguards on 9051
      elif [ "$CHOICE" == "RESTART" ]; then
        clear
        sudo systemctl restart vanguards@default.service
        vanguardsStatus=$(sudo systemctl is-active vanguards@default.service)
        sleep 3
        whiptail --msgbox "Vanguards are now: ${vanguardsStatus}" 10 35
      elif [ "$CHOICE" == "STOP" ]; then
        clear
        sudo systemctl stop vanguards@default.service
        vanguardsStatus=$(sudo systemctl is-active vanguards@default.service)
        sleep 3
        whiptail --msgbox "Vanguards are now: ${vanguardsStatus}" 10 35
      elif [ "$CHOICE" == "REMOVE" ]; then
        ${ONION_SERVICE_SCRIPT} vanguards off
      fi
    fi
  ;;

  AUTH)
    INPUT=$(cat text/onion-auth-text)
    if (whiptail --title "Tor - INFO" --defaultno --no-button "NO" --yes-button "YES" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
      bash 96torAuthMenu.sh
    fi
  ;;

  RENEW_ADDRESS)
    INPUT=$(cat text/renew-address-text)
    if (whiptail --title "Tor - INFO" --defaultno --no-button "NO" --yes-button "YES" --yesno "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH); then
      bash 96torRenewAddressMenu.sh
    fi

  ;;

  # Informational
  VERSION)
    TorV=$(dpkg -s tor | grep "Version:" | cut -c10-)
    TorD=$(dpkg -s tor | grep "Description:" | cut -c14-)
    TorsocksV=$(dpkg -s torsocks | grep "Version:" | cut -c10-)
    TorsocksD=$(dpkg -s torsocks | grep "Description:" | cut -c14-)
    NyxV=$(dpkg -s nyx | grep "Version:" | cut -c10-)
    NyxD=$(dpkg -s nyx | grep "Description:" | cut -c14-)
    Obfs4proxyV=$(dpkg -s obfs4proxy | grep "Version:" | cut -c10-)
    Obfs4proxyD=$(dpkg -s obfs4proxy | grep "Description:" | cut -c14-)
    TPOKeyringV=$(dpkg -s deb.torproject.org-keyring | grep "Version:" | cut -c10-)
    TPOKeyringD=$(dpkg -s deb.torproject.org-keyring | grep "Description:" | cut -c14-)

    dialog --title "Tor packages: version - description" --msgbox "\n\
Tor: ${TorV} - ${TorD} \n
\n
Torsocks: ${TorsocksV} - ${TorsocksD} \n
\n
Nyx: ${NyxV} - ${NyxD} \n
\n
Obfs4proxy: ${Obfs4proxyV} - ${Obfs4proxyD} \n
\n
TPOKeyring: ${TPOKeyringV} - ${TPOKeyringD} \n
\n\n
How to upgrade Tor packages? \n
All Tor packages can be upgrade via 'Menu > Update > Tor'
" 20 84
  ;;

  ONION)
    INPUT=$(cat text/onion-explanation-tor-text)
    whiptail --title "Tor - INFO" --msgbox "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH
  ;;

  DISCLAIMERS)
    INPUT=$(cat text/disclaimer-tor-text)
    whiptail --title "Tor - INFO (scroll down)" --msgbox --scrolltext "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH
  ;;

  # Defend the open internet
  SUPPORT_TPO)
    INPUT=$(cat text/support-tor-text)
    whiptail --title "Tor - INFO" --msgbox "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH
  ;;

  SUPPORT_TORBOX)
    INPUT=$(cat text/support-torbox-text)
    whiptail --title "Tor - INFO" --msgbox "$INPUT" $MENU_HEIGHT_25 $MENU_WIDTH
  ;;

  *)
    exit 0

esac

bash ${SOURCE_SCRIPT}
