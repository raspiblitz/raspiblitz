#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "monitor and troubleshot the c-lightning network"
 echo "cl.monitor.sh [mainnet|testnet|signet] status"
 echo "cl.monitor.sh [mainnet|testnet|signet] config"
 echo "cl.monitor.sh [mainnet|testnet|signet] info"
 echo "cl.monitor.sh [mainnet|testnet|signet] wallet"
 echo "cl.monitor.sh [mainnet|testnet|signet] channels"
 echo "cl.monitor.sh [mainnet|testnet|signet] fees"
 exit 1
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='run as root'"
  exit 1
fi

# set based on network type (using own mapping to be able to run without calling sudo -u bitcoin)
if [ "$1" == "mainnet" ]; then
  clHomeDir="/home/bitcoin/.lightning"
  lightningcli_alias="sudo /usr/local/bin/lightning-cli --lightning-dir=${clHomeDir} --conf=${clHomeDir}/config"
  blockchainHeightKey="btc_blocks_verified"
  netprefix=""
elif [ "$1" == "testnet" ]; then
  clHomeDir="/home/bitcoin/.lightning/testnet"
  lightningcli_alias="sudo /usr/local/bin/lightning-cli --lightning-dir=${clHomeDir} --conf=${clHomeDir}/config"
  blockchainHeightKey="btc_testnet_blocks_verified"
  netprefix="t"
elif [ "$1" == "signet" ]; then
  clHomeDir="/home/bitcoin/.lightning/signet"
  lightningcli_alias="sudo /usr/local/bin/lightning-cli --lightning-dir=${clHomeDir} --conf=${clHomeDir}/config"
  blockchainHeightKey="btc_signet_blocks_verified"
  netprefix="s"
else
  echo "error='not supported net'"
  exit 1
fi

######################################################
# STATUS
# check general status info
######################################################

if [ "$2" = "status" ]; then

  cl_version=$($lightningcli_alias --version 2>/dev/null | cut -d ' ' -f3)
  cl_running=$(systemctl status ${netprefix}lightningd 2>/dev/null | grep -c "active (running)")
  cl_ready="0"
  cl_online="0"
  cl_error_short=""
  cl_error_full=""

  if [ "${cl_running}" != "0" ]; then
    cl_running="1"

    # test connection - record win & fail info
    randStr=$(echo "$RANDOM")
    rm /var/cache/raspiblitz/.cl-${randStr}.out 2>/dev/null
    rm /var/cache/raspiblitz/.cl-${randStr}.error 2>/dev/null
    touch /var/cache/raspiblitz/.cl-${randStr}.out
    touch /var/cache/raspiblitz/.cl-${randStr}.error
    $lightningcli_alias getinfo 1>/var/cache/raspiblitz/.cl-${randStr}.out 2>/var/cache/raspiblitz/.cl-${randStr}.error
    winData=$(cat /var/cache/raspiblitz/.cl-${randStr}.out 2>/dev/null)
    failData=$(cat /var/cache/raspiblitz/.cl-${randStr}.error 2>/dev/null)
    rm /var/cache/raspiblitz/.cl-${randStr}.out
    rm /var/cache/raspiblitz/.cl-${randStr}.error

    # check for errors
    if [ "${failData}" != "" ]; then
      cl_ready="0"
      cl_error_short=""
      cl_error_full=$(echo ${failData} | tr -d "'" | tr -d '"')

    # check results if proof for online
    else
      lnd_ready="1"
      connections=$( echo "${winData}" | grep "num_peers\"" | tr -cd '[[:digit:]]')
      if [ "${connections}" != "" ] && [ "${connections}" != "0" ]; then
        cl_online="1"
      fi
    fi

  fi 

  # print results
  echo "cl_version='${cl_version}'"
  echo "cl_running='${cl_running}'"
  echo "cl_ready='${cl_ready}'"
  echo "cl_online='${cl_online}'"
  echo "cl_error_short='${cl_error_short}'"
  echo "cl_error_full='${cl_error_full}'"

  exit 0
fi   

######################################################
# CONFIG
######################################################

if [ "$2" = "config" ]; then

  # get data
  clConfigData=$(cat $clHomeDir/config)
  if [ "${clConfigData}" == "" ]; then
    echo "error='no config'"
    exit 1
  fi

  # no usesul data to monitor in config yet

  exit 1
fi


######################################################
# INFO
######################################################

if [ "$2" = "info" ]; then

  # raw data demo:
  # sudo /usr/local/bin/lightning-cli --lightning-dir=/home/bitcoin/.lightning --conf=/home/bitcoin/.lightning/config getinfo

  # get data
  ln_getInfo=$($lightningcli_alias getinfo 2>/dev/null)
  if [ "${ln_getInfo}" == "" ]; then
    echo "error='no data'"
    exit 1
  fi

  # parse data
  cl_alias=$(echo "${ln_getInfo}" | grep '"alias":' | cut -d '"' -f4)
  port=$(echo "${ln_getInfo}" | grep '"port":' | cut -d: -f2 | tail -1 | bc)
  pubkey=$(echo "${ln_getInfo}" | grep '"id":' | cut -d '"' -f4)
  address=$(echo "${ln_getInfo}" | grep '.onion' | cut -d '"' -f4)
  if [ ${#address} -eq 0 ]; then
    address=$(echo "${ln_getInfo}" | grep '"ipv4"' -A 1 | tail -1 | cut -d '"' -f4)
  fi
  cl_address="${pubkey}@${address}:${port}"
  cl_tor=$(echo "${cl_address}" | grep -c ".onion")
  cl_channels_pending=$(echo "${ln_getInfo}" | jq -r '.num_pending_channels')
  cl_channels_active=$(echo "${ln_getInfo}" | jq -r '.num_active_channels')
  cl_channels_inactive=$(echo "${ln_getInfo}" | jq -r '.num_inactive_channels')
  cl_channels_total=$(( cl_channels_pending + cl_channels_active + cl_channels_inactive ))
  cl_peers=$(echo "${ln_getInfo}" | jq -r '.num_peers')

  # calculate with cached value if c-lightning is fully synced
  source <(/home/admin/config.scripts/blitz.cache.sh get ${blockchainHeightKey})
  echo "blockchainHeightKey(${!blockchainHeightKey})"
  blockheight="${!blockchainHeightKey}"
  echo "blockheight(${blockheight})"
  cl_sync_height=$(echo "${ln_getInfo}" | jq .blockheight)
  cl_sync_chain=""
  if [ "${blockheight}" != "" ]; then
    if [ ${blockheight} > ${cl_sync_height} ];then
      cl_sync_chain=0
    else
      cl_sync_chain=1
    fi
  fi
  
  # print data
  echo "cl_alias='${cl_alias}'"
  echo "cl_address='${cl_address}'"
  echo "cl_tor='${cl_tor}'"
  echo "cl_sync_chain='${cl_sync_chain}'"
  echo "cl_channels_pending='${cl_channels_pending}'"
  echo "cl_channels_active='${cl_channels_active}'"
  echo "cl_channels_inactive='${cl_channels_inactive}'"
  echo "cl_channels_total='${cl_channels_total}'"
  echo "cl_peers='${cl_peers}'"
  exit 0
  
fi

######################################################
# WALLETS (FUNDS)
######################################################

if [ "$2" = "wallet" ]; then

  # raw data demo:
  # sudo /usr/local/bin/lncli -n=mainnet --rpcserver=localhost:10009 --macaroonpath=/home/bitcoin/.lnd/data/chain/bitcoin/mainnet/readonly.macaroon --tlscertpath=/home/bitcoin/.lnd/tls.cert walletbalance

  # get data
  ln_walletbalance=$($lightningcli_alias walletbalance 2>/dev/null)
  if [ "${ln_walletbalance}" == "" ]; then
    echo "error='no data'"
    exit 1
  fi

  echo "ln_walletbalance(${ln_walletbalance})"

  # parse data
  cl_wallet_confirmed=$(echo "$ln_walletbalance" | jq -r '.confirmed_balance')
  cl_wallet_unconfirmed=$(echo "$ln_walletbalance" | jq -r '.unconfirmed_balance')

  # print data
  echo "cl_wallet_confirmed='${cl_wallet_confirmed}'"
  echo "cl_wallet_unconfirmed='${cl_wallet_unconfirmed}'"
  exit 0

fi

echo "FAIL - Unknown Parameter $2"
exit 1
