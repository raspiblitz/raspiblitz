#!/bin/bash

# Check if lnd is synced to chain and channels are open
# If it isn't, wait until it is
# exits with 1 if it isn't.

network=$1
chain=$2

# check if chain is in sync
cmdChainInSync="lncli --chain=${network} --network=${chain}net getinfo | grep '"synced_to_chain": true' -c"
chainInSync=${cmdChainInSync}
while [ $chainInSync -eq 0 ]; do
  dialog --title "Fail: not in sync" \
	 --ok-label "Try now" \
	 --cancel-label "Give up" \
	 --pause "\n\n'lncli getinfo' shows 'synced_to_chain': false\n\nTry again in a few seconds." 15 60 5
  
  if [ $? -gt 0 ]; then
      exit 1
  fi
  chainInSync=${cmdChainInSync}
done

# check number of connected peers
echo "check for open channels"
openChannels=$(sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net listchannels 2>/dev/null | grep chan_id -c)
if [ ${openChannels} -eq 0 ]; then
  echo ""
  echo "!!!!!!!!!!!!!!!!!!!"
  echo "FAIL - You have NO ESTABLISHED CHANNELS .. open a channel first."
  echo "!!!!!!!!!!!!!!!!!!!"
  echo ""
  exit 1
fi

exit 0
