#!/bin/bash
clear

# load raspiblitz config data
source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

# make sure txindex and wallet of bitcoin is on
/home/admin/config.scripts/network.wallet.sh on
/home/admin/config.scripts/network.txindex.sh on

# extract RPC credentials from bitcoin.conf - store only in var
RPC_USER=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)

if [ "${chain}net" == "mainnet" ]; then
  BITCOINRPCPORT=8332
elif [ "${chain}net" == "testnet" ]; then
  BITCOINRPCPORT=18332
elif [ "${chain}net" == "signet" ]; then
  BITCOINRPCPORT=38332
fi

# check and set up the HS    
/home/admin/config.scripts/internet.hiddenservice.sh bitcoin${BITCOINRPCPORT} ${BITCOINRPCPORT} ${BITCOINRPCPORT}

hiddenService=$(sudo cat /mnt/hdd/tor/bitcoin${BITCOINRPCPORT}/hostname)
# https://github.com/rootzoll/raspiblitz/issues/2339
if [ ${#hiddenService} -eq 0 ];then
  hiddenService=$(sudo cat /mnt/hdd/tor/bitcoin/hostname)
fi

echo "# The Hidden Service for bitcoind port ${BITCOINRPCPORT} is:"
echo "${hiddenService}"

# btcstandup://<rpcuser>:<rpcpassword>@<hidden service hostname>:<hidden service port>/?label=<optional node label> 
quickConnect="btcstandup://${RPC_USER}:${PASSWORD_B}@${hiddenService}:${BITCOINRPCPORT}/?label=${hostname}"
echo
echo "scan the QR Code with Fully Noded to connect to your node:"
/home/admin/config.scripts/blitz.display.sh qr "${quickConnect}"
qrencode -t ANSI256 $quickConnect
echo "Press ENTER to return to the menu"
read key

# clean up
/home/admin/config.scripts/blitz.display.sh hide
clear