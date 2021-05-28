#!/bin/bash


# TODO: ON BASIC BITCOIN CONFIG
###### OPTIMIZE IF RAM >1GB
kbSizeRAM=$(cat /proc/meminfo | grep "MemTotal" | sed 's/[^0-9]*//g')
if [ ${kbSizeRAM} -gt 1500000 ]; then
  echo "Detected RAM >1GB --> optimizing ${network}.conf"
  sudo sed -i "s/^dbcache=.*/dbcache=512/g" /home/admin/assets/bitcoin.conf
  sudo sed -i "s/^maxmempool=.*/maxmempool=300/g" /home/admin/assets/bitcoin.conf
fi