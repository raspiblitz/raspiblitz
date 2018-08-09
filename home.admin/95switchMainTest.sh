#!/usr/bin/env bash
# based on pull request from vnnkl

# load network
network=`cat .network`

echo ""
echo "*** Switch between Testnet/Mainnet ***"

# allow only on bitcoin network
if [ "${network}" = "bitcoin" ]; then
  echo "Bitcoin network can be switched between testnet/mainnet ..."
else 
  echo "FAIL - Only Bitcoin Network can be switched between man/tast at the moment."
  exit 1
fi

NETWORK_CONFIG="/home/bitcoin/.${network}/${network}.conf"
NETWORK_TEMPLATE="/home/admin/assets/${network}.conf"
LND_CONFIG="/home/bitcoin/.lnd/lnd.conf"
LND_TEMPLATE="/home/admin/assets/lnd.${network}.conf"
echo "NETWORK_CONFIG(${NETWORK_CONFIG})"
echo "LND_CONFIG(${LND_CONFIG})"
echo "NETWORK_TEMPLATE(${NETWORK_TEMPLATE})"
echo "LND_TEMPLATE(${LND_TEMPLATE})"

# function to detect main/testnet
function isMainnet(){
	grep "^#testnet=1$" -q $NETWORK_CONFIG && return 1
	return 0
}

function switchToMainnet {
	echo "switching to mainnet"
	sed -i "s/^testnet=1/#testnet=1/g" $NETWORK_CONFIG 
	sed -i "s/^testnet=1/#testnet=1/g" $NETWORK_TEMPLATE 
  sed -i "s/^#mainnet=1/mainnet=1/g" $NETWORK_CONFIG 
	sed -i "s/^#mainnet=1/mainnet=1/g" $NETWORK_TEMPLATE 
	sed -i "s/^${network}.testnet=1/#${network}.testnet=1/g" $LND_CONFIG 
	sed -i "s/^#${network}.mainnet=1/${network}.mainnet=1/g" $LND_CONFIG
	sed -i "s/^${network}.testnet=1/#${network}.testnet=1/g" $LND_TEMPLATE 
	sed -i "s/^#${network}.mainnet=1/${network}.mainnet=1/g" $LND_TEMPLATE 
	echo "OK switched to mainnet"
}

function switchToTestnet {
	echo "switching to testnet"
	sed -i "s/^#testnet=1/testnet=1/g" $NETWORK_CONFIG 
	sed -i "s/^#testnet=1/testnet=1/g" $NETWORK_TEMPLATE 
  sed -i "s/^mainnet=1/#mainnet=1/g" $NETWORK_CONFIG 
	sed -i "s/^mainnet=1/#mainnet=1/g" $NETWORK_TEMPLATE 
	sed -i "s/^#${network}.testnet=1/${network}.testnet=1/g" $LND_CONFIG 
	sed -i "s/^${network}.mainnet=1/#${network}.mainnet=1/g" $LND_CONFIG
	sed -i "s/^#${network}.testnet=1/${network}.testnet=1/g" $LND_TEMPLATE 
	sed -i "s/^${network}.mainnet=1/#${network}.mainnet=1/g" $LND_TEMPLATE
	echo "OK switched to testnet"
}

# LND Service
lndInstalled=$(systemctl status lnd.service | grep loaded -c)
if [ ${lndInstalled} -gt 0 ]; then

  echo "check for open channels"
  openChannels=$(sudo -u bitcoin lncli listchannels 2>/dev/null | grep chan_id -c)
  if [ ${openChannels} -gt 0 ]; then
    echo ""
    echo "!!!!!!!!!!!!!!!!!!!"
    echo "FAIL - You have still open channels and could loose funds !! - close those first with lncli closeallchannels"
    echo "!!!!!!!!!!!!!!!!!!!"
    exit 1
  else
    echo "no open channels found"
  fi

  echo "stopping lnd client"
  systemctl stop lnd
  sleep 4

else
  echo "LND not running"
fi

# NETWORK Service
networkInstalled=$(systemctl status ${network}d.service | grep loaded -c)
if [ ${networkInstalled} -gt 0 ]; then
  echo "stopping bitcoind client"
  systemctl stop bitcoind
  sleep 4
else
  echo "Network ${network} not running"
fi

# TURN THE SWITCH
isMainnet
if [ $? -eq 1 ]; then
	echo "switching from mainnet to testnet"
	switchToTestnet
else
	echo "switching from testnet to mainnet"
	switchToMainnet
fi


echo "copying over config to bitcoin user"
cp $NETWORK_CONFIG /home/admin/.${network}/
 
# restarting network
if [ ${networkInstalled} -gt 0 ]; then
  
  # start network
  systemctl start bitcoind
  echo "started ${network}d back up, giving it a 120 SECONDS to prepare"
  sleep 120

  # set setup info again
  echo "60" > /home/admin/.setup

  # run again the complete LND init procedure
  ./70initLND.sh

else
  echo "No starting of network, because it was not running before"
fi