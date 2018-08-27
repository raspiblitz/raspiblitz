#!/bin/bash
_temp="./download/dialog.$$"
_error="./.error.out"

# load network and chain info
network=`cat .network`
chain=$(${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo | jq -r '.chain')

# get available amount in on-chain wallet
maxAmount=$(lncli --chain=${network} walletbalance | grep '"confirmed_balance"' | cut -d '"' -f4)

# TODO: pre-check if channels are open or are still in closing 
# and let user know not all funds are available yet (just info Dialoge)

# TODO: pre-check user hast more than 0 sat in on-chain wallet to send

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

command="lncli --chain=${network} --conf_target 3 sendcoins  ${address} ${amount}"

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
