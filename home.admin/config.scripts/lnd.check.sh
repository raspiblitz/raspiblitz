#!/bin/bash

if [ $# -eq 0 ]; then
 echo "# script to check LND states"
 echo "# lnd.check.sh basic-setup"
 exit 1
fi

if [ "$1" == "basic-setup" ]; then

   # check TLS exits
  tlsExists=$(sudo ls /mnt/hdd/lnd/tls.cert | grep -c 'tls.cert')
  if [ ${tlsExists} -gt 0 ]; then
    echo "tls=1"
  else
    echo "tls=0"
  fi

  # check lnd.conf exits
  lndConfExists=$(sudo ls /mnt/hdd/lnd/lnd.conf | grep -c 'lnd.conf')
  if [ ${lndConfExists} -gt 0 ]; then
    echo "config=1"
  else
    echo "config=0"
  fi

  # load config values
  source <(sudo sed -e 's/\[/#/g' /mnt/hdd/lnd/lnd.conf)
  echo "debuglevel=${debuglevel}"
  echo "bitcoin.mainnet=${bitcoin.mainnet}"
  echo "bitcoin.testnet=${bitcoin.testnet}"

else
  echo "# FAIL: parameter not known"
fi