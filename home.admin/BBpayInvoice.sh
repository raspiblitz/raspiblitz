#!/bin/bash
clear
_temp=$(mktemp -p /dev/shm/)
_error=$(mktemp -p /dev/shm/)
sudo chmod 7777 ${_error} 2>/dev/null

# load raspiblitz config data (with backup from old config)
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then network=`cat .network`; fi
if [ ${#network} -eq 0 ]; then network="bitcoin"; fi
if [ ${#chain} -eq 0 ]; then
  echo "gathering chain info ... please wait"
  chain=$(${network}-cli getblockchaininfo | jq -r '.chain')
fi

# Check if ready (chain in sync and channels open)
./XXchainInSync.sh $network $chain
if [ $? != 0 ]; then
    exit 1
fi

paymentRequestStart="???"
if [ "${network}" = "bitcoin" ]; then
  if [ "${chain}" = "main" ]; then
    paymentRequestStart="lnbc"
  else
    paymentRequestStart="lntb"
  fi
elif [ "${network}" = "litecoin" ]; then
    paymentRequestStart="lnltc"
fi

testSite="???"
if [ "${network}" = "bitcoin" ]; then
  if [ "${chain}" = "main" ]; then
    testSite="https://satoshis.place"
  else
    testSite="https://testnet.satoshis.place"
  fi
elif [ "${network}" = "litecoin" ]; then
    testSite="https://millionlitecoinhomepage.net"
fi

# let user enter the invoice
l1="Copy the LightningInvoice/PaymentRequest into here:"
l2="Its a long string starting with '${paymentRequestStart}'"
l3="To try it out go to: ${testSite}"
dialog --title "Pay thru Lightning Network" \
--inputbox "$l1\n$l2\n$l3" 10 70 2>$_temp
invoice=$(cat $_temp | xargs)
shred -u $_temp
if [ ${#invoice} -eq 0 ]; then
  clear
  echo
  echo "no invoice entered - returning to menu ..."
  sleep 2
  exit 1
fi

# TODO: maybe try/show the decoded info first by using https://api.lightning.community/#decodepayreq

# build command
command="lncli --chain=${network} --network=${chain}net sendpayment --force --pay_req=${invoice}"

# info output
clear
echo "************************************************************"
echo "Pay Invoice / Payment Request"
echo "This script is as an example how to use the lncli interface."
echo "Its not optimized for performance or error handling."
echo "************************************************************"
echo ""
echo "COMMAND LINE: "
echo $command
echo ""
echo "RESULT (may wait in case of timeout):"

# execute command
result=$($command 2>$_error)
error=`cat ${_error}`

#echo "result(${result})"
#echo "error(${error})"

resultIsError=$(echo "${result}" | grep -c "payment_error")
if [ ${resultIsError} -gt 0 ]; then
  error="${result}"
fi

if [ ${#error} -gt 0 ]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "FAIL"
  echo "try with a wallet app or the RTL WebGUI (see services)"
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
echo "Press ENTER to return to main menu."
read key
