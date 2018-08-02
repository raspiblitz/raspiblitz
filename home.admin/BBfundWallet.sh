#!/bin/bash

# load network and chain info
network=`cat .network`
chain=$(${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo 2>/dev/null | jq -r '.chain')

command="lncli newaddress np2wkh"

clear
echo "******************************"
echo "Fund your Blockchain Wallet"
echo "******************************"
echo ""
echo "COMMAND LINE: "
echo $command
echo ""
echo "RESULT:"

# execute command
result=$($command)

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
  echo "get some testnet coins from https://testnet.manu.backend.hamburg/faucet"
fi
echo "Whats next? --> Wait for confirmations. You can use lnbalance for main menu or info on LCD to check if funds have arrived."
echo ""
