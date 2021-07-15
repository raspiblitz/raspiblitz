#!/bin/bash

# Usage:
# source <(/home/admin/config.scripts/network.aliases.sh <lnd|cln> <mainnet|testnet|signet>
# shopt -s expand_aliases
# alias bitcoincli_alias="$bitcoincli_alias"
# alias lncli_alias="$lncli_alias"
# alias lightningcli_alias="$lightningcli_alias"
source /mnt/hdd/raspiblitz.conf

if [ $1 = getvars ];then
  # LNTYPE is lnd | cln
  if [ $# -gt 1 ];then
    LNTYPE=$2
  else
    if [ ${#LNdefault} -gt 0 ];then
      LNTYPE=${LNdefault}
    else
      LNTYPE=lnd
    fi
  fi
  echo "LNTYPE=${LNTYPE}"
  if [ $LNTYPE = cln ];then
    echo "typeprefix=c"
  elif [ $LNTYPE = lnd ];then
    echo "typeprefix=''"
  fi

  # CHAIN is signet | testnet | mainnet
  if [ $# -gt 2 ];then
    CHAIN=$3
    chain=${CHAIN::-3}
  else
    CHAIN=${chain}net
  fi
  echo "CHAIN=${chain}net"
  echo "chain=${chain}"
  if [ "${chain}" = "test" ];then
    netprefix="t"
    echo "netprefix=t"
    L1rpcportmod=1
    L2rpcportmod=1
    echo "portprefix=1"
  elif [ "${chain}" = "sig" ];then
    netprefix="s"
    echo "netprefix=s"
    L1rpcportmod=3
    L2rpcportmod=3
    echo "portprefix=3"
  elif [ "${chain}" = "main" ];then
    netprefix=""
    echo "netprefix=''"
    L1rpcportmod=""
    L2rpcportmod=0
    echo "portprefix=''"
  fi

  #TODO ALL
  # instead of all
  # sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net
  echo "lncli_alias=\"sudo -u bitcoin /usr/local/bin/lncli -n=${chain}net --rpcserver localhost:1${L2rpcportmod}009\""
  # sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network}
  echo "bitcoincli_alias=\"/usr/local/bin/${network}-cli -datadir=/home/bitcoin/.${network} -rpcport=${L1rpcportmod}8332\""
  echo "lightningcli_alias=\"sudo -u bitcoin /usr/local/bin/lightning-cli --conf=/home/bitcoin/.lightning/${netprefix}config\""
fi

#TODO
#change all /lnd.conf to /${netprefix}lnd.conf