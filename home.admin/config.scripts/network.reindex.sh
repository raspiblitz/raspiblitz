#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "script to run re-index if the blockchain - blocks will not be deleted but re-indexed"
 echo "will trigger reboot after started and progress can be monitored thru normal sync status"
 echo "There are two ways to re-index - for details see: https://bitcoin.stackexchange.com/a/60711"
 echo "network.reindex.sh reindex [mainnet|testnet|signet] --> re-index chain & repair corrupt blocks"
 echo "network.reindex.sh reindex-chainstate [mainnet|testnet|signet] --> only re-build UTXO set (fast)"
 exit 1
fi

source /mnt/hdd/app-data/raspiblitz.conf

if [ "$1" = "reindex" ] || [ "$1" = "reindex-chainstate" ]; then

  action="$1"

  # network prefixes
  if [ "$2" = "mainnet" ]; then
    echo "# network.reindex.sh ${action} --> mainnet"
    prefix=""
    netparam=""
  elif [ "$2" = "testnet" ]; then
    echo "# network.reindex.sh ${action} --> testnet"
    prefix="t"
    netparam="-testnet "
  elif [ "$2" = "signet" ]; then
    echo "# network.reindex.sh ${action} --> signet"
    prefix="s"
    netparam="-signet "
  else
    echo "error='unknown/missing secondary parameter'"
    exit 1
  fi

  # stop bitcoin service
  echo "# stopping ${network} service (please wait - can take time) .."
  sudo systemctl stop ${prefix}${network}d

  # starting reindex
  echo "# starting ${network} service with -${action} flag"
  sudo -u bitcoin /usr/local/bin/${network}d ${netparam}-daemon -blockfilterindex=0 -${action} -conf=/mnt/hdd/app-data/${network}/${network}.conf -datadir=/mnt/hdd/app-storage/${network} 1>&2
  echo "# waiting 10 secs"
  sleep 10
  echo "# going into reboot - reindex process can be monitored like normal blockchain sync status"
  sudo /home/admin/config.scripts/blitz.shutdown.sh reboot

  exit 0
fi

echo "error='unknown main parameter'"
exit 1

