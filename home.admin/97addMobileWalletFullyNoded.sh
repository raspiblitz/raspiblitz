#!/bin/bash
clear

./config.scripts/network.wallet.sh on
./config.scripts/network.txindex.sh on
./config.scripts/internet.hiddenservice.sh bitcoinrpc 8332 8332

whiptail --title 'Connect Fully Noded' --yes-button='Show QR code' --no-button='Cancel' --yesno "
Find the links to download Fully Noded here:
https://github.com/Fonta1n3/FullyNoded#join-the-testflight\n
                       ***WARNING*** \n
The QR code to allow connecting to your node remotely will show on your computer screen.\
 Be aware of the windows, cameras, mirrors and bystanders!
" 15 62

if [ $? -eq 0 ]; then
  # extract RPC credentials from bitcoin.conf - store only in var
  RPC_USER=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcuser | cut -c 9-)
  PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
  hiddenService=$(sudo cat /mnt/hdd/tor/bitcoinrpc/hostname)
  
  # btcstandup://<rpcuser>:<rpcpassword>@<hidden service hostname>:<hidden service port>/?label=<optional node label> 
  quickConnect="btcstandup://$RPC_USER:$PASSWORD_B@$hiddenService:8332/?label=$hostname"
  echo ""
  echo "scan the QR Code with Fully Noded to connect to your node:"
  qrencode -t ANSI256 $quickConnect
  echo "Press ENTER to return to the menu"
  read key
else
  ech0 "pairing cancelled"
  exit0
fi