#!/bin/bash

# CHECK 1: BITCOIND is running correctly
# - systemd says its running

# CHECK 2: LND is running correctly
# - systemd says its running
# - TLS.cert was created

source lnd/bin/activate
python /home/admin/config.scripts/lnd.initwallet.sh ahdahdkash