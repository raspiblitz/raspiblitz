#!/bin/bash

source <(/home/admin/_cache.sh get \
  state \
  setupPhase \
  network \
  chain \
  lightning \
  codeVersion \
  hostname \
  undervoltageReports \
  hdd_used_info \
  internet_localip \
  internet_public_ip_clean \
  internet_rx \
  internet_tx \
  system_ram_available_mb \
  system_ram_mb \
  system_ups_status \
  system_cpu_load \
  system_temp_celsius \
  system_temp_fahrenheit \
  runBehindTor \
  ups \
  ElectRS \
  BTCRPCexplorer \
)

# PARAMETER 1: forcing view on a lightning implementation
PARAMETER_LIGHTNING=$1
if [ "${PARAMETER_LIGHTNING}" == "lnd" ]; then
  lightning="lnd"
fi
if [ "${PARAMETER_LIGHTNING}" == "cl" ]; then
  lightning="cl"
fi
if [ "${PARAMETER_LIGHTNING}" == "none" ]; then
  lightning=""
fi

# PARAMETER 2: forcing view on a given network
PARAMETER_CHAIN=$2
if [ "${PARAMETER_CHAIN}" == "mainnet" ]; then
  chain="main"
fi
if [ "${PARAMETER_CHAIN}" == "testnet" ]; then
  chain="test"
fi
if [ "${PARAMETER_CHAIN}" == "signet" ]; then
  chain="sig"
fi

# generate netprefix
netprefix=${chain:0:1}
if [ "${netprefix}" == "m" ]; then
  netprefix=""
fi

## get UPS info
upsInfo=""
if [ "${system_ups_status}" = "ONLINE" ]; then
  upsInfo="${color_gray}${upsBattery}"
fi
if [ "$system_ups_status}" = "ONBATT" ]; then
  upsInfo="${color_red}${upsBattery}"
fi
if [ "${system_ups_status}" = "SHUTTING DOWN" ]; then
  upsInfo="${color_red}DOWN"
fi

# set colors
color_red='\033[0;31m'
color_green='\033[0;32m'
color_amber='\033[0;33m'
color_yellow='\033[1;93m'
color_gray='\033[0;37m'

# check hostname
if [ ${#hostname} -eq 0 ]; then hostname="raspiblitz"; fi

# for oldnodes
if [ ${#network} -eq 0 ]; then
  network="bitcoin"
fi
if [ ${#chain} -eq 0 ]; then
  chain="main"
fi

# ram info string
ram=$(printf "%sM / %sM" "${system_ram_available_mb}" "${system_ram_mb}")
if [ "${system_ram_available_mb}" != "" ] && [ ${system_ram_available_mb} -lt 50 ]; then
  color_ram="${color_red}\e[7m"
else
  color_ram=${color_green}
fi

# Tor info string
torInfo=""
if [ "${runBehindTor}" = "on" ]; then
  torInfo="+ Tor"
fi

#######################
# BITCOIN INFO

# get block data - use meta on cache to call dynamic variable name
source <(/home/admin/_cache.sh meta btc_${chain}net_blocks_headers)
btc_blocks_headers="${value}"
source <(/home/admin/_cache.sh meta btc_${chain}net_blocks_verified)
btc_blocks_verified="${value}"
source <(/home/admin/_cache.sh meta btc_${chain}net_blocks_behind)
btc_blocks_behind="${value}"
source <(/home/admin/_cache.sh meta btc_${chain}net_sync_percentage)
sync_percentage="${value}%"

blockInfo="${btc_blocks_verified}/${btc_blocks_headers}"
if [ "${btc_blocks_behind}" == "" ]; then 
  sync="WAIT"
  sync_color="${color_yellow}"
elif [ ${btc_blocks_behind} -lt 2 ]; then 
  sync="OK"
  sync_color="${color_green}"
else
  sync=""
  sync_color="${color_red}"
fi

# get address data - use meta on cache to call dynamic variable name
source <(/home/admin/_cache.sh meta btc_${chain}net_peers)
btc_peers=${value}
source <(/home/admin/_cache.sh meta btc_${chain}net_version)
networkVersion=${value}
if 
if [ "${btc_peers}" != "" ] && [  ${btc_peers} -gt 0 ]; then
  networkConnectionsInfo="${color_green}${btc_peers} ${color_gray}peers"
else
  networkConnectionsInfo="${color_red}${btc_peers} ${color_gray}peers"
fi

