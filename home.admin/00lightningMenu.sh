#!/bin/bash

# get raspiblitz config
echo "get raspiblitz config"
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# get the local network IP to be displayed on the LCD
source <(/home/admin/config.scripts/internet.sh status local)

# BASIC MENU INFO
HEIGHT=13
WIDTH=64
CHOICE_HEIGHT=7
BACKTITLE="RaspiBlitz"
TITLE="Lightning Options"
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
  HEIGHT=$((HEIGHT+3))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+3))  
fi

OPTIONS+=(NAME "Change Name/Alias of Node")

openChannels=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net listchannels 2>/dev/null | jq '.[] | length')
if [ ${#openChannels} -gt 0 ] && [ ${openChannels} -gt 0 ]; then
  OPTIONS+=(CLOSEALL "Close all open Channels")
  HEIGHT=$((HEIGHT+1))
  CHOICE_HEIGHT=$((CHOICE_HEIGHT+1))  
fi

OPTIONS+=(CASHOUT "Remove Funds from LND")

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
            /home/admin/BBconnectPeer.sh
            ;;
        FUNDING)
            /home/admin/BBfundWallet.sh
            ;;
        CASHOUT)
            /home/admin/BBcashoutWallet.sh
            ;;
        CHANNEL)
            /home/admin/BBopenChannel.sh
            ;;
        SEND)
            /home/admin/BBpayInvoice.sh
            ;;
        RECEIVE)
            /home/admin/BBcreateInvoice.sh
            ;;
        NAME)
            sudo /home/admin/config.scripts/lnd.setname.sh
            noreboot=$?
            if [ "${noreboot}" = "0" ]; then
              sudo -u bitcoin ${network}-cli stop
              echo "Press ENTER to Reboot."
              read key
              sudo /home/admin/XXshutdown.sh reboot
              exit 0
            fi
            ;;
        CLOSEALL)
            /home/admin/BBcloseAllChannels.sh
            echo "Press ENTER to return to main menu."
            read key
            ;;
esac

# go into loop - start script from beginning to load config/sate fresh
/home/admin/00mainMenu.sh