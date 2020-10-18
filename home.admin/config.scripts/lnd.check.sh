#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "# script to check LND states"
  echo "# lnd.check.sh basic-setup"
  exit 1
fi

# load raspiblitz conf
source /mnt/hdd/raspiblitz.conf

# check basic LND setup
if [ "$1" == "basic-setup" ]; then

  # check TLS exits
  tlsExists=$(sudo ls /mnt/hdd/lnd/tls.cert 2>/dev/null | grep -c 'tls.cert')
  if [ ${tlsExists} -gt 0 ]; then
    echo "tls=1"
  else
    echo "tls=0"
    echo "err='tls.cert is missing in /mnt/hdd/lnd'"
  fi
  # check TLS exits (on SD card for admin)
  tlsExists=$(sudo ls /home/admin/.lnd/tls.cert 2>/dev/null | grep -c 'tls.cert')
  if [ ${tlsExists} -gt 0 ]; then
    echo "tlsCopy=1"
    # check if the same
    orgChecksum=$(sudo shasum -a 256 /mnt/hdd/lnd/tls.cert 2>/dev/null | cut -d " " -f1)
    cpyChecksum=$(sudo shasum -a 256 /home/admin/.lnd/tls.cert 2>/dev/null | cut -d " " -f1)
    if [ "${orgChecksum}" == "${cpyChecksum}" ]; then
      echo "tlsMismatch=0"
    else
      echo "tlsMismatch=1"
      echo "err='tls.cert for user admin is old'"
    fi
  else
    echo "tlsCopy=0"
    echo "tlsMismatch=0"
    echo "err='tls.cert is missing for user admin'"
  fi

  # check lnd.conf exits
  lndConfExists=$(sudo ls /mnt/hdd/lnd/lnd.conf 2>/dev/null | grep -c 'lnd.conf')
  if [ ${lndConfExists} -gt 0 ]; then
    echo "config=1"
  else
    echo "config=0"
    echo "err='lnd.conf is missing in /mnt/hdd/lnd'"
  fi
  # check lnd.conf exits (on SD card for admin)
  lndConfExists=$(sudo ls /home/admin/.lnd/lnd.conf 2>/dev/null | grep -c 'lnd.conf')
  if [ ${lndConfExists} -gt 0 ]; then
    echo "configCopy=1"
    # check if the same
    orgChecksum=$(sudo shasum -a 256 /mnt/hdd/lnd/lnd.conf 2>/dev/null | cut -d " " -f1)
    cpyChecksum=$(sudo shasum -a 256 /home/admin/.lnd/lnd.conf 2>/dev/null | cut -d " " -f1)
    if [ "${orgChecksum}" == "${cpyChecksum}" ]; then
      echo "configMismatch=0"
    else
      echo "configMismatch=1"
      echo "err='lnd.conf for user admin is old'"
    fi
  else
    echo "configCopy=0"
    echo "configMismatch=0"
    echo "err='lnd.conf is missing for user admin'"
  fi

  # get network from config (BLOCKCHAIN)
  lndNetwork=""
  source <(sudo cat /mnt/hdd/lnd/lnd.conf 2>/dev/null | grep 'bitcoin.active' | sed 's/^[a-z]*\./bitcoin_/g')
  source <(sudo cat /mnt/hdd/lnd/lnd.conf 2>/dev/null | grep 'litecoin.active' | sed 's/^[a-z]*\./litecoin_/g')
  if [ "${bitcoin_active}" == "1" ] && [ "${litecoin_active}" == "1" ]; then
    echo "err='lnd.conf: bitcoin and litecoin are set active at the same time'"
  elif [ "${bitcoin_active}" == "1" ]; then
    lndNetwork="bitcoin"
  elif [ "${litecoin_active}" == "1" ]; then
    lndNetwork="litecoin"
  else
    echo "err='lnd.conf: no blockchain network is set'"
  fi
  echo "network='${lndNetwork}'"

  # check if network is same the raspiblitz config
  if [ "${network}" != "${lndNetwork}" ]; then
    echo "err='lnd.conf: blockchain network in lnd.conf (${lndNetwork}) is different from raspiblitz.conf (${network})'"
  fi

  # get chain from config (TESTNET / MAINNET)
  lndChain=""
  source <(sudo cat /mnt/hdd/lnd/lnd.conf 2>/dev/null | grep "${lndNetwork}.mainnet" | sed 's/^[a-z]*\.//g')
  source <(sudo cat /mnt/hdd/lnd/lnd.conf 2>/dev/null | grep "${lndNetwork}.testnet" | sed 's/^[a-z]*\.//g')
  if [ "${mainnet}" == "1" ] && [ "${testnet}" == "1" ]; then
    echo "err='lnd.conf: mainnet and testnet are set active at the same time'"
  elif [ "${mainnet}" == "1" ]; then
    lndChain="main"
  elif [ "${testnet}" == "1" ]; then
    lndChain="test"
  else
    echo "err='lnd.conf: neither testnet or mainnet is set active (raspiblitz needs one of them active in lnd.conf)'"
  fi
  echo "chain='${lndChain}'"

  # check if chain is same the raspiblitz config
  if [ "${chain}" != "${lndChain}" ]; then
    echo "err='lnd.conf: testnet/mainnet in lnd.conf (${lndChain}) is different from raspiblitz.conf (${chain})'"
  fi

  # check for admin macaroon exist (on HDD)
  adminMacaroonExists=$(sudo ls /mnt/hdd/lnd/data/chain/${network}/${chain}net/admin.macaroon 2>/dev/null | grep -c 'admin.macaroon')
  if [ ${adminMacaroonExists} -gt 0 ]; then
    echo "macaroon=1"
  else
    echo "macaroon=0"
    echo "err='admin.macaroon is missing in /mnt/hdd/lnd/data/chain/${network}/${chain}net'"
  fi
  # check for admin macaroon exist (on SD card for admin)
  adminMacaroonExists=$(sudo ls /home/admin/.lnd/data/chain/${network}/${chain}net/admin.macaroon 2>/dev/null | grep -c 'admin.macaroon')
  if [ ${adminMacaroonExists} -gt 0 ]; then
    echo "macaroonCopy=1"
    # check if the same
    orgChecksum=$(sudo shasum -a 256 /mnt/hdd/lnd/data/chain/${network}/${chain}net/admin.macaroon 2>/dev/null | cut -d " " -f1)
    cpyChecksum=$(sudo shasum -a 256 /home/admin/.lnd/data/chain/${network}/${chain}net/admin.macaroon 2>/dev/null | cut -d " " -f1)
    if [ "${orgChecksum}" == "${cpyChecksum}" ]; then
      echo "macaroonMismatch=0"
    else
      echo "macaroonMismatch=1"
      echo "err='admin.macaroon for user admin is old'"
    fi
  else
    echo "macaroonCopy=0"
    echo "macaroonMismatch=0"
    echo "err='admin.macaroon is missing for user admin"
  fi

  # check for walletDB exist
  walletExists=$(sudo ls /mnt/hdd/lnd/data/chain/${network}/${chain}net/wallet.db 2>/dev/null | grep -c 'wallet.db')
  if [ ${walletExists} -gt 0 ]; then
    echo "wallet=1"
  else
    echo "wallet=0"
  fi

  # check that RPC USER between Bitcoin and LND is correct
  rpcusercorrect=0
  source <(sudo cat /mnt/hdd/lnd/lnd.conf 2>/dev/null | grep "${lndNetwork}d.rpcuser" | sed 's/^[a-z]*\./lnd/g')
  source <(sudo cat /mnt/hdd/${lndNetwork}/${lndNetwork}.conf 2>/dev/null | grep "rpcuser" | sed 's/^[a-z]*\./lnd/g')
  if [ ${#lndrpcuser} -eq 0 ]; then
    echo "err='lnd.conf: missing ${lndNetwork}d.rpcuser (needs to be same as set in ${lndNetwork}.conf)'"
  elif [ ${#rpcuser} -eq 0 ]; then
    echo "err='${lndNetwork}.conf: missing rpcuser (needs to be same as set in lnd.conf)'"
  elif [ "${rpcuser}" != "${lndrpcuser}" ]; then
    echo "err='${lndNetwork}.conf (${rpcuser}) & lnd.conf (${lndrpcuser}): RPC user missmatch! - LND cannot connect to blockchain RPC'"
  else
    # OK looks good
    rpcusercorrect=1
  fi
  echo "rpcusercorrect=${rpcusercorrect}"

  # check that RPC PASSWORD between Bitcoin and LND is correct
  rpcpasscorrect=0
  source <(sudo cat /mnt/hdd/lnd/lnd.conf 2>/dev/null | grep "${lndNetwork}d.rpcpass" | sed 's/^[a-z]*\./lnd/g')
  source <(sudo cat /mnt/hdd/${lndNetwork}/${lndNetwork}.conf 2>/dev/null | grep "rpcpassword" | sed 's/^[a-z]*\./lnd/g')
  if [ ${#lndrpcpass} -eq 0 ]; then
    echo "err='lnd.conf: missing ${lndNetwork}d.rpcpass (needs to be same as set in ${lndNetwork}.conf)'"
  elif [ ${#rpcpassword} -eq 0 ]; then
    echo "err='${lndNetwork}.conf: missing rpcpassword (needs to be same as set in lnd.conf)'"
  elif [ "${rpcpassword}" != "${lndrpcpass}" ]; then
    echo "err='${lndNetwork}.conf (${rpcpassword}) & lnd.conf (${lndrpcpass}): RPC password missmatch! - should autofix on reboot'"
  else
    # OK looks good
    rpcpasscorrect=1
  fi
  echo "rpcpasscorrect=${rpcpasscorrect}"

  # check basic LND logs
  torConnectionProblem=$(sudo journalctl -u lnd -b --no-pager -n14 | grep "lnd\[" | grep -c "dial tcp 127.0.0.1:9050: connect: connection refused")
  if [ ${torConnectionProblem} -gt 0 ]; then
    echo "err='Tor tcp connection refused'"
  fi

else
  echo "# FAIL: parameter not known - run with -h for help"
  exit 1
fi
