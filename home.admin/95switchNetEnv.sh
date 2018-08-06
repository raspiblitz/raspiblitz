#!/usr/bin/env bash
BITCOIN_CONFIG="/home/bitcoin/.bitcoin/bitcoin.conf"
LND_CONFIG="/home/bitcoin/.lnd/lnd.conf"
# function to detect main/testnet

function isMainnet(){
	grep "^#testnet=1$" -q $BITCOIN_CONFIG  && return 1
	return 0
}

function switchToMainnet {
	echo "switching to mainnet"
	sed -i 's/^testnet=1/#testnet=1/g' $BITCOIN_CONFIG && \
	sed -i 's/^bitcoin.testnet=1/#bitcoin.testnet=1/g' $LND_CONFIG && \
	sed -i 's/^#bitcoin.mainnet=1/bitcoin.mainnet=1/g' $LND_CONFIG
	echo "switched to mainnet"
}

function switchToTestnet {
	echo "switching to testnet"
	sed -i 's/^#testnet=1/testnet=1/g' $BITCOIN_CONFIG && \
	sed -i 's/^#bitcoin.testnet=1/bitcoin.testnet=1/g' $LND_CONFIG && \
	sed -i 's/^bitcoin.mainnet=1/#bitcoin.mainnet=1/g' $LND_CONFIG
	echo "switched to testnet"
}

# change to test: check both configs for commented out testnet arguments and mainnet
echo "stopping lnd client"
systemctl stop lnd
sleep 4
echo "stopping bitcoind client"
systemctl stop bitcoind
sleep 4
isMainnet
if [ $? -eq 1 ]; then
	echo "switching from mainnet to testnet"
	switchToTestnet
else
	echo "switching from testnet to mainnet"
	switchToMainnet
fi
echo "copying over config to bitcoin user"
cp $BITCOIN_CONFIG /home/admin/.bitcoin/
systemctl start bitcoind
echo "started bitcoind back up, giving it a minute to come up"
sleep 60
systemctl start lnd
echo "started lnd back up, giving it a minute, you will have to unlock your wallet"
sleep 60
echo "finished config switch - started back up"
echo "you will still have to unlock your LND wallet"
./00mainMenu.sh