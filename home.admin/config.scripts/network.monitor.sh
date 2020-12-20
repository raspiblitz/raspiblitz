#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "monitor and troubleshot the bitcoin network"
 echo "network.monitor.sh peer-status"
 echo "network.monitor.sh peer-kickstart"
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
  echo "${bitnodesRawData}"

  # filter raw data for node addresses based on what kind of connection is running
  addressFormat="ipv4"
  if [ "${runBehindTor}" == "on" ]; then
    # get TOR nodes
    addressFormat="tor"
    nodeList=$(echo "${bitnodesRawData}" | grep -o '[0-9a-z]\{16,56\}\.onion')
  else
    source <(sudo ./config.scripts/internet.sh status global)
    if [ "${ipv6}" == "off" ]; then
      # get IPv4 nodes
      nodeList=$(echo "${bitnodesRawData}" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\:[0-9]\{3,5\}')
    else
      # get IPv6 nodes
      nodeList=$(echo "${bitnodesRawData}" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\:[0-9]\{3,5\}')
    fi
  fi  
  echo "${nodeList}"  

  # random line number (1-25)
  randNodeNumber=$((1 + RANDOM % 26))
  echo "${randNodeNumber}"

  # random node
  nodeAddress=$(echo "${nodeList}" | sed -n "${randNodeNumber}p")
  echo "${nodeAddress}"

#   | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\:[0-9]\{3,5\}' | 
#echo 'f"vww6ybal4bd7szmgncyruucpgfkqahzddi37ktceo3ah7ngmcopnpyyd.onion:8333",sg' | grep -o '[0-9a-z]\{16,56\}\.onion'
#echo '189.164.139.162:8333","rdvlepy6ghgpapzo.onion:8333","189.164.140.162:8333":[70015,"/Satoshi:0.20.1/",1607715058,1037,662239,null,null,null,0.0,0.0,null,"TOR","Tor network"]'

  exit 0
fi




echo "FAIL - Unknown Parameter $1"
exit 1
