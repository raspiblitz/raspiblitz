#!/bin/bash

# Usage:
# source <(/home/admin/config.scripts/network.aliases.sh getvars <lnd|cln> <mainnet|testnet|signet>)
# if no values given uses the default values from the raspiblitz.conf

source /home/admin/raspiblitz.info
source /mnt/hdd/raspiblitz.conf

if [ $1 = getvars ];then
  
  # LNTYPE is: lnd | cln
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

  # typeprefix is: "" | c
  if [ $LNTYPE = cln ];then
    typeprefix=c
  elif [ $LNTYPE = lnd ];then
    typeprefix=''
  fi
  echo "typeprefix=${typeprefix}"

  # CHAIN is: signet | testnet | mainnet
  if [ $# -gt 2 ];then
    CHAIN=$3
    chain=${CHAIN::-3}
  else
    CHAIN=${chain}net
  fi
  echo "CHAIN=${chain}net"
  echo "chain=${chain}"

  # netprefix is:  "" | t | s
  # portprefix is: "" | 1 | 3
  if [ ${chain} = "test" ];then
    netprefix="t"
    L1rpcportmod=1
    L2rpcportmod=1
    portprefix=1
  elif [ ${chain} = "sig" ];then
    netprefix="s"
    L1rpcportmod=3
    L2rpcportmod=3
    portprefix=3
  elif [ ${chain} = "main" ];then
    netprefix=""
    L1rpcportmod=""
    L2rpcportmod=0
    portprefix=""
  fi
  echo "netprefix=${netprefix}"
  echo "portprefix=${portprefix}"

  # CLNETWORK is: bitcoin / signet / testnet
  if [ $chain = main ];then
    CLNETWORK=${network}
  else
    CLNETWORK=${chain}net
  fi
  echo CLNETWORK=${CLNETWORK}

  # instead of all
  # sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net
  echo "lncli_alias=\"sudo -u bitcoin /usr/local/bin/lncli -n=${chain}net --rpcserver localhost:1${L2rpcportmod}009\""
  # sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network}
  echo "bitcoincli_alias=\"/usr/local/bin/${network}-cli -datadir=/home/bitcoin/.${network} -rpcport=${L1rpcportmod}8332\""
  echo "lightningcli_alias=\"sudo -u bitcoin /usr/local/bin/lightning-cli --conf=/home/bitcoin/.lightning/${netprefix}config\""

fi

#TODO
# where /lnd.conf is not changed to /${netprefix}lnd.conf
# the service remains mainnet only