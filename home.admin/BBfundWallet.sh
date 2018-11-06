#!/bin/bash

# load network and chain info
network=`cat .network`
chain=$(${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo | jq -r '.chain')

command="lncli --chain=${network} newaddress np2wkh"

clear
echo "******************************"
echo "Fund your Blockchain Wallet"
echo "******************************"
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
  result=$($command)
fi

# on no result
if [ ${#result} -eq 0 ]; then
  echo "Sorry something went wrong - thats unusual."
  echo ""
  exit 1
fi
 
# when result is available
echo "$result"

# get address from result
address=$( echo "$result" | grep "address" | cut -d '"' -f4)

# prepare coin info
coininfo="REAL Bitcoin"
if [ "$network" = "litecoin" ]; then
  coininfo="REAL Litecoin"
fi
if [ "$chain" = "test" ]; then
  coininfo="TESTNET Bitcoin"
fi

# output info
echo ""
echo "******************************"
echo "TODO"
echo "******************************"
echo "Send ${coininfo} to address --> ${address}"
if [ "$chain" = "test" ]; then
  echo "get some testnet coins from https://testnet-faucet.mempool.co"
fi
echo "Whats next? --> Wait for confirmations. You can use lnbalance for main menu or info on LCD to check if funds have arrived."
echo "If you want your lighting node to open channels automatically, activate the 'Autopilot' under 'Activate/Deactivate Services'"
echo ""
