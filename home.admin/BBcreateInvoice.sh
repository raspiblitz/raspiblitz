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
  exit 0
fi

# let user enter the invoice
l1="Enter the AMOUNT IN SATOSHIS to invoice:"
l2="1 ${network} = 100 000 000 SAT"
dialog --title "Request payment through Lightning" \
--inputbox "$l1\n$l2" 9 50 2>$_temp
amount=$(cat $_temp | xargs | tr -dc '0-9')
shred -u $_temp
if [ ${#amount} -eq 0 ]; then
  clear
  echo
  echo "no amount entered - returning to menu ..."
  sleep 3
  exit 0
fi

# TODO let user enter a description

# build command
if [ $LNTYPE = cl ];then
  label=$(date +%s) # seconds since 1970-01-01 00:00:00 UTC
  # invoice msatoshi label description [expiry] [fallbacks] [preimage] [exposeprivatechannels] [cltv]
  command="$lightningcli_alias invoice ${amount}sat $label ''"
  # TODO warn about insufficient liquidity
elif [ $LNTYPE = lnd ];then
  command="$lncli_alias addinvoice ${amount}"
fi

# info output
clear
echo "******************************"
echo "Create Invoice / Payment Request"
echo "******************************"
echo
echo "COMMAND LINE: "
echo $command
echo
echo "RESULT:"
sleep 2

# execute command
result=$($command 2>$_error)
error=$(cat ${_error} 2>/dev/null)

#echo "result(${result})"
#echo "error(${error})"

if [ ${#error} -gt 0 ]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "FAIL"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "${error}"
else
  if [ $LNTYPE = cl ];then
    payReq=$(echo "$result" | grep bolt11 | cut -d '"' -f4)
  elif [ $LNTYPE = lnd ];then
    rhash=$(echo "$result" | grep r_hash | cut -d '"' -f4)
    payReq=$(echo "$result" | grep payment_request | cut -d '"' -f4)
  fi
  /home/admin/config.scripts/blitz.display.sh qr "${payReq}"

  if [ $(sudo dpkg-query -l | grep "ii  qrencode" | wc -l) = 0 ]; then
   sudo apt-get install qrencode -y > /dev/null
  fi

  # raise high focus on lightning channel balance next 5min
  /home/admin/_cache.sh focus ln_${LNTYPE}_${CHAIN}_channels_balance 0 300

  echo
  echo "********************"
  echo "Here is your invoice"
  echo "********************"
  echo
  qrencode -t ANSI256 "${payReq}"
  echo
  echo "Give this Invoice/PaymentRequest to someone to pay it:"
  echo
  echo "${payReq}"
  echo
  echo "Monitoring the Incoming Payment with:"
  if [ $LNTYPE = cl ];then
    echo "$lightningcli_alias waitinvoice $label"
  elif [ $LNTYPE = lnd ];then
    echo "$lncli_alias lookupinvoice ${rhash}"
  fi
  echo "Press x and hold to skip to menu."

  while :
    do
    if [ $LNTYPE = cl ];then
      result=$($lightningcli_alias waitinvoice $label)
      wasPayed=$(echo $result | grep -c 'paid')
    elif [ $LNTYPE = lnd ];then
      result=$($lncli_alias lookupinvoice ${rhash})
      wasPayed=$(echo $result | grep -c '"settled": true')
    fi
    if [ ${wasPayed} -gt 0 ]; then
      echo 
      echo $result
      echo
      echo "OK the Invoice was paid - returning to menu."
      /home/admin/config.scripts/blitz.display.sh hide
      /home/admin/config.scripts/blitz.display.sh image /home/admin/raspiblitz/pictures/ok.png
      sleep 2
      break
    fi
 
    # wait 2 seconds for key input
    read -n 1 -t 2 keyPressed

    # check if user wants to abort session
    if [ "${keyPressed}" = "x" ]; then
      echo 
      echo $result
      echo
      echo "Returning to menu - invoice was not payed yet."
      break
    fi

  done

  /home/admin/config.scripts/blitz.display.sh hide

fi
echo "Press ENTER to return to main menu."
read key