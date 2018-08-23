#!/bin/bash

# load network and chain info
network=`cat .network`
chain=$(${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo | jq -r '.chain')

command="lncli closeallchannels --force"

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

# execute command
if [ ${#command} -gt 0 ]; then
  ${command}
fi
 
echo ""
echo "OK - wait a 5 seconds"
sleep 5

echo "Your Open Channel List (to check):" 
lnchannels
