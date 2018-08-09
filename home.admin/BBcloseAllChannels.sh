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
echo "OK"
sleep 2

openChannels=$(sudo -u bitcoin lncli listchannels 2>/dev/null | grep chan_id -c)
if [ ${openChannels} -gt 0 ]; then
    echo ""
    echo "*******************"
    echo "OK All Channels are closed now."
    echo "You can now switch test/main or update RaspiBlitz safely, as long as you got your CIPHER WORD LIST SEED."
    echo "*******************"
else
  echo "!! WARNING you still have open channels:" 
  lnchannels
fi


