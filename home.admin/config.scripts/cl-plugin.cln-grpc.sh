#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install the cln-grpc plugin for CLN"
  echo "Usage:"
  echo "cl-plugin.cln-grpc.sh install - called by build_sdcard.sh"
  echo "cl-plugin.cln-grpc.sh [on|off] <testnet|mainnet|signet>"
  echo
  exit 1
fi

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

# netprefix is:     "" |  t | s
# portprefix is:    "" |  1 | 3
PORT="${portprefix}4772"

function buildGRPCplugin() {
  echo "- build the cln-grpc plugin"
  if [ ! -f /home/bitcoin/cl-plugins-available/cln-grpc/debug/cln-grpc ]; then
    # check if the source code is present
    if [ ! -d /home/bitcoin/lightning/plugins/grpc-plugin ];then
      echo "* Adding c-lightning ..."
      /home/admin/config.scripts/cl.install.sh install || exit 1
    fi
    # rust for cln-grpc, includes rustfmt
    sudo -u bitcoin curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
     sudo -u bitcoin sh -s -- -y
    cd /home/bitcoin/lightning/plugins/grpc-plugin || exit 1
    # build
    sudo -u bitcoin /home/bitcoin/.cargo/bin/cargo build \
     --target-dir /home/bitcoin/cl-plugins-available/cln-grpc
  fi
}

if [ "$1" = install ]; then
  buildGRPCplugin
  exit 0

elif [ "$1" = on ]; then
  buildGRPCplugin

  # symlink to plugin directory
  sudo ln -s /home/bitcoin/cl-plugins-available/cln-grpc/debug/cln-grpc \
   /home/bitcoin/${netprefix}cl-plugins-enabled/

  # blitz.conf.sh set [key] [value] [?conffile] <noquotes>
  /home/admin/config.scripts/blitz.conf.sh set grpc-port "${PORT}" "${CLCONF}" noquotes
  /home/admin/config.scripts/blitz.conf.sh set "${netprefix}cln-grpc-port" "${PORT}"

  # firewall
  sudo ufw allow "${PORT}" comment "${netprefix}cln-grpc-port"
  # Tor
  /home/admin/config.scripts/tor.onion-service.sh "${netprefix}cln-grpc-port" "${PORT}" "${PORT}"
  exit 0

elif [ "$1" = off ]; then
  sed -i "/^grpc-port/d" "${CLCONF}"
  rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/cln-grpc
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}cln-grpc-port "off"
  # firewall
  sudo ufw deny "${PORT}" comment "cln-grpc-port"
  # Tor
  /home/admin/config.scripts/tor.onion-service.sh off ${netprefix}cln-grpc-port
  exit 0

else
  echo "FAIL - Unknown Parameter $1"
  exit 1
fi
