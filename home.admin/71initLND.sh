#!/bin/bash

# CHECK 1: BITCOIND is running correctly
# - systemd says its running

# CHECK 2: LND is running correctly
# - systemd says its running
# - TLS.cert was created

# UI: Ask if user wants NEW wallet or RECOVER a wallet


source lnd/bin/activate
python /home/admin/config.scripts/lnd.initwallet.py new ahdahdkash