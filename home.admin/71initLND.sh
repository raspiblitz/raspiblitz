#!/bin/bash

# CHECK 1: BITCOIND is running correctly
# - systemd says its running

# CHECK 2: LND is running correctly
# - systemd says its running
# - TLS.cert was created

# CHECK 3: Does LND wallet already exists
# - yes: Jump to next point or ask to delete
# 
# sudo rm /mnt/hdd/lnd/data/chain/bitcoin/mainnet/wallet.db

# UI: Ask if user wants NEW wallet or RECOVER a wallet

source lnd/bin/activate
python /home/admin/config.scripts/lnd.initwallet.py new 12345678