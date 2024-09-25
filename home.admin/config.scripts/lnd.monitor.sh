#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "monitor and troubleshot the lnd network"
 echo "lnd.monitor.sh [mainnet|testnet|signet] status"
 echo "lnd.monitor.sh [mainnet|testnet|signet] config"
 echo "lnd.monitor.sh [mainnet|testnet|signet] info"
 echo "lnd.monitor.sh [mainnet|testnet|signet] wallet"
 echo "lnd.monitor.sh [mainnet|testnet|signet] channels"
 echo "lnd.monitor.sh [mainnet|testnet|signet] fees"
 exit 1
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='run as root'"
  exit 1
fi

# base directory of lnd
lndHomeDir="/home/bitcoin/.lnd"

# set based on network type (using own mapping to be able to run without calling sudo -u bitcoin)
if [ "$1" == "mainnet" ]; then
  lndcli_alias="/usr/local/bin/lncli -n=mainnet --rpcserver=localhost:10009 --macaroonpath=${lndHomeDir}/data/chain/bitcoin/mainnet/readonly.macaroon --tlscertpath=${lndHomeDir}/tls.cert"
  netprefix=""
elif [ "$1" == "testnet" ]; then
  lndcli_alias="/usr/local/bin/lncli -n=testnet --rpcserver=localhost:11009 --macaroonpath=${lndHomeDir}/data/chain/bitcoin/testnet/readonly.macaroon --tlscertpath=${lndHomeDir}/tls.cert"
  netprefix="t"
elif [ "$1" == "signet" ]; then
  lndcli_alias="/usr/local/bin/lncli -n=signet --rpcserver=localhost:13009 --macaroonpath=${lndHomeDir}/data/chain/bitcoin/signet/readonly.macaroon --tlscertpath=${lndHomeDir}/tls.cert"
  netprefix="s"
else
  echo "error='not supported net'"
  exit 1
fi

# general info on the lnd service
lnd_running=$(systemctl show ${netprefix}lnd --property=ActiveState 2>/dev/null | grep -c "=active")
lnd_locked=$(systemctl show ${netprefix}lnd --property=StatusText 2>/dev/null | grep -c "Wallet locked")
echo "ln_lnd_running='${lnd_running}'"
echo "ln_lnd_locked='${lnd_locked}'"

######################################################
# STATUS
# check general status info
######################################################

if [ "$2" = "status" ]; then

  lnd_version=$($lndcli_alias --version 2>/dev/null | cut -d ' ' -f3)
  lnd_locked="0"
  lnd_ready="0"
  lnd_online="0"
  lnd_error_short=""
  lnd_error_full=""

  if [ "${lnd_running}" != "0" ]; then
    lnd_running="1"
    # only if wallet is not locked get more info
    if [ ${lnd_locked} -eq 0 ]; then
      # test connection - record win & fail info
      randStr=$(echo "$RANDOM")
      rm /var/cache/raspiblitz/.lnd-${randStr}.out 2>/dev/null
      rm /var/cache/raspiblitz/.lnd-${randStr}.error 2>/dev/null
      touch /var/cache/raspiblitz/.lnd-${randStr}.out
      touch /var/cache/raspiblitz/.lnd-${randStr}.error
      echo "# $lndcli_alias getinfo"
      $lndcli_alias getinfo 1>/var/cache/raspiblitz/.lnd-${randStr}.out 2>/var/cache/raspiblitz/.lnd-${randStr}.error
      winData=$(cat /var/cache/raspiblitz/.lnd-${randStr}.out 2>/dev/null)
      failData=$(cat /var/cache/raspiblitz/.lnd-${randStr}.error 2>/dev/null)
      rm /var/cache/raspiblitz/.lnd-${randStr}.out
      rm /var/cache/raspiblitz/.lnd-${randStr}.error

      # check for errors
      if [ "${failData}" != "" ]; then
        lnd_ready="0"

        # store error messages 
        lnd_error_short=""
        lnd_error_full=$(echo ${failData} | tr -d "'" | tr -d '"')

        # check if error because wallet is locked
        if [ $(echo "${failData}" | grep -c "wallet locked") -gt 0 ]; then
          # signal wallet locked
          lnd_locked="1"
          # dont report it as error
          lnd_error_short=""
          lnd_error_full=""
        fi

      # check results if proof for online
      else
        lnd_ready="1"
        connections=$( echo "${winData}" | grep "num_peers\"" | tr -cd '[[:digit:]]')
        if [ "${connections}" != "" ] && [ "${connections}" != "0" ]; then
          lnd_online="1"
        fi
      fi
    fi  
  fi 

  # print results
  echo "ln_lnd_version='${lnd_version}'"
  echo "ln_lnd_running='${lnd_running}'"
  echo "ln_lnd_ready='${lnd_ready}'"
  echo "ln_lnd_online='${lnd_online}'"
  echo "ln_lnd_locked='${lnd_locked}'"
  echo "ln_lnd_error_short='${lnd_error_short}'"
  echo "ln_lnd_error_full='${lnd_error_full}'"

  exit 0
fi   

######################################################
# CONFIG
######################################################

if [ "$2" = "config" ]; then

  # get data
  lndConfigData=$(cat "${lndHomeDir}/${netprefix}lnd.conf")
  if [ "${lndConfigData}" == "" ]; then
    echo "error='no config'"
    exit 1
  fi

  # parse data
  lnd_alias=$( echo "${lndConfigData}" | grep "^alias=*" | cut -f2 -d=)

  # print data
  echo "ln_lnd_alias='${lnd_alias}'"
  exit 0
fi


######################################################
# INFO
######################################################

if [ "$2" = "info" ]; then

  # quick if not running
  if [ "${lnd_running}" == "0" ]; then
    echo "error='not running'"
    exit 1
  fi

  # quick if wallet is locked
  if [ "${lnd_locked}" == "1" ]; then
    echo "error='wallet locked'"
    exit 1
  fi

  # raw data demo:
  # sudo /usr/local/bin/lncli -n=mainnet --rpcserver=localhost:10009 --macaroonpath=/home/bitcoin/.lnd/data/chain/bitcoin/mainnet/readonly.macaroon --tlscertpath=/home/bitcoin/.lnd/tls.cert getinfo

  # get data
  ln_getInfo=$($lndcli_alias getinfo 2>/dev/null)
  if [ $? != 0 ] || [ "${ln_getInfo}" == "" ]; then
    echo "command='$lndcli_alias getinfo'"
    echo "error='no data'"
    exit 1
  fi

  # parse data
  lnd_address=$(echo "${ln_getInfo}" | grep "uris" -A 1 | tr -d '\n' | cut -d '"' -f4)
  lnd_tor=$(echo "${lnd_address}" | grep -c ".onion")
  lnd_sync_chain=$(echo "${ln_getInfo}" | grep "synced_to_chain" | grep "true" -c)
  lnd_sync_graph=$(echo "${ln_getInfo}" | grep "synced_to_graph" | grep "true" -c)
  lnd_channels_pending=$(echo "${ln_getInfo}" | jq -r '.num_pending_channels')
  lnd_channels_active=$(echo "${ln_getInfo}" | jq -r '.num_active_channels')
  lnd_channels_inactive=$(echo "${ln_getInfo}" | jq -r '.num_inactive_channels')
  lnd_channels_total=$(( lnd_channels_pending + lnd_channels_active + lnd_channels_inactive ))
  lnd_peers=$(echo "${ln_getInfo}" | jq -r '.num_peers')

  # calculate the sync/scan progress
  lnd_sync_progress=""
  scanTimestamp=$(echo "${ln_getInfo}" | jq -r '.best_header_timestamp')
  nowTimestamp=$(date +%s)
  if [ "${scanTimestamp}" != "" ] && [ ${scanTimestamp} -gt ${nowTimestamp} ]; then
    scanTimestamp=${nowTimestamp}
  fi
  if [ "${scanTimestamp}" != "" ]; then
    # calculate LND scan progress by seconds since Genesis block
    echo "#scanTimestamp=${scanTimestamp}"
    genesisTimestamp=1230940800
    totalSeconds=$(echo "${nowTimestamp}-${genesisTimestamp}" | bc)
    scannedSeconds=$(echo "${scanTimestamp}-${genesisTimestamp}" | bc)
    lnd_sync_progress=$(echo "scale=2; $scannedSeconds*100/$totalSeconds" | bc)
    if [ "${lnd_sync_progress}" == "99.99" ]; then
      lnd_sync_progress="100.00"
    fi
  fi

  # recovery info
  source <(/home/admin/config.scripts/lnd.backup.sh $1 recoverymode status)
  lnd_recovery_mode="${recoverymode}"
  lnd_recovery_done="0"
  if [ "${lnd_recovery_mode}" == "1" ]; then
    ln_getrecoveryinfo=$($lndcli_alias getrecoveryinfo 2>/dev/null)
    activated=$(echo "${ln_getrecoveryinfo}" | grep "recovery_mode" | grep "true" -c)
    finished=$(echo "${ln_getrecoveryinfo}" | grep "recovery_finished" | grep "true" -c)
    if [ "${activated}" == "1" ] && [ "${finished}" == "1" ]; then
      lnd_recovery_done="1"
    fi
  fi
  
  # print data
  echo "ln_lnd_address='${lnd_address}'"
  echo "ln_lnd_tor='${lnd_tor}'"
  echo "ln_lnd_sync_chain='${lnd_sync_chain}'"
  echo "ln_lnd_sync_progress='${lnd_sync_progress}'"
  echo "ln_lnd_sync_graph='${lnd_sync_graph}'"
  echo "ln_lnd_channels_pending='${lnd_channels_pending}'"
  echo "ln_lnd_channels_active='${lnd_channels_active}'"
  echo "ln_lnd_channels_inactive='${lnd_channels_inactive}'"
  echo "ln_lnd_channels_total='${lnd_channels_total}'"
  echo "ln_lnd_peers='${lnd_peers}'"
  echo "ln_lnd_recovery_mode='${lnd_recovery_mode}'"
  echo "ln_lnd_recovery_done='${lnd_recovery_done}'"
  exit 0
  
fi

######################################################
# WALLETS
######################################################

if [ "$2" = "wallet" ]; then

  # quick if not running
  if [ "${lnd_running}" == "0" ]; then
    echo "error='not running'"
    exit 1
  fi

  # quick if wallet is locked
  if [ "${lnd_locked}" == "1" ]; then
    echo "error='wallet locked'"
    exit 1
  fi

  # raw data demo:
  # /usr/local/bin/lncli -n=mainnet --rpcserver=localhost:10009 --macaroonpath=/home/bitcoin/.lnd/data/chain/bitcoin/mainnet/readonly.macaroon --tlscertpath=/home/bitcoin/.lnd/tls.cert walletbalance
  # /usr/local/bin/lncli -n=mainnet --rpcserver=localhost:10009 --macaroonpath=/home/bitcoin/.lnd/data/chain/bitcoin/mainnet/readonly.macaroon --tlscertpath=/home/bitcoin/.lnd/tls.cert channelbalance
  # get data
  ln_walletbalance=$($lndcli_alias walletbalance 2>/dev/null)
  if [ "${ln_walletbalance}" == "" ]; then
    echo "error='no data'"
    exit 1
  fi

  # parse data
  lnd_wallet_onchain_balance=$(echo "$ln_walletbalance" | jq -r '.confirmed_balance')
  lnd_wallet_onchain_pending=$(echo "$ln_walletbalance" | jq -r '.unconfirmed_balance')

  ln_channelbalance=$($lndcli_alias channelbalance 2>/dev/null)
  if [ "${ln_channelbalance}" == "" ]; then
    echo "error='no data'"
    exit 1
  fi

   # parse data
  lnd_wallet_channels_balance=$(echo "$ln_channelbalance" | jq -r '.balance')
  lnd_wallet_channels_pending=$(echo "$ln_channelbalance" | jq -r '.pending_open_balance')

  # print data
  echo "ln_lnd_wallet_onchain_balance='${lnd_wallet_onchain_balance}'"
  echo "ln_lnd_wallet_onchain_pending='${lnd_wallet_onchain_pending}'"
  echo "ln_lnd_wallet_channels_balance='${lnd_wallet_channels_balance}'"
  echo "ln_lnd_wallet_channels_pending='${lnd_wallet_channels_pending}'"
  exit 0

fi

######################################################
# CHANNELS
######################################################

if [ "$2" = "channels" ]; then

  # quick if not running
  if [ "${lnd_running}" == "0" ]; then
    echo "error='not running'"
    exit 1
  fi

  # quick if wallet is locked
  if [ "${lnd_locked}" == "1" ]; then
    echo "error='wallet locked'"
    exit 1
  fi

  # raw data demo:
  # sudo /usr/local/bin/lncli -n=mainnet --rpcserver=localhost:10009 --macaroonpath=/home/bitcoin/.lnd/data/chain/bitcoin/mainnet/readonly.macaroon --tlscertpath=/home/bitcoin/.lnd/tls.cert listchannels

  # get data
  ln_channels=$($lndcli_alias listchannels 2>/dev/null)
  if [ "${ln_channels}" == "" ]; then
    echo "error='no data'"
    exit 1
  fi

  # parse data
  lnd_channels_total=$(echo "$ln_channels" | jq '.[] | length')

  # print data
  echo "ln_lnd_channels_total='${lnd_channels_total}'"
  exit 0
  
fi

######################################################
# FEES
######################################################

if [ "$2" = "fees" ]; then

# raw data demo:
# sudo /usr/local/bin/lncli -n=mainnet --rpcserver=localhost:10009 --macaroonpath=/home/bitcoin/.lnd/data/chain/bitcoin/mainnet/readonly.macaroon --tlscertpath=/home/bitcoin/.lnd/tls.cert feereport

  # quick if not running
  if [ "${lnd_running}" == "0" ]; then
    echo "error='not running'"
    exit 1
  fi

  # quick if wallet is locked
  if [ "${lnd_locked}" == "1" ]; then
    echo "error='wallet locked'"
    exit 1
  fi

  # get data
  ln_feereport=$($lndcli_alias feereport 2>/dev/null)
  if [ "${ln_feereport}" == "" ]; then
    echo "error='no data'"
    exit 1
  fi

  # parse data
  lnd_fees_daily=$(echo "$ln_feereport" | jq -r '.day_fee_sum')
  lnd_fees_weekly=$(echo "$ln_feereport" | jq -r '.week_fee_sum')
  lnd_fees_month=$(echo "$ln_feereport" | jq -r '.month_fee_sum')
  lnd_fees_total=$((${lnd_fees_daily} + ${lnd_fees_weekly} + ${lnd_fees_month}))

  # print data
  echo "ln_lnd_fees_daily='${lnd_fees_daily}'"
  echo "ln_lnd_fees_weekly='${lnd_fees_weekly}'"
  echo "ln_lnd_fees_month='${lnd_fees_month}'"
  echo "ln_lnd_fees_total='${lnd_fees_total}'"
  exit 0
  
fi

echo "FAIL - Unknown Parameter $2"
exit 1
