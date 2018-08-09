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
  ${command}
fi
 
echo ""
echo "OK your list of channels looks now like this:" 
sleep 2
lnchannels
