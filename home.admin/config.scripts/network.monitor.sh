#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "monitor and troubleshoot the bitcoin network"
 echo "network.monitor.sh peer-status"
 echo "network.monitor.sh peer-kickstart [ipv4|ipv6|tor|auto]"
 echo "network.monitor.sh peer-disconnectall"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf
source /home/admin/raspiblitz.info

source <(/home/admin/config.scripts/network.aliases.sh getvars lnd ${chain}net)
shopt -s expand_aliases
alias bitcoincli_alias="$bitcoincli_alias"
alias lncli_alias="$lncli_alias"
alias lightningcli_alias="$lightningcli_alias"

###################
# STATUS
###################
if [ "$1" = "peer-status" ]; then
  echo "#network.monitor.sh peer-status"

  # number of peers connected
  peerNum=$($bitcoincli_alias getnetworkinfo | grep "connections\"" | tr -cd '[[:digit:]]')
  echo "peers=${peerNum}"

  exit 0
fi

###################
# PEER KICK START
###################
if [ "$1" = "peer-kickstart" ]; then
  echo "#network.monitor.sh peer-kickstart"

  # check if started with sudo
  if [ "$EUID" -ne 0 ]; then 
    echo "error='missing sudo'"
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
  bitcoincli_alias addnode "${nodeAddress}" "onetry" 1>/dev/null
  echo "exitcode=$?"

  exit 0
fi

###################
# DISCONNECT ALL PEERS
# for testing peer kick-start
###################
if [ "$1" = "peer-disconnectall" ]; then
  echo "#network.monitor.sh peer-disconnectall"

  # check if started with sudo
  if [ "$EUID" -ne 0 ]; then 
    echo "error='missing sudo'"
    exit 1
  fi

  # get all peer id and disconnect them
  bitcoincli_alias getpeerinfo | grep '"addr": "' | while read line 
  do
    peerID=$(echo $line | cut -d '"' -f4)
    echo "# disconnecting peer with ID: ${peerID}"
    bitcoincli_alias disconnectnode ${peerID}
  done

  echo "#### FINAL PEER INFO FROM BITCOIND"
  bitcoincli_alias getpeerinfo
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
