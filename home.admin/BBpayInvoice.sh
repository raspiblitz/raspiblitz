#!/bin/bash
clear
trap 'rm -f "$_temp"' EXIT
trap 'rm -f "$_error"' EXIT
_temp=$(mktemp -p /dev/shm/)
_error=$(mktemp -p /dev/shm/)
sudo chmod 7777 ${_error} 2>/dev/null

# load raspiblitz config data (with backup from old config)
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then network=$(cat .network); fi
if [ ${#network} -eq 0 ]; then network="bitcoin"; fi
if [ ${#chain} -eq 0 ]; then
  echo "gathering chain info ... please wait"
  chain=$(${network}-cli getblockchaininfo | jq -r '.chain')
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars $1 $2)

source <(/home/admin/config.scripts/network.aliases.sh getvars $LNTYPE ${chain}net)

# check if chain is in sync
if [ $LNTYPE = cl ];then
  lncommand="${netprefix}lightning-cli"
  BLOCKHEIGHT=$($bitcoincli_alias getblockchaininfo|grep blocks|awk '{print $2}'|cut -d, -f1)
  CLHEIGHT=$($lightningcli_alias getinfo | jq .blockheight)
  if [ $BLOCKHEIGHT -eq $CLHEIGHT ];then
    cmdChainInSync=1
  else
    cmdChainInSync=0
  fi
elif [ $LNTYPE = lnd ];then
  lncommand="${netprefix}lncli"
  cmdChainInSync="$lncli_alias getinfo | grep '"synced_to_chain": true' -c"
fi
chainInSync=${cmdChainInSync}
while [ "${chainInSync}" == "0" ]; do
  dialog --title "Fail: not in sync" \
	 --ok-label "Try now" \
	 --cancel-label "Give up" \
	 --pause "\n\n'$lncommand getinfo' shows 'synced_to_chain': false\n\nTry again in a few seconds." 15 60 5
  
  if [ $? -gt 0 ]; then
      exit 0
  fi
  chainInSync=${cmdChainInSync}
done

# check number of connected peers
echo "check for open channels"
if [ $LNTYPE = cl ];then
  openChannels=$($lightningcli_alias listpeers | grep -c "CHANNELD_NORMAL")
elif [ $LNTYPE = lnd ];then
  openChannels=$($lncli_alias  listchannels 2>/dev/null | grep chan_id -c)
fi
if [ ${openChannels} -eq 0 ]; then
  echo 
  echo "!!!!!!!!!!!!!!!!!!!"
  echo "FAIL - You have NO ESTABLISHED CHANNELS .. open a channel first."
  echo "!!!!!!!!!!!!!!!!!!!"
  sleep 3
  echo 
  exit 0
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
    testSite="https://starblocks.acinq.co/"
  fi
elif [ "${network}" = "litecoin" ]; then
    testSite="https://millionlitecoinhomepage.net"
fi

# let user enter the invoice
l1="Copy the LightningInvoice/PaymentRequest into here:"
l2="Its a long string starting with '${paymentRequestStart}'"
l3="To try it out go to: ${testSite}"
dialog --title "Pay through the Lightning Network" \
--inputbox "$l1\n$l2\n$l3" 10 70 2>$_temp
invoice=$(cat $_temp | xargs)
shred -u $_temp
if [ ${#invoice} -eq 0 ]; then
  clear
  echo
  echo "no invoice entered - returning to menu ..."
  sleep 3
  exit 0
fi

# TODO: maybe try/show the decoded info first by using https://api.lightning.community/#decodepayreq

# build command
if [ $LNTYPE = cl ];then
  # pay bolt11 [msatoshi] [label] [riskfactor] [maxfeepercent] [retry_for] [maxdelay] [exemptfee]
  command="$lightningcli_alias pay ${invoice}"
elif [ $LNTYPE = lnd ];then
  command="$lncli_alias sendpayment --force --pay_req=${invoice}"
fi

# info output
clear
echo "************************************************************"
echo "Pay Invoice / Payment Request"
echo "This script is an example using lightning in the command line."
echo "It is not optimized for performance or error handling."
echo "************************************************************"
echo 
echo "COMMAND LINE: "
echo $command
echo
echo "RESULT (may wait in case of timeout):"

# execute command
result=$($command 2>$_error)
error=$(cat ${_error})

#echo "result(${result})"
#echo "error(${error})"

if [ $LNTYPE = cl ];then
  resultIsError=$(echo "${result}" | grep -c '"code":')
elif [ $LNTYPE = lnd ];then
  resultIsError=$(echo "${result}" | grep -c "payment_error")
fi
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
  echo "It worked :) - check the service you were paying."
fi
echo
echo "Press ENTER to return to main menu."
read key
