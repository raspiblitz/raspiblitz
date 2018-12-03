#!/bin/bash
_temp="./download/dialog.$$"
_error="./.error.out"

# load raspiblitz config data (with backup from old config)
source /mnt/hdd/raspiblitz.conf 2>/dev/null
if [ ${#network} -eq 0 ]; then network=`cat .network`; fi
if [ ${#chain} -eq 0 ]; then
  chain=$(${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo | jq -r '.chain')
fi

# check if user has money in lightning channels - info about close all
openChannels=$(lncli --chain=${network} listchannels 2>/dev/null | jq '.[] | length')
if [ ${#openChannels} -eq 0 ]; then
  echo "*** IMPORTANT **********************************"
  echo "It looks like LND is not responding."
  echo "Still starting up, is locked or is not running?"
  echo "Try later, try reboot or check ./XXdebugLogs.sh"
  echo "************************************************"
  exit 1
fi
if [ ${openChannels} -gt 0 ]; then
   dialog --title 'Info' --msgbox 'You still have funds in open Lightning Channels.\nUse CLOSEALL first if you want to cashout all funds.\nNOTICE: Just confirmed on-chain funds can be moved.' 7 58
fi

# check if money is waiting to get confirmed
unconfirmed=$(lncli --chain=${network} walletbalance | grep '"unconfirmed_balance"' | cut -d '"' -f4)
if [ ${unconfirmed} -gt 0 ]; then
   dialog --title 'Info' --msgbox "Still waiting confirmation for ${unconfirmed} sat.\nNOTICE: Just confirmed on-chain funds can be moved." 6 58
fi

# get available amount in on-chain wallet
maxAmount=$(lncli --chain=${network} walletbalance | grep '"confirmed_balance"' | cut -d '"' -f4)
if [ ${maxAmount} -eq 0 ]; then
   dialog --title 'Info' --msgbox "You have 0 moveable funds available.\nNOTICE: Just confirmed on-chain funds can be moved." 6 58
   exit 1
fi

# let user enter the amount
l1="Enter the amount of funds you want to send/remove:"
l2="You have max available: ${maxAmount} sat"
l3="If you enter nothing, all funds available will be send."
dialog --title "Remove Funds from RaspiBlitz" \
--inputbox "$l1\n$l2\n$l3" 10 60 2>$_temp
amount=$(cat $_temp | xargs)
shred $_temp
if [ ${#amount} -eq 0 ]; then
  amount=${maxAmount}
fi

# TODO: check if amount is in valid range

# let user enter the address
l1="Enter the on-chain address to send funds to:"
l2="You will send: ${amount} sat to that address"
dialog --title "Where to send funds?" \
--inputbox "$l1\n$l2" 8 65 2>$_temp
address=$(cat $_temp | xargs)
shred $_temp
if [ ${#address} -eq 0 ]; then
  echo "FAIL - not a valid address (${address})"
  exit 1
fi

# TODO: check address is valid for network and chain

# TODO: check if fees are getting done right so that transaction will get processed
amount=$((amount - 10000))
command="lncli --chain=${network} sendcoins --addr ${address} --amt ${amount} --conf_target 3"


clear
echo "******************************"
echo "Send on-chain Funds"
echo "******************************"
echo ""
echo "COMMAND LINE: "
echo $command
echo ""
echo "RESULT:"

# execute command
if [ ${#command} -gt 0 ]; then
  result=$($command)
fi

# on no result
if [ ${#result} -eq 0 ]; then
  echo "Sorry something went wrong - thats unusual."
  echo ""
  exit 1
fi
 
# when result is available
echo "$result"

# TODO: check if all cashed out (0 funds + 0 channels) -> let user knwo its safe to update/reset RaspiBlitz

echo "OK. That worked :)"
echo ""
