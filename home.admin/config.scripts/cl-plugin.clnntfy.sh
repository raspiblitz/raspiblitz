#!/bin/bash

# https://github.com/steepdawn974/cln-ntfy
# A core lightning plugin that forwards node events to an ntfy topic.
# Uses prebuilt release binaries (no Rust toolchain required at install time).
# Note: upstream yukibtc/cln-ntfy is archived; the releases below are
# published on the steepdawn974 fork which carries the v0.2 refactor.

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo
  echo "Install the cln-ntfy plugin (ntfy notifications) for Core Lightning"
  echo "Source: https://github.com/steepdawn974/cln-ntfy"
  echo
  echo "Usage:"
  echo "  cl-plugin.clnntfy.sh on  [mainnet|testnet|signet] [--version=<tag>]"
  echo "  cl-plugin.clnntfy.sh off [mainnet|testnet|signet]"
  echo "  cl-plugin.clnntfy.sh remove [mainnet|testnet|signet]"
  echo
  echo "  --version=<tag>  optional git release tag to pin (e.g. v0.2.0)."
  echo "                  Omit to use the latest release."
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

plugin="cln-ntfy"
plugindir="/home/bitcoin/cl-plugins-available/${plugin}"
pluginbin="${plugindir}/${plugin}"
enabled_dir="/home/bitcoin/${netprefix}cl-plugins-enabled"
symlink_target="${enabled_dir}/${plugin}"
repo_owner="steepdawn974"
repo_name="cln-ntfy"

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
isAARCH64=$(uname -m | grep -c 'aarch64')
isX86_64=$(uname -m | grep -c 'x86_64')
if [ ${isAARCH64} -eq 1 ]; then
  arch="aarch64"
elif [ ${isX86_64} -eq 1 ]; then
  arch="x86_64"
else
  echo "# FAIL: unsupported architecture $(uname -m) (no release build)"
  exit 1
fi
echo "# architecture: ${arch}"

# ensure enabled directory exists (idempotent)
if [ ! -d "${enabled_dir}" ]; then
  sudo -u bitcoin mkdir -p "${enabled_dir}"
fi

install_binary() {
  local version="${pinnedVersion}"
  local asset="${plugin}-linux-${arch}.tar.gz"
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

  # the tarball contains a single 'cln-ntfy' binary at its root
  local extracted_bin="${tmpdir}/${plugin}"
  if [ ! -f "${extracted_bin}" ]; then
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

  # fetch the sample template from the same release tag (not in the tarball)
  local template_src="${plugindir}/ntfy-template.sample.conf"
  if [ ! -f "${template_src}" ]; then
    echo "# Downloading ntfy-template.sample.conf (${version}) ..."
    if ! sudo -u bitcoin wget -q -O "${template_src}" \
      "https://raw.githubusercontent.com/${repo_owner}/${repo_name}/${version}/ntfy-template.sample.conf"; then
      echo "# WARNING: could not download sample template (optional)"
      sudo rm -f "${template_src}"
    fi
  fi

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
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clnntfy "on"

  # set default CLN config options if not present yet.
  # SAFE DEFAULTS: the plugin starts but publishes NOTHING until the user
  # explicitly opts in by changing ntfy-events. A random topic is generated so
  # that even when events are later enabled on the public ntfy.sh, the topic
  # is unguessable and the user's notifications stay private.
  if ! grep -q "^ntfy-url=" "${CLCONF}"; then
    echo "# setting ntfy-url=https://ntfy.sh (public server; change to self-hosted if desired)"
    sudo /home/admin/config.scripts/blitz.conf.sh set "ntfy-url" "https://ntfy.sh" "${CLCONF}" "noquotes"
  fi
  if ! grep -q "^ntfy-topic=" "${CLCONF}"; then
    random_suffix=$(head -c 8 /dev/urandom | xxd -p)
    topic="cln-${random_suffix}"
    echo "# setting ntfy-topic=${topic} (random, private)"
    sudo /home/admin/config.scripts/blitz.conf.sh set "ntfy-topic" "${topic}" "${CLCONF}" "noquotes"
  fi
  if ! grep -q "^ntfy-events=" "${CLCONF}"; then
    echo "# setting ntfy-events=none (nothing published until you opt in)"
    sudo /home/admin/config.scripts/blitz.conf.sh set "ntfy-events" "none" "${CLCONF}" "noquotes"
  fi

  # copy the sample template file next to the CLN config (idempotent)
  template_src="${plugindir}/ntfy-template.sample.conf"
  template_dst="/home/bitcoin/.lightning/ntfy-template.conf"
  if [ -f "${template_src}" ] && [ ! -f "${template_dst}" ]; then
    echo "# copying sample template to ${template_dst}"
    sudo cp "${template_src}" "${template_dst}"
    sudo chown bitcoin:bitcoin "${template_dst}"
  fi
  if ! grep -q "^ntfy-template-file=" "${CLCONF}" && [ -f "${template_dst}" ]; then
    echo "# setting ntfy-template-file=${template_dst}"
    sudo /home/admin/config.scripts/blitz.conf.sh set "ntfy-template-file" "${template_dst}" "${CLCONF}" "noquotes"
  fi

  # restart service to apply updated CLCONF and load plugin (if system is ready)
  source <(/home/admin/_cache.sh get state)
  if [ "${state}" = "ready" ] && [ "${norestart}" != "1" ]; then
    echo "# Restarting ${netprefix}lightningd to apply ntfy options and load plugin"
    sudo systemctl restart ${netprefix}lightningd
  fi

  # Display next steps
  echo ""
  echo "#####################################################################################################"
  echo "# cln-ntfy ${pinnedVersion} is installed but INERT (ntfy-events=none)."
  echo "# Nothing is published until you enable events in ${CLCONF}."
  echo "# https://github.com/steepdawn974/cln-ntfy#options"
  echo ""
  echo "# Defaults already set: ntfy-url, ntfy-topic (random), ntfy-events=none"
  echo ""
  echo "# TO ENABLE NOTIFICATIONS, edit ${CLCONF} and set:"
  echo "#   ntfy-events=all   # or a subset: invoice_payment,channel_opened"
  echo ""
  echo "# OPTIONAL (self-hosted server):"
  echo "#   ntfy-url=https://ntfy.example.com"
  echo "# OPTIONAL (basic auth):"
  echo "#   ntfy-username=alice"
  echo "#   ntfy-password=secret"
  echo "# OPTIONAL (access token, mutually exclusive with basic auth):"
  echo "#   ntfy-token=tk_abc123..."
  echo "# OPTIONAL (for .onion servers):"
  echo "#   ntfy-proxy=socks5h://127.0.0.1:9050"
  echo "# OPTIONAL (custom message templates):"
  echo "#   A sample template was copied to /home/bitcoin/.lightning/ntfy-template.conf"
  echo "#   Edit it to customize titles/messages, or remove ntfy-template-file to use defaults."
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

  # remove any explicit plugin options from ${CLCONF} using the ntfy-* keys (no-op if none)
  echo "# Clean any ntfy-* options from ${CLCONF} (if present)"
  sudo sed -i "/^ntfy-/d" ${CLCONF}

  # set flag in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ${netprefix}clnntfy "off"

  echo "# The ${plugin} has been disabled"
fi

if [ "$1" = "remove" ]; then
  # ensure it's turned off first
  $0 off $2 norestart

  echo "# Removing plugin directory ${plugindir}"
  sudo rm -rf "${plugindir}"
  echo "# Removed ${plugin}"
fi
