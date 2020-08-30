#!/bin/bash
#
bitcoind_uptime=$(ps -p `pidof bitcoind` -o etimes='' 2>/dev/null | tr -d '[:space:]')
     lnd_uptime=$(ps -p `pidof      lnd` -o etimes='' 2>/dev/null | tr -d '[:space:]')
 electrs_uptime=$(ps -p `pidof  electrs` -o etimes='' 2>/dev/null | tr -d '[:space:]')
#
echo "service-uptime,service=bitcoind uptime=${bitcoind_uptime}"
echo "service-uptime,service=lnd uptime=${lnd_uptime}"
echo "service-uptime,service=electrs uptime=${electrs_uptime}"
# -eof-
