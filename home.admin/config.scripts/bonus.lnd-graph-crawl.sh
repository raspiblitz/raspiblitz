#!/bin/bash

# https://github.com/mutatrum/lnd_graph_crawl

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to switch the lnd-graph-crawl on or off"
 echo "bonus.lnd-graph-crawl.sh [on|off]"
 echo "Crawl the data writing only 'lndgraphcrawl' on the terminal"
 exit 1
fi

if [ "$1" = "on" ]; then
  sudo mkdir /mnt/hdd/app-storage/lnd-graph-crawl/
  sudo rm -f lncli describegraph > /mnt/hdd/app-storage/lnd-graph-crawl/lnd-graph-crawl/describegraph.json
  sudo git clone https://github.com/mutatrum/lnd_graph_crawl /mnt/hdd/app-storage/lnd-graph-crawl/lnd-graph-crawl
  sudo chown -R admin:admin /mnt/hdd/app-storage/lnd-graph-crawl/
fi

if [ "$1" = "off" ]; then
  sudo rm -rf /mnt/hdd/app-storage/lnd-graph-crawl/
fi
