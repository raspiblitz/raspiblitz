#!/bin/bash

# load network and chain info
network=`cat .network`
chain=$(${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo | jq -r '.chain')

command="lncli closeallchannels -f"

clear
echo "***********************************"
echo "Closing All Channels (EXPERIMENTAL)"
echo "***********************************"
echo ""
echo "COMMAND LINE: "
echo $command
echo ""
echo "RESULT:"

# PRECHECK) check if chain is in sync
chainInSync=$(lncli getinfo | grep '"synced_to_chain": true' -c)
if [ ${chainInSync} -eq 0 ]; then
  command=""
  result="FAIL PRECHECK - lncli getinfo shows 'synced_to_chain': false - wait until chain is sync "
fi

# TODO PRECHECK) are any channels open at all

# TODO PRECHECK) are there INACTIVE channels that would need a force close (and manual YES)
# remember that for info below

# execute command
if [ ${#command} -gt 0 ]; then
  result=$($command)
fi

# on no result TODO: check if there is any result at all
if [ ${#result} -eq 0 ]; then
  echo "Sorry something went wrong - thats unusual."
  echo ""
  exit 1
fi
 
# when result is available
echo "$result"

# TODO parse out closing transactions and monitor those with blockchain for confirmations

# TODO give final info - let user know if its now safe to update RaspiBlitz or change test/main
# ask to make sure user has list for seed words still safe
echo ""
echo "******************************"
echo "INFO"
echo "******************************"
