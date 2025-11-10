#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Install the cln-nip47 plugin (Nostr Wallet Connect) for Core Lightning"
  echo "Source: https://github.com/daywalker90/cln-nip47"
  echo
  echo "Usage:"
  echo "cl-plugin.clnnip47.sh [on|off|remove] <testnet|mainnet|signet>"
  echo
  exit 1
fi

# load CLN network aliases and useful vars
# provides: netprefix ("" or "t" or "s"), CLCONF, lightningcli_alias, CLNETWORK
source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

plugin="cln-nip47"
plugindir="/home/bitcoin/cl-plugins-available/${plugin}"
pluginbin="${plugindir}/target/release/${plugin}"
enabled_dir="/home/bitcoin/${netprefix}cl-plugins-enabled"
symlink_target="${enabled_dir}/${plugin}"
repo_url="https://github.com/daywalker90/cln-nip47.git"

# ensure enabled directory exists (idempotent)
if [ ! -d "${enabled_dir}" ]; then
  sudo -u bitcoin mkdir -p "${enabled_dir}"
fi

install_build() {
  # clone if missing
  if [ ! -d "${plugindir}/.git" ]; then
    sudo -u bitcoin mkdir -p "/home/bitcoin/cl-plugins-available"
    cd /home/bitcoin/cl-plugins-available || exit 1
    sudo -u bitcoin git clone "${repo_url}" "${plugin}" || exit 1
  else
    # update repo if it exists
    cd "${plugindir}" || exit 1
    sudo -u bitcoin git fetch --all
    sudo -u bitcoin git pull --ff-only || true
  fi

  # build release binary (idempotent) using system-wide Rust (/opt/rust)
  echo "# Building ${plugin} with cargo --release (RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/rust) ..."
  cd "${plugindir}" || exit 1
  sudo -u bitcoin RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/rust cargo build --release || exit 1

  # ensure binary permissions
  if [ -f "${pluginbin}" ]; then
    sudo chmod +x "${pluginbin}"
  else
    echo "# Build seems to have failed, missing ${pluginbin}"
    exit 1
  fi

  # create/refresh symlink into enabled dir
  if [ -L "${symlink_target}" ] || [ -f "${symlink_target}" ]; then
    sudo rm -f "${symlink_target}"
  fi
  sudo ln -s "${pluginbin}" "${enabled_dir}" || exit 1
}

if [ "$1" = "on" ]; then
  install_build

  # set flag in raspiblitz config (idempotent)
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clnnip47 "on"

  # set default CLN config options if not present yet
  if ! grep -q "^nip47-relays=" "${CLCONF}"; then
    echo "# setting nip47-relays=wss://relay.getalby.com/v1"
    sudo /home/admin/config.scripts/blitz.conf.sh set "nip47-relays" "wss://relay.getalby.com/v1" "${CLCONF}" "noquotes"
  fi
  if ! grep -q "^nip47-notifications=" "${CLCONF}"; then
    echo "# setting nip47-notifications=false"
    sudo /home/admin/config.scripts/blitz.conf.sh set "nip47-notifications" "false" "${CLCONF}" "noquotes"
  fi

  # restart service to apply updated CLCONF and load plugin (if system is ready)
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" = "ready" ] && [ "$3" != "norestart" ]; then
    echo "# Restarting ${netprefix}lightningd to apply nip47 options and load plugin"
    sudo systemctl restart ${netprefix}lightningd
  fi

  # Display next steps
  echo ""
  echo "#####################################################################################################"
  echo "# Usage: cl nip47-create label [budget_msat] [interval]"
  echo "# https://github.com/daywalker90/cln-nip47?tab=readme-ov-file#methods"
  echo ""
  echo "# Example: cl nip47-create my_nwc 10000 30d"
  echo "creates a new NWC entry named `my_nwc` with a budget of 10000 msat and an interval of 30 days"
  echo ""
  echo "# To display as QR code for scanning:"
  echo "cl nip47-list | jq -r '.[].my_nwc.uri' | qrencode  -t ANSIUTF8"
  echo ""
  echo "#####################################################################################################"


fi

if [ "$1" = "off" ]; then
  echo "# Stop the ${plugin} if running (ignore errors)"
  $lightningcli_alias plugin stop "${symlink_target}" 2>/dev/null || true

  echo "# Remove symlink from enabled dir"
  sudo rm -f "${symlink_target}"

  # remove any explicit plugin options from ${CLCONF} using the nip47-* keys (no-op if none)
  echo "# Clean any nip47-* options from ${CLCONF} (if present)"
  sudo sed -i "/^nip47-/d" ${CLCONF}

  # set flag in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clnnip47 "off"

  echo "# The ${plugin} has been disabled"
fi

if [ "$1" = "remove" ]; then
  # ensure it's turned off first
  $0 off $2 norestart

  echo "# Removing plugin source directory ${plugindir}"
  sudo rm -rf "${plugindir}"
  echo "# Removed ${plugin}"
fi
