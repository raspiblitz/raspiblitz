#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# BASIC MENU INFO
HEIGHT=12 # add 6 to CHOICE_HEIGHT + MENU lines
WIDTH=64
CHOICE_HEIGHT=6 # 1 line / OPTIONS
BACKTITLE="RaspiBlitz"
TITLE="System Options"
MENU=""    # adds lines to HEIGHT
OPTIONS=() # adds lines to HEIGHt + CHOICE_HEIGHT

OPTIONS+=(${network}LOG "Monitor the debug.log")
OPTIONS+=(${network}CONF "Edit the bitcoin.conf")
OPTIONS+=(LNDLOG "Monitor the lnd.log")
OPTIONS+=(LNDCONF "Edit the lnd.conf")

if [ "${runBehindTor}" == "on" ]; then
  OPTIONS+=(TORLOG "Monitor the Tor Service with Nyx")
  OPTIONS+=(TORRC "Edit the Tor Configuration")
    HEIGHT=$((HEIGHT+2))
    CHOICE_HEIGHT=$((CHOICE_HEIGHT+2))
fi
OPTIONS+=(CUSTOMLOG "Monitor a custom service")
OPTIONS+=(CUSTOMRESTART "Restart a custom service")
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
  ${network}LOG)
    clear
    echo
    echo "Will follow the /mnt/hdd/${network}/debug.log"
    echo "running: 'sudo tail -n 30 -f /mnt/hdd/${network}/debug.log'"
    echo
    echo "Press ENTER to continue"
    echo "use CTRL+C any time to abort .. then use command 'raspiblitz' to return to menu"
    read key
    sudo tail -n 30 -f /mnt/hdd/${network}/debug.log;;
  ${network}CONF)
    if /home/admin/config.scripts/blitz.setconf.sh "/mnt/hdd/${network}/${network}.conf" "root"
    then
      whiptail \
        --title "Restart" --yes-button "Restart" --no-button "Not now" \
        --yesno "To apply the new settings ${network}d needs to restart.
        Do you want to restart ${network}d now?" 10 55
      if [ $? -eq 0 ]; then
        echo "# Restarting ${network}d"
        sudo systemctl restart ${network}d
      else
        echo "# Continue without restarting."
      fi
    else
      echo "# No change made"
    fi;;
  LNDLOG)
    clear
    echo
    echo "Will follow the /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log"
    echo "running 'sudo tail -n 30 -f /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log'"
    echo
    echo "Press ENTER to continue"
    echo "use CTRL+C any time to abort .. then use command 'raspiblitz' to return to menu"
    read key
    sudo tail -n 30 -f /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log;;
  LNDCONF)
    if /home/admin/config.scripts/blitz.setconf.sh "/mnt/hdd/lnd/lnd.conf" "root"
    then
      whiptail \
        --title "Restart" --yes-button "Restart" --no-button "Not now" \
        --yesno "To apply the new settings LND needs to restart.
        Do you want to restart LND now?" 10 55
      if [ $? -eq 0 ]; then
        echo "# Restarting LND"
        sudo systemctl restart ${network}d
      else
        echo "# Continue without restarting."
      fi
     else
      echo "# No change made"
    fi;;         
  TORLOG)
    sudo -u debian-tor nyx;;
  TORRC)
    if /home/admin/config.scripts/blitz.setconf.sh "/etc/tor/torrc" "debian-tor"
    then
      whiptail \
        --title "Restart" --yes-button "Restart" --no-button "Not now" \
        --yesno "To apply the new settings Tor needs to restart.
        Do you want to restart Tor now?" 10 55
      if [ $? -eq 0 ]; then
        echo "# Restarting tor"
        sudo systemctl restart tor@default
      else
        echo "# Continue without restarting."
      fi
    else
      echo "# No change made"
    fi;;
  CUSTOMLOG)
    clear
    echo
    echo "Example list: 
btc-rpc-explorer, btcpayserver, circuitbreaker,
cryptoadvance-specter, getty@tty1, electrs, litd,
lnbits, mempool, nbxlorer, nginx, RTL, telegraf,
thunderhub, tor@default, tor@lnd, tor
"
    echo "Type the name of the service you would like to monitor:"  
    read SERVICE
    echo
    echo "Will show the logs with:"
    echo "'sudo journalctl -n 100 -fu $SERVICE'"
    echo
    echo "Press ENTER to continue"
    echo "use CTRL+C any time to abort .. then use command 'raspiblitz' to return to menu"
    sudo journalctl -n 100 -fu $SERVICE;;
  CUSTOMRESTART)
    clear
    echo
    echo "Example list: 
btc-rpc-explorer, btcpayserver, circuitbreaker,
cryptoadvance-specter, getty@tty1, electrs, litd,
lnbits, mempool, nbxlorer, nginx, RTL, telegraf,
thunderhub, tor@default, tor@lnd, tor
"
    echo "Type the name of the service you would like to restart:" 
    read SERVICE
    echo
    echo "Will use the command:"
    echo "'sudo systemctl restart $SERVICE'"
    echo
    echo "Press ENTER to restart $SERVICE or use CTRL+C to abort"
    read key
    sudo systemctl restart $SERVICE
    echo
    echo "Will show the logs with:"
    echo "'sudo journalctl -n 100 -fu $SERVICE'"
    echo
    echo "Press ENTER to continue"
    echo "use CTRL+C any time to abort .. then use command 'raspiblitz' to return to menu"
    sudo journalctl -n 100 -fu $SERVICE;;
esac
