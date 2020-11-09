#!/bin/bash
_temp="./download/dialog.$$"
_error="./.error.out"

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
  echo "FAIL - 'lncli getinfo' shows 'synced_to_chain': false"
  echo "Wait until chain is sync with LND and try again."
  echo ""
  echo "Press ENTER to return to main menu."
  read key
  exit 1
fi

# check available funding
confirmedBalance=$(lncli --chain=${network} --network=${chain}net walletbalance | grep '"confirmed_balance"' | cut -d '"' -f4)
if [ ${confirmedBalance} -eq 0 ]; then
  echo "FAIL - You have 0 SATOSHI in your confirmed LND On-Chain Wallet."
  echo "Please fund your on-chain wallet first and wait until confirmed."
  echo ""
  echo "Press ENTER to return to main menu."
  read key
  exit 1
fi

# check number of connected peers
numConnectedPeers=$(lncli --chain=${network} --network=${chain}net listpeers | grep pub_key -c)
if [ ${numConnectedPeers} -eq 0 ]; then
  echo "FAIL - no peers connected on lightning network"
  echo "You can only open channels to peer nodes to connected to first."
  echo "Use CONNECT peer option in main menu first."
  echo ""
  echo "Press ENTER to return to main menu."
  read key
  exit 1
fi

# let user pick a peer to open a channels with
OPTIONS=()
while IFS= read -r grepLine
do
  pubKey=$(echo ${grepLine} | cut -d '"' -f4)
  #echo "grepLine(${pubKey})"
  OPTIONS+=(${pubKey} "")
done < <(lncli --chain=${network} --network=${chain}net listpeers | grep pub_key)
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
_error="./.error.out"
lncli --chain=${network} openchannel --network=${chain}net ${CHOICE} 1 0 2>$_error
error=`cat ${_error}`
if [ $(echo "${error}" | grep "channel is too small" -c) -eq 1 ]; then
  minSat=$(echo "${error}" | tr -dc '0-9')
fi

# let user enter an amount
l1="Amount in SATOSHI to fund this channel:"
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
dialog --title "Open channel speed" \
--inputbox "$l1\n$l2" 10 60 2>$_temp
conf_target=$(cat $_temp | xargs | tr -dc '0-9')
shred -u $_temp
if [ ${#conf_target} -eq 0 ]; then
  echo
  echo "no valid speed entered - returning to menu ..."
  sleep 4
  exit 1
fi

# build command
command="lncli --chain=${network} --network=${chain}net openchannel --conf_target=${conf_target} ${pubKey} ${amount} 0"

# info output
clear
echo "******************************"
echo "Open Channel"
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
  echo "******************************"
  echo "WIN"
  echo "******************************"
  echo "${result}"
  echo ""
  echo "Whats next? --> You need to wait 3 confirmations, for the channel to be ready."
  fundingTX=$(echo "${result}" | grep 'funding_txid' | cut -d '"' -f4)
  if [ "${network}" = "bitcoin" ]; then
    if [ "${chain}" = "main" ]; then
        echo "https://live.blockcypher.com/btc/tx/${fundingTX}"
    else
        echo "https://live.blockcypher.com/btc-testnet/tx/${fundingTX}"
    fi
  fi
  if [ "${network}" = "litecoin" ]; then
    echo "https://live.blockcypher.com/ltc/tx/${fundingTX}/"
  fi
fi
echo ""
echo "Press ENTER to return to main menu."
read key