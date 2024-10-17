#!/bin/bash

# command info
if [ $# -eq 0 ] || [[ "$1" =~ ^(-h|--help|-help)$ ]]; then
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
  if ! [[ "$2" =~ ^(mainnet|testnet|signet)$ ]]; then
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
  case "${CHAIN}" in
    mainnet)
      bitcoinlog_entry="main.debuglogfile"
      bitcoinlog_path="/mnt/hdd/bitcoin/debug.log"
      ;;
    testnet)
      bitcoinlog_entry="test.debuglogfile"
      bitcoinlog_path="/mnt/hdd/bitcoin/testnet3/debug.log"
      ;;
    signet)
      bitcoinlog_entry="signet.debuglogfile"
      bitcoinlog_path="/mnt/hdd/bitcoin/signet/debug.log"
      ;;
  esac

  # make sure entry exists
  echo "# make sure entry(${bitcoinlog_entry}) exists"
  if ! grep -q "^${bitcoinlog_entry}=" /mnt/hdd/bitcoin/bitcoin.conf; then
    echo "${bitcoinlog_entry}=${bitcoinlog_path}" >> /mnt/hdd/bitcoin/bitcoin.conf
  fi

  # make sure entry has the correct value
  echo "# make sure entry(${bitcoinlog_entry}) has the correct value(${bitcoinlog_path})"
  sed -i "s|^${bitcoinlog_entry}=.*|${bitcoinlog_entry}=${bitcoinlog_path}|g" /mnt/hdd/bitcoin/bitcoin.conf

  # make sure bitcoin debug file exists
  echo "# make sure bitcoin debug file exists"
  touch ${bitcoinlog_path}
  chown bitcoin:bitcoin ${bitcoinlog_path}
  chmod 600 ${bitcoinlog_path}

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