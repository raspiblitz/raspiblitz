#!/bin/bash

# get raspiblitz config
echo "# get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

source <(/home/admin/config.scripts/network.aliases.sh getvars cln $1)

# get the local network IP to be displayed on the LCD
source <(/home/admin/config.scripts/internet.sh status local)

# BASIC MENU INFO
HEIGHT=14
WIDTH=64
CHOICE_HEIGHT=8
BACKTITLE="RaspiBlitz"
TITLE="C-Lightning Options"
MENU=""
OPTIONS=()

OPTIONS+=(FUNDING "Fund your C-Lightning Wallet")
OPTIONS+=(PEERING "Connect to a Peer")
OPTIONS+=(CHANNEL "Open a Channel with Peer")
OPTIONS+=(SEND "Pay an Invoice/PaymentRequest")
OPTIONS+=(RECEIVE "Create Invoice/PaymentRequest")
OPTIONS+=(SUMMARY "Information about this node")
OPTIONS+=(NAME "Change Name/Alias of the Node")

ln_getInfo=$($lightningcli_alias getinfo 2>/dev/null)
ln_channels_online="$(echo "${ln_getInfo}" | jq -r '.num_active_channels')" 2>/dev/null
cln_num_inactive_channels="$(echo "${ln_getInfo}" | jq -r '.num_inactive_channels')" 2>/dev/null
openChannels=$((ln_channels_online+cln_num_inactive_channels))
if [ ${#openChannels} -gt 0 ] && [ ${openChannels} -gt 0 ]; then
OPTIONS+=(SUEZ "Visualize channels")
OPTIONS+=(CLOSEALL "Close all open Channels on $CHAIN")
  HEIGHT=$((HEIGHT+2))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+2))  
fi

if [ ${#LNdefault} -gt 0 ]&&[ $LNdefault = lnd ];then
  OPTIONS+=(SWITCHLN  "Use C-lightning as default")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))
fi  

OPTIONS+=(CASHOUT "Withdraw all funds from C-lightning on $CHAIN")

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
  SUMMARY)
      /home/admin/config.scripts/cln-plugin.summary.sh $CHAIN
      ;;
  PEERING)
      /home/admin/BBconnectPeer.sh cln $CHAIN
      ;;
  FUNDING)
      /home/admin/BBfundWallet.sh cln $CHAIN
      ;;
  CASHOUT)
      /home/admin/BBcashoutWallet.sh cln $CHAIN
      ;;
  CHANNEL)
      /home/admin/BBopenChannel.sh cln $CHAIN
      ;;
  SEND)
      /home/admin/BBpayInvoice.sh cln $CHAIN
      ;;
  RECEIVE)
      /home/admin/BBcreateInvoice.sh cln $CHAIN
      ;;
  NAME)
      sudo /home/admin/config.scripts/cln.setname.sh $CHAIN
      ;;
  SUEZ)
      clear
      if [ ! -f /home/bitcoin/suez/suez ];then
        /home/admin/config.scripts/bonus.suez.sh on
      fi
      cd /home/bitcoin/suez || exit 1 
      sudo -u bitcoin /home/bitcoin/.local/bin/poetry run ./suez \
        --client=c-lightning \
        --client-args=--conf=/home/bitcoin/.lightning/${netprefix}config
      echo
      echo "Press ENTER to return to main menu."
      read key
      ;;
  CLOSEALL)
      /home/admin/BBcloseAllChannels.sh cln $CHAIN
      echo "Press ENTER to return to main menu."
      read key
      ;;
  SWITCHLN)
      clear 
      echo
      # setting value in raspi blitz config
      sudo sed -i "s/^LNdefault=.*/LNdefault=cln/g" /mnt/hdd/raspiblitz.conf
      echo "# OK - LNdefault=cln is set in /mnt/hdd/raspiblitz.conf"
      echo
      echo "Press ENTER to return to main menu."
      read key
      ;;
esac
