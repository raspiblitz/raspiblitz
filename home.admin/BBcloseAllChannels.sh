#!/bin/bash

source /mnt/hdd/raspiblitz.conf
if [ "${autoPilot}" = "on" ]; then
  echo "PRECHECK: You need to turn OFF the AutoPilot first,"
  echo "so that closed channels are not opening up again."
  echo "You find the AutoPilot under the SERVICES section."
  exit 1
fi

# load network and chain info
network=`cat .network`
chain=$(${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo | jq -r '.chain')

command="lncli --chain=${network} closeallchannels --force"

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
chainInSync=$(lncli --chain=${network} getinfo | grep '"synced_to_chain": true' -c)
if [ ${chainInSync} -eq 0 ]; then
  command=""
  result="FAIL PRECHECK - lncli getinfo shows 'synced_to_chain': false - wait until chain is sync "
fi

# execute command
if [ ${#command} -gt 0 ]; then
  ${command}
fi
 
echo ""
echo "OK - please recheck if channels really closed"
sleep 5
