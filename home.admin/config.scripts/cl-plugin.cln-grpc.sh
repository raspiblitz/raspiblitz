#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install the cln-grpc plugin for CLN"
  echo "Usage:"
  echo "cl-plugin.cln-grpc.sh [on|off] <testnet|mainnet|signet>"
  echo
  exit 1
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

function buildGRPCplugin() {
  echo "- build the cln-grpc plugin"
  if -f /home/bitcoin/cl-plugins-available/cln-grpc/debug/cln-grpc; then
    cd /home/bitcoin/lightning/plugins/grpc-plugin
    sudo -u bitcoin /home/bitcoin/.cargo/bin/cargo build \
     --target-dir /home/bitcoin/cl-plugins-available/cln-grpc
  fi
}

if [ "$1" = install ]; then
  buildGRPCplugin

elif [ "$1" = on ]; then
  buildGRPCplugin
  sudo ln -s /home/bitcoin/cl-plugins-available/cln-grpc/debug/cln-grpc \
   /home/bitcoin/${netprefix}cl-plugins-enabled/
  #blitz.conf.sh set [key] [value] [?conffile] <noquotes>
  /home/admin/config.scripts/blitz.conf.sh set grpc-port "7777" ${CLCONF} noquotes
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}cln-grpc-port "7777"

elif [ "$1" = off ]; then
    sed -i "/^grpc-port/d" ${CLCONF}
    rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/cln-grpc
    /home/admin/config.scripts/blitz.conf.sh set ${netprefix}cln-grpc-port "off"

else
  echo "FAIL - Unknown Parameter $1"
  exit 1
fi