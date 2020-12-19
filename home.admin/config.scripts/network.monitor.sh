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

echo "FAIL - Unknown Parameter $1"
exit 1
