#!/bin/bash

# getLNvars <lnd|cln> <mainnet|testnet|signet>
function getLNvars {
  # LNTYPE is lnd | cln
  if [ $# -gt 0 ];then
    LNTYPE=$1
  else
    LNTYPE=lnd
  fi
  # CHAIN is signet | testnet | mainnet
  if [ $# -gt 1 ];then
    CHAIN=$2
    chain=${CHAIN::-3}
  else
    CHAIN=${chain}net
  fi
  if [ ${chain} = test ];then
    netprefix="t"
    L1rpcportmod=1
    L2rpcportmod=1
  elif [ ${chain} = sig ];then
    netprefix="s"
    L1rpcportmod=3
    L2rpcportmod=3
  elif [ ${chain} = main ];then
    netprefix=""
    L1rpcportmod=""
    L2rpcportmod=0
  fi
}

# getLNaliases <vars set by getLNvars>
function getLNaliases {
lncli_alias="sudo -u bitcoin /usr/local/bin/lncli -n=${chain}net --rpcserver localhost:1${L2rpcportmod}009"
bitcoincli_alias="/usr/local/bin/${network}-cli -rpcport=${L1rpcportmod}8332"
lightningcli_alias="sudo -u bitcoin /usr/local/bin/lightning-cli --conf=/home/bitcoin/.lightning/${netprefix}config"
shopt -s expand_aliases
alias lncli_alias="$lncli_alias"
alias bitcoincli_alias="$bitcoincli_alias"
alias lightningcli_alias="$lightningcli_alias"
}