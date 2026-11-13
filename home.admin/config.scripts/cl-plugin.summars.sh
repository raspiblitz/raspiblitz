#!/bin/bash

# https://github.com/daywalker90/summars
# Show a summary of your channels in a nice table.
# Uses prebuilt release binaries (no Rust toolchain required at install time).

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Install and show the output of the summars plugin for Core Lightning"
  echo "Usage:"
  echo "cl-plugin.summars.sh [mainnet|testnet|signet] [runonce] [--version=<tag>]"
  echo
  echo "  runonce         stop the plugin again after printing the table"
  echo "  --version=<tag> optional git release tag to pin (e.g. v6.2.4)."
  echo "                  Omit to use the latest release."
  echo
  exit 1
fi

# parse named arguments
network="$1"
pinnedVersion=""
runonce=0
for arg in "${@:2}"; do
  case "${arg}" in
    --version=*) pinnedVersion="${arg#--version=}" ;;
    runonce)     runonce=1 ;;
    *) ;;
  esac
done

source <(/home/admin/config.scripts/network.aliases.sh getvars cl $network)

plugin="summars"
plugindir="/home/bitcoin/cl-plugins-available/${plugin}"
pluginbin="${plugindir}/${plugin}"
repo_owner="daywalker90"
repo_name="summars"

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

  # the tarball contains a single 'summars' binary at its root
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

  # remove legacy source-build directory (git clone + cargo target/)
  if [ -d "${plugindir}/.git" ] || [ -d "${plugindir}/target" ]; then
    echo "# Removing legacy source-build directory ${plugindir}"
    sudo rm -rf "${plugindir}"
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

if [ $($lightningcli_alias | grep -c "summars") -eq 0 ]; then
  echo "# Starting the summars plugin"

  if [ ! -f "${pluginbin}" ]; then
    install_binary
  fi

  $lightningcli_alias plugin start -H ${pluginbin} 1>/dev/null
fi

echo
echo "# Running:"
echo "${netprefix}lightning-cli -H summars summars-columns=IN_SATS,OUT_SATS,GRAPH_SATS,ALIAS,FLAG,BASE,PPM,UPTIME,HTLCS,STATE summars-sort-by=-IN_SATS"
echo
$lightningcli_alias -H summars summars-columns=IN_SATS,OUT_SATS,GRAPH_SATS,ALIAS,FLAG,BASE,PPM,UPTIME,HTLCS,STATE summars-sort-by=-IN_SATS
echo

if [ ${runonce} -eq 1 ]; then
  $lightningcli_alias plugin stop ${pluginbin}
fi
