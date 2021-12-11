#!/bin/bash

# For now just list all testnet/signet options available
# injecting specific perspectives can be done later

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# BASIC MENU INFO
WIDTH=64
BACKTITLE="RaspiBlitz"
TITLE=" Testnet/Signet Options "
MENU="Choose one of the following options:"
OPTIONS=()
plus=""

if [ "${testnet}" == "on" ]; then
  OPTIONS+=(tSYS "TESTNET Monitoring & Configuration")
  if [ "${lightning}" == "lnd" ] || [ "${lnd}" == "on" ]; then OPTIONS+=(tLND "TESTNET LND Wallet Options"); fi
  if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ]; then OPTIONS+=(tCL "TESTNET C-Lightning Wallet Options"); fi
fi

# just an optical splitter - ignored on select
OPTIONS+=(--- "----------------------------------")

if [ "${signet}" == "on" ]; then
  OPTIONS+=(sSYS "SIGNET Monitoring & Configuration")
  if [ "${lightning}" == "cl" ] || [ "${cl}" == "on" ]; then OPTIONS+=(sCL "SIGNET C-Lightning Wallet Options"); fi
fi

# DONT OFFER SERVICES FOR TESTNET RIGHT NOW
# OPTIONS+=(RTL "RTL Web Node Manager for LND ${CHAIN}")
# OPTIONS+=(SERVICES "Additional Apps & Services on ${CHAIN}")

# MAYBE LATER
# OPTIONS+=(CONNECT "Connect Apps & Show Credentials")

CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
HEIGHT=$((CHOICE_HEIGHT+6))
CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --ok-label "Select" \
                --cancel-label "Back" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

case $CHOICE in
  tSYS)
    /home/admin/99systemMenu.sh testnet
    ;;
  sSYS)
    /home/admin/99systemMenu.sh signet
    ;;
  tLND)
    /home/admin/99lndMenu.sh testnet
    ;;
  sLND)
    /home/admin/99lndMenu.sh signet
    ;;
  tCL)
    /home/admin/99clMenu.sh testnet
    ;;
  sCL)
    /home/admin/99clMenu.sh signet
    ;;
esac