#!/bin/bash

# https://github.com/lightningd/plugins/tree/master/feeadjuster

# https://github.com/lightningd/plugins/commits/master/feeadjuster
# optional: pin to a specific commit by passing it as the 3rd argument to 'on'
pinnedVersion=""

plugin="feeadjuster"
plugindir="/home/bitcoin/cl-plugins-available/plugins"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Install the feeadjuster plugin for Core Lightning"
  echo "Dynamically adjusts channel fees according to channel balances."
  echo
  echo "Usage:"
  echo "  cl-plugin.feeadjuster.sh on  [mainnet|testnet|signet] [--commit=<hash>]"
  echo "  cl-plugin.feeadjuster.sh off [mainnet|testnet|signet]"
  echo
  echo "  --commit=<hash>  optional git commit hash to pin the plugins repo to."
  echo "                   Omit to use the latest master (HEAD)."  
  echo
  echo "Key options (pass via CLN config or lightning-cli):"
  echo "  feeadjuster-adjustment-method   'default' | 'soft' | 'hard'"
  echo "  feeadjuster-threshold           relative balance delta to trigger update (default 0.05 = 5%)"
  echo "  feeadjuster-threshold-abs       absolute delta to always trigger update (default 0.001btc)"
  echo "  feeadjuster-enough-liquidity    beyond this liquidity, stop adjusting (default 0msat = off)"
  echo "  feeadjuster-imbalance           ratio at which to start acting (default 0.5)"
  echo "  feeadjuster-feestrategy         'global' (default) | 'median'"
  echo "  feeadjuster-median-multiplier   factor for median strategy (default 1.0)"
  echo "  feeadjuster-max-htlc-steps      max htlc stepping (default 0 = off)"
  echo "  feeadjuster-deactivate-fuzz     deactivate threshold randomization (default false)"
  echo "  feeadjuster-deactivate-fee-update  deactivate auto fee updates on forwards (default false)"
  echo "  feeadjuster-basefee             also adjust base fee dynamically (default false)"
  echo
  echo "Requires: uv (installed system-wide via cl.install.sh)"
  echo "https://github.com/lightningd/plugins/tree/master/feeadjuster"
  echo
  exit 1
fi

# parse named arguments (remaining args after $1 and $2)
norestart=0
for arg in "${@:3}"; do
  case "${arg}" in
    --commit=*) pinnedVersion="${arg#--commit=}" ;;
    norestart)  norestart=1 ;;
    *) ;;
  esac
done

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

function install() {
  # Clone the plugins repo if not yet present
  if [ ! -d "${plugindir}" ]; then
    cd /home/bitcoin/cl-plugins-available || exit 1
    sudo -u bitcoin git clone https://github.com/lightningd/plugins.git
  fi

  cd "${plugindir}" || exit 1
  sudo -u bitcoin git fetch origin
  if [ -n "${pinnedVersion}" ]; then
    echo "# Pinning plugins repo to commit ${pinnedVersion}"
    sudo -u bitcoin git reset --hard "${pinnedVersion}" || exit 1
  else
    echo "# Using latest master (HEAD)"
    sudo -u bitcoin git reset --hard origin/master || exit 1
  fi

  # uv is installed system-wide at /usr/local/bin/uv by cl.install.sh
  if ! command -v uv &>/dev/null; then
    echo "# ERROR: uv not found. Install Core Lightning first via cl.install.sh"
    exit 1
  fi

  echo "# Installing ${plugin} Python dependencies with uv"
  cd "${plugindir}/${plugin}" || exit 1
  sudo -u bitcoin uv sync --all-extras

  sudo chmod +x "${plugindir}/${plugin}/${plugin}.py"
}

if [ "$1" = "on" ]; then

  # warn interactively - skip in automated/scripted calls
  if [ "${norestart}" != "1" ]; then
    echo
    echo "# WARNING: feeadjuster will immediately recalculate and overwrite"
    echo "# the fees on ALL your channels upon startup based on current balances."
    echo "# Any manually set fees will be replaced."
    echo "# Make sure feeadjuster-* options are configured in cl.conf first."
    echo
    echo "# Press ENTER to continue or CTRL+C to abort."
    read -r _
  fi

  install

  if [ ! -L "/home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}.py" ]; then
    echo "# Creating symlink for ${plugin}"
    sudo ln -s "${plugindir}/${plugin}/${plugin}.py" \
               "/home/bitcoin/${netprefix}cl-plugins-enabled/"
  fi

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}feeadjuster "on"

  source <(/home/admin/_cache.sh get state)
  if [ "${state}" == "ready" ] && [ "${norestart}" != "1" ]; then
    echo "# Start ${netprefix}${plugin}"
    $lightningcli_alias plugin start "/home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}.py"
  fi

  echo "# The ${plugin} plugin is installed and enabled"

fi

if [ "$1" = "off" ]; then

  echo "# Stop the ${plugin}"
  $lightningcli_alias plugin stop "/home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}.py" 2>/dev/null

  echo "# Delete symlink"
  sudo rm -f "/home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}.py"

  # setting value in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}feeadjuster "off"

  echo "# The ${plugin} plugin was disabled"

fi