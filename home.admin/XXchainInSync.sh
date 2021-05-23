#!/bin/bash

# Check if lnd is synced to chain and channels are open
# If it isn't, wait until it is
# exits with 1 if it isn't.

network=$1
chain=$2

# LNTYPE is lnd | cln
if [ $# -gt 2 ];then
  LNTYPE=$3
else
  LNTYPE=lnd
fi

if [ ${chain} = test ];then
  netprefix="t"
  L1rpcportmod=1
  L2rpcportmod=1
elif [ ${chain} = sig ];then
  netprefix="s"
  L1rpcportmod=3
  L2rpcportmod=3
elif [ ${chain} = main ];then
  netprefix=""
  L1rpcportmod=""
  L2rpcportmod=0
fi

lncli_alias="sudo -u bitcoin /usr/local/bin/lncli -n=${chain}net --rpcserver localhost:1${L2rpcportmod}009"
bitcoincli_alias="/usr/local/bin/${network}-cli -rpcport=${L1rpcportmod}8332"
lightningcli_alias="sudo -u bitcoin /usr/local/bin/lightning-cli --conf=/home/bitcoin/.lightning/${netprefix}config"
shopt -s expand_aliases
alias lncli_alias="$lncli_alias"
alias bitcoincli_alias="$bitcoincli_alias"
alias lightningcli_alias="$lightningcli_alias"

# check if chain is in sync
if [ $LNTYPE = cln ];then
  lncommand="lightning-cli"
  BLOCKHEIGHT=$(bitcoincli_alias getblockchaininfo|grep blocks|awk '{print $2}'|cut -d, -f1)
  CLHEIGHT=$(lightningcli_alias getinfo | jq .blockheight)
  if [ $BLOCKHEIGHT -eq $CLHEIGHT ];then
    cmdChainInSync=1
  else
    cmdChainInSync=0
  fi
elif [ $LNTYPE = lnd ];then
  lncommand="lncli"
  cmdChainInSync="lncli_alias getinfo | grep '"synced_to_chain": true' -c"
fi
chainInSync=${cmdChainInSync}
while [ "${chainInSync}" == "0" ]; do
  dialog --title "Fail: not in sync" \
	 --ok-label "Try now" \
	 --cancel-label "Give up" \
	 --pause "\n\n'$lncommand getinfo' shows 'synced_to_chain': false\n\nTry again in a few seconds." 15 60 5
  
  if [ $? -gt 0 ]; then
      exit 1
  fi
  chainInSync=${cmdChainInSync}
done

# check number of connected peers
echo "check for open channels"
if [ $LNTYPE = cln ];then
  openChannels=$(lightningcli_alias listpeers | grep -c '"CHANNELD_NORMAL:Funding transaction locked. Channel announced."')
elif [ $LNTYPE = lnd ];then
  openChannels=$(lncli_alias  listchannels 2>/dev/null | grep chan_id -c)
fi
if [ ${openChannels} -eq 0 ]; then
  echo 
  echo "!!!!!!!!!!!!!!!!!!!"
  echo "FAIL - You have NO ESTABLISHED CHANNELS .. open a channel first."
  echo "!!!!!!!!!!!!!!!!!!!"
  echo 
  exit 1
fi

exit 0
