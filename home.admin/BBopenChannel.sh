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
  echo "FAIL - 'lncli getinfo' shows 'synced_to_chain': false"
  echo "Wait until chain is sync with LND and try again."
  echo ""
  exit 1
fi

# check available funding
confirmedBalance=$(lncli walletbalance | grep '"confirmed_balance"' | cut -d '"' -f4)
if [ "${network}" = "bitcoin" ]; then
  if [ ${confirmedBalance} -lt 100 ]; then
    
  fi
elif [ "${network}" = "litecoin" ]; then
 // 20000 SAT
 // 546
 // 616233 SAT

fi

# check number of connected peers
numConnectedPeers=$(lncli listpeers | grep pub_key -c)
if [ ${numConnectedPeers} -eq 0 ]; then
  echo "FAIL - no peers connected on lightning network"
  echo "You can only open channels to peer nodes to connected to first."
  echo "Use CONNECT peer option in main menu first."
  echo ""
  exit 1
fi

# let user pick a peer to open a channels with
OPTIONS=()
while IFS= read -r grepLine
do
  pubKey=$(echo ${grepLine} | cut -d '"' -f4)
  echo "grepLine(${pubKey})"
  OPTIONS+=(pubKey "")
done < <(lncli listpeers | grep pub_key)
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
 echo "Selected CANCEL"
 echo ""
 exit 1
fi

# find out what is the minimum amount
minSat=20000
_error="./.error.out"
lncli openchannel ${CHOICE} 1 0 2>$_error
error=`cat ${_error}`
if [ $(echo "${error}" | grep "channel is too small" -c) -eq 1 ]; then
  minSat=$(echo "${error}" | tr -dc '0-9')
fi

# let user enter a amount
l1="Enter the amount in SATOSHI you want to fund this channel:"
l2="min required  : ${minSat}"
l3="max available : ${confirmedBalance}"
dialog --title "Funding of Channel" \
--inputbox "$l1\n$l2\n$l3" 10 60 2>$_temp
amount=$(cat $_temp | xargs | tr -dc '0-9')
shred $_temp
if [ ${#amount} -eq 0 ]; then
  echo "FAIL - not a valid input (${amount})"
  exit 1
fi

# build command
command="lncli openchannel ${#pubKey} ${amount} 0"

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
echo "result(${result})"
echo "error(${error})"

exit 1

# on no result
if [ ${#result} -eq 0 ]; then

  # basic error
  win=0
  info="No return value. Error not known."

  # try to get error output
  result=`cat ${_error}`
  echo "$result"

  # basic cli error
  cliError=$(echo "${result}" | grep "[lncli]" -c )
  if [ ${cliError} -gt 0 ]; then
    info="Its possible that LND daemon is not running, not configured correct or not connected to the lncli."
  fi

else

  # when result is available
  echo "$result"

  # check if the node is now in peer list
  pubkey=$(echo $_input | cut -d '@' -f1)
  isPeer=$(lncli listpeers 2>/dev/null| grep "${pubkey}" -c)
  if [ ${isPeer} -eq 0 ]; then

    # basic error message
    win=0
    info="Was not able to establish connection to node."

    # TODO: try to find out more details from cli output

  else
    info="Perfect - a connection to that node got established :)"
  fi

fi

# output info
echo ""
if [ ${win} -eq 1 ]; then
  echo "******************************"
  echo "WIN"
  echo "******************************"
  echo "${info}"
  echo ""
  echo "Whats next? --> Open a channel with that node."
else
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "FAIL"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "${info}"
fi

echo ""