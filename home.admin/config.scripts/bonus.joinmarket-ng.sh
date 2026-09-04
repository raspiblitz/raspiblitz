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
# Only fixed maker service actions are exposed to the joinmarketng user via
# the /etc/sudoers.d/${USER_JM}-maker rules. Password storage and updates run
# as the unprivileged app user.

# APPID
APPID="joinmarket-ng"
# Config key in raspiblitz.conf (must be valid bash variable name - no hyphens)
CONFIGKEY="joinmarketNG"
USER_JM="joinmarketng"

# VERSION
# Pinning a specific version/commit for stability
GITHUB_REPO="https://github.com/joinmarket-ng/joinmarket-ng"
GITHUB_TAG="0.38.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_HELPER="/usr/local/sbin/raspiblitz-joinmarket-ng-service"
SERVICE_HELPER_SOURCE="${SCRIPT_DIR}/joinmarket-ng-service.sh"
TRUSTED_KEYRING="${SCRIPT_DIR}/joinmarket-ng-trusted-keys.asc"
TRUSTED_FINGERPRINTS=(
  "1C53A412D11EF3051704419C44912E1E03005B31"
  "9253062A4F92D63459085CA62D230520212A5901"
)
REQUIRED_SIGNATURES=2

SYSTEM_DEPENDENCIES=(
  build-essential
  git
  libffi-dev
  libsecp256k1-dev
  libsodium-dev
  pkg-config
  python3-dev
  python3-venv
)

run_as_joinmarketng() {
  if [ "$(id -un)" = "${USER_JM}" ]; then
    "$@"
  else
    sudo -u "${USER_JM}" "$@"
  fi
}

install_system_dependencies() {
  local missing_dependencies=()
  local package

  for package in "${SYSTEM_DEPENDENCIES[@]}"; do
    if ! dpkg -s "${package}" >/dev/null 2>&1; then
      missing_dependencies+=("${package}")
    fi
  done

  if [ ${#missing_dependencies[@]} -eq 0 ]; then
    echo "# System dependencies are already installed."
    return 0
  fi

  if [ "$(id -un)" = "${USER_JM}" ]; then
    echo "# Missing system dependencies require an administrator update: ${missing_dependencies[*]}"
    return 1
  fi

  echo "# Installing system dependencies: ${missing_dependencies[*]}"
  sudo apt-get update \
    && sudo apt-get install -y "${missing_dependencies[@]}"
}

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

  restore_gnupghome() {
    if [ -n "${GNUPGHOME_ORIG}" ]; then
      export GNUPGHOME="${GNUPGHOME_ORIG}"
    else
      unset GNUPGHOME
    fi
  }

  # Download release manifest
  local MANIFEST="${TMPDIR}/release-manifest-${TAG}.txt"
  echo "# Downloading release manifest for ${TAG}..."
  if ! curl -sfL "${GITHUB_RELEASES}/${TAG}/release-manifest-${TAG}.txt" -o "${MANIFEST}"; then
    echo "# FAIL: Could not download release manifest for ${TAG}"
    rm -rf "${TMPDIR}"
    restore_gnupghome
    return 1
  fi

  if [ ! -r "${TRUSTED_KEYRING}" ]; then
    echo "# FAIL: Local JoinMarket-NG trust root is unavailable."
    rm -rf "${TMPDIR}"
    restore_gnupghome
    return 1
  fi

  if ((REQUIRED_SIGNATURES < 1 || REQUIRED_SIGNATURES > ${#TRUSTED_FINGERPRINTS[@]})); then
    echo "# FAIL: Invalid JoinMarket-NG signature threshold ${REQUIRED_SIGNATURES}."
    rm -rf "${TMPDIR}"
    restore_gnupghome
    return 1
  fi

  if ! gpg --batch --quiet --import "${TRUSTED_KEYRING}" 2>/dev/null; then
    echo "# FAIL: Could not import the local JoinMarket-NG trust root."
    rm -rf "${TMPDIR}"
    restore_gnupghome
    return 1
  fi

  local fp
  for fp in "${TRUSTED_FINGERPRINTS[@]}"; do
    if ! gpg --batch --with-colons --list-keys "${fp}" 2>/dev/null \
      | awk -F: -v expected="${fp}" '$1 == "fpr" && toupper($10) == expected { found = 1 } END { exit !found }'; then
      echo "# FAIL: Local trust root does not contain expected fingerprint ${fp}."
      rm -rf "${TMPDIR}"
      restore_gnupghome
      return 1
    fi
  done

  echo "# Imported ${#TRUSTED_FINGERPRINTS[@]} locally pinned key(s)."

  # Release signatures are untrusted inputs. A success requires a matching
  # VALIDSIG fingerprint from the local trust root.
  local VALID_SIGS=0
  for fp in "${TRUSTED_FINGERPRINTS[@]}"; do
    local SIG="${TMPDIR}/${fp}.sig"
    if ! curl -sfL "${GITHUB_RAW}/signatures/${TAG}/${fp}.sig" -o "${SIG}"; then
      echo "#   Key ${fp}: no signature for ${TAG}, skipping"
      continue
    fi

    local GPG_STATUS
    if GPG_STATUS=$(gpg --batch --status-fd 1 --verify "${SIG}" "${MANIFEST}" 2>/dev/null) \
      && printf '%s\n' "${GPG_STATUS}" \
        | awk -v expected="${fp}" '$1 == "[GNUPG:]" && $2 == "VALIDSIG" && $3 == expected { found = 1 } END { exit !found }'; then
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

    if ! GPG_STATUS=$(gpg --batch --status-fd 1 --verify "${SIG}" "${LOCAL_MANIFEST}" 2>/dev/null) \
      || ! printf '%s\n' "${GPG_STATUS}" \
        | awk -v expected="${fp}" '$1 == "[GNUPG:]" && $2 == "VALIDSIG" && $3 == expected { found = 1 } END { exit !found }'; then
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

  # Require independent signatures from the configured number of pinned keys.
  if [ "${VALID_SIGS}" -lt "${REQUIRED_SIGNATURES}" ]; then
    echo "# FAIL: Release ${TAG} has ${VALID_SIGS} valid trusted signature(s), ${REQUIRED_SIGNATURES} required."
    echo "# This could indicate a compromised or unsigned release. Aborting."
    rm -rf "${TMPDIR}"
    restore_gnupghome
    return 1
  fi

  echo "# GPG verification passed: ${VALID_SIGS} valid trusted signature(s), ${REQUIRED_SIGNATURES} required."

  # Extract the immutable commit hash from the manifest
  VERIFIED_COMMIT=$(grep '^commit:' "${MANIFEST}" | awk '{print $2}')
  if [ -z "${VERIFIED_COMMIT}" ]; then
    echo "# FAIL: Could not extract commit hash from release manifest."
    rm -rf "${TMPDIR}"
    restore_gnupghome
    return 1
  fi
  echo "# Verified commit: ${VERIFIED_COMMIT}"

  # Cleanup
  rm -rf "${TMPDIR}"
  restore_gnupghome
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

  run_as_joinmarketng "${VENV_PYTHON}" - "${EXPECTED_COMMIT}" <<'PYEOF'
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

patch_upstream_tui() {
  local VENV_DIR="$1"
  local TUI_SCRIPT

  TUI_SCRIPT=$(run_as_joinmarketng "${VENV_DIR}/bin/python" - <<'PYEOF'
from importlib import resources

print(resources.files("jmcore").joinpath("data/menu.joinmarket-ng.sh"))
PYEOF
) || return 1

  if [ ! -f "${TUI_SCRIPT}" ]; then
    echo "# FAIL: Installed JoinMarket-NG TUI script was not found."
    return 1
  fi

  if ! run_as_joinmarketng "${VENV_DIR}/bin/python" - "${TUI_SCRIPT}" <<'PYEOF'
import os
import pathlib
import stat
import sys
import tempfile

menu_path = pathlib.Path(sys.argv[1])
source = menu_path.read_text()
replacements = {
    'BONUS_SCRIPT="/home/admin/config.scripts/bonus.joinmarket-ng.sh"\nif [ -f "$BONUS_SCRIPT" ]; then': (
        'BONUS_SCRIPT="/home/admin/config.scripts/bonus.joinmarket-ng.sh"\n'
        'SERVICE_HELPER="/usr/local/sbin/raspiblitz-joinmarket-ng-service"\n'
        'if [ -f "$BONUS_SCRIPT" ] && [ -x "$SERVICE_HELPER" ]; then'
    ),
    'sudo "$BONUS_SCRIPT" store-password "$password"': (
        'printf \'%s\\n\' "$password" | "$BONUS_SCRIPT" store-password'
    ),
    'sudo "$BONUS_SCRIPT" maker-start': 'sudo "$SERVICE_HELPER" start',
    'sudo "$BONUS_SCRIPT" maker-stop': 'sudo "$SERVICE_HELPER" stop',
    'sudo "$BONUS_SCRIPT" maker-status': 'sudo "$SERVICE_HELPER" status',
    'sudo "$BONUS_SCRIPT" update "$TARGET_VERSION"\n': '"$BONUS_SCRIPT" update "$TARGET_VERSION"\n',
    'sudo "$BONUS_SCRIPT" update main\n': '"$BONUS_SCRIPT" update main\n',
    'sudo "$BONUS_SCRIPT" update\n': '"$BONUS_SCRIPT" update\n',
}

patched = source
for pattern, replacement in replacements.items():
    source_count = patched.count(pattern)
    if source_count == 1:
        patched = patched.replace(pattern, replacement)
        continue
    if source_count == 0 and patched.count(replacement) == 1:
        continue
    sys.stderr.write("Unexpected JoinMarket-NG TUI compatibility patch state.\n")
    sys.exit(1)

if patched == source:
    sys.exit(0)

with tempfile.NamedTemporaryFile(
    mode="w", encoding="utf-8", dir=menu_path.parent, delete=False
) as temporary_file:
    temporary_file.write(patched)
    temporary_path = pathlib.Path(temporary_file.name)

os.chmod(temporary_path, stat.S_IMODE(menu_path.stat().st_mode))
os.replace(temporary_path, menu_path)
PYEOF
  then
    echo "# FAIL: Could not apply the JoinMarket-NG TUI compatibility patch."
    return 1
  fi
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

echo "# Running: 'bonus.${APPID}.sh $1'"

# check & load raspiblitz config
# shellcheck source=/dev/null
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
# shellcheck disable=SC2154  # Assigned by raspiblitz.conf.
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
isInstalled=$(test -f /etc/systemd/system/${APPID}-maker.service && echo 1 || echo 0)
# check if service is running
isRunning=$(systemctl status ${APPID}-maker 2>/dev/null | grep -c 'active (running)')

if [ "$1" = "status" ]; then
  # Determine the actually installed version via pip; fall back to pinned tag
  installedVersion=$(run_as_joinmarketng /home/${USER_JM}/venv/bin/pip show jmcore 2>/dev/null \
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
# STORE-PASSWORD
# Permanently write mnemonic_password to config.toml.
# Password is accepted only from standard input.
##########################

if [ "$1" = "store-password" ]; then
  if [ "$#" -ne 1 ]; then
    echo "# FAIL: Password must be provided on standard input."
    exit 1
  fi
  if [ "${EUID}" -eq 0 ] || [ "$(id -un)" != "${USER_JM}" ]; then
    echo "# FAIL: store-password must run as ${USER_JM}."
    exit 1
  fi
  if ! IFS= read -r -s PASSWORD; then
    echo "# FAIL: Could not read password from standard input."
    exit 1
  fi
  CONFIG_FILE="/home/${USER_JM}/.joinmarket-ng/config.toml"
  if [ ! -f "${CONFIG_FILE}" ]; then
    echo "# FAIL: config.toml not found"
    exit 1
  fi
  exec 3<<<"${PASSWORD}"
  unset PASSWORD
  if ! python3 - "${CONFIG_FILE}" 3<&3 <<'PYEOF'
import os, re, sys

config_path = sys.argv[1]
with os.fdopen(3) as password_file:
    password = password_file.read().rstrip("\n")

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
  then
    exec 3<&-
    echo "# FAIL: Could not update config.toml."
    exit 1
  fi
  exec 3<&-
  echo "# Password stored in config.toml"
  # Now that the wallet password is permanently stored, enable maker
  # auto-start at boot. systemd can decrypt the wallet on its own, no
  # interactive prompt needed.
  if [ -f "/etc/systemd/system/${APPID}-maker.service" ]; then
    sudo "${SERVICE_HELPER}" enable 2>/dev/null \
      && echo "# Maker auto-start enabled (boot)." \
      || echo "# WARNING: Could not enable maker auto-start."
  fi
  exit 0
fi

##########################
# PRESTART
#########################

if [ "$1" = "prestart" ]; then
  echo "# PRESTART: Validating configuration..."

  CONFIG_FILE="/mnt/hdd/app-data/${APPID}/config.toml"

  if [ ! -f "${CONFIG_FILE}" ]; then
    echo "# PRESTART ERROR: Config file not found at ${CONFIG_FILE}"
    echo "# Run 'bonus.joinmarket-ng.sh on' to reinstall."
    exit 1
  fi

  # Abort if no wallet is configured — prevents a useless restart loop
  MNEMONIC_FILE=$(grep '^mnemonic_file[[:space:]]*=' "${CONFIG_FILE}" 2>/dev/null | head -1 | sed 's/^mnemonic_file[[:space:]]*=[[:space:]]*//' | tr -d '"')
  if [ -z "${MNEMONIC_FILE}" ] || [ ! -f "${MNEMONIC_FILE}" ]; then
    echo "# PRESTART ERROR: No wallet configured (mnemonic_file not set or file missing)."
    echo "# Use the JoinMarket-NG menu to create or import a wallet, then start the maker."
    exit 1
  fi

  echo "# PRESTART: Wallet OK: ${MNEMONIC_FILE}"
  exit 0
fi

##########################
# ON / INSTALL
#########################

if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ "${isInstalled}" -eq 1 ]; then
    echo "# ${APPID} is already installed."
    exit 1
  fi

  HOME_DATA_LINK="/home/${USER_JM}/.joinmarket-ng"
  DATA_DIR="/mnt/hdd/app-data/${APPID}"
  if [ -L "${DATA_DIR}" ] || { [ -e "${DATA_DIR}" ] && [ ! -d "${DATA_DIR}" ]; }; then
    echo "# FAIL: ${DATA_DIR} must be a real directory."
    echo "# Move the unexpected path aside and retry."
    exit 1
  fi
  if [ -L "${DATA_DIR}/config.toml" ]; then
    echo "# FAIL: ${DATA_DIR}/config.toml must not be a symlink."
    echo "# Replace it with an app-owned regular file and retry."
    exit 1
  fi
  if [ -e "${HOME_DATA_LINK}" ] && [ ! -L "${HOME_DATA_LINK}" ]; then
    echo "# FAIL: ${HOME_DATA_LINK} is a real directory or file."
    echo "# Move its contents to ${DATA_DIR}, then remove ${HOME_DATA_LINK} and retry."
    exit 1
  fi
  if [ -L "${HOME_DATA_LINK}" ] && [ "$(readlink -f "${HOME_DATA_LINK}")" != "${DATA_DIR}" ]; then
    echo "# FAIL: ${HOME_DATA_LINK} points outside ${DATA_DIR}."
    echo "# Replace the symlink with one that points to ${DATA_DIR}, then retry."
    exit 1
  fi

  echo "# Installing ${APPID} ..."

  # 1. Install System Dependencies
  echo "# Installing system dependencies..."
  if ! install_system_dependencies; then
    echo "# FAIL - system dependency installation failed"
    exit 1
  fi

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
  run_as_joinmarketng cp -r /etc/skel/. /home/${USER_JM}/ 2>/dev/null

  # Add user to debian-tor group (for Tor control port cookie access)
  sudo usermod -aG debian-tor ${USER_JM}

  # 3. Create Data Directory on HDD
  echo "# Setting up data directory..."
  if ! [ -d "${DATA_DIR}" ]; then
    sudo mkdir -p "${DATA_DIR}"
  fi
  sudo chown -hR ${USER_JM}:${USER_JM} "${DATA_DIR}"

  # Create wallets subdirectory
  run_as_joinmarketng mkdir -p "${DATA_DIR}/wallets"
  run_as_joinmarketng chmod 700 "${DATA_DIR}/wallets"

  # Create logs subdirectory (readable by the user for menu access)
  run_as_joinmarketng mkdir -p "${DATA_DIR}/logs"

  # Symlink to home for standard JM-NG path (~/.joinmarket-ng)
  if [ ! -L "${HOME_DATA_LINK}" ]; then
    run_as_joinmarketng ln -s "${DATA_DIR}" "${HOME_DATA_LINK}"
  fi
  if [ "$(readlink -f "${HOME_DATA_LINK}")" != "${DATA_DIR}" ]; then
    echo "# FAIL: Could not create ${HOME_DATA_LINK} -> ${DATA_DIR}."
    exit 1
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
    run_as_joinmarketng python3 -m venv "${VENV_DIR}"
  fi

  echo "# Installing jmcore, jmwallet, maker, taker..."
  # Use the venv pip directly by full path. This is more reliable than
  # 'source activate && pip' under sudo -u, which can resolve the wrong pip
  # or cause pip to install scripts to ~/.local/bin instead of the venv.
  if ! run_as_joinmarketng bash -c "
    ${VENV_DIR}/bin/pip install --upgrade pip && \
    ${VENV_DIR}/bin/pip install '${GIT_URL}#subdirectory=jmcore' && \
    ${VENV_DIR}/bin/pip install '${GIT_URL}#subdirectory=jmwallet' && \
    ${VENV_DIR}/bin/pip install '${GIT_URL}#subdirectory=maker' && \
    ${VENV_DIR}/bin/pip install '${GIT_URL}#subdirectory=taker' && \
    ${VENV_DIR}/bin/pip install packaging
  "; then
    echo "# FAIL - pip install failed"
    exit 1
  fi

  if ! patch_upstream_tui "${VENV_DIR}"; then
    exit 1
  fi

  # 6. Configuration
  echo "# configuring config.toml..."

  CONFIG_FILE="${DATA_DIR}/config.toml"

  # Only create config from template on first install.
  # On reinstall (off/on), preserve the existing config to keep user customizations
  # (network, rpc_port, wallet settings, etc.). The service helper supplies
  # Bitcoin RPC credentials through its root-owned runtime environment.
  if [ ! -f "${CONFIG_FILE}" ]; then
    echo "# Downloading config template (first install)..."
    TEMPLATE_URL="https://raw.githubusercontent.com/joinmarket-ng/joinmarket-ng/${VERIFIED_COMMIT}/jmcore/src/jmcore/data/config.toml.template"
    if ! run_as_joinmarketng wget -q "${TEMPLATE_URL}" -O "${CONFIG_FILE}" || [ ! -s "${CONFIG_FILE}" ]; then
      echo "# FAIL: Could not download config template from ${TEMPLATE_URL}"
      run_as_joinmarketng rm -f "${CONFIG_FILE}"
      exit 1
    fi

    run_as_joinmarketng chmod 600 "${CONFIG_FILE}"

    set_toml_value() {
      local key=$1
      local value=$2
      local file=$3
      local quote=$4

      if [ "${quote}" = "true" ]; then
        value="\"${value}\""
      fi

      local sed_value
      sed_value=$(printf '%s' "${value}" | sed -e 's/[&\\/|]/\\&/g')

      if grep -q "^${key}[[:space:]]*=" "${file}"; then
        run_as_joinmarketng sed -i "s|^${key}[[:space:]]*=.*|${key} = ${sed_value}|" "${file}"
      elif grep -q "^#[[:space:]]*${key}[[:space:]]*=" "${file}"; then
        run_as_joinmarketng sed -i "s|^#[[:space:]]*${key}[[:space:]]*=.*|${key} = ${sed_value}|" "${file}"
      else
        echo "# Warning: Could not find key '${key}' in ${file}"
      fi
    }

    set_toml_value "network" "${jm_network}" "${CONFIG_FILE}" "true"
    set_toml_value "rpc_url" "http://127.0.0.1:${bitcoin_rpc_port}" "${CONFIG_FILE}" "true"
    set_toml_value "backend_type" "descriptor_wallet" "${CONFIG_FILE}" "true"
    set_toml_value "socks_host" "127.0.0.1" "${CONFIG_FILE}" "true"
    set_toml_value "socks_port" "9050" "${CONFIG_FILE}" "false"
    set_toml_value "control_enabled" "true" "${CONFIG_FILE}" "false"
    set_toml_value "control_host" "127.0.0.1" "${CONFIG_FILE}" "true"
    set_toml_value "control_port" "9051" "${CONFIG_FILE}" "false"
    set_toml_value "cookie_path" "/run/tor/control.authcookie" "${CONFIG_FILE}" "true"
  else
    echo "# Existing config.toml found, preserving user settings."
    run_as_joinmarketng chmod 600 "${CONFIG_FILE}"
  fi
  
  # 7. Root service helper and systemd service
  if [ ! -f "${SERVICE_HELPER_SOURCE}" ]; then
    echo "# FAIL: Service helper source is missing: ${SERVICE_HELPER_SOURCE}"
    exit 1
  fi
  if ! sudo install -o root -g root -m 0755 "${SERVICE_HELPER_SOURCE}" "${SERVICE_HELPER}"; then
    echo "# FAIL: Could not install the root service helper."
    exit 1
  fi

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
EnvironmentFile=-/run/joinmarket-ng/rpc.env
EnvironmentFile=-/home/${USER_JM}/.joinmarket-ng/.maker.env
ExecStartPre=+${SERVICE_HELPER} prepare
ExecStartPre=/home/admin/config.scripts/bonus.${APPID}.sh prestart
ExecStart=/bin/bash -c 'exec jm-maker start'
ExecStopPost=/bin/bash -c 'rm -f /home/${USER_JM}/.joinmarket-ng/.maker.env'
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
      # shellcheck disable=SC2016  # Write literal variables to the target shell config.
      echo 'export PATH="$HOME/.local/bin:$PATH"' | sudo -u ${USER_JM} tee -a /home/${USER_JM}/.bashrc
  fi

  # 9. Sudoers rule: fixed maker service actions only
  echo "# Adding sudoers rule..."
  cat <<EOF | sudo tee /etc/sudoers.d/joinmarketng-maker
# Allow joinmarketng to run fixed maker service actions without a password.
${USER_JM} ALL=(root) NOPASSWD: ${SERVICE_HELPER} start
${USER_JM} ALL=(root) NOPASSWD: ${SERVICE_HELPER} stop
${USER_JM} ALL=(root) NOPASSWD: ${SERVICE_HELPER} status
${USER_JM} ALL=(root) NOPASSWD: ${SERVICE_HELPER} enable
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
    sudo "${SERVICE_HELPER}" enable
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

  # Reconcile native dependencies on existing installations before checking
  # whether the selected source version is already installed. This ensures an
  # update can repair nodes provisioned before a dependency was introduced.
  if ! install_system_dependencies; then
    echo "# FAIL - system dependency installation failed"
    exit 1
  fi

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

  ENV_FILE="/home/${USER_JM}/.joinmarket-ng/.maker.env"
  MAKER_WAS_RUNNING=0
  MAKER_STOPPED=0
  MAKER_PASSWORD_MODE="none"
  TEMP_ENV_BACKUP=""

  if toml_has_wallet_password "/home/${USER_JM}/.joinmarket-ng/config.toml"; then
    MAKER_PASSWORD_MODE="stored"
  elif [ -f "${ENV_FILE}" ] && grep -q '^MNEMONIC_PASSWORD=' "${ENV_FILE}"; then
    MAKER_PASSWORD_MODE="temporary"
  fi

  if systemctl is-active --quiet ${APPID}-maker 2>/dev/null; then
    MAKER_WAS_RUNNING=1
  fi

  restore_temporary_maker_environment() {
    if [ "${MAKER_PASSWORD_MODE}" != "temporary" ]; then
      return 0
    fi
    if [ -z "${TEMP_ENV_BACKUP}" ] || [ ! -f "${TEMP_ENV_BACKUP}" ]; then
      echo "# WARNING: Temporary maker credential backup is unavailable."
      return 1
    fi
    run_as_joinmarketng cp "${TEMP_ENV_BACKUP}" "${ENV_FILE}" \
      && run_as_joinmarketng chmod 600 "${ENV_FILE}"
  }

  cleanup_temporary_maker_environment() {
    if [ -n "${TEMP_ENV_BACKUP}" ]; then
      run_as_joinmarketng rm -f "${TEMP_ENV_BACKUP}"
    fi
  }

  restore_maker_after_update_failure() {
    local credentials_restored=1
    if [ "${MAKER_STOPPED}" = "1" ] && [ "${MAKER_WAS_RUNNING}" = "1" ]; then
      if ! restore_temporary_maker_environment; then
        echo "# WARNING: Could not restore temporary maker credentials."
        credentials_restored=0
      fi
      if [ "${credentials_restored}" = "1" ] && ! sudo "${SERVICE_HELPER}" start; then
        echo "# WARNING: Could not restart maker after update failure."
        if ! restore_temporary_maker_environment; then
          echo "# WARNING: Temporary maker credential backup was retained for recovery."
          credentials_restored=0
        fi
      fi
    fi
    if [ "${credentials_restored}" = "1" ]; then
      cleanup_temporary_maker_environment
    fi
  }

  update_fail() {
    echo "# FAIL - $1"
    restore_maker_after_update_failure
    exit 1
  }

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
    CURRENT_TAG=$(run_as_joinmarketng /home/${USER_JM}/venv/bin/pip show jmcore 2>/dev/null \
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
      if ! patch_upstream_tui "${VENV_DIR}"; then
        exit 1
      fi
      echo "# Already on release ${UPDATE_TAG} at commit ${VERIFIED_COMMIT}, nothing to do."
      exit 0
    fi
    if [ "${CURRENT_TAG}" = "${UPDATE_TAG}" ]; then
      echo "# Package version matches, but source provenance differs; reinstalling release."
    fi

    # Use the verified commit SHA (immutable) instead of the mutable tag
    GIT_URL="git+${GITHUB_REPO}.git@${VERIFIED_COMMIT}"
  fi

  if [ "${MAKER_WAS_RUNNING}" = "1" ] && [ "${MAKER_PASSWORD_MODE}" = "temporary" ]; then
    TEMP_ENV_BACKUP=$(run_as_joinmarketng mktemp "/tmp/${APPID}-maker-env.XXXXXX") || exit 1
    if ! run_as_joinmarketng cp "${ENV_FILE}" "${TEMP_ENV_BACKUP}" \
      || ! run_as_joinmarketng chmod 600 "${TEMP_ENV_BACKUP}"; then
      cleanup_temporary_maker_environment
      echo "# FAIL - Could not preserve temporary maker credentials before update"
      exit 1
    fi
  fi

  if [ "${MAKER_WAS_RUNNING}" = "1" ]; then
    echo "# Stopping maker service..."
    if ! sudo "${SERVICE_HELPER}" stop; then
      cleanup_temporary_maker_environment
      echo "# FAIL - Could not stop maker service"
      exit 1
    fi
    MAKER_STOPPED=1
  fi

  echo "# Upgrading pip packages to ${UPDATE_TAG}..."
  # Source commits can share a package version, so force-reinstall the four
  # managed packages first. Resolve dependencies separately to avoid forcing
  # costly reinstalls of every third-party package.
  if ! run_as_joinmarketng bash -c "
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
  "; then
    update_fail "pip upgrade failed"
  fi

  if [ "${UPDATE_TAG}" != "main" ] && ! installed_release_matches "${VERIFIED_COMMIT}"; then
    update_fail "installed packages do not match verified release commit"
  fi

  if ! patch_upstream_tui "${VENV_DIR}"; then
    update_fail "could not apply the JoinMarket-NG TUI compatibility patch"
  fi

  if [ "${MAKER_WAS_RUNNING}" = "1" ]; then
    if ! restore_temporary_maker_environment; then
      echo "# FAIL - Could not restore temporary maker credentials"
      echo "# Temporary maker credential backup was retained for recovery."
      exit 1
    fi
    case "${MAKER_PASSWORD_MODE}" in
      stored)
        echo "# Restarting maker service with stored wallet password..."
        ;;
      temporary)
        echo "# Restarting maker service with restored temporary wallet password..."
        ;;
      none)
        echo "# Restarting maker service without a wallet password..."
        ;;
    esac
    if ! sudo "${SERVICE_HELPER}" start; then
      if ! restore_temporary_maker_environment; then
        echo "# WARNING: Could not preserve temporary maker credentials for retry."
        echo "# Temporary maker credential backup was retained for recovery."
        echo "# FAIL - Could not restart maker service"
        exit 1
      fi
      cleanup_temporary_maker_environment
      echo "# FAIL - Could not restart maker service"
      exit 1
    fi
  else
    echo "# Maker was not running before update — leaving it stopped."
  fi

  cleanup_temporary_maker_environment
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
  sudo rm -f "${SERVICE_HELPER}"
  sudo rm -rf /run/joinmarket-ng
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
