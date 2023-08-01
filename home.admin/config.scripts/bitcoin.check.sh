#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "-help" ]; then
  echo "# bitcoin.check.sh prestart [mainnet|testnet|signet]"
  exit 1
fi

######################################################################
# PRESTART
# is executed by systemd bitcoind services everytime before bitcoin is started
# so it tries to make sure the config is in valid shape
######################################################################

# check/repair lnd config before starting
if [ "$1" == "prestart" ]; then

  echo "### RUNNING bitcoin.check.sh prestart"

  # check correct user
  if [ "$USER" != "bitcoin" ]; then
    echo "# FAIL: run as user 'bitcoin'"
    exit 1
  fi

  # check correct parameter
  if [ "$2" != "mainnet" ] && [ "$2" != "testnet" ] && [ "$2" != "signet" ]; then
    echo "# FAIL: missing/wrong parameter"
    exit 1
  fi

  CHAIN="$2"

  ##### DIRECTORY PERMISSIONS #####

  /bin/chgrp bitcoin /mnt/hdd/bitcoin

  ##### CLEAN UP #####

  # all lines with just spaces to empty lines
  sed -i 's/^[[:space:]]*$//g' /mnt/hdd/bitcoin/bitcoin.conf
  # all double empty lines to single empty lines
  sed -i '/^$/N;/^\n$/D' /mnt/hdd/bitcoin/bitcoin.conf

  ##### CHECK/SET CONFIG VALUES #####

  # correct debug log path
  if [ "${CHAIN}" == "mainnet" ]; then
    bitcoinlog_entry="main.debuglogfile"
    bitcoinlog_path="/mnt/hdd/bitcoin/debug.log"
  elif [ "${CHAIN}" == "testnet" ]; then
    bitcoinlog_entry="test.debuglogfile"
    bitcoinlog_path="/mnt/hdd/bitcoin/testnet3/debug.log"
  elif [ "${CHAIN}" == "signet" ]; then
    bitcoinlog_entry="signet.debuglogfile"
    bitcoinlog_path="/mnt/hdd/bitcoin/signet/debug.log"
  fi

  # make sure entry exists
  echo "# make sure entry(${bitcoinlog_entry}) exists"
  extryExists=$(grep -c "^${bitcoinlog_entry}=" /mnt/hdd/bitcoin/bitcoin.conf)
  if [ "${extryExists}" == "0" ]; then
    echo "${bitcoinlog_entry}=${bitcoinlog_path}" >> /mnt/hdd/bitcoin/bitcoin.conf
  fi

  # make sure entry has the correct value
  echo "# make sure entry(${bitcoinlog_entry}) has the correct value(${bitcoinlog_path})"
  sed -i "s|^${bitcoinlog_entry}=.*|${bitcoinlog_entry}=${bitcoinlog_path}|g" /mnt/hdd/bitcoin/bitcoin.conf

  ##### STATISTICS #####

  # count startings
  if [ "${CHAIN}" == "mainnet" ]; then
    /home/admin/config.scripts/blitz.systemd.sh log blockchain STARTED
  fi

  echo "# OK PRESTART DONE"

else
  echo "# FAIL: parameter not known - run with -h for help"
  exit 1
fi
