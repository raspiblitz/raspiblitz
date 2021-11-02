#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "monitor and troubleshot the bitcoin network"
 echo "bitcoin.monitor.sh [mainnet|testnet|signet] status"
 echo "bitcoin.monitor.sh [mainnet|testnet|signet] info"
 echo "bitcoin.monitor.sh [mainnet|testnet|signet] mempool"
 echo "bitcoin.monitor.sh [mainnet|testnet|signet] network"
 echo "bitcoin.monitor.sh [mainnet] peer-kickstart [ipv4|ipv6|tor|auto]"
 echo "bitcoin.monitor.sh [mainnet] peer-disconnectall"
 exit 1
fi

# check if started with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "error='run as root'"
  exit 1
fi

# set based on network type
if [ "$1" == "mainnet" ]; then
  bitcoincli_alias="/usr/local/bin/bitcoin-cli -datadir=/home/bitcoin/.bitcoin -rpcport=8332"
  service_alias="bitcoind"
elif [ "$1" == "testnet" ]; then
  bitcoincli_alias="/usr/local/bin/bitcoin-cli -datadir=/home/bitcoin/.bitcoin -rpcport=18332"
  service_alias="tbitcoind"
elif [ "$1" == "signet" ]; then
  bitcoincli_alias="/usr/local/bin/bitcoin-cli -datadir=/home/bitcoin/.bitcoin -rpcport=38332"
  service_alias="sbitcoind"
else
  echo "error='not supported net'"
  exit 1
fi

######################################################
# STATUS
# check general status info
######################################################

if [ "$2" = "status" ]; then

  btc_version=$($bitcoincli_alias -version 2>/dev/null | cut -d ' ' -f6)
  btc_running=$(systemctl status $service_alias 2>/dev/null | grep -c "active (running)")
  btc_ready="0"
  btc_online="0"
  btc_error_short=""
  btc_error_full=""

  if [ "${btc_running}" != "0" ]; then
    btc_running="1"

    # test connection - record win & fail info
    randStr=$(echo "$RANDOM")
    rm /var/cache/raspiblitz/.bitcoind-${randStr}.out 2>/dev/null
    rm /var/cache/raspiblitz/.bitcoind-${randStr}.error 2>/dev/null
    touch /var/cache/raspiblitz/.bitcoind-${randStr}.out
    touch /var/cache/raspiblitz/.bitcoind-${randStr}.error
    $bitcoincli_alias getnetworkinfo 1>/var/cache/raspiblitz/.bitcoind-${randStr}.out 2>/var/cache/raspiblitz/.bitcoind-${randStr}.error
    winData=$(cat /var/cache/raspiblitz/.bitcoind-${randStr}.out 2>/dev/null)
    failData=$(cat /var/cache/raspiblitz/.bitcoind-${randStr}.error 2>/dev/null)
    rm /var/cache/raspiblitz/.bitcoind-${randStr}.out
    rm /var/cache/raspiblitz/.bitcoind-${randStr}.error

    # check for errors
    if [ "${failData}" != "" ]; then
      btc_ready="0"
      btc_error_short=$(echo ${failData/error*:/} | sed 's/[^a-zA-Z0-9 ]//g')
      btc_error_full=$(echo ${failData} | tr -d "'" | tr -d '"')
      btc_ready="0"

    # check results if proof for online
    else
      btc_ready="1"
      connections=$( echo "${winData}" | grep "connections\"" | tr -cd '[[:digit:]]')
      if [ "${connections}" != "" ] && [ "${connections}" != "0" ]; then
        btc_online="1"
      fi
    fi

  fi 

  # print results
  echo "btc_version='${btc_version}'"
  echo "btc_running='${btc_running}'"
  echo "btc_ready='${btc_ready}'"
  echo "btc_online='${btc_online}'"
  echo "btc_error_short='${btc_error_short}'"
  echo "btc_error_full='${btc_error_full}'"

  exit 0
fi   

######################################################
# NETWORK
######################################################

if [ "$2" = "network" ]; then

  # get data
  getnetworkinfo=$($bitcoincli_alias getnetworkinfo 2>/dev/null)
  if [ "${getnetworkinfo}" == "" ]; then
    echo "error='no data'"
    exit 1
  fi

  # parse data
  btc_peers=$(echo "${getnetworkinfo}" | grep "connections\"" | tr -cd '[[:digit:]]')
  btc_address=$(echo ${getnetworkinfo} | jq -r '.localaddresses [0] .address')
  btc_port=$(echo "${getnetworkinfo}" | jq -r '.localaddresses [0] .port')

  # print data
  echo "btc_peers='${btc_peers}'"
  echo "btc_address='${btc_address}'"
  echo "btc_port='${btc_port}'"
  exit 0
  
fi

######################################################
# BLOCKCHAIN
######################################################

if [ "$2" = "info" ]; then

  # get data
  blockchaininfo=$($bitcoincli_alias getblockchaininfo 2>/dev/null)
  if [ "${blockchaininfo}" == "" ]; then
    echo "error='no data'"
    exit 1
  fi

  # parse data
  btc_blocks_headers=$(echo "${blockchaininfo}" | jq -r '.headers')
  btc_blocks_verified=$(echo "${blockchaininfo}" | jq -r '.blocks')
  btc_blocks_behind=$((${btc_blocks_headers} - ${btc_blocks_verified}))
  btc_sync_progress=$(echo "${blockchaininfo}" | jq -r '.verificationprogress')
  btc_sync_percentage=$(echo ${btc_sync_progress} | awk '{printf( "%.2f%%", 100 * $1)}')

  # print data
  echo "btc_blocks_headers='${btc_blocks_headers}'"
  echo "btc_blocks_verified='${btc_blocks_verified}'"
  echo "btc_blocks_behind='${btc_blocks_behind}'"
  echo "btc_sync_progress='${btc_sync_progress}'"
  echo "btc_sync_percentage='${btc_sync_percentage}'"
  exit 0
  
fi

######################################################
# MEMPOOL
######################################################

if [ "$2" = "mempool" ]; then

  # get data
  mempoolinfo=$($bitcoincli_alias getmempoolinfo 2>/dev/null)
  if [ "${mempoolinfo}" == "" ]; then
    echo "error='no data'"
    exit 1
  fi

  # parse data
  btc_mempool_transactions=$(echo "${mempoolinfo}" | jq -r '.size')

  # print data
  echo "btc_mempool_transactions=${btc_mempool_transactions}"
  exit 0
  
fi

###################
# PEER KICK START
###################

if [ "$2" = "peer-kickstart" ]; then

  # check calling only for mainnet
  if [ "$1" != "mainnet" ]; then 
    echo "error='only available for mainnet yet'"
    exit 1
  fi

  # get raw node data from bitnodes.io (use Tor if available)
  #if [ "${runBehindTor}" == "on" ]; then
    # call over tor proxy (CAPTCHA BLOCKED)
    #bitnodesRawData=$(curl --socks5-hostname 127.0.0.1:9050 -H "Accept: application/json; indent=4" https://bitnodes.io/api/v1/snapshots/latest/ 2>/dev/null)
  #else
    # call over clearnet
    # bitnodesRawData=$(curl -H "Accept: application/json; indent=4" https://bitnodes.io/api/v1/snapshots/latest/ 2>/dev/null)
  #fi

  bitnodesRawData=$(sudo -u admin cat /home/admin/fallback.nodes)
  if [ ${#bitnodesRawData} -lt 100 ]; then
    echo "error='no valid data from bitnodes.io'"
    exit 1
  fi

  # determine which address to choose
  addressFormat="$3"
  # set default to auto
  if [ "${addressFormat}" == "" ]; then
    addressFormat="auto"
  fi
  # check valid value
  if [ "${addressFormat}" != "ipv4" ] && [ "${addressFormat}" != "ipv6" ] && [ "${addressFormat}" != "tor" ] && [ "${addressFormat}" != "auto" ]; then
    echo "error='invalid address type'"
    exit 1
  fi
  # if auto then determine whats running
  if [ "${addressFormat}" == "auto" ]; then
    source <()
    if [ "$(cat /mnt/hdd/raspiblitz.conf | grep -c "^runBehindTor=on")" != "0" ]; then
      addressFormat="tor"
    else
      source <(sudo ./config.scripts/internet.sh status global)
      if [ "${ipv6}" == "off" ]; then
        addressFormat="ipv4"
      else
        addressFormat="ipv6"
      fi
    fi
  fi
  echo "addressFormat='${addressFormat}'"

  # filter raw data for node addresses based on what kind of connection is running
  if [ "${addressFormat}" == "tor" ]; then
    # get Tor nodes (v2 or v3)
    nodeList=$(echo "${bitnodesRawData}" | grep -o '[0-9a-z]\{16,56\}\.onion')
  elif [ "${addressFormat}" == "ipv4" ]; then
    # get IPv4 nodes
    nodeList=$(echo "${bitnodesRawData}" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\:[0-9]\{3,5\}')
  elif [ "${addressFormat}" == "ipv6" ]; then
    # get IPv6 nodes
    nodeList=$(echo "${bitnodesRawData}" | grep -o '\[.\{5,45\}\]\:[0-9]\{3,5\}')
  else
    # invalid address
    echo "error='invalid address format'"
    exit 1
  fi
  #echo "${nodeList}"
  nodesAvailable=$(echo "${nodeList}" | wc -l)
  echo "nodesAvailable=${nodesAvailable}"
  if [ "${nodesAvailable}" == "0" ]; then
    echo "error='no nodes available'"
    exit 1
  fi

  # pick random node from list
  randomLineNumber=$((1 + RANDOM % ${nodesAvailable}))
  echo "randomNumber=${randomLineNumber}"
  nodeAddress=$(echo "${nodeList}" | sed -n "${randomLineNumber}p")
  if [ "${nodeAddress}" == "" ]; then
    # if random pick fails pick first line
    nodeAddress=$(echo "${nodeList}" | sed -n "1p")
  fi
  if [ "${nodeAddress}" == "" ]; then
    echo "error='selecting node from list failed'"
    exit 1
  fi
  echo "newpeer='${nodeAddress}"

  # kick start node with 
  $bitcoincli_alias addnode "${nodeAddress}" "onetry" 1>/dev/null
  echo "exitcode=$?"

  exit 0
fi

###################
# DISCONNECT ALL PEERS
# for testing peer kick-start
###################
if [ "$2" = "peer-disconnectall" ]; then

  # check calling only for mainnet
  if [ "$1" != "mainnet" ]; then 
    echo "error='only available for mainnet yet'"
    exit 1
  fi

  # get all peer id and disconnect them
  $bitcoincli_alias getpeerinfo | grep '"addr": "' | while read line 
  do
    peerID=$(echo $line | cut -d '"' -f4)
    echo "# disconnecting peer with ID: ${peerID}"
    $bitcoincli_alias disconnectnode ${peerID}
  done

  echo "#### FINAL PEER INFO FROM BITCOIND"
  $bitcoincli_alias getpeerinfo
  exit 0
fi

echo "FAIL - Unknown Parameter $2"
exit 1
