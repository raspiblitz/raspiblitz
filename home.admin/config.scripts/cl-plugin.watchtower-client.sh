#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
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
source /mnt/hdd/raspiblitz.conf #to get runBehindTor
plugin="watchtower-client"
pkg_dependencies="libssl-dev"

if [ "$1" = info ]; then
  whiptail --title "The Eye of Satoshi CLN Watchtower" \
    --msgbox "
This is a watchtower client plugin to interact with an Eye of Satoshi tower, and
eventually with any BOLT13 compliant watchtower.

The plugin manages all the client-side logic to send appointment to a number of
registered towers every time a new commitment transaction is generated.
It also keeps a summary of the messages sent to the towers and their responses.

Usage (from the command line):

cl registertower <tower_id>: registers the user id (compressed public key) with a given tower.
cl gettowerinfo <tower_id>: gets all the locally stored data about a given tower.
cl retrytower <tower_id>: tries to send pending appointment to a (previously) unreachable tower.
cl abandontower <tower_id>: deletes all data associated with a given tower.
cl listtowers: lists all registered towers.
cl getappointment <tower_id> <locator>: queries a given tower about an appointment.
cl getsubscriptioninfo <tower_id>: gets the subscription information by querying the tower.
cl getappointmentreceipt <tower_id> <locator>: pulls a given appointment receipt from the local database.
cl getregistrationreceipt <tower_id>: pulls the latest registration receipt from the local database.

Links with more info:
https://github.com/talaia-labs/rust-teos/tree/master/watchtower-plugin
" 0 0
  exit 0
fi

if [ "$1" = "on" ]; then

  # rust for rust-teos, includes rustfmt
  sudo -u bitcoin curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs |
    sudo -u bitcoin sh -s -- -y

  #Cleanup existing
  if [ -d "/home/bitcoin/cl-plugins-available/plugins/${plugin}/" ]; then
    sudo rm -rf "/home/bitcoin/cl-plugins-available/plugins/${plugin}/"
  fi

  if [ -d "/home/bitcoin/cl-plugins-available/rust-teos/" ]; then
    sudo rm -rf "/home/bitcoin/cl-plugins-available/rust-teos/"
  fi

  #Clone source repository
  cd /home/bitcoin/cl-plugins-available || exit 1
  sudo -u bitcoin git clone https://github.com/talaia-labs/rust-teos.git

  #Install additional dependencies
  sudo apt-get install -y ${pkg_dependencies} >/dev/null

  #Compile
  cd /home/bitcoin/cl-plugins-available/rust-teos || exit 1
  sudo -u bitcoin /home/bitcoin/.cargo/bin/cargo install --locked --path watchtower-plugin \
    --target-dir /home/bitcoin/cl-plugins-available/${plugin} || exit 1

  #Symlink to enable
  if [ ! -L /home/bitcoin/${netprefix}cl-plugins-enabled/${plugin} ]; then
    echo "Running: sudo -u bitcoin ln -s /home/bitcoin/cl-plugins-available/${plugin}/release/${plugin} /home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}"
    sudo -u bitcoin ln -s /home/bitcoin/cl-plugins-available/${plugin}/release/${plugin} /home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}
  fi

  #check if toronly node, then add watchtower proxy config to CL
  if [ "$runBehindTor" = "on" ]; then
    # Check if the line is already in the file
    if ! grep -q "^proxy=127.0.0.1:9050$" "${CLCONF}"; then
      # If not, append the line to the file
      echo "Adding proxy configuration to ${CLCONF}"
      echo "proxy=127.0.0.1:9050" | sudo tee -a "${CLCONF}" >/dev/null
    else
      echo "Proxy configuration already exists in ${CLCONF}"
    fi
  fi

  # setting value in raspiblitz.conf
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clWatchtowerClient "on"

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ]; then
    echo "# Restart the ${netprefix}lightningd.service to activate watchtower-client"
    sudo systemctl restart ${netprefix}lightningd
  fi

fi

if [ "$1" = off ]; then
  # delete symlink
  sudo rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}

  echo "# Restart the ${netprefix}lightningd.service to deactivate ${plugin}"
  sudo systemctl restart ${netprefix}lightningd

  # purge
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ]; then
    echo "# Delete plugin and source code"
    sudo rm -rf /home/bitcoin/cl-plugins-available/rust-teos*
    sudo rm -rf /home/bitcoin/cl-plugins-available/${plugin}
  fi

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clWatchtowerClient "off"
  echo "# watchtower-client was uninstalled for ${CHAIN}"

fi
