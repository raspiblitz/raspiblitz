#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "monitor and troubleshot the bitcoin network"
 echo "network.monitor.sh peer-status [cached]"
 echo "network.monitor.sh peer-kickstart [ipv4|ipv6|tor|auto]"
 echo "network.monitor.sh peer-disconnectall"
 exit 1
fi

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

###################
# STATUS
###################
if [ "$1" = "peer-status" ]; then
  echo "#network.monitor.sh peer-status"

  # if second parameter is "cached" deliver cahed result if available
  if [ "$2" == "cached" ]; then
    cacheExists=$(ls /var/cache/raspiblitz/network.monitor.peer-status.cache 2>/dev/null | grep -c "etwork.monitor.peer-status.cache")
    if [ "${cacheExists}" == "1" ]; then
      echo "cached=1"
      cat /var/cache/raspiblitz/network.monitor.peer-status.cache
      exit 1
    else
      echo "cached=0"
    fi
  fi

  # number of peers connected
  running=1
  if [ "$EUID" -eq 0 ]; then
    # sudo call
    peerNum=$(sudo -u admin ${network}-cli getnetworkinfo 2>/dev/null | grep "connections\"" | tr -cd '[[:digit:]]')
  else
    # user call
    peerNum=$(${network}-cli getnetworkinfo 2>/dev/null | grep "connections\"" | tr -cd '[[:digit:]]') 
  fi
  if [ "${peerNum}" = "" ]; then
    running=0
    peerNum=0
  fi

  # output to cache (normally gets written every 1min by background) if sudo
  if [ "$EUID" -eq 0 ]; then
    touch /var/cache/raspiblitz/network.monitor.peer-status.cache
    echo "running=${running}" > /var/cache/raspiblitz/network.monitor.peer-status.cache
    echo "peers=${peerNum}" >> /var/cache/raspiblitz/network.monitor.peer-status.cache
    sudo chmod 664 /var/cache/raspiblitz/network.monitor.peer-status.cache
  fi

  # output to user
  echo "running=${running}"
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
  sudo -u admin ${network}-cli addnode "${nodeAddress}" "onetry" 1>/dev/null
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
  sudo -u admin ${network}-cli getpeerinfo | grep '"addr": "' | while read line 
  do
    peerID=$(echo $line | cut -d '"' -f4)
    echo "# disconnecting peer with ID: ${peerID}"
    sudo -u admin ${network}-cli disconnectnode ${peerID}
  done

  echo "#### FINAL PEER INFO FORM BITCOIND"
  sudo -u admin ${network}-cli getpeerinfo
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
