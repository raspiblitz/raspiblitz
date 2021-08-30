#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# get the local network IP to be displayed on the LCD
source <(/home/admin/config.scripts/internet.sh status local)

source <(/home/admin/config.scripts/network.aliases.sh getvars lnd $1)

# BASIC MENU INFO
WIDTH=64
BACKTITLE="RaspiBlitz"
TITLE=" LND Lightning Options "
MENU=""
OPTIONS=()

OPTIONS+=(FUNDING "Fund your LND Wallet")
OPTIONS+=(PEERING "Connect to a Peer")
OPTIONS+=(CHANNEL "Open a Channel with Peer")
OPTIONS+=(SEND "Pay an Invoice/PaymentRequest")
OPTIONS+=(RECEIVE "Create Invoice/PaymentRequest")

if [ "${chain}" = "main" ]; then
  OPTIONS+=(lnbalance "Detailed Wallet Balances")
  OPTIONS+=(lnchannels "Lightning Channel List")
  OPTIONS+=(lnfwdreport "Lightning Forwarding Events Report")
fi

OPTIONS+=(NAME "Change Name/Alias of Node")

openChannels=$($lncli_alias listchannels 2>/dev/null | jq '.[] | length')
if [ ${#openChannels} -gt 0 ] && [ ${openChannels} -gt 0 ]; then
  OPTIONS+=(SUEZ "Visualize channels")
  OPTIONS+=(CLOSEALL "Close all open Channels on $CHAIN")
fi

OPTIONS+=(CASHOUT "Withdraw all funds from LND on $CHAIN")

if [ "${lightning} "= "lnd" ];then
  OPTIONS+=(SWITCHLN  "Use LND as default")
fi  

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
  lnbalance)
      clear
      echo "*** YOUR SATOSHI BALANCES ***"
      /home/admin/config.scripts/lnd.balance.sh ${network}
      echo "Press ENTER to return to main menu."
      read key
      ;;
  lnchannels)
      clear
      echo "*** YOUR LIGHTNING CHANNELS ***"
      echo ""
      echo "Capacity -> total sats in the channel (their side + your side)"
      echo "Commit-Fee -> the fee that's charged if either side of the channel closes"
      echo "Balance-Local -> sats on your side of the channel (outbound liquidity)"
      echo "Balance-Remote -> sats on their side of the channel (inbound liquidity)"
      echo "Fee-Base -> fixed fee (in millisatoshis) per forwarding on channel"
      echo "Fee-PerMil -> amount based fee (millisatoshis per 1 satoshi) on forwarding"
      /home/admin/config.scripts/lnd.channels.sh ${network}
      echo "Press ENTER to return to main menu."
      read key
      ;;
  lnfwdreport)
      /home/admin/config.scripts/lnd.fwdreport.sh -menu
      echo "Press ENTER to return to main menu."
      read key
      ;;
  PEERING)
      /home/admin/BBconnectPeer.sh lnd $CHAIN
      ;;
  FUNDING)
      /home/admin/BBfundWallet.sh lnd $CHAIN
      ;;
  CASHOUT)
      /home/admin/BBcashoutWallet.sh lnd $CHAIN
      ;;
  CHANNEL)
      /home/admin/BBopenChannel.sh lnd $CHAIN
      ;;
  SEND)
      /home/admin/BBpayInvoice.sh lnd $CHAIN
      ;;
  RECEIVE)
      /home/admin/BBcreateInvoice.sh lnd $CHAIN
      ;;
  NAME)
      sudo /home/admin/config.scripts/lnd.setname.sh $CHAIN
      noreboot=$?
      if [ "${noreboot}" = "0" ]; then
        sudo -u bitcoin ${network}-cli stop
        echo "Press ENTER to Reboot."
        read key
        sudo /home/admin/config.scripts/blitz.shutdown.sh reboot
        exit 0
      fi
      ;;
  SUEZ)
      clear
      if [ ! -f /home/bitcoin/suez/suez ];then
        /home/admin/config.scripts/bonus.suez.sh on
      fi
      cd /home/bitcoin/suez || exit 1 
      sudo -u bitcoin /home/bitcoin/.local/bin/poetry run ./suez \
        --client-args=-n=${CHAIN} \
        --client-args=--rpcserver=localhost:1${L2rpcportmod}009
      echo
      echo "Press ENTER to return to main menu."
      read key
      ;;
  CLOSEALL)
      /home/admin/BBcloseAllChannels.sh lnd $CHAIN
      echo "Press ENTER to return to main menu."
      read key
      ;;
  SWITCHLN)
      clear 
      echo
      # setting value in raspi blitz config
      sudo sed -i "s/^lightning=.*/lightning=lnd/g" /mnt/hdd/raspiblitz.conf
      echo "# OK - lightning=lnd is set in /mnt/hdd/raspiblitz.conf"
      echo
      echo "Press ENTER to return to main menu."
      read key
      ;;
esac
