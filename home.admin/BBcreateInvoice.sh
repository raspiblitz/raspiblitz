#!/bin/bash
_temp="./download/dialog.$$"
_error="./.error.out"
sudo chmod 7777 ${_error}

# load raspiblitz config data (with backup from old config)
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then network=`cat .network`; fi
if [ ${#network} -eq 0 ]; then network="bitcoin"; fi
if [ ${#chain} -eq 0 ]; then
  echo "gathering chain info ... please wait"
  chain=$(${network}-cli getblockchaininfo | jq -r '.chain')
fi

echo ""
echo "*** Precheck ***"

# check if chain is in sync
chainInSync=$(lncli --chain=${network} --network=${chain}net getinfo | grep '"synced_to_chain": true' -c)
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
openChannels=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net listchannels 2>/dev/null | grep chan_id -c)
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
--inputbox "$l1\n$l2" 9 50 2>$_temp
amount=$(cat $_temp | xargs | tr -dc '0-9')
shred $_temp
if [ ${#amount} -eq 0 ]; then
  echo "FAIL - not a valid input (${amount})"
  exit 1
fi

# build command
command="lncli --chain=${network} --network=${chain}net addinvoice ${amount}"

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
sleep 2

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
  echo "******************************"
  echo "WIN"
  echo "******************************"
  echo "${result}"
  echo ""
  rhash=$(echo "$result" | grep r_hash | cut -d '"' -f4)
  payReq=$(echo "$result" | grep pay_req | cut -d '"' -f4)
  echo "Give this Invoice/PaymentRequest to someone to pay it:"
  echo ""
  echo ${payReq}
  echo ""
  echo "You can use 'lncli --chain=${network} --network=${chain}net lookupinvoice ${rhash}' to check the payment. "

  # TODO: Offer to go into monitor for incommin payment loop.

fi
echo ""