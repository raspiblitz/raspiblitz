#!/bin/bash

# bonus.joinmarket-ng.sh
# Installs JoinMarket-NG (Next Generation JoinMarket implementation)
# https://github.com/joinmarket-ng/joinmarket-ng

# APPID
APPID="joinmarket-ng"
# Config key in raspiblitz.conf (must be valid bash variable name - no hyphens)
CONFIGKEY="joinmarketNG"
USER_JM="joinmarketng"

# VERSION
# Pinning a specific version/commit for stability
GITHUB_REPO="https://github.com/joinmarket-ng/joinmarket-ng"
GITHUB_TAG="0.18.0"

# GPG signature verification URLs
GITHUB_RAW="https://raw.githubusercontent.com/joinmarket-ng/joinmarket-ng/main"
GITHUB_RELEASES="https://github.com/joinmarket-ng/joinmarket-ng/releases/download"

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

    # Verify
    if gpg --batch --verify "${SIG}" "${MANIFEST}" 2>/dev/null; then
      echo "#   Key ${fp}: VALID signature"
      VALID_SIGS=$((VALID_SIGS + 1))
    else
      echo "#   Key ${fp}: INVALID signature!"
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

# BASIC COMMANDLINE OPTIONS
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "# bonus.${APPID}.sh status    -> status information (key=value)"
  echo "# bonus.${APPID}.sh on        -> install the app"
  echo "# bonus.${APPID}.sh off       -> uninstall the app"
  echo "# bonus.${APPID}.sh menu      -> SSH menu dialog"
  echo "# bonus.${APPID}.sh prestart  -> will be called by systemd before start"
  echo "# bonus.${APPID}.sh update [TAG] -> update to latest or specific version"
  exit 1
fi

echo "# Running: 'bonus.${APPID}.sh $*'"

# check & load raspiblitz config
source /mnt/hdd/app-data/raspiblitz.conf

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
  echo "appID='${APPID}'"
  echo "version='${GITHUB_TAG}'"
  echo "githubRepo='${GITHUB_REPO}'"
  echo "isInstalled=${isInstalled}"
  echo "isRunning=${isRunning}"
  exit
fi

##########################
# MENU
#########################

if [ "$1" = "menu" ]; then
  # Show the TUI menu if installed
  if [ "${isInstalled}" == "1" ]; then
    sudo -u ${USER_JM} /home/${USER_JM}/menu.sh
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
  # If mnemonic_password is already stored in config.toml, skip the prompt.
  # Otherwise, prompt for it and write a temporary .maker.env for prestart.
  CONFIG_FILE="/home/${USER_JM}/.joinmarket-ng/config.toml"
  ENV_FILE="/home/${USER_JM}/.joinmarket-ng/.maker.env"
  if grep -q "^[[:space:]]*mnemonic_password[[:space:]]*=" "${CONFIG_FILE}" 2>/dev/null; then
    echo "# Password found in config.toml, no prompt needed."
  else
    read -r -s -p "Wallet encryption password (Enter to skip if unencrypted): " WALLET_PWD
    echo ""
    printf 'MNEMONIC_PASSWORD=%s\n' "${WALLET_PWD}" > "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
    chown "${USER_JM}:${USER_JM}" "${ENV_FILE}"
    unset WALLET_PWD
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
# WIPE-PASSWORD
# Called by ExecStopPost to remove mnemonic_password from config.toml
# so the password does not persist on disk after the maker stops.
##########################

if [ "$1" = "wipe-password" ]; then
  CONFIG_FILE="/home/${USER_JM}/.joinmarket-ng/config.toml"
  if [ -f "${CONFIG_FILE}" ]; then
    python3 - "${CONFIG_FILE}" <<'PYEOF'
import sys, re
path = sys.argv[1]
with open(path, "r") as fh:
    content = fh.read()
content = re.sub(r"^\s*mnemonic_password\s*=.*\n?", "", content, flags=re.MULTILINE)
with open(path, "w") as fh:
    fh.write(content)
PYEOF
  fi
  exit 0
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

escaped = password.replace("\\", "\\\\").replace('"', '\\"')
new_line = 'mnemonic_password = "{}"'.format(escaped)

if re.search(r"^\s*mnemonic_password\s*=", content, re.MULTILINE):
    content = re.sub(
        r"^\s*mnemonic_password\s*=.*$", new_line, content, flags=re.MULTILINE
    )
elif re.search(r"^\[wallet\]", content, re.MULTILINE):
    content = re.sub(
        r"(^\[wallet\])", r"\1\n" + new_line, content, flags=re.MULTILINE
    )
else:
    content += "\n[wallet]\n" + new_line + "\n"

with open(config_path, "w") as fh:
    fh.write(content)
PYEOF
  echo "# Password stored in config.toml"
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

  # Update RPC User
  if grep -q "^rpc_user =" "${CONFIG_FILE}"; then
     sed -i "s/^rpc_user = .*/rpc_user = \"${RPC_USER}\"/" "${CONFIG_FILE}"
  elif grep -q "^# rpc_user =" "${CONFIG_FILE}"; then
     sed -i "s/^# rpc_user = .*/rpc_user = \"${RPC_USER}\"/" "${CONFIG_FILE}"
  fi

  # Update RPC Password
  if grep -q "^rpc_password =" "${CONFIG_FILE}"; then
     sed -i "s/^rpc_password = .*/rpc_password = \"${RPC_PASSWORD}\"/" "${CONFIG_FILE}"
  elif grep -q "^# rpc_password =" "${CONFIG_FILE}"; then
     sed -i "s/^# rpc_password = .*/rpc_password = \"${RPC_PASSWORD}\"/" "${CONFIG_FILE}"
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

  # If a password env file exists (written by maker-start), inject mnemonic_password
  # into config.toml temporarily. This is only used when the user chose NOT to store
  # the password permanently — if it's already in config.toml, we skip this entirely.
  ENV_FILE="/home/${USER_JM}/.joinmarket-ng/.maker.env"
  INJECTED_FLAG="/home/${USER_JM}/.joinmarket-ng/.password_injected"
  if grep -q "^[[:space:]]*mnemonic_password[[:space:]]*=" "${CONFIG_FILE}" 2>/dev/null; then
      echo "# PRESTART: Password already in config.toml — no injection needed."
  elif [ -f "${ENV_FILE}" ]; then
      MNEMONIC_PASSWORD=$(grep '^MNEMONIC_PASSWORD=' "${ENV_FILE}" | cut -d '=' -f2-)
      # Use python3 to safely inject the password into config.toml.
      # Direct sed is unsafe when the password contains metacharacters (|, \, &, ", $).
      python3 - "${CONFIG_FILE}" "${MNEMONIC_PASSWORD}" <<'PYEOF'
import sys, re

config_path = sys.argv[1]
password = sys.argv[2]

with open(config_path, "r") as fh:
    content = fh.read()

# Escape backslashes and double quotes for TOML string value
escaped = password.replace("\\", "\\\\").replace('"', '\\"')
new_line = 'mnemonic_password = "{}"'.format(escaped)

if re.search(r"^\s*mnemonic_password\s*=", content, re.MULTILINE):
    content = re.sub(
        r"^\s*mnemonic_password\s*=.*$", new_line, content, flags=re.MULTILINE
    )
elif re.search(r"^\[wallet\]", content, re.MULTILINE):
    content = re.sub(
        r"(^\[wallet\])", r"\1\n" + new_line, content, flags=re.MULTILINE
    )
else:
    content += "\n[wallet]\n" + new_line + "\n"

with open(config_path, "w") as fh:
    fh.write(content)
PYEOF
      # Mark that we injected the password so ExecStopPost knows to wipe it
      touch "${INJECTED_FLAG}"
      echo "# PRESTART: Wallet password injected from ${ENV_FILE}."
  else
      echo "# PRESTART: No password file found — assuming unencrypted wallet."
  fi

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
     sudo wget -q https://raw.githubusercontent.com/joinmarket-ng/joinmarket-ng/${GITHUB_TAG}/config.toml.template -O "${CONFIG_FILE}"

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

         # 1. Try to replace uncommented key (e.g. 'key = ...')
         if grep -q "^${key}[[:space:]]*=" "${file}"; then
             sudo sed -i "s|^${key}[[:space:]]*=.*|${key} = ${value}|" "${file}"
         # 2. Try to replace commented key (e.g. '# key = ...')
         elif grep -q "^#[[:space:]]*${key}[[:space:]]*=" "${file}"; then
             sudo sed -i "s|^#[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "${file}"
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
Wants=${bitcoind_service}.service
After=${bitcoind_service}.service

[Service]
Type=simple
User=${USER_JM}
Group=${USER_JM}
Environment="PATH=/home/${USER_JM}/venv/bin:/home/${USER_JM}/.local/bin:/usr/local/bin:/usr/bin:/bin"
EnvironmentFile=-/home/${USER_JM}/.joinmarket-ng/.maker.env
ExecStartPre=+/home/admin/config.scripts/bonus.${APPID}.sh prestart
ExecStart=/bin/bash -c 'exec jm-maker start'
ExecStopPost=+/bin/bash -c 'rm -f /home/${USER_JM}/.joinmarket-ng/.maker.env'
ExecStopPost=+/home/admin/config.scripts/bonus.${APPID}.sh wipe-password
Restart=no
StandardOutput=append:/home/${USER_JM}/.joinmarket-ng/logs/maker.log
StandardError=append:/home/${USER_JM}/.joinmarket-ng/logs/maker.log
EOF
  
  # 8. Menu Script (TUI)
  echo "# Installing Menu Script..."
  # Look for menu script in same directory as this script
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  MENU_SRC="${SCRIPT_DIR}/menu.joinmarket-ng.sh"
  if [ ! -f "${MENU_SRC}" ]; then
      # Fallback to standard raspiblitz path
      MENU_SRC="/home/admin/config.scripts/menu.joinmarket-ng.sh"
  fi
  if [ -f "${MENU_SRC}" ]; then
      sudo cp "${MENU_SRC}" /home/${USER_JM}/menu.sh
      sudo chown ${USER_JM}:${USER_JM} /home/${USER_JM}/menu.sh
      sudo chmod +x /home/${USER_JM}/menu.sh
  else
      echo "# Warning: menu.joinmarket-ng.sh not found in ${SCRIPT_DIR} or /home/admin/config.scripts/"
  fi

  # Add alias and PATH setup to .bashrc
  if ! grep -q "alias jm-ng" /home/${USER_JM}/.bashrc; then
      echo "alias jm-ng='/home/${USER_JM}/menu.sh'" | sudo -u ${USER_JM} tee -a /home/${USER_JM}/.bashrc
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
EOF
  sudo chmod 440 /etc/sudoers.d/joinmarketng-maker

  # 10. Enable & reload (no auto-start — service must be started manually from menu)
  sudo systemctl daemon-reload
  
  # Mark installed in raspiblitz config
  /home/admin/config.scripts/blitz.conf.sh set ${CONFIGKEY} "on"

  echo "# ${APPID} installation successful"
  echo "# To start the maker bot, configure your wallet first!"
  echo "# Use 'sudo su - ${USER_JM}' then 'jm-ng' (or menu.sh) to access the menu."
  
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

    if [ "${CURRENT_TAG}" = "${UPDATE_TAG}" ]; then
      echo "# Already on version ${UPDATE_TAG}, nothing to do."
      exit 0
    fi

    # Verify release signatures and get immutable commit hash
    echo "# Verifying GPG signatures for release ${UPDATE_TAG}..."
    VERIFIED_COMMIT=""
    if ! verify_release "${UPDATE_TAG}"; then
      echo "# FAIL - GPG signature verification failed for ${UPDATE_TAG}"
      exit 1
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
  # When installing from main, version strings don't change so pip skips
  # reinstall unless forced. --no-deps avoids redundant dep reinstalls.
  if [ "${UPDATE_TAG}" = "main" ]; then
    PIP_INSTALL_FLAGS="--force-reinstall --no-deps"
  else
    PIP_INSTALL_FLAGS="--upgrade"
  fi

  sudo -u ${USER_JM} bash -c "
    ${VENV_DIR}/bin/pip install --upgrade pip && \
    ${VENV_DIR}/bin/pip install ${PIP_INSTALL_FLAGS} '${GIT_URL}#subdirectory=jmcore' && \
    ${VENV_DIR}/bin/pip install ${PIP_INSTALL_FLAGS} '${GIT_URL}#subdirectory=jmwallet' && \
    ${VENV_DIR}/bin/pip install ${PIP_INSTALL_FLAGS} '${GIT_URL}#subdirectory=maker' && \
    ${VENV_DIR}/bin/pip install ${PIP_INSTALL_FLAGS} '${GIT_URL}#subdirectory=taker'
  "
  if [ $? -ne 0 ]; then
      echo "# FAIL - pip upgrade failed"
      exit 1
  fi

  # Update menu script
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  MENU_SRC="${SCRIPT_DIR}/menu.joinmarket-ng.sh"
  if [ ! -f "${MENU_SRC}" ]; then
      MENU_SRC="/home/admin/config.scripts/menu.joinmarket-ng.sh"
  fi
  if [ -f "${MENU_SRC}" ]; then
      sudo cp "${MENU_SRC}" /home/${USER_JM}/menu.sh
      sudo chown ${USER_JM}:${USER_JM} /home/${USER_JM}/menu.sh
      sudo chmod +x /home/${USER_JM}/menu.sh
  fi

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
