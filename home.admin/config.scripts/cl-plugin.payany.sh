#!/bin/bash

# https://github.com/daywalker90/payany
# A core lightning plugin that supercharges pay/xpay/renepay: it can
# automatically fetch invoices for static lightning payment addresses
# (LNURL, LUD-16 ln-addresses, BIP353, bolt12 offers) and enforce a
# spending budget per time window.
# Uses prebuilt release binaries (no Rust toolchain required at install time).

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Install the payany plugin for Core Lightning"
  echo "Pay static lightning addresses (user@domain, LNURL, BIP353, bolt12)"
  echo "via pay/xpay/renepay and optionally enforce a spending budget."
  echo "Source: https://github.com/daywalker90/payany"
  echo
  echo "Usage:"
  echo "  cl-plugin.payany.sh on  [mainnet|testnet|signet] [--version=<tag>]"
  echo "  cl-plugin.payany.sh off [mainnet|testnet|signet]"
  echo "  cl-plugin.payany.sh remove [mainnet|testnet|signet]"
  echo
  echo "  --version=<tag>  optional git release tag to pin (e.g. v0.4.0)."
  echo "                  Omit to use the latest release."
  echo
  echo "Key options (set in CLN config or via 'lightning-cli setconfig'):"
  echo "  payany-budget-per           rolling time window for the budget"
  echo "                              (e.g. 1day, 1week; unset = unrestricted)"
  echo "  payany-budget-amount-msat   max spend incl. fees in that window"
  echo "                              (unset = unrestricted)"
  echo "  payany-xpay-handle-pay      let xpay handle 'pay', default false"
  echo "  payany-strict-lnurl         strict LUD-06/LUD-16 checks, default false"
  echo
  echo "RPC method: payany <invstring> <amount_msat> [message]"
  echo "  (fetch the invoice only, without paying)"
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

plugin="payany"
plugindir="/home/bitcoin/cl-plugins-available/${plugin}"
pluginbin="${plugindir}/${plugin}"
enabled_dir="/home/bitcoin/${netprefix}cl-plugins-enabled"
symlink_target="${enabled_dir}/${plugin}"
repo_owner="daywalker90"
repo_name="payany"

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

  # the tarball contains a single 'payany' binary at its root
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
  install_binary

  # create/refresh symlink into enabled dir
  if [ -L "${symlink_target}" ] || [ -f "${symlink_target}" ]; then
    sudo rm -f "${symlink_target}"
  fi
  sudo ln -s "${pluginbin}" "${enabled_dir}"

  # set flag in raspiblitz config (idempotent)
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}payany "on"

  # restart service to load plugin (if system is ready)
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" = "ready" ] && [ "${norestart}" != "1" ]; then
    echo "# Restarting ${netprefix}lightningd to load ${plugin}"
    sudo systemctl restart ${netprefix}lightningd
  fi

  echo ""
  echo "#####################################################################################################"
  echo "# payany ${pinnedVersion} is installed and enabled."
  echo "# https://github.com/daywalker90/payany#readme"
  echo ""
  echo "# payany extends pay/xpay/renepay so they accept static lightning"
  echo "# payment addresses. An explicit amount_msat is always required:"
  echo "#   ${netprefix}lightning-cli xpay user@domain.com 10000"
  echo "#   ${netprefix}lightning-cli pay -k bolt11=user@domain.com amount_msat=10000 \\"
  echo "#       message=\"thanks for the item\""
  echo ""
  echo "# Fetch an invoice without paying (offers, bip353, LNURL, ln-address):"
  echo "#   ${netprefix}lightning-cli payany user@domain.com 10000"
  echo ""
  echo "# OPTIONAL spending budget (in ${CLCONF} or via setconfig):"
  echo "#   payany-budget-per=1week"
  echo "#   payany-budget-amount-msat=100000000   # 100k sats per week"
  echo "# The budget only applies to pay/xpay/renepay - withdraw and"
  echo "# fundchannel push_msat are NOT covered."
  echo ""
  echo "# NOTE: payany fetches invoices over clearnet HTTP(S) unless CLN has"
  echo "# proxy + always-use-proxy=true configured. It also sets"
  echo "# xpay-handle-pay=false; set payany-xpay-handle-pay=true to restore."
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

  # remove any explicit plugin options from ${CLCONF} using the payany-* keys (no-op if none)
  echo "# Clean any payany-* options from ${CLCONF} (if present)"
  sudo sed -i "/^payany-/d" ${CLCONF}

  # set flag in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}payany "off"

  echo "# The ${plugin} has been disabled"
fi

if [ "$1" = "remove" ]; then
  # ensure it's turned off first
  $0 off $2 norestart

  echo "# Removing plugin directory ${plugindir}"
  sudo rm -rf "${plugindir}"
  echo "# Removed ${plugin}"
fi
