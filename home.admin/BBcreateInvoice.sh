#!/bin/bash
_temp="./download/dialog.$$"
_error="./.error.out"

# load network and chain info
network=`cat .network`
chain=$(sudo -bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo | jq -r '.chain')

echo ""
echo "*** Precheck ***"

# check if chain is in sync
chainInSync=$(lncli getinfo | grep '"synced_to_chain": true' -c)
if [ ${chainInSync} -eq 0 ]; then
  echo "!!!!!!!!!!!!!!!!!!!"
  echo "FAIL - 'lncli getinfo' shows 'synced_to_chain': false"
  echo "Wait until chain is sync with LND and try again."
  echo "!!!!!!!!!!!!!!!!!!!"
  echo ""
  exit 1
fi

# check number of connected peers
echo "check for open channels"
openChannels=$(sudo -u bitcoin lncli listchannels 2>/dev/null | grep chan_id -c)
if [ ${openChannels} -eq 0 ]; then
  echo ""
  echo "!!!!!!!!!!!!!!!!!!!"
  echo "FAIL - You have NO ESTABLISHED CHANNELS .. open a channel first."
  echo "!!!!!!!!!!!!!!!!!!!"
  echo ""
  exit 1
fi

# let user enter the invoice
l1="Enter the AMOUNT IN SATOSHI of the invoice:"
l2="1 ${network} = 100 000 000 SAT"
dialog --title "Pay thru Lightning Network" \
--inputbox "$l1\n$l2" 9 40 2>$_temp
amount=$(cat $_temp | xargs | tr -dc '0-9')
shred $_temp
if [ ${#amount} -eq 0 ]; then
  echo "FAIL - not a valid input (${amount})"
  exit 1
fi

# build command
command="lncli addinvoice ${amount}"

# info output
clear
echo "******************************"
echo "Create Invoice / Payment Request"
echo "******************************"
echo ""
echo "COMMAND LINE: "
echo $command
echo ""
echo "RESULT:"

# execute command
result=$($command 2>$_error)
error=`cat ${_error}`

#echo "result(${result})"
#echo "error(${error})"

if [ ${#error} -gt 0 ]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "FAIL"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "${error}"
else
  echo "${result}"
  echo "******************************"
  echo "WIN"
  echo "******************************"
  echo "It worked :) - check out the service you were paying."
fi
echo ""