#!/bin/bash
_temp=$(mktemp -p /dev/shm/)
_error=$(mktemp -p /dev/shm/)

# load raspiblitz config data (with backup from old config)
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf
if [ ${#network} -eq 0 ]; then network=`cat .network`; fi
if [ ${#network} -eq 0 ]; then network="bitcoin"; fi
if [ ${#chain} -eq 0 ]; then
  echo "gathering chain info ... please wait"
  chain=$(${network}-cli getblockchaininfo | jq -r '.chain')
fi

source /home/admin/config.scripts/_functions.lightning.sh
getLNvars $1 $2
getLNaliases

echo ""
echo "*** Precheck ***"

# PRECHECK) check if chain is in sync
if [ $LNTYPE = cln ];then
  BLOCKHEIGHT=$($bitcoincli_alias getblockchaininfo|grep blocks|awk '{print $2}'|cut -d, -f1)
  CLHEIGHT=$($lightningcli_alias getinfo | jq .blockheight)
  if [ $BLOCKHEIGHT -eq $CLHEIGHT ];then
    chainOutSync=0
  else
    chainOutSync=1
  fi
elif [ $LNTYPE = lnd ];then
  chainOutSync=$($lncli_alias getinfo | grep '"synced_to_chain": false' -c)
fi
if [ ${chainOutSync} -eq 1 ]; then
  if [ $LNTYPE = cln ];then
    echo "# FAIL PRECHECK - lncli getinfo shows 'synced_to_chain': false - wait until chain is sync "
  else
    echo "# FAIL PRECHECK - 'lightning-cli getinfo' blockheight is different from 'bitcoind getblockchaininfo' - wait until chain is sync "
  fi
  echo 
  echo "# PRESS ENTER to return to menu"
  read key
  exit 1
else
  echo "# OK - the chain is synced"
fi

# check available funding
if [ $LNTYPE = cln ];then
  for i in $($lightningcli_alias listfunds | jq .outputs | grep value | awk '{print $2}' | cut -d, -f1);do
    confirmedBalance=$((confirmedBalance+i))
  done
elif [ $LNTYPE = lnd ];then
  confirmedBalance=$($lncli_alias walletbalance | grep '"confirmed_balance"' | cut -d '"' -f4)
fi

if [ ${confirmedBalance} -eq 0 ]; then
  echo "FAIL - You have 0 SATOSHI in your confirmed LND On-Chain Wallet."
  echo "Please fund your on-chain wallet first and wait until confirmed."
  echo
  echo "Press ENTER to return to main menu."
  read key
  exit 1
fi

# check number of connected peers
if [ $LNTYPE = cln ];then
  numConnectedPeers=$($lightningcli_alias listpeers | grep -c '"id":')
elif [ $LNTYPE = lnd ];then
  numConnectedPeers=$($lncli_alias listpeers | grep pub_key -c)
fi

if [ ${numConnectedPeers} -eq 0 ]; then
  echo "FAIL - no peers connected on the lightning network"
  echo "You can only open channels to peer nodes to connected to first."
  echo "Use CONNECT peer option in main menu first."
  echo
  echo "Press ENTER to return to main menu."
  read key
  exit 1
fi

# let user pick a peer to open a channels with
OPTIONS=()
if [ $LNTYPE = cln ];then
  while IFS= read -r grepLine
  do
    pubKey=$(echo ${grepLine} | cut -d '"' -f4)
    # echo "grepLine(${pubKey})"
    OPTIONS+=(${pubKey} "")
  done < <(lightningcli_alias listpeers | grep '"id":')
elif [ $LNTYPE = lnd ];then
  while IFS= read -r grepLine
  do
    pubKey=$(echo ${grepLine} | cut -d '"' -f4)
    # echo "grepLine(${pubKey})"
    OPTIONS+=(${pubKey} "")
  done < <(lncli_alias listpeers | grep pub_key)
fi
TITLE="Open (Payment) Channel"
MENU="\nChoose a peer you connected to, to open the channel with: \n "
pubKey=$(dialog --clear \
                --title "$TITLE" \
                --menu "$MENU" \
                14 73 5 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

clear
if [ ${#pubKey} -eq 0 ]; then
  clear
  echo 
  echo "no channel selected - returning to menu ..."
  sleep 4
  exit 1
fi

# find out what is the minimum amount 
# TODO find a better way - also consider dust and channel reserve
# details see here: https://github.com/btcontract/lnwallet/issues/52
minSat=20000
if [ "${network}" = "bitcoin" ]; then
  minSat=50000
fi
if [ $LNTYPE = lnd ];then
  _error="./.error.out"
  lncli_alias openchannel ${pubkey} 1 0 2>$_error
  error=$(cat ${_error})
  if [ $(echo "${error}" | grep "channel is too small" -c) -eq 1 ]; then
    minSat=$(echo "${error}" | tr -dc '0-9')
  fi
fi

# let user enter an amount
l1="Amount in satoshis to fund this channel:"
l2="min required  : ${minSat}"
l3="max available : ${confirmedBalance}"
dialog --title "Funding of Channel" \
--inputbox "$l1\n$l2\n$l3" 10 60 2>$_temp
amount=$(cat $_temp | xargs | tr -dc '0-9')
shred -u $_temp
if [ ${#amount} -eq 0 ]; then
  echo
  echo "no valid amount entered - returning to menu ..."
  sleep 4
  exit 1
fi

# let user enter a confirmation target
l1=""
l2="Urgent = 1 / Economy = 20"
dialog --title "Set confirmation target" \
--inputbox "$l1\n$l2" 10 60 2>$_temp
conf_target=$(cat $_temp | xargs | tr -dc '0-9')
shred -u $_temp
if [ ${#conf_target} -eq 0 ]; then
  echo
  echo "no valid target entered - returning to menu ..."
  sleep 4
  exit 1
fi

# build command
if [ $LNTYPE = cln ];then
  # fundchannel id amount [feerate] [announce] [minconf] [utxos] [push_msat] [close_to]
  feerate=$($bitcoincli_alias estimatesmartfee $conf_target |grep feerate|awk '{print $2}'|cut -c 5-7|bc)
  command="lightningcli_alias fundchannel ${pubKey} ${amount} $feerate"
elif [ $LNTYPE = lnd ];then
  command="lncli_alias openchannel --conf_target=${conf_target} ${pubKey} ${amount} 0"
fi
# info output
clear
echo "******************************"
echo "Open Channel"
echo "******************************"
echo
echo "COMMAND LINE: "
echo $command
echo
echo "RESULT:"

# execute command
result=$(eval $command 2>$_error)
error=$(cat ${_error})

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
  echo
  echo "What's next? --> You need to wait 3 confirmations for the channel to be ready."
  if [ $LNTYPE = cln ];then
    fundingTX=$(echo "${result}" | grep 'txid' | cut -d '"' -f4)
  elif [ $LNTYPE = lnd ];then
    fundingTX=$(echo "${result}" | grep 'funding_txid' | cut -d '"' -f4)
  fi
  echo
  if [ "${network}" = "bitcoin" ]; then
    if [ "${chain}" = "main" ]; then
      #echo "https://live.blockcypher.com/btc/tx/${fundingTX}"
      echo "https://mempool.space/tx/${fundingTX}"
    elif [ "${chain}" = "test" ]||[ "${chain}" = "sig" ]; then
      echo "https://mempool.space/${chain}net/tx/${fundingTX}"
    fi
    echo
    echo "In the Tor Browser:"
    if [ "${chain}" = "main" ]; then
      echo "http://mempoolhqx4isw62xs7abwphsq7ldayuidyx2v2oethdhhj6mlo2r6ad.onion/tx/${fundingTX}"
    elif [ "${chain}" = "test" ]||[ "${chain}" = "sig" ]; then
      echo "http://mempoolhqx4isw62xs7abwphsq7ldayuidyx2v2oethdhhj6mlo2r6ad.onion/${chain}net/tx/${fundingTX}"
    fi
  fi
  if [ "${network}" = "litecoin" ]; then
    echo "https://live.blockcypher.com/ltc/tx/${fundingTX}/"
  fi
fi
echo
echo "Press ENTER to return to main menu."
read key