#!/bin/bash

# command info
if [ $# -eq 0 ] || [[ "$1" =~ ^(-h|--help|-help)$ ]]; then
  echo "# bitcoin.check.sh prestart [mainnet|testnet|signet]"
  exit 1
fi

# Recover only owner traversal on the two directories used by the default mainnet wallet.
# Run as the same unprivileged account as Bitcoin Core.
if [ "$1" = "recover-wallet-access" ]; then
  if [ "$(id -un)" != bitcoin ]; then
    echo "# FAIL: check wallet access as bitcoin" >&2
    exit 1
  fi
  # O_PATH lets the service inspect its own directory even when the recovered
  # mode lacks traversal. Keep descriptors open across checks and corrections.
  exec python3 - "$2" "$3" <<'PY'
import os
import stat
import sys
from contextlib import ExitStack

mount, expected = sys.argv[1:]
parts = ("app-data", "bitcoin", "wallets", "wallet.dat", "wallet.dat")
position = mount
try:
    with ExitStack() as stack:
        current = os.open(mount, os.O_PATH | os.O_NOFOLLOW | os.O_DIRECTORY)
        stack.callback(os.close, current)
        device = os.fstat(current).st_dev
        if f"{os.major(device)}:{os.minor(device)}" != expected:
            sys.exit("Wallet access: selected DATA mount changed")
        can_repair = True
        for index, name in enumerate(parts):
            position = os.path.join(position, name)
            try:
                child = os.open(name, os.O_PATH | os.O_NOFOLLOW, dir_fd=current)
            except FileNotFoundError:
                if index >= 1:
                    break  # Bitcoin or its optional wallet has not been created.
                raise
            stack.callback(os.close, child)
            entry = os.fstat(child)
            if stat.S_ISLNK(entry.st_mode):
                # Support an accessible, operator-managed link without applying chmod.
                can_repair = False
                child = os.open(name, os.O_PATH, dir_fd=current)
                stack.callback(os.close, child)
                entry = os.fstat(child)
            if entry.st_dev != device:
                can_repair = False
            descriptor = f"/proc/self/fd/{child}"
            if index >= 3 and stat.S_ISREG(entry.st_mode):
                # Validate flat and nested wallet files as the service account.
                # Opening the pinned file read-only leaves its mode and bytes intact.
                os.close(os.open(descriptor, os.O_RDONLY))
                break
            if index == 4 or not stat.S_ISDIR(entry.st_mode):
                raise NotADirectoryError
            if not os.access(descriptor, os.X_OK):
                if index < 2 or not can_repair or entry.st_uid != os.geteuid():
                    raise PermissionError
                os.chmod(descriptor, stat.S_IMODE(entry.st_mode) | stat.S_IXUSR)
                if not os.access(descriptor, os.X_OK):
                    raise PermissionError
            current = child
except OSError:
    sys.exit(f"Wallet access: check read or directory traversal permission for {position}")
PY
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
  sed -i 's/^[[:space:]]*$//g' /mnt/hdd/app-data/bitcoin/bitcoin.conf
  # all double empty lines to single empty lines
  sed -i '/^$/N;/^\n$/D' /mnt/hdd/app-data/bitcoin/bitcoin.conf

  ##### CHECK/SET CONFIG VALUES #####
  case "${CHAIN}" in
    mainnet)
      bitcoinlog_entry="main.debuglogfile"
      bitcoinlog_path="/mnt/hdd/app-data/bitcoin/debug.log"
      ;;
    testnet)
      bitcoinlog_entry="test.debuglogfile"
      bitcoinlog_path="/mnt/hdd/app-data/bitcoin/testnet3/debug.log"
      ;;
    signet)
      bitcoinlog_entry="signet.debuglogfile"
      bitcoinlog_path="/mnt/hdd/app-data/bitcoin/signet/debug.log"
      ;;
  esac

  # make sure entry exists
  echo "# make sure entry(${bitcoinlog_entry}) exists"
  if ! grep -q "^${bitcoinlog_entry}=" /mnt/hdd/app-data/bitcoin/bitcoin.conf; then
    echo "${bitcoinlog_entry}=${bitcoinlog_path}" >> /mnt/hdd/app-data/bitcoin/bitcoin.conf
  fi

  # delete any debuglogfile in app-storage and link to new location in app-data
  rm -f /mnt/hdd/app-storage/bitcoin/debug.log
  ln -s /mnt/hdd/app-data/bitcoin/debug.log /mnt/hdd/app-storage/bitcoin/debug.log

  # make sure entry has the correct value
  echo "# make sure entry(${bitcoinlog_entry}) has the correct value(${bitcoinlog_path})"
  sed -i "s|^${bitcoinlog_entry}=.*|${bitcoinlog_entry}=${bitcoinlog_path}|g" /mnt/hdd/app-data/bitcoin/bitcoin.conf

  # make sure wallet directory entry exists and points to app-data
  echo "# make sure entry(walletdir) is set"
  # remove existing wallet entries first
  sed -i '/^main.walletdir=/d' /mnt/hdd/app-data/bitcoin/bitcoin.conf
  sed -i '/^main.wallet=/d' /mnt/hdd/app-data/bitcoin/bitcoin.conf
  sed -i '/^walletdir=/d' /mnt/hdd/app-data/bitcoin/bitcoin.conf
  sed -i '/^wallet=/d' /mnt/hdd/app-data/bitcoin/bitcoin.conf
  # add wallet entries with correct values
  echo "main.walletdir=/mnt/hdd/app-data/bitcoin/wallets" >> /mnt/hdd/app-data/bitcoin/bitcoin.conf
  echo "main.wallet=wallet.dat" >> /mnt/hdd/app-data/bitcoin/bitcoin.conf

  # remove any data directory entries - is already forced by parameter in bitcoind.service
  echo "# remove any data directory entries"
  sed -i '/^datadir=/d' /mnt/hdd/app-data/bitcoin/bitcoin.conf
  sed -i '/^main.datadir=/d' /mnt/hdd/app-data/bitcoin/bitcoin.conf
  sed -i '/^test.datadir=/d' /mnt/hdd/app-data/bitcoin/bitcoin.conf
  sed -i '/^signet.datadir=/d' /mnt/hdd/app-data/bitcoin/bitcoin.conf   
  
  # remove any whitelist entries (whitebind is used instead)
  sed -i '/^whitelist=/d' /mnt/hdd/app-data/bitcoin/bitcoin.conf

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
