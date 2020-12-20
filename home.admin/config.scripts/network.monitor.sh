#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "monitor and troubleshot the bitcoin network"
 echo "network.monitor.sh peer-status"
 echo "network.monitor.sh peer-kickstart [ipv4|ipv6|tor|auto]"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf
source /home/admin/raspiblitz.info

###################
# STATUS
###################
if [ "$1" = "peer-status" ]; then
  echo "#network.monitor.sh peer-status"

  # number of peers connected
  peerNum=$(${network}-cli getnetworkinfo | grep "connections" | tr -cd '[[:digit:]]')
  echo "peers=${peerNum}"

  exit 0
fi

###################
# STATUS
###################
if [ "$1" = "peer-kickstart" ]; then
  echo "#network.monitor.sh peer-kickstart"

  # check if started with sudo
  if [ "$EUID" -ne 0 ]; then 
    echo "error='missing sudo'"
    exit 1
  fi

  # get raw node data from bitnodes.io (use Tor if available)
  bitnodesRawData=$(curl -H "Accept: application/json; indent=4" https://bitnodes.io/api/v1/snapshots/latest/ 2>/dev/null)
  if [ ${#bitnodesRawData} -lt 100 ]; then
    echo "error='no valid data from bitnodes.io'"
    exit 1
  fi

  # determine which address to choose
  addressFormat="$2"
  # set default to auto
  if [ "${addressFormat}" == "" ]; then
    addressFormat="auto"
  fi
  # check valid value
  if [ "${addressFormat}" != "ipv4" ] && [ "${addressFormat}" != "ipv6" ] && [ "${addressFormat}" != "tor" ] && [ "${addressFormat}" != "auto" ]; then
    echo "error='unvalid network type'"
    exit 1
  fi
  # if auto then deterine whats running
  if [ "${addressFormat}" == "auto" ]; then
    if [ "${runBehindTor}" == "on" ]; then
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
    # unvalid address
    echo "error='unvalid 2nd parameter'"
    exit 1
  fi
  #echo "${nodeList}"
  nodesAvailable=$(echo "${nodeList}" | wc -l)
  echo "nodesAvailable=${nodesAvailable}"

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
  sudo -u admin bitcoin-cli addnode "${nodeAddress}" "onetry" 

  exit 0
fi




echo "FAIL - Unknown Parameter $1"
exit 1
