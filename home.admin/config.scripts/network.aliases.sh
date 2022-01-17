#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo "# Usage:"
  echo "# source <(/home/admin/config.scripts/network.aliases.sh getvars <lnd|cl> <mainnet|testnet|signet>)"
  echo "# if no values given uses the default values from the raspiblitz.conf"
  echo
  echo "# chain is: main | test ; from raspiblitz.conf or raspiblitz.info or defaults to main"
  echo
  echo "# LNTYPE is: lnd | cl ; default: lnd"
  echo "# typeprefix is: "" | c"
  echo
  echo "# CHAIN is: mainnet | testnet | signet"
  echo "# netprefix is:  "" | t | s"
  echo "# portprefix is: "" | 1 | 3"
  echo "# CLNETWORK is: bitcoin / signet / testnet"
  exit 1
fi

source /home/admin/raspiblitz.info 
source /mnt/hdd/raspiblitz.conf 2>/dev/null

if [ "$1" = getvars ];then
  
  # LNTYPE is: lnd | cl
  if [ $# -gt 1 ];then
    LNTYPE=$2
  else
    if [ ${#lightning} -gt 0 ];then
      LNTYPE=${lightning}
    else
      LNTYPE=lnd
    fi
  fi
  echo "LNTYPE=${LNTYPE}"

  # from raspiblitz.conf or raspiblitz.info or defaults to main
  if [ ${#chain} -eq 0 ]; then
    chain=main
  fi
  # CHAIN is: signet | testnet | mainnet
  if [ $# -gt 2 ]&&[ "$3" != net ];then
    CHAIN=$3
    chain=${CHAIN::-3}
  else
    CHAIN=${chain}net
  fi
  echo "CHAIN=${chain}net"
  echo "chain=${chain}"

  # netprefix is:     "" | t | s
  # portprefix is:    "" | 1 | 3
  # L2rpcportmod is:   0 | 1 | 3   
  if [ "${chain}" == "main" ];then
    netprefix=""
    L1rpcportmod=""
    L2rpcportmod=0
    portprefix=""
  elif [ "${chain}" == "test" ];then
    netprefix="t"
    L1rpcportmod=1
    L2rpcportmod=1
    portprefix=1
  elif [ "${chain}" == "sig" ];then
    netprefix="s"
    L1rpcportmod=3
    L2rpcportmod=3
    portprefix=3
  fi
  echo "netprefix=${netprefix}"
  echo "portprefix=${portprefix}"
  echo "L2rpcportmod=${L2rpcportmod}"
  
  if [ "${LNTYPE}" == "cl" ];then
    # CLNETWORK is: bitcoin / signet / testnet
    if [ "${chain}" == "main" ];then
      CLNETWORK=${network}
    else
      CLNETWORK=${chain}net
    fi
    echo "CLNETWORK=${CLNETWORK}"

    # CLCONF is the path to the config
    if [ "${CLNETWORK}" == "bitcoin" ]; then
      CLCONF="/home/bitcoin/.lightning/config"
    else
      CLCONF="/home/bitcoin/.lightning/${CLNETWORK}/config"
    fi
    echo "CLCONF=${CLCONF}"
    typeprefix=c
  fi

  # typeprefix is: "" | c
  if [ "${LNTYPE}" == "lnd" ];then
    typeprefix=''
  fi
  echo "typeprefix=${typeprefix}"

  # instead of all
  # sudo -u bitcoin /usr/local/bin/lncli --chain=${network} --network=${chain}net
  echo "lncli_alias=\"sudo -u bitcoin /usr/local/bin/lncli -n=${chain}net --rpcserver localhost:1${L2rpcportmod}009\""
  # sudo -u bitcoin ${network}-cli -datadir=/home/bitcoin/.${network}
  echo "bitcoincli_alias=\"/usr/local/bin/${network}-cli -datadir=/home/bitcoin/.${network} -rpcport=${L1rpcportmod}8332\""
  echo "lightningcli_alias=\"sudo -u bitcoin /usr/local/bin/lightning-cli --conf=${CLCONF}\""

fi

#TODO
# where /lnd.conf is not changed to /${netprefix}lnd.conf the service remains for mainnet only