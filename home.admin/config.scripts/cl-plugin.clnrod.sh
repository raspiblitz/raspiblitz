#!/bin/bash

# https://github.com/daywalker90/clnrod
# A core lightning plugin to allow/deny incoming channel opens (including
# zeroconf configuration) based on lists and/or a custom rule.
# Uses prebuilt release binaries (no Rust toolchain required at install time).

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Install the clnrod plugin for Core Lightning"
  echo "Allow/deny incoming channel opens based on allow/deny/zeroconf lists"
  echo "and/or a custom rule (channel acceptor)."
  echo "Source: https://github.com/daywalker90/clnrod"
  echo
  echo "Usage:"
  echo "  cl-plugin.clnrod.sh on  [mainnet|testnet|signet] [--version=<tag>]"
  echo "  cl-plugin.clnrod.sh off [mainnet|testnet|signet]"
  echo "  cl-plugin.clnrod.sh remove [mainnet|testnet|signet]"
  echo
  echo "  --version=<tag>  optional git release tag to pin (e.g. v0.6.1)."
  echo "                  Omit to use the latest release."
  echo
  echo "Key options (set in CLN config or via 'lightning-cli setconfig'):"
  echo "  clnrod-blockmode          allow|deny, default deny (with no config"
  echo "                            clnrod accepts all channels)"
  echo "  clnrod-customrule         custom rule for accepting channels"
  echo "  clnrod-denymessage        message sent to rejected peers"
  echo "  clnrod-leakreason         leak reject reason to peer, default false"
  echo "  clnrod-pinglength         ping msg size for rule check, default 256"
  echo "  clnrod-smtp-*             smtp settings for email notifications"
  echo "  clnrod-email-from/to      email addresses for notifications"
  echo "  clnrod-notify-verbosity   ERROR|ACCEPTED|ALL"
  echo
  echo "Lists live in ~/.lightning/<network>/clnrod/:"
  echo "  allowlist.txt  denylist.txt  zeroconflist.txt"
  echo
  echo "RPC methods: clnrod-managelists, clnrod-reload, clnrod-testrule,"
  echo "  clnrod-testmail, clnrod-testping"
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

plugin="clnrod"
plugindir="/home/bitcoin/cl-plugins-available/${plugin}"
pluginbin="${plugindir}/${plugin}"
enabled_dir="/home/bitcoin/${netprefix}cl-plugins-enabled"
symlink_target="${enabled_dir}/${plugin}"
repo_owner="daywalker90"
repo_name="clnrod"

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

  # the tarball contains a single 'clnrod' binary at its root
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
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clnrod "on"

  # restart service to load plugin (if system is ready)
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" = "ready" ] && [ "${norestart}" != "1" ]; then
    echo "# Restarting ${netprefix}lightningd to load ${plugin}"
    sudo systemctl restart ${netprefix}lightningd
  fi

  echo ""
  echo "#####################################################################################################"
  echo "# clnrod ${pinnedVersion} is installed and enabled."
  echo "# https://github.com/daywalker90/clnrod#options"
  echo ""
  echo "# DEFAULT BEHAVIOR: with no clnrod-* options set, all channel opens are"
  echo "# accepted (blockmode=deny with empty denylist and no custom rule)."
  echo ""
  echo "# USAGE (via ${netprefix}lightning-cli):"
  echo "#   clnrod-managelists allow add <pubkey>    # manage allow/deny/zeroconf lists"
  echo "#   clnrod-reload                            # reload list files"
  echo "#   clnrod-testrule -k pubkey=<pk> public=true their_funding_sat=1000000 \\"
  echo "#       rule='amboss_terminal_web_rank < 1000'"
  echo "#   clnrod-testping <pubkey> [count] [length]"
  echo ""
  echo "# SET OPTIONS while CLN is running (persists to ${CLCONF}):"
  echo "#   lightning-cli setconfig clnrod-blockmode allow"
  echo "#   lightning-cli setconfig clnrod-customrule 'their_funding_sat >= 1000000'"
  echo ""
  echo "# EXAMPLE CONFIGS (add to ${CLCONF} or via setconfig):"
  echo ""
  echo "#   1) Reputable-peers-only (fail-closed, recommended):"
  echo "#      clnrod-blockmode=allow"
  echo "#      clnrod-customrule=their_funding_sat >= 1000000 && \\"
  echo "#        their_funding_sat <= 50000000 && cln_multi_channel_count <= 1 && \\"
  echo "#        (amboss_terminal_web_rank <= 2000 || oneml_age <= 5000 || \\"
  echo "#         (cln_channel_count >= 5 && cln_node_capacity_sat >= 100000000))"
  echo "#      Then allowlist trusted peers (bypasses the rule, allows 2nd channels):"
  echo "#      lightning-cli clnrod-managelists allow add <pubkey>"
  echo ""
  echo "#   2) Simple size gate (default-accept posture):"
  echo "#      clnrod-blockmode=deny"
  echo "#      clnrod-customrule=their_funding_sat >= 1000000 && \\"
  echo "#        cln_multi_channel_count <= 1"
  echo ""
  echo "#   3) Whitelist only (reject all unlisted peers):"
  echo "#      clnrod-blockmode=allow"
  echo "#      (no customrule; populate allowlist.txt via clnrod-managelists)"
  echo ""
  echo "# OPTIONAL: email notifications on rejects/errors:"
  echo "#   clnrod-smtp-username=<user>     clnrod-smtp-password=<pass>"
  echo "#   clnrod-smtp-server=<host>       clnrod-smtp-port=587"
  echo "#   clnrod-email-from=<addr>        clnrod-email-to=<addr>"
  echo "#   clnrod-notify-verbosity=ALL     # ERROR|ACCEPTED|ALL"
  echo "#   lightning-cli clnrod-testmail   # verify email config"
  echo ""
  echo "# WARNING: blockmode=allow with an empty allowlist rejects ALL channel"
  echo "# opens. Test rules first with clnrod-testrule."
  echo "# To guarantee no open bypasses clnrod, load it as an important-plugin"
  echo "# (CLN stops entirely if the plugin crashes)."
  echo "#####################################################################################################"

fi

if [ "$1" = "off" ]; then
  echo "# Stop the ${plugin} if running (ignore errors)"
  $lightningcli_alias plugin stop "${symlink_target}" 2>/dev/null || true

  echo "# Remove symlink from enabled dir"
  sudo rm -f "${symlink_target}"

  # remove any explicit plugin options from ${CLCONF} using the clnrod-* keys (no-op if none)
  echo "# Clean any clnrod-* options from ${CLCONF} (if present)"
  sudo sed -i "/^clnrod-/d" ${CLCONF}

  # set flag in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clnrod "off"

  echo "# The ${plugin} has been disabled"
fi

if [ "$1" = "remove" ]; then
  # ensure it's turned off first
  $0 off $2 norestart

  echo "# Removing plugin directory ${plugindir}"
  sudo rm -rf "${plugindir}"
  echo "# Removed ${plugin}"
fi
