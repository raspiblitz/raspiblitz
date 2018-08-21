#!/bin/sh

# load network
network=`cat .network`

echo ""
echo "****************************************************************************"
echo "Unlock LND Wallet --> lncli unlock"
echo "****************************************************************************"
echo "HELP: Enter your PASSWORD C"
echo "****************************************************************************"
while :
  do
    chain="$(${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo | jq -r '.chain')"
    sudo -u bitcoin /usr/local/bin/lncli unlock
    sleep 4
    locked=$(sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log | grep -c unlock)
    if [ ${locked} -eq 0  ]; then
      break
    fi

    echo ""
    echo "network(${network}) chain(${chain})"
    sudo tail -n 1 /mnt/hdd/lnd/logs/${network}/${chain}net/lnd.log
    echo "Wallet still locked - please try again or Cancel with CTRL+C"
  done
