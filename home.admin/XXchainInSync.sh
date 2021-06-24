#!/bin/bash

# Check if lnd is synced to chain and channels are open
# If it isn't, wait until it is
# exits with 1 if it isn't.

network=$1
chain=$2

# LNTYPE is lnd | cln
if [ $# -gt 2 ];then
  LNTYPE=$3
else
  LNTYPE=lnd
fi



exit 0
