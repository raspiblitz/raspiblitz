#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# source <(/home/admin/config.scripts/network.aliases.sh getvars <lnd|cln> <mainnet|testnet|signet>)
source <(/home/admin/config.scripts/network.aliases.sh getvars cln $1)

# BASIC MENU INFO
WIDTH=64
BACKTITLE="RaspiBlitz"
TITLE=" ${CHAIN} System Options "
MENU=""    # adds lines to HEIGHT
OPTIONS=() # adds lines to HEIGHt + CHOICE_HEIGHT

if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then
  OPTIONS+=(${network}LOG "Monitor the debug.log for ${CHAIN}")
  OPTIONS+=(${network}CONF "Edit the bitcoin.conf")
fi

if 
OPTIONS+=(LNDLOG "Monitor the lnd.log for ${CHAIN}")
OPTIONS+=(LNDCONF "Edit the lnd.conf for ${CHAIN}")

if grep "^${netprefix}cln=on" /mnt/hdd/raspiblitz.conf;then
  OPTIONS+=(CLNLOG "Monitor the CLN log for ${CHAIN}")
  OPTIONS+=(CLNCONF "Edit the CLN config for ${CHAIN}")
fi

if [ "${runBehindTor}" == "on" ]; then
  OPTIONS+=(TORLOG "Monitor the Tor Service with Nyx")
  OPTIONS+=(TORRC "Edit the Tor Configuration")
fi

OPTIONS+=(CUSTOMLOG "Monitor a custom service")
OPTIONS+=(CUSTOMRESTART "Restart a custom service")

CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
HEIGHT=$((CHOICE_HEIGHT+6))
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
    if [ ${CHAIN} = signet ]; then
      bitcoinlogpath="/mnt/hdd/bitcoin/signet/debug.log"
    elif [ ${CHAIN} = testnet ]; then
      bitcoinlogpath="/mnt/hdd/bitcoin/testnet3/debug.log"
    elif [ ${CHAIN} = mainnet ]; then
      bitcoinlogpath="/mnt/hdd/bitcoin/debug.log"      
    fi
    clear
    echo
    echo "Will follow the ${bitcoinlogpath}"
    echo "running: 'sudo tail -n 30 -f ${bitcoinlogpath}'"
    echo
    echo "Press ENTER to continue"
    echo "use CTRL+C any time to abort .. then use command 'raspiblitz' to return to menu"
    echo "###############################################################################"
    read key
    sudo tail -n 30 -f ${bitcoinlogpath};;
  ${network}CONF)
    if /home/admin/config.scripts/blitz.setconf.sh "/mnt/hdd/${network}/${network}.conf" "root"
    then
      whiptail \
        --title "Restart" --yes-button "Restart" --no-button "Not now" \
        --yesno "To apply the new settings ${netprefix}${network}d needs to restart.
        Do you want to restart ${netprefix}${network}d now?" 10 55
      if [ $? -eq 0 ]; then
        echo "# Restarting ${netprefix}${network}d"
        sudo systemctl restart ${netprefix}${network}d
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
    echo "###############################################################################"
    read key
    sudo tail -n 30 -f /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log;;
  LNDCONF)
    if /home/admin/config.scripts/blitz.setconf.sh "/mnt/hdd/lnd/${netprefix}lnd.conf" "root"
    then
      whiptail \
        --title "Restart" --yes-button "Restart" --no-button "Not now" \
        --yesno "To apply the new settings LND needs to restart.
        Do you want to restart LND now?" 10 55
      if [ $? -eq 0 ]; then
        echo "# Restarting LND"
        sudo systemctl restart ${netprefix}lnd
      else
        echo "# Continue without restarting."
      fi
     else
      echo "# No change made"
    fi;;
  CLNLOG)
    clear
    echo
    echo "Will follow the /home/bitcoin/.lightning/${CLNETWORK}/cl.log"
    echo "running 'sudo tail -n 30 -f /home/bitcoin/.lightning/${CLNETWORK}/cl.log'"
    echo
    echo "Press ENTER to continue"
    echo "use CTRL+C any time to abort .. then use command 'raspiblitz' to return to menu"
    echo "###############################################################################"
    read key
    sudo tail -n 30 -f /home/bitcoin/.lightning/${CLNETWORK}/cl.log;;
  CLNCONF)
    if /home/admin/config.scripts/blitz.setconf.sh "/home/bitcoin/.lightning/${netprefix}config" "root"
    then
      whiptail \
        --title "Restart" --yes-button "Restart" --no-button "Not now" \
        --yesno "To apply the new settings C-lightning needs to restart.
        Do you want to restart C-lightning now?" 0 0
      if [ $? -eq 0 ]; then
        echo "# Restarting C-lightning"
        sudo systemctl restart ${netprefix}lightningd
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
specter, getty@tty1, electrs, litd,
lnbits, mempool, nbxlorer, nginx, RTL, telegraf,
thunderhub, tor@default, tor@lnd, tor
"
    echo "Type the name of the service you would like to monitor:"  
    read SERVICE
    echo
    echo "Will show the logs with:"
    echo "'sudo journalctl -n 10 -fu $SERVICE'"
    echo
    echo "use CTRL+C any time to abort .. then use command 'raspiblitz' to return to menu"
    echo "###############################################################################"
    sudo journalctl -n 10 -fu $SERVICE;;
  CUSTOMRESTART)
    clear
    echo
    echo "Example list: 
btc-rpc-explorer, btcpayserver, circuitbreaker,
specter, getty@tty1, electrs, litd,
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
    echo "'sudo journalctl -n 10 -fu $SERVICE'"
    echo
    echo "use CTRL+C any time to abort .. then use command 'raspiblitz' to return to menu"
    echo "###############################################################################"
    sudo journalctl -n 10 -fu $SERVICE;;
esac
