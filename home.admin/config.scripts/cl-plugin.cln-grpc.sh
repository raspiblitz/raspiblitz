#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Install the cln-grpc plugin for CLN"
  echo "Usage:"
  echo "cl-plugin.cln-grpc.sh install - called by build_sdcard.sh"
  echo "cl-plugin.cln-grpc.sh on <testnet|mainnet|signet>"
  echo "cl-plugin.cln-grpc.sh off <testnet|mainnet|signet> <purge>"
  echo "cl-plugin.cln-grpc.sh status <testnet|mainnet|signet>"
  echo "cl-plugin.cln-grpc.sh update <source>"
  echo
  exit 1
fi

echo "# cl-plugin.cln-grpc.sh $*"

if [ "$2" = testnet ] || [ "$2" = signet ]; then
  NETWORK=$2
else
  NETWORK=mainnet
fi
source <(/home/admin/config.scripts/network.aliases.sh getvars cl $NETWORK)

# netprefix is:     "" |  t | s
# portprefix is:    "" |  1 | 3
PORT="${portprefix}4772"

function buildGRPCplugin() {
  echo "# - check the cln-grpc plugin"
  if [ ! -f /usr/local/libexec/c-lightning/plugins/cln-grpc ] || [ ! -f /home/bitcoin/cl-plugins-available/cln-grpc ]; then
    # check if the source code is present
    if [ ! -d /home/bitcoin/lightning/plugins/grpc-plugin ]; then
      echo "# - install Core Lightning ..."
      /home/admin/config.scripts/cl.install.sh install || exit 1
    fi
    if [ -f /usr/local/libexec/c-lightning/plugins/cln-grpc ]; then
      echo "# - cln-grpc plugin was installed"
    else
      echo "# install dependencies"
      sudo apt-get install protobuf-compiler -y
      echo "# rust for cln-grpc, includes rustfmt"
      sudo -u bitcoin curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sudo -u bitcoin sh -s -- -y
      cd /home/bitcoin/lightning/plugins/grpc-plugin || exit 1
      echo "# build"
      sudo -u bitcoin /home/bitcoin/.cargo/bin/cargo build --target-dir /home/bitcoin/cln-grpc-build
      echo "# delete old dir or binary"
      sudo rm -rf /home/bitcoin/cl-plugins-available/cln-grpc
      echo "# move to /home/bitcoin/cl-plugins-available/"
      sudo mkdir -p /home/bitcoin/cl-plugins-available
      sudo -u bitcoin mv /home/bitcoin/cln-grpc-build/debug/cln-grpc /home/bitcoin/cl-plugins-available/
    fi
  else
    echo "# - cln-grpc plugin was already built/installed"
  fi
  echo "# Cleaning"
  sudo rm -rf /home/bitcoin/.rustup
  sudo rm -rf /home/bitcoin/.cargo/
  sudo rm -rf /home/bitcoin/.cache
  sudo rm -rf /home/bitcoin/cln-grpc-build
}

function switchOn() {
  if ! $lightningcli_alias plugin list | grep "/home/bitcoin/${netprefix}cl-plugins-enabled/cln-grpc"; then
    buildGRPCplugin

    if [ ! -f /usr/local/libexec/c-lightning/plugins/cln-grpc ]; then
      # symlink to plugin directory
      echo "# symlink cln-grpc to /home/bitcoin/${netprefix}cl-plugins-enabled/"
      # delete old symlink
      sudo rm -f /home/bitcoin/${netprefix}cl-plugins-enabled/cln-grpc
      sudo ln -s /home/bitcoin/cl-plugins-available/cln-grpc /home/bitcoin/${netprefix}cl-plugins-enabled/
    fi
    # blitz.conf.sh set [key] [value] [?conffile] <noquotes>
    /home/admin/config.scripts/blitz.conf.sh set "grpc-port" "${PORT}" "${CLCONF}" "noquotes"
    /home/admin/config.scripts/blitz.conf.sh set "${netprefix}clnGRPCport" "${PORT}"

    # firewall
    sudo ufw allow "${PORT}" comment "${netprefix}clnGRPCport"
    # Tor
    /home/admin/config.scripts/tor.onion-service.sh "${netprefix}clnGRPCport" "${PORT}" "${PORT}"
    source <(/home/admin/_cache.sh get state)
    if [ "${state}" == "ready" ]; then
      sudo systemctl restart ${netprefix}lightningd
    fi
    echo "# cl-plugin.cln-grpc.sh on --> done"

  else
    echo "# cl-plugin.cln-grpc.sh on --> already installed and running"
  fi
  exit 0
}

if [ "$1" = install ]; then
  buildGRPCplugin
  echo "# cl-plugin.cln-grpc.sh install --> done"
  exit 0

elif [ "$1" = status ]; then

  portActive=$(nc -vz 127.0.0.1 $PORT 2>&1 | grep -c "succeeded")
  echo "port=${PORT}"
  echo "portActive=${portActive}"
  exit 0

elif [ "$1" = on ]; then
  switchOn

elif [ "$1" = off ]; then
  sed -i "/^grpc-port/d" "${CLCONF}"
  sudo rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/cln-grpc
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ]; then
    sudo rm -rf /home/bitcoin/cl-plugins-available/cln-grpc
  fi
  /home/admin/config.scripts/blitz.conf.sh set "${netprefix}clnGRPCport" "off"
  # firewall
  sudo ufw deny "${PORT}" comment "${netprefix}clnGRPCport"
  # Tor
  /home/admin/config.scripts/tor.onion-service.sh off "${netprefix}clnGRPCport"
  exit 0

elif [ "$1" = update ]; then
  if [ "$(echo "$@" | grep -c source)" -gt 0 ]; then
    cd /home/bitcoin/lightning/ || exit 1
    sudo -u bitcoin git pull
  fi
  sudo rm -rf /home/bitcoin/cl-plugins-available/cln-grpc
  buildGRPCplugin
  sudo systemctl stop ${netprefix}lightningd
  switchOn
  echo "# cl-plugin.cln-grpc.sh update  --> done"

else
  echo "FAIL - Unknown Parameter $1"
  exit 1
fi
