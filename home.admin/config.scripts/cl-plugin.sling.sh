#!/bin/bash

# https://github.com/daywalker90/sling
# A core lightning plugin to automatically rebalance multiple channels.
# Uses prebuilt release binaries (no Rust toolchain required at install time).

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Install the sling plugin for Core Lightning"
  echo "Automatic channel rebalancing (pull/push sats between channels)."
  echo "Source: https://github.com/daywalker90/sling"
  echo
  echo "Usage:"
  echo "  cl-plugin.sling.sh on  [mainnet|testnet|signet] [--version=<tag>]"
  echo "  cl-plugin.sling.sh off [mainnet|testnet|signet]"
  echo "  cl-plugin.sling.sh remove [mainnet|testnet|signet]"
  echo
  echo "  --version=<tag>  optional git release tag to pin (e.g. v4.3.0)."
  echo "                  Omit to use the latest release."
  echo
  echo "Key options (set in ${CLCONF} or via lightning-cli):"
  echo "  sling-depleteuptopercent         float 0-<1, default 0.2"
  echo "  sling-depleteuptoamount          sats, default 2000000"
  echo "  sling-maxhops                    max hops, default 8"
  echo "  sling-paralleljobs               parallel routes, default 1"
  echo "  sling-timeoutpay                 seconds, default 120"
  echo "  sling-max-htlc-count             softcap, default 5"
  echo "  sling-autogo                     auto-start jobs, default false"
  echo "  sling-refresh-aliasmap-interval  seconds, default 3600"
  echo "  sling-reset-liquidity-interval   minutes, default 360"
  echo "  sling-candidates-min-age         blocks, default 0"
  echo "  sling-stats-delete-failures-age  days, default 30 (0=never)"
  echo "  sling-stats-delete-successes-age days, default 30 (0=never)"
  echo "  sling-stats-delete-failures-size count, default 10000 (0=never)"
  echo "  sling-stats-delete-successes-size count, default 10000 (0=never)"
  echo "  sling-inform-layers              layers to inform, default xpay"
  echo
  echo "RPC methods: sling-version, sling-job, sling-jobsettings, sling-go,"
  echo "  sling-stop, sling-once, sling-stats, sling-deletejob,"
  echo "  sling-except-chan, sling-except-peer"
  echo
  exit 1
fi

# parse named arguments (remaining args after $1 and $2)
pinnedVersion=""
norestart=0
for arg in "${@:3}"; do
  case "${arg}" in
    --version=*) pinnedVersion="${arg#--version=}" ;;
    norestart)   norestart=1 ;;
    *) ;;
  esac
done

# load CLN network aliases and useful vars
# provides: netprefix ("" or "t" or "s"), CLCONF, lightningcli_alias, CLNETWORK
source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

plugin="sling"
plugindir="/home/bitcoin/cl-plugins-available/${plugin}"
pluginbin="${plugindir}/${plugin}"
enabled_dir="/home/bitcoin/${netprefix}cl-plugins-enabled"
symlink_target="${enabled_dir}/${plugin}"
repo_owner="daywalker90"
repo_name="sling"

# resolve the version to install and fetch release metadata
# (release_json is also used for sha256 verification in install_binary)
if [ -z "${pinnedVersion}" ]; then
  release_api="https://api.github.com/repos/${repo_owner}/${repo_name}/releases/latest"
else
  release_api="https://api.github.com/repos/${repo_owner}/${repo_name}/releases/tags/${pinnedVersion}"
fi
release_json=$(curl -s "${release_api}")
if [ -z "${pinnedVersion}" ]; then
  pinnedVersion=$(echo "${release_json}" | grep '"tag_name"' | cut -d '"' -f4)
  if [ -z "${pinnedVersion}" ]; then
    echo "# ERROR: could not determine latest ${plugin} release"
    exit 1
  fi
fi
echo "# ${plugin} version: ${pinnedVersion}"

# detect CPU architecture and map to the release asset suffix
isARM=$(uname -m | grep -c 'arm')
isAARCH64=$(uname -m | grep -c 'aarch64')
isX86_64=$(uname -m | grep -c 'x86_64')
if [ ${isARM} -eq 1 ]; then
  arch="armv7-linux-gnueabihf"
elif [ ${isAARCH64} -eq 1 ]; then
  arch="aarch64-linux-gnu"
elif [ ${isX86_64} -eq 1 ]; then
  arch="x86_64-linux-gnu"
else
  echo "# FAIL: unsupported architecture $(uname -m)"
  exit 1
fi
echo "# architecture: ${arch}"

# ensure enabled directory exists (idempotent)
if [ ! -d "${enabled_dir}" ]; then
  sudo -u bitcoin mkdir -p "${enabled_dir}"
fi

install_binary() {
  local version="${pinnedVersion}"
  local asset="${plugin}-${version}-${arch}.tar.gz"
  local url="https://github.com/${repo_owner}/${repo_name}/releases/download/${version}/${asset}"
  local tmpdir
  tmpdir=$(mktemp -d)

  chown bitcoin:bitcoin "${tmpdir}"
  # expected sha256 from the asset digest published in the release metadata
  local expected
  expected=$(echo "${release_json}" | jq -r --arg a "${asset}" \
    '.assets[] | select(.name==$a) | .digest' | sed 's/^sha256://')
  if [ -z "${expected}" ] || [ "${expected}" = "null" ]; then
    echo "# ERROR: no sha256 digest for ${asset} in release ${version}"
    sudo rm -rf "${tmpdir}"
    exit 1
  fi

  echo "# Downloading ${asset} ..."
  if ! sudo -u bitcoin wget -O "${tmpdir}/${asset}" "${url}"; then
    echo "# ERROR: download failed for ${url}"
    sudo rm -rf "${tmpdir}"
    exit 1
  fi

  echo "# Verifying sha256 checksum ..."
  if ! echo "${expected}  ${tmpdir}/${asset}" | sha256sum -c -; then
    echo "# ERROR: checksum mismatch for ${asset} - aborting install"
    sudo rm -rf "${tmpdir}"
    exit 1
  fi

  echo "# Extracting ${asset} ..."
  if ! sudo -u bitcoin tar -xzf "${tmpdir}/${asset}" -C "${tmpdir}"; then
    echo "# ERROR: extraction failed"
    sudo rm -rf "${tmpdir}"
    exit 1
  fi

  # the tarball contains a single 'sling' binary at its root
  local extracted_bin="${tmpdir}/${plugin}"
  if [ ! -f "${extracted_bin}" ]; then
    # fall back to searching one level deep
    extracted_bin=$(find "${tmpdir}" -type f -name "${plugin}" | head -1)
  fi
  if [ -z "${extracted_bin}" ] || [ ! -f "${extracted_bin}" ]; then
    echo "# ERROR: ${plugin} binary not found in archive"
    sudo rm -rf "${tmpdir}"
    exit 1
  fi

  # install into the plugin directory
  sudo -u bitcoin mkdir -p "${plugindir}"
  sudo install -m 0755 -o bitcoin -g bitcoin "${extracted_bin}" "${pluginbin}"

  sudo rm -rf "${tmpdir}"

  if [ ! -f "${pluginbin}" ]; then
    echo "# ERROR: ${pluginbin} missing after install"
    exit 1
  fi
}

if [ "$1" = "on" ]; then
  # warn interactively - skip in automated/scripted calls
  if [ "${norestart}" != "1" ]; then
    echo
    echo "# NOTE: sling rebalances channels by sending payments through your"
    echo "# other channels. This costs on-chain fee budget (sats in routing fees)."
    echo "# Configure sling-* options in ${CLCONF} and add jobs with 'sling-job'."
    echo
    echo "# Press ENTER to continue or CTRL+C to abort."
    read -r _
  fi

  install_binary

  # create/refresh symlink into enabled dir
  if [ -L "${symlink_target}" ] || [ -f "${symlink_target}" ]; then
    sudo rm -f "${symlink_target}"
  fi
  sudo ln -s "${pluginbin}" "${enabled_dir}"

  # set flag in raspiblitz config (idempotent)
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}sling "on"

  # restart service to load plugin (if system is ready)
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" = "ready" ] && [ "${norestart}" != "1" ]; then
    echo "# Restarting ${netprefix}lightningd to load ${plugin}"
    sudo systemctl restart ${netprefix}lightningd
  fi

  echo ""
  echo "#####################################################################################################"
  echo "# sling ${pinnedVersion} is installed and enabled."
  echo "# https://github.com/daywalker90/sling#options"
  echo ""
  echo "# USAGE (via ${netprefix}lightning-cli):"
  echo "#   sling-version"
  echo "#   sling-job -k scid=<scid> direction=pull amount=<sats> maxppm=<ppm> outppm=<ppm>"
  echo "#   sling-go            # start all jobs"
  echo "#   sling-stop          # stop all jobs"
  echo "#   sling-stats         # show status"
  echo "#   sling-deletejob all # remove all jobs"
  echo ""
  echo "# OPTIONAL global options (in ${CLCONF}):"
  echo "#   sling-maxhops=8"
  echo "#   sling-paralleljobs=1"
  echo "#   sling-timeoutpay=120"
  echo "#   sling-autogo=true   # auto-start jobs on plugin load"
  echo ""
  echo "# After editing ${CLCONF} restart CLN:"
  echo "#   sudo systemctl restart ${netprefix}lightningd"
  echo "#####################################################################################################"

fi

if [ "$1" = "off" ]; then
  echo "# Stop the ${plugin} if running (ignore errors)"
  $lightningcli_alias plugin stop "${symlink_target}" 2>/dev/null || true

  echo "# Remove symlink from enabled dir"
  sudo rm -f "${symlink_target}"

  # remove any explicit plugin options from ${CLCONF} using the sling-* keys (no-op if none)
  echo "# Clean any sling-* options from ${CLCONF} (if present)"
  sudo sed -i "/^sling-/d" ${CLCONF}

  # set flag in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}sling "off"

  echo "# The ${plugin} has been disabled"
fi

if [ "$1" = "remove" ]; then
  # ensure it's turned off first
  $0 off $2 norestart

  echo "# Removing plugin directory ${plugindir}"
  sudo rm -rf "${plugindir}"
  echo "# Removed ${plugin}"
fi
