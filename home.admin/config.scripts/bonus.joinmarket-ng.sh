#!/bin/bash

# bonus.joinmarket-ng.sh
# Installs JoinMarket-NG (Next Generation JoinMarket implementation)
# https://github.com/joinmarket-ng/joinmarket-ng
#
# Data and wallet layout
# ----------------------
# Wallets, config, and logs are owned by the dedicated ${USER_JM} system
# user and live under /mnt/hdd/app-data/${APPID} (symlinked into
# /home/${USER_JM}/.joinmarket-ng). The wallets directory is mode 0700.
#
# This is intentional: the admin user cannot read the wallet files directly.
# To use any command that touches the wallet (jm-wallet, jm-ng, jm-maker,
# jm-taker, ...), switch to the joinmarketng user first. A couple of
# equivalent options from the admin shell:
#
#     sudo su - ${USER_JM}          # interactive login as joinmarketng
#     sudo -u ${USER_JM} jm-ng      # run a single command
#
# Only management entry points (start/stop/status of the maker service,
# storing the wallet password, running self-update) are exposed to the
# joinmarketng user via the /etc/sudoers.d/${USER_JM}-maker rules.

# APPID
APPID="joinmarket-ng"
# Config key in raspiblitz.conf (must be valid bash variable name - no hyphens)
CONFIGKEY="joinmarketNG"
USER_JM="joinmarketng"

# VERSION
# Pinning a specific version/commit for stability
GITHUB_REPO="https://github.com/joinmarket-ng/joinmarket-ng"
GITHUB_TAG="0.30.0"

# GPG signature verification URLs
GITHUB_RAW="https://raw.githubusercontent.com/joinmarket-ng/joinmarket-ng/main"
GITHUB_RELEASES="https://github.com/joinmarket-ng/joinmarket-ng/releases/download"

# Compare local and release manifests by immutable git commit.
# Raspiblitz installs Python packages from git source and does not use the
# Docker image artifacts, so commit identity is the critical verification step.
manifest_commit_matches() {
  local RELEASE_MANIFEST="$1"
  local LOCAL_MANIFEST="$2"

  local RELEASE_COMMIT
  RELEASE_COMMIT=$(grep '^commit:' "${RELEASE_MANIFEST}" | awk '{print $2}')
  local LOCAL_COMMIT
  LOCAL_COMMIT=$(grep '^commit:' "${LOCAL_MANIFEST}" | awk '{print $2}')

  if [ -z "${RELEASE_COMMIT}" ] || [ -z "${LOCAL_COMMIT}" ]; then
    echo "#     Missing commit in release or local manifest."
    return 1
  fi

  if [ "${RELEASE_COMMIT}" != "${LOCAL_COMMIT}" ]; then
    echo "#     Commit mismatch between release and local manifest."
    return 1
  fi

  return 0
}

##########################
# verify_release <TAG>
# Downloads the release manifest and verifies at least one trusted GPG
# signature. On success, sets VERIFIED_COMMIT to the immutable commit SHA.
# On failure, prints an error and returns 1.
##########################
verify_release() {
  local TAG="$1"
  local TMPDIR
  TMPDIR=$(mktemp -d)
  local GNUPGHOME_ORIG="${GNUPGHOME:-}"
  export GNUPGHOME="${TMPDIR}/gnupg"
  mkdir -m 700 "${GNUPGHOME}"

  # Download release manifest
  local MANIFEST="${TMPDIR}/release-manifest-${TAG}.txt"
  echo "# Downloading release manifest for ${TAG}..."
  if ! curl -sfL "${GITHUB_RELEASES}/${TAG}/release-manifest-${TAG}.txt" -o "${MANIFEST}"; then
    echo "# FAIL: Could not download release manifest for ${TAG}"
    rm -rf "${TMPDIR}"
    [ -n "${GNUPGHOME_ORIG}" ] && export GNUPGHOME="${GNUPGHOME_ORIG}" || unset GNUPGHOME
    return 1
  fi

  # Download trusted-keys.txt
  local TRUSTED_KEYS="${TMPDIR}/trusted-keys.txt"
  if ! curl -sfL "${GITHUB_RAW}/signatures/trusted-keys.txt" -o "${TRUSTED_KEYS}"; then
    echo "# FAIL: Could not download trusted-keys.txt"
    rm -rf "${TMPDIR}"
    [ -n "${GNUPGHOME_ORIG}" ] && export GNUPGHOME="${GNUPGHOME_ORIG}" || unset GNUPGHOME
    return 1
  fi

  # Parse trusted fingerprints (skip comments and blank lines)
  local FINGERPRINTS=()
  while IFS= read -r line; do
    line=$(echo "${line}" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "${line}" ] && continue
    # First field is the fingerprint
    local fp
    fp=$(echo "${line}" | awk '{print $1}')
    FINGERPRINTS+=("${fp}")
  done < "${TRUSTED_KEYS}"

  if [ ${#FINGERPRINTS[@]} -eq 0 ]; then
    echo "# FAIL: No trusted keys found in trusted-keys.txt"
    rm -rf "${TMPDIR}"
    [ -n "${GNUPGHOME_ORIG}" ] && export GNUPGHOME="${GNUPGHOME_ORIG}" || unset GNUPGHOME
    return 1
  fi

  echo "# Found ${#FINGERPRINTS[@]} trusted key(s). Importing and verifying..."

  # Import public keys and verify signatures
  local VALID_SIGS=0
  for fp in "${FINGERPRINTS[@]}"; do
    # Import public key
    local PUBKEY="${TMPDIR}/${fp}.asc"
    if ! curl -sfL "${GITHUB_RAW}/signatures/pubkeys/${fp}.asc" -o "${PUBKEY}"; then
      echo "#   Key ${fp}: public key not found, skipping"
      continue
    fi
    gpg --batch --quiet --import "${PUBKEY}" 2>/dev/null

    # Download signature for this release
    local SIG="${TMPDIR}/${fp}.sig"
    if ! curl -sfL "${GITHUB_RAW}/signatures/${TAG}/${fp}.sig" -o "${SIG}"; then
      echo "#   Key ${fp}: no signature for ${TAG}, skipping"
      continue
    fi

    # Verify against CI release manifest first.
    if gpg --batch --verify "${SIG}" "${MANIFEST}" 2>/dev/null; then
      echo "#   Key ${fp}: VALID signature"
      VALID_SIGS=$((VALID_SIGS + 1))
      continue
    fi

    # Fallback for local-first workflow: signature may target <fingerprint>-manifest.txt.
    local LOCAL_MANIFEST="${TMPDIR}/${fp}-manifest.txt"
    if ! curl -sfL "${GITHUB_RAW}/signatures/${TAG}/${fp}-manifest.txt" -o "${LOCAL_MANIFEST}"; then
      echo "#   Key ${fp}: INVALID signature!"
      continue
    fi

    if ! gpg --batch --verify "${SIG}" "${LOCAL_MANIFEST}" 2>/dev/null; then
      echo "#   Key ${fp}: INVALID signature!"
      continue
    fi

    if manifest_commit_matches "${MANIFEST}" "${LOCAL_MANIFEST}"; then
      echo "#   Key ${fp}: VALID signature (local manifest commit matches release manifest)"
      VALID_SIGS=$((VALID_SIGS + 1))
    else
      echo "#   Key ${fp}: INVALID signature! (local manifest commit does not match release manifest)"
    fi
  done

  # Require at least one valid trusted signature
  if [ ${VALID_SIGS} -eq 0 ]; then
    echo "# FAIL: No valid trusted signatures found for release ${TAG}!"
    echo "# This could indicate a compromised or unsigned release. Aborting."
    rm -rf "${TMPDIR}"
    [ -n "${GNUPGHOME_ORIG}" ] && export GNUPGHOME="${GNUPGHOME_ORIG}" || unset GNUPGHOME
    return 1
  fi

  echo "# GPG verification passed: ${VALID_SIGS} valid trusted signature(s)."

  # Extract the immutable commit hash from the manifest
  VERIFIED_COMMIT=$(grep '^commit:' "${MANIFEST}" | awk '{print $2}')
  if [ -z "${VERIFIED_COMMIT}" ]; then
    echo "# FAIL: Could not extract commit hash from release manifest."
    rm -rf "${TMPDIR}"
    [ -n "${GNUPGHOME_ORIG}" ] && export GNUPGHOME="${GNUPGHOME_ORIG}" || unset GNUPGHOME
    return 1
  fi
  echo "# Verified commit: ${VERIFIED_COMMIT}"

  # Cleanup
  rm -rf "${TMPDIR}"
  [ -n "${GNUPGHOME_ORIG}" ] && export GNUPGHOME="${GNUPGHOME_ORIG}" || unset GNUPGHOME
  return 0
}

##########################
# installed_release_matches <COMMIT>
# Returns success only when every JoinMarket-NG package managed by this script
# records the expected immutable git commit in its PEP 610 direct_url.json.
##########################
installed_release_matches() {
  local EXPECTED_COMMIT="$1"
  local VENV_PYTHON="/home/${USER_JM}/venv/bin/python"

  if [ ! -x "${VENV_PYTHON}" ]; then
    echo "# Installed package provenance is unavailable: venv Python not found."
    return 1
  fi

  sudo -u ${USER_JM} "${VENV_PYTHON}" - "${EXPECTED_COMMIT}" <<'PYEOF'
import json
import re
import sys
from importlib.metadata import PackageNotFoundError, distribution

expected_commit = sys.argv[1].lower()
packages = {
    "jmcore": "jmcore",
    "jmwallet": "jmwallet",
    "jm-maker": "maker",
    "jm-taker": "taker",
}

if re.fullmatch(r"[0-9a-f]{40}", expected_commit) is None:
    print(f"# Invalid verified release commit: {expected_commit}")
    sys.exit(1)

for package, expected_subdirectory in packages.items():
    try:
        metadata = distribution(package)
        direct_url_text = metadata.read_text("direct_url.json")
        if direct_url_text is None:
            raise ValueError("direct_url.json is missing")
        direct_url = json.loads(direct_url_text)
        if not isinstance(direct_url, dict):
            raise ValueError("direct_url.json is not an object")
        vcs_info = direct_url.get("vcs_info")
        if not isinstance(vcs_info, dict) or vcs_info.get("vcs") != "git":
            raise ValueError("git provenance is missing")
        installed_commit = vcs_info.get("commit_id")
        if not isinstance(installed_commit, str):
            raise ValueError("git commit is missing")
        if direct_url.get("subdirectory") != expected_subdirectory:
            raise ValueError("source subdirectory does not match")
    except (PackageNotFoundError, json.JSONDecodeError, OSError, UnicodeError, ValueError) as exc:
        print(f"# Installed {package} provenance is unavailable: {exc}")
        sys.exit(1)

    if installed_commit.lower() != expected_commit:
        print(
            f"# Installed {package} commit {installed_commit} does not match "
            f"release commit {expected_commit}."
        )
        sys.exit(1)

sys.exit(0)
PYEOF
}

# BASIC COMMANDLINE OPTIONS
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# bonus.${APPID}.sh status    -> status information (key=value)"
  echo "# bonus.${APPID}.sh on        -> install the app"
  echo "# bonus.${APPID}.sh off       -> uninstall the app"
  echo "# bonus.${APPID}.sh menu      -> SSH menu dialog"
  echo "# bonus.${APPID}.sh verify-release [TAG] -> verify release signatures only"
  echo "# bonus.${APPID}.sh prestart  -> will be called by systemd before start"
  echo "# bonus.${APPID}.sh update [TAG] -> update to latest or specific version"
  exit 1
fi

echo "# Running: 'bonus.${APPID}.sh $*'"

# check & load raspiblitz config
source /mnt/hdd/app-data/raspiblitz.conf

# Helper: returns exit 0 if [wallet] mnemonic_password is set in config.toml (TOML-aware).
# Usage: toml_has_wallet_password <config_file>
toml_has_wallet_password() {
  local cfg="$1"
  python3 - "${cfg}" <<'PYEOF'
import sys, pathlib
try:
    import tomllib
except ImportError:
    import tomli as tomllib  # type: ignore[no-redef]
path = pathlib.Path(sys.argv[1])
if not path.exists():
    sys.exit(1)
try:
    data = tomllib.loads(path.read_text())
except Exception:
    sys.exit(1)
pwd = data.get("wallet", {}).get("mnemonic_password")
sys.exit(0 if (pwd is not None and str(pwd).strip() != "") else 1)
PYEOF
}

# determine the correct bitcoind service name based on chain
if [ "${chain}" = "test" ]; then
  bitcoind_service="tbitcoind"
  jm_network="testnet"
  bitcoin_rpc_port=18332
elif [ "${chain}" = "sig" ]; then
  bitcoind_service="sbitcoind"
  jm_network="signet"
  bitcoin_rpc_port=38332
else
  bitcoind_service="bitcoind"
  jm_network="mainnet"
  bitcoin_rpc_port=8332
fi

#########################
# INFO
#########################

# check if app is already installed
isInstalled=$(sudo ls /etc/systemd/system/${APPID}-maker.service 2>/dev/null | grep -c "${APPID}-maker.service")
# check if service is running
isRunning=$(systemctl status ${APPID}-maker 2>/dev/null | grep -c 'active (running)')

if [ "$1" = "status" ]; then
  # Determine the actually installed version via pip; fall back to pinned tag
  installedVersion=$(sudo -u ${USER_JM} /home/${USER_JM}/venv/bin/pip show jmcore 2>/dev/null \
    | awk '/^Version:/{print $2}')
  if [ -z "${installedVersion}" ]; then
    installedVersion="${GITHUB_TAG}"
  fi
  echo "appID='${APPID}'"
  echo "version='${installedVersion}'"
  echo "githubRepo='${GITHUB_REPO}'"
  echo "isInstalled=${isInstalled}"
  echo "isRunning=${isRunning}"
  exit
fi

if [ "$1" = "verify-release" ]; then
  VERIFY_TAG="${2:-${GITHUB_TAG}}"
  echo "# Verifying GPG signatures for release ${VERIFY_TAG}..."
  VERIFIED_COMMIT=""
  if ! verify_release "${VERIFY_TAG}"; then
    echo "# FAIL - GPG signature verification failed for ${VERIFY_TAG}"
    exit 1
  fi
  exit 0
fi

##########################
# MENU
#########################

if [ "$1" = "menu" ]; then
  # Show the TUI menu if installed
  if [ "${isInstalled}" == "1" ]; then
    sudo -u ${USER_JM} /home/${USER_JM}/venv/bin/jm-ng
  else
    whiptail --title " JoinMarket-NG " --msgbox "JoinMarket-NG is not installed." 10 40
  fi
  exit 0
fi

##########################
# MAKER-START
##########################

if [ "$1" = "maker-start" ]; then
  # Called as root (via sudoers from menu).
  # Password resolution order (the password is never written to config.toml
  # unless the user explicitly opted in via 'store-password'):
  #   1. Permanently stored in config.toml [wallet] -> nothing to do.
  #   2. Already provided by the TUI in .maker.env -> reuse it (no prompt).
  #   3. Otherwise prompt and write .maker.env for the systemd EnvironmentFile.
  CONFIG_FILE="/home/${USER_JM}/.joinmarket-ng/config.toml"
  ENV_FILE="/home/${USER_JM}/.joinmarket-ng/.maker.env"
  if toml_has_wallet_password "${CONFIG_FILE}"; then
    echo "# Password found in config.toml [wallet] section, no prompt needed."
  elif [ -f "${ENV_FILE}" ] && grep -q '^MNEMONIC_PASSWORD=' "${ENV_FILE}"; then
    echo "# Wallet password already staged in .maker.env, no prompt needed."
  else
    read -r -s -p "Wallet encryption password (Enter to skip if unencrypted): " WALLET_PWD
    echo ""
    # Write the password for the systemd EnvironmentFile using the
    # double-quoted form so special characters survive. systemd interprets
    # C-style escapes inside double quotes, so escape backslash and quote.
    ESCAPED_PWD=$(printf '%s' "${WALLET_PWD}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    printf 'MNEMONIC_PASSWORD="%s"\n' "${ESCAPED_PWD}" > "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
    chown "${USER_JM}:${USER_JM}" "${ENV_FILE}"
    unset WALLET_PWD ESCAPED_PWD
  fi
  echo "Starting ${APPID}-maker..."
  systemctl start ${APPID}-maker
  exit $?
fi

##########################
# MAKER-STOP
##########################

if [ "$1" = "maker-stop" ]; then
  echo "Stopping ${APPID}-maker..."
  systemctl stop ${APPID}-maker
  rm -f "/home/${USER_JM}/.joinmarket-ng/.maker.env"
  echo "Done."
  exit $?
fi

##########################
# MAKER-STATUS
##########################

if [ "$1" = "maker-status" ]; then
  systemctl status ${APPID}-maker --no-pager -l
  exit $?
fi

##########################
# STORE-PASSWORD
# Permanently write mnemonic_password to config.toml.
# Usage: bonus.joinmarket-ng.sh store-password <password>
##########################

if [ "$1" = "store-password" ]; then
  PASSWORD="${2}"
  CONFIG_FILE="/home/${USER_JM}/.joinmarket-ng/config.toml"
  if [ ! -f "${CONFIG_FILE}" ]; then
    echo "# FAIL: config.toml not found"
    exit 1
  fi
  python3 - "${CONFIG_FILE}" "${PASSWORD}" <<'PYEOF'
import sys, re

config_path = sys.argv[1]
password = sys.argv[2]

with open(config_path, "r") as fh:
    content = fh.read()

# Escape backslashes and double quotes for the TOML basic string value.
escaped = password.replace("\\", "\\\\").replace('"', '\\"')
new_line = 'mnemonic_password = "{}"'.format(escaped)

# Use a lambda replacement so re.sub does not reinterpret backslash escapes
# in the password value (which would un-escape the carefully escaped output).
if re.search(r"^\s*mnemonic_password\s*=", content, re.MULTILINE):
    content = re.sub(
        r"^\s*mnemonic_password\s*=.*$",
        lambda _m: new_line,
        content,
        flags=re.MULTILINE,
    )
elif re.search(r"^\[wallet\]", content, re.MULTILINE):
    content = re.sub(
        r"^\[wallet\]",
        lambda _m: "[wallet]\n" + new_line,
        content,
        flags=re.MULTILINE,
    )
else:
    content += "\n[wallet]\n" + new_line + "\n"

with open(config_path, "w") as fh:
    fh.write(content)
PYEOF
  echo "# Password stored in config.toml"
  # Now that the wallet password is permanently stored, enable maker
  # auto-start at boot. systemd can decrypt the wallet on its own, no
  # interactive prompt needed.
  if [ -f "/etc/systemd/system/${APPID}-maker.service" ]; then
    sudo systemctl enable ${APPID}-maker.service 2>/dev/null \
      && echo "# Maker auto-start enabled (boot)." \
      || echo "# WARNING: Could not enable maker auto-start."
  fi
  exit 0
fi

##########################
# PRESTART
#########################

if [ "$1" = "prestart" ]; then
  echo "# PRESTART: Updating configuration..."
  
  # Update RPC credentials before start
  # We read from bitcoin.conf which is root-owned, so this script must run as root (default for ExecStartPre if not restricted)
  RPC_USER=$(sudo grep rpcuser /mnt/hdd/app-data/bitcoin/bitcoin.conf | cut -d "=" -f 2)
  RPC_PASSWORD=$(sudo grep rpcpassword /mnt/hdd/app-data/bitcoin/bitcoin.conf | cut -d "=" -f 2)
  
  CONFIG_FILE="/mnt/hdd/app-data/${APPID}/config.toml"
  
  if [ ! -f "${CONFIG_FILE}" ]; then
      echo "# PRESTART ERROR: Config file not found at ${CONFIG_FILE}"
      echo "# Run 'bonus.joinmarket-ng.sh on' to reinstall."
      exit 1
  fi

  # Helper: escape a string for safe use in sed replacement
  escape_sed_replacement() {
      printf '%s' "$1" | sed -e 's/[&\\/|]/\\&/g'
  }

  RPC_USER_ESCAPED=$(escape_sed_replacement "${RPC_USER}")
  RPC_PASSWORD_ESCAPED=$(escape_sed_replacement "${RPC_PASSWORD}")

  # Update RPC User
  if grep -q "^rpc_user =" "${CONFIG_FILE}"; then
     sed -i "s|^rpc_user =.*|rpc_user = \"${RPC_USER_ESCAPED}\"|" "${CONFIG_FILE}"
  elif grep -q "^# rpc_user =" "${CONFIG_FILE}"; then
     sed -i "s|^# rpc_user =.*|rpc_user = \"${RPC_USER_ESCAPED}\"|" "${CONFIG_FILE}"
  fi

  # Update RPC Password
  if grep -q "^rpc_password =" "${CONFIG_FILE}"; then
     sed -i "s|^rpc_password =.*|rpc_password = \"${RPC_PASSWORD_ESCAPED}\"|" "${CONFIG_FILE}"
  elif grep -q "^# rpc_password =" "${CONFIG_FILE}"; then
     sed -i "s|^# rpc_password =.*|rpc_password = \"${RPC_PASSWORD_ESCAPED}\"|" "${CONFIG_FILE}"
  fi

  echo "# PRESTART: Config updated."

  # Abort if no wallet is configured — prevents a useless restart loop
  MNEMONIC_FILE=$(grep '^mnemonic_file[[:space:]]*=' "${CONFIG_FILE}" 2>/dev/null | head -1 | sed 's/^mnemonic_file[[:space:]]*=[[:space:]]*//' | tr -d '"')
  if [ -z "${MNEMONIC_FILE}" ] || [ ! -f "${MNEMONIC_FILE}" ]; then
      echo "# PRESTART ERROR: No wallet configured (mnemonic_file not set or file missing)."
      echo "# Use the JoinMarket-NG menu to create or import a wallet, then start the maker."
      exit 1
  fi

  echo "# PRESTART: Wallet OK: ${MNEMONIC_FILE}"

  # The wallet encryption password (when the user has NOT permanently stored
  # it in config.toml via 'store-password') is delivered to the maker process
  # through the systemd EnvironmentFile (.maker.env -> MNEMONIC_PASSWORD; see
  # the unit's EnvironmentFile= directive). We deliberately do NOT inject the
  # password into config.toml: keeping it out of the config file means the
  # secret is never left in cleartext on disk after the maker stops (including
  # after an unclean shutdown where ExecStopPost would not run).

  exit 0
fi

##########################
# ON / INSTALL
#########################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ ${isInstalled} -eq 1 ]; then
    echo "# ${APPID} is already installed."
    exit 1
  fi

  echo "# Installing ${APPID} ..."

  # 1. Install System Dependencies
  echo "# Installing system dependencies..."
  sudo apt-get update
  sudo apt-get install -y build-essential libffi-dev libsodium-dev pkg-config python3-dev python3-venv git

  # 1b. Ensure Bitcoin Core wallet support is enabled.
  #
  # RaspiBlitz defaults to 'disablewallet=1' for Bitcoin-only nodes (LND has
  # its own wallet, so Core's wallet subsystem is off by default to save
  # resources). When 'disablewallet=1', every wallet RPC -- including
  # 'listwallets', 'loadwallet', 'createwallet' and 'getaddressinfo' --
  # responds with '-32601 Method not found', which makes the JoinMarket-NG
  # descriptor wallet backend fail with a cryptic error on first use.
  #
  # JoinMarket-NG's descriptor wallet backend creates a watch-only descriptor
  # wallet inside Bitcoin Core, so wallet support MUST be enabled. We use
  # the existing 'network.wallet.sh on' helper, which is idempotent: it
  # rewrites 'disablewallet' to 0 in bitcoin.conf and restarts bitcoind
  # only if the value actually changed.
  echo "# Ensuring Bitcoin Core wallet support is enabled..."
  sudo /home/admin/config.scripts/network.wallet.sh on

  # 2. Create User
  echo "# Creating user ${USER_JM}..."
  if ! id -u "${USER_JM}" > /dev/null 2>&1; then
    sudo adduser --system --group --shell /bin/bash --home /home/${USER_JM} ${USER_JM}
  else 
    echo "# User ${USER_JM} already exists"
  fi
  
  # Copy skeleton files
  sudo -u ${USER_JM} cp -r /etc/skel/. /home/${USER_JM}/ 2>/dev/null

  # Add user to debian-tor group (for Tor control port cookie access)
  sudo usermod -aG debian-tor ${USER_JM}

  # 3. Create Data Directory on HDD
  echo "# Setting up data directory..."
  if ! [ -d /mnt/hdd/app-data/${APPID} ]; then
    sudo mkdir -p /mnt/hdd/app-data/${APPID}
  fi
  sudo chown ${USER_JM}:${USER_JM} -R /mnt/hdd/app-data/${APPID}

  # Create wallets subdirectory
  sudo -u ${USER_JM} mkdir -p /mnt/hdd/app-data/${APPID}/wallets
  sudo chmod 700 /mnt/hdd/app-data/${APPID}/wallets

  # Create logs subdirectory (readable by the user for menu access)
  sudo -u ${USER_JM} mkdir -p /mnt/hdd/app-data/${APPID}/logs

  # Symlink to home for standard JM-NG path (~/.joinmarket-ng)
  # JM-NG expects data in ~/.joinmarket-ng by default
  # We link the folder itself
  if [ -d "/home/${USER_JM}/.joinmarket-ng" ] && [ ! -L "/home/${USER_JM}/.joinmarket-ng" ]; then
     # If it's a real directory (not link), move contents or back up?
     # For safety, we assume fresh install or handled manually. 
     # But let's force link for now if empty or not critical.
     echo "# Warning: /home/${USER_JM}/.joinmarket-ng exists and is not a link."
  else
     sudo -u ${USER_JM} ln -sfn /mnt/hdd/app-data/${APPID} /home/${USER_JM}/.joinmarket-ng
  fi

  # 4. Verify release signature and get immutable commit hash
  echo "# Verifying GPG signatures for release ${GITHUB_TAG}..."
  VERIFIED_COMMIT=""
  if ! verify_release "${GITHUB_TAG}"; then
    echo "# FAIL - GPG signature verification failed for ${GITHUB_TAG}"
    exit 1
  fi

  # 5. Install JoinMarket-NG (using verified commit for immutable install)
  echo "# Installing JoinMarket-NG software..."
  
  # Venv lives on the system disk (not HDD) because /mnt/hdd is mounted noexec.
  # Only data (config, wallets, logs) goes on the HDD via the ~/.joinmarket-ng symlink.
  VENV_DIR="/home/${USER_JM}/venv"
  # Use the verified commit SHA (immutable) instead of the mutable tag
  GIT_URL="git+${GITHUB_REPO}.git@${VERIFIED_COMMIT}"
  
  # Create venv and install packages as the dedicated user
  if [ ! -d "${VENV_DIR}" ]; then
      echo "# Creating Python venv..."
      sudo -u ${USER_JM} python3 -m venv "${VENV_DIR}"
  fi
  
  echo "# Installing jmcore, jmwallet, maker, taker..."
  # Use the venv pip directly by full path. This is more reliable than
  # 'source activate && pip' under sudo -u, which can resolve the wrong pip
  # or cause pip to install scripts to ~/.local/bin instead of the venv.
  sudo -u ${USER_JM} bash -c "
    ${VENV_DIR}/bin/pip install --upgrade pip && \
    ${VENV_DIR}/bin/pip install '${GIT_URL}#subdirectory=jmcore' && \
    ${VENV_DIR}/bin/pip install '${GIT_URL}#subdirectory=jmwallet' && \
    ${VENV_DIR}/bin/pip install '${GIT_URL}#subdirectory=maker' && \
    ${VENV_DIR}/bin/pip install '${GIT_URL}#subdirectory=taker' && \
    ${VENV_DIR}/bin/pip install packaging
  "
  if [ $? -ne 0 ]; then
      echo "# FAIL - pip install failed"
      exit 1
  fi

  # 6. Configuration
  echo "# configuring config.toml..."
  
  # Get Bitcoin RPC Creds
  RPC_USER=$(sudo grep rpcuser /mnt/hdd/app-data/bitcoin/bitcoin.conf | cut -d "=" -f 2)
  RPC_PASSWORD=$(sudo grep rpcpassword /mnt/hdd/app-data/bitcoin/bitcoin.conf | cut -d "=" -f 2)
  
  CONFIG_FILE="/mnt/hdd/app-data/${APPID}/config.toml"
  
  # Only create config from template on first install.
  # On reinstall (off/on), preserve the existing config to keep user customizations
  # (network, rpc_port, wallet settings, etc.). prestart updates RPC creds on each boot.
  if [ ! -f "${CONFIG_FILE}" ]; then
     echo "# Downloading config template (first install)..."
     # The template ships inside jmcore in the source tree. An explicit
     # non-empty check makes us fail loudly instead of writing an empty file
     # (which would silently produce a broken config that prestart cannot repair).
     TEMPLATE_URL="https://raw.githubusercontent.com/joinmarket-ng/joinmarket-ng/${GITHUB_TAG}/jmcore/src/jmcore/data/config.toml.template"
     if ! sudo wget -q "${TEMPLATE_URL}" -O "${CONFIG_FILE}" || [ ! -s "${CONFIG_FILE}" ]; then
        echo "# FAIL: Could not download config template from ${TEMPLATE_URL}"
        sudo rm -f "${CONFIG_FILE}"
        exit 1
     fi

     # Ensure file permissions
     sudo chmod 600 ${CONFIG_FILE}
     sudo chown ${USER_JM}:${USER_JM} ${CONFIG_FILE}

     # Apply initial configuration (only on first install)

     # Function to uncomment and set value in TOML
     set_toml_value() {
         local key=$1
         local value=$2
         local file=$3
         local quote=$4 # "true" to wrap value in quotes

         if [ "$quote" == "true" ]; then
             value="\"${value}\""
         fi

         # Escape sed metacharacters in the value for safe replacement
         local sed_value
         sed_value=$(printf '%s' "$value" | sed -e 's/[&\\/|]/\\&/g')

         # 1. Try to replace uncommented key (e.g. 'key = ...')
         if grep -q "^${key}[[:space:]]*=" "${file}"; then
             sudo sed -i "s|^${key}[[:space:]]*=.*|${key} = ${sed_value}|" "${file}"
         # 2. Try to replace commented key (e.g. '# key = ...')
         elif grep -q "^#[[:space:]]*${key}[[:space:]]*=" "${file}"; then
             sudo sed -i "s|^#[[:space:]]*${key}[[:space:]]*=.*|${key} = ${sed_value}|" "${file}"
         else
             echo "# Warning: Could not find key '${key}' in ${file}"
         fi
     }

     # Network
     set_toml_value "network" "${jm_network}" "${CONFIG_FILE}" "true"

     # Bitcoin Backend
     set_toml_value "rpc_url" "http://127.0.0.1:${bitcoin_rpc_port}" "${CONFIG_FILE}" "true"
     set_toml_value "rpc_user" "${RPC_USER}" "${CONFIG_FILE}" "true"
     set_toml_value "rpc_password" "${RPC_PASSWORD}" "${CONFIG_FILE}" "true"
     set_toml_value "backend_type" "descriptor_wallet" "${CONFIG_FILE}" "true"

     # Tor
     set_toml_value "socks_host" "127.0.0.1" "${CONFIG_FILE}" "true"
     set_toml_value "socks_port" "9050" "${CONFIG_FILE}" "false"

     # Tor Control Port (needed for maker to create ephemeral onion services)
     # Raspiblitz runs Tor with ControlPort 9051 and CookieAuthentication
     set_toml_value "control_enabled" "true" "${CONFIG_FILE}" "false"
     set_toml_value "control_host" "127.0.0.1" "${CONFIG_FILE}" "true"
     set_toml_value "control_port" "9051" "${CONFIG_FILE}" "false"
     set_toml_value "cookie_path" "/run/tor/control.authcookie" "${CONFIG_FILE}" "true"
  else
     echo "# Existing config.toml found — preserving user settings."
     echo "# RPC credentials will be updated by prestart on next service start."
     # Just ensure permissions are correct
     sudo chmod 600 ${CONFIG_FILE}
     sudo chown ${USER_JM}:${USER_JM} ${CONFIG_FILE}
  fi
  
  # 7. Systemd Service (Maker)
  echo "# Creating systemd service for Maker..."
  cat <<EOF | sudo tee /etc/systemd/system/${APPID}-maker.service
[Unit]
Description=JoinMarket-NG Maker Bot
Wants=${bitcoind_service}.service tor.service
After=${bitcoind_service}.service tor.service

[Service]
Type=simple
User=${USER_JM}
Group=${USER_JM}
Environment="PATH=/home/${USER_JM}/venv/bin:/home/${USER_JM}/.local/bin:/usr/local/bin:/usr/bin:/bin"
EnvironmentFile=-/home/${USER_JM}/.joinmarket-ng/.maker.env
ExecStartPre=+/home/admin/config.scripts/bonus.${APPID}.sh prestart
ExecStart=/bin/bash -c 'exec jm-maker start'
ExecStopPost=+/bin/bash -c 'rm -f /home/${USER_JM}/.joinmarket-ng/.maker.env'
# Bitcoind on RaspiBlitz can take a long time to come up after boot
# (IBD, mempool rebuild, ...). Retry forever with a 30s backoff instead
# of letting systemd give up after a few failed attempts.
Restart=on-failure
RestartSec=30
StartLimitIntervalSec=0
StandardOutput=append:/home/${USER_JM}/.joinmarket-ng/logs/maker.log
StandardError=append:/home/${USER_JM}/.joinmarket-ng/logs/maker.log

[Install]
WantedBy=multi-user.target
EOF
  
  # 8. Menu Script (TUI)
  # The TUI menu script is bundled as package data inside jmcore and launched
  # via the 'jm-ng' console script entry point (installed in the venv by pip).
  # No separate download or file copy is needed.
  if [ ! -x "/home/${USER_JM}/venv/bin/jm-ng" ]; then
    # Sanity check: jm-ng should be available after pip install jmcore.
    # Do not execute it here: jm-ng starts an interactive whiptail menu.
    echo "# Warning: jm-ng entry point not found in venv — TUI may not work."
  fi

  # Add alias and PATH setup to .bashrc
  if ! grep -q "alias jm-ng" /home/${USER_JM}/.bashrc; then
      echo "alias jm-ng='/home/${USER_JM}/venv/bin/jm-ng'" | sudo -u ${USER_JM} tee -a /home/${USER_JM}/.bashrc
  fi
  if ! grep -q "source /home/${USER_JM}/venv/bin/activate" /home/${USER_JM}/.bashrc; then
      echo "source /home/${USER_JM}/venv/bin/activate" | sudo -u ${USER_JM} tee -a /home/${USER_JM}/.bashrc
  fi
  # Ensure ~/.local/bin is in PATH (fallback for pip console scripts)
  if ! grep -q '\.local/bin' /home/${USER_JM}/.bashrc; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' | sudo -u ${USER_JM} tee -a /home/${USER_JM}/.bashrc
  fi

  # 9. Sudoers rule: allow joinmarketng to call this script for maker control
  echo "# Adding sudoers rule..."
  cat <<EOF | sudo tee /etc/sudoers.d/joinmarketng-maker
# Allow joinmarketng user to run maker commands via the bonus script (no password)
${USER_JM} ALL=(ALL) NOPASSWD: /home/admin/config.scripts/bonus.${APPID}.sh maker-start
${USER_JM} ALL=(ALL) NOPASSWD: /home/admin/config.scripts/bonus.${APPID}.sh maker-stop
${USER_JM} ALL=(ALL) NOPASSWD: /home/admin/config.scripts/bonus.${APPID}.sh maker-status
${USER_JM} ALL=(ALL) NOPASSWD: /home/admin/config.scripts/bonus.${APPID}.sh store-password *
${USER_JM} ALL=(ALL) NOPASSWD: /home/admin/config.scripts/bonus.${APPID}.sh update
${USER_JM} ALL=(ALL) NOPASSWD: /home/admin/config.scripts/bonus.${APPID}.sh update *
EOF
  sudo chmod 440 /etc/sudoers.d/joinmarketng-maker

  # 10. Reload systemd, and enable auto-start at boot only when a
  # mnemonic password is already permanently stored in config.toml.
  # Without the password the maker cannot decrypt the wallet under
  # systemd (no TTY to prompt), so we keep the unit disabled by default
  # and rely on the TUI 'maker-start' flow to inject a temporary
  # password via the .maker.env file.
  sudo systemctl daemon-reload
  if toml_has_wallet_password "${CONFIG_FILE}"; then
    echo "# Wallet password already stored — enabling maker auto-start at boot."
    sudo systemctl enable ${APPID}-maker.service
  else
    echo "# No stored wallet password — leaving maker auto-start disabled."
    echo "# Use the TUI ('Store wallet password') to enable boot auto-start."
    sudo systemctl disable ${APPID}-maker.service 2>/dev/null || true
  fi

  # Mark installed in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ${CONFIGKEY} "on"

  echo "# ${APPID} installation successful"
  echo "# To start the maker bot, configure your wallet first!"
  echo "# Use 'sudo su - ${USER_JM}' then 'jm-ng' to access the menu."
  echo "# Wallet files live at /mnt/hdd/app-data/${APPID}/wallets (owned by"
  echo "# ${USER_JM}, mode 0700). Access them via 'sudo -u ${USER_JM} ...'."
  
  exit 0
fi

##########################
# UPDATE
#########################

if [ "$1" = "update" ]; then

  echo "# Updating ${APPID} ..."

  # Determine target version
  if [ -n "${2}" ]; then
    UPDATE_TAG="${2}"
    echo "# Using specified version: ${UPDATE_TAG}"
  else
    echo "# Querying GitHub for latest release..."
    UPDATE_TAG=$(curl -sf https://api.github.com/repos/joinmarket-ng/joinmarket-ng/releases/latest \
      | grep '"tag_name"' | cut -d '"' -f4)
    if [ -z "${UPDATE_TAG}" ]; then
      echo "# WARNING: Could not fetch latest version from GitHub, falling back to ${GITHUB_TAG}"
      UPDATE_TAG="${GITHUB_TAG}"
    else
      echo "# Latest version on GitHub: ${UPDATE_TAG}"
    fi
  fi

  VENV_DIR="/home/${USER_JM}/venv"

  # Special case: install from the main branch (unreleased, no GPG signing)
  if [ "${UPDATE_TAG}" = "main" ]; then
    echo ""
    echo "# ============================================================"
    echo "# WARNING: Installing from the 'main' branch."
    echo "# This is an UNRELEASED version with NO GPG signature."
    echo "# Only use this if you trust the current state of main."
    echo "# ============================================================"
    echo ""
    GIT_URL="git+${GITHUB_REPO}.git@main"
  else
    # Get currently installed version
    CURRENT_TAG=$(sudo -u ${USER_JM} /home/${USER_JM}/venv/bin/pip show jmcore 2>/dev/null \
      | grep '^Version:' | awk '{print $2}')
    echo "# Currently installed version: ${CURRENT_TAG:-unknown}"

    # Verify release signatures and get immutable commit hash
    echo "# Verifying GPG signatures for release ${UPDATE_TAG}..."
    VERIFIED_COMMIT=""
    if ! verify_release "${UPDATE_TAG}"; then
      echo "# FAIL - GPG signature verification failed for ${UPDATE_TAG}"
      exit 1
    fi

    # Development commits can have the same package version as the latest
    # release. Only immutable source provenance can prove this release is
    # already installed.
    if installed_release_matches "${VERIFIED_COMMIT}"; then
      echo "# Already on release ${UPDATE_TAG} at commit ${VERIFIED_COMMIT}, nothing to do."
      exit 0
    fi
    if [ "${CURRENT_TAG}" = "${UPDATE_TAG}" ]; then
      echo "# Package version matches, but source provenance differs; reinstalling release."
    fi

    # Use the verified commit SHA (immutable) instead of the mutable tag
    GIT_URL="git+${GITHUB_REPO}.git@${VERIFIED_COMMIT}"
  fi

  # Check if maker was running before update so we can restore state
  MAKER_WAS_RUNNING=0
  if systemctl is-active --quiet ${APPID}-maker 2>/dev/null; then
    MAKER_WAS_RUNNING=1
  fi

  echo "# Stopping maker service..."
  sudo systemctl stop ${APPID}-maker 2>/dev/null

  echo "# Upgrading pip packages to ${UPDATE_TAG}..."
  # Source commits can share a package version, so force-reinstall the four
  # managed packages first. Resolve dependencies separately to avoid forcing
  # costly reinstalls of every third-party package.
  sudo -u ${USER_JM} bash -c "
    ${VENV_DIR}/bin/pip install --upgrade pip && \
    ${VENV_DIR}/bin/pip install --upgrade --force-reinstall --no-deps \
      '${GIT_URL}#subdirectory=jmcore' \
      '${GIT_URL}#subdirectory=jmwallet' \
      '${GIT_URL}#subdirectory=maker' \
      '${GIT_URL}#subdirectory=taker' && \
    ${VENV_DIR}/bin/pip install --upgrade \
      '${GIT_URL}#subdirectory=jmcore' \
      '${GIT_URL}#subdirectory=jmwallet' \
      '${GIT_URL}#subdirectory=maker' \
      '${GIT_URL}#subdirectory=taker' && \
    ${VENV_DIR}/bin/pip check
  "
  if [ $? -ne 0 ]; then
      echo "# FAIL - pip upgrade failed"
      exit 1
  fi

  if [ "${UPDATE_TAG}" != "main" ] && ! installed_release_matches "${VERIFIED_COMMIT}"; then
    echo "# FAIL - installed packages do not match verified release commit"
    exit 1
  fi

  # Menu script is bundled in the jmcore pip package — updated automatically
  # by the pip upgrade above. No separate download needed.

  # Only restart maker if it was running before the update (and password file still exists)
  if [ "${MAKER_WAS_RUNNING}" = "1" ]; then
    ENV_FILE="/home/${USER_JM}/.joinmarket-ng/.maker.env"
    if [ -f "${ENV_FILE}" ]; then
      echo "# Restarting maker service (was running before update)..."
      sudo systemctl start ${APPID}-maker
    else
      echo "# Maker was running but password file is gone — not restarting."
      echo "# Start the maker manually from the JoinMarket-NG menu."
    fi
  else
    echo "# Maker was not running before update — leaving it stopped."
  fi

  echo "# ${APPID} updated to ${UPDATE_TAG} (commit: ${VERIFIED_COMMIT:-main})"
  exit 0
fi

##########################
# OFF / UNINSTALL
#########################

if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  echo "# Stopping & disabling services..."
  sudo systemctl stop ${APPID}-maker 2>/dev/null
  sudo systemctl disable ${APPID}-maker 2>/dev/null || true
  sudo rm -f /etc/systemd/system/${APPID}-maker.service
  sudo rm -f /etc/sudoers.d/joinmarketng-maker
  sudo systemctl daemon-reload

  echo "# Removing user..."
  sudo userdel -rf ${USER_JM} 2>/dev/null

  echo "# Mark uninstalled in config"
  /home/admin/config.scripts/blitz.conf.sh set ${CONFIGKEY} "off"
  
  echo "# Note: Data directory /mnt/hdd/app-data/${APPID} was KEPT safe."
  echo "# To delete data: sudo rm -rf /mnt/hdd/app-data/${APPID}"

  exit 0
fi

echo "# FAIL - Unknown Parameter $1"
exit 1
