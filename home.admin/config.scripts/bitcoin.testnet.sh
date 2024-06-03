#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# Switches on bitcoind mainnet behind the scenes to testnet."
  echo "# !!! JUST USE FOR DEVELOPEMNT - NOT FOR PRODUCTION !!!"
  echo "# "
  echo "# bitcoin.testnet.sh [activate|revert]"
  echo
  exit 1
fi

# make sure user is root
if [ $UID -ne 0 ]; then
  echo "error='run this script with sudo'"
  exit 1
fi

echo "# Running: bitcoin.testnet.sh $*"

if [ "$1" == "activate" ]; then

  # check if bitcoin testnet is already activated
  testnetSet=$(cat /mnt/hdd/bitcoin/bitcoin.conf | grep -c "^testnet=1")
  if [ $testnetSet -gt 0 ]; then
   echo "error='testnet is already activated'"
   exit 1
  fi

  echo "# SWITCHING TO TESTNET .."

  # make changes to bitcoin.conf
  sed -i 's|^testnet=0|testnet=1|' /mnt/hdd/bitcoin/bitcoin.conf
  sed -i 's/^\(main.debuglogfile=.*\)/#\1/' /mnt/hdd/bitcoin/bitcoin.conf
  sed -i 's|^test.debuglogfile=/mnt/hdd/bitcoin/testnet3/debug.log|test.debuglogfile=/mnt/hdd/bitcoin/debug.log|' /mnt/hdd/bitcoin/bitcoin.conf
  sed -i 's/^\(main.rpcbind=.*\)/#\1/' /mnt/hdd/bitcoin/bitcoin.conf 
  sed -i 's|^test.rpcbind=127.0.0.1:18332|test.rpcbind=127.0.0.1:8332|' /mnt/hdd/bitcoin/bitcoin.conf

  # restart bitcoind service
  systemctl restart bitcoind.service

  echo "# OK bitcoind should now run testnet on mainnet ports"
  echo "# If you want to save space you can delete old mainnet blockchain with:"
  echo "# rm -rf /mnt/hdd/bitcoin/blocks"
  echo "# rm -rf /mnt/hdd/bitcoin/chainstate"

  exit 0
fi

if [ "$1" == "revert" ]; then

  # check if bitcoin testnet is already activated
  testnetSet=$(cat /mnt/hdd/bitcoin/bitcoin.conf | grep -c "^testnet=1")
  if [ $testnetSet -eq 0 ]; then
   echo "error='testnet is not activated'"
   exit 1
  fi

  echo "# SWITCHING BACK TO MAINNET .."

  # make changes to bitcoin.conf
  sed -i 's|^testnet=1|testnet=0|' /mnt/hdd/bitcoin/bitcoin.conf
  sed -i 's|^#main.debuglogfile=.*|main.debuglogfile=/mnt/hdd/bitcoin/debug.log|' /mnt/hdd/bitcoin/bitcoin.conf
  sed -i 's|^test.debuglogfile=/mnt/hdd/bitcoin/debug.log|test.debuglogfile=/mnt/hdd/bitcoin/testnet3/debug.log|' /mnt/hdd/bitcoin/bitcoin.conf
  sed -i 's|^#main.rpcbind=.*|main.rpcbind=127.0.0.1:8332|' /mnt/hdd/bitcoin/bitcoin.conf
  sed -i 's|^test.rpcbind=127.0.0.1:8332|test.rpcbind=127.0.0.1:18332|' /mnt/hdd/bitcoin/bitcoin.conf

  # restart bitcoind service
  systemctl restart bitcoind.service

  echo "# OK bitcoind should now run normal mainnet again"
  echo "# If you want to save space you can delete old testnet blockchain with:"
  echo "# rm -rf /mnt/hdd/bitcoin/testnet3/blocks"
  echo "# rm -rf /mnt/hdd/bitcoin/testnet3/chainstate"

  exit 0
fi

echo "error='unkown parameter'"
exit 1