#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install the rust-teos watchtower-client plugin for CLN"
  echo "Usage:"
  echo "cl-plugin.watchtower-client.sh on <testnet|mainnet|signet>"
  echo "cl-plugin.watchtower-client.sh off <testnet|mainnet|signet> <purge>"
  echo "cl-plugin.watchtower-client.sh info"
  echo
  exit 1
fi

echo "# cl-plugin.watchtower-client.sh $*"

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)
source /mnt/hdd/raspiblitz.conf  #to get runBehindTor
plugin="watchtower-client"
pkg_dependencies="libssl-dev"

if [ "$1" = info ]; then
    echo "The Eye of Satoshi is a Lightning watchtower compliant with BOLT13, written in Rust."
    echo ""
    echo "To connect to a tower, use:"
    echo "cl registertower <tower_id>"
    echo ""
    echo "Links with more info:"
    echo "https://github.com/talaia-labs/rust-teos/tree/master/watchtower-plugin"
fi


if [ "$1" = "on" ];then

  # rust for rust-teos, includes rustfmt
  sudo -u bitcoin curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
  sudo -u bitcoin sh -s -- -y

  #Cleanup existing
  if [ -d "/home/bitcoin/cl-plugins-available/plugins/${plugin}/" ]; then
    rm -rf "/home/bitcoin/cl-plugins-available/plugins/${plugin}/"
  fi

  #Clone source repository
  cd /home/bitcoin/cl-plugins-available || exit 1
  sudo -u bitcoin git clone https://github.com/talaia-labs/rust-teos.git
  
  #Install additional dependencies
  sudo apt-get install -y ${pkg_dependencies} > /dev/null

  #Compile
  cd /home/bitcoin/cl-plugins-available/rust-teos || exit 1
  sudo -u bitcoin /home/bitcoin/.cargo/bin/cargo install --path watchtower-plugin \
      --target-dir /home/bitcoin/cl-plugins-available/${plugin}

  #Symlink to enable
  if [ ! -L  /home/bitcoin/${netprefix}cl-plugins-enabled/${plugin} ]; then
    echo "Running: sudo -u bitcoin ln -s /home/bitcoin/cl-plugins-available/${plugin}/release/${plugin} /home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}"
    sudo -u bitcoin ln -s /home/bitcoin/cl-plugins-available/${plugin}/release/${plugin} /home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}
  fi

  #check if toronly node, then add watchtower-proxy config to CL 
  if [ "$runBehindTor" = on ]; then
    echo "watchtower-proxy=127.0.0.1:9050" | sudo tee -a ${CLCONF}
  fi

  # setting value in raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clWatchtowerClient "on"

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# Restart the ${netprefix}lightningd.service to activate watchtower-client"
    sudo systemctl restart ${netprefix}lightningd
  fi

fi


if [ "$1" = off ];then
  # delete symlink
  sudo rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}

  # delete watchtower-proxy config line from ${CLCONF}
  sudo sed -i '/watchtower-proxy=/d' ${CLCONF}

  echo "# Restart the ${netprefix}lightningd.service to deactivate ${plugin}"
  sudo systemctl restart ${netprefix}lightningd

  # purge
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
    echo "# Delete plugin and source code"
    sudo rm -rf /home/bitcoin/cl-plugins-available/rust-teos*
    sudo rm -rf /home/bitcoin/cl-plugins-available/${plugin}
  fi


  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clWatchtowerClient "off"
  echo "# watchtower-client was uninstalled for ${CHAIN}"

fi

