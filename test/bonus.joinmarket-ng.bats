#!/usr/bin/env bats

# Integration tests for bonus.joinmarket-ng.sh
#
# These tests ACTUALLY RUN the bonus script (install, status, config, uninstall)
# against a real Ubuntu 24.04 environment. They require:
#   - Network access (pip install from GitHub, GPG key fetching)
#   - Python >= 3.11 (joinmarket-ng requirement)
#   - Root privileges (sudo bats)
#   - ~4 minutes for first install (pip builds coincurve C extension)
#
# Tests are sequential and stateful: install -> use -> uninstall -> reinstall -> cleanup.
# Following the pattern from bonus.postgresql-15.bats.

SCRIPT="../home.admin/config.scripts/bonus.joinmarket-ng.sh"
APPID="joinmarket-ng"
USER_JM="joinmarketng"
DATA_DIR="/mnt/hdd/app-data/${APPID}"
CONFIG_TOML="${DATA_DIR}/config.toml"
SERVICE_FILE="/etc/systemd/system/${APPID}-maker.service"
SUDOERS_FILE="/etc/sudoers.d/${USER_JM}-maker"

setup_file() {
  # Create the minimal mock environment that bonus.joinmarket-ng.sh expects.
  # The script sources raspiblitz.conf and calls blitz.conf.sh unconditionally.
  mkdir -p /mnt/hdd/app-data/bitcoin
  mkdir -p /home/admin/config.scripts

  echo "chain=main" > /mnt/hdd/app-data/raspiblitz.conf

  cat > /mnt/hdd/app-data/bitcoin/bitcoin.conf <<'EOF'
rpcuser=testuser
rpcpassword=testpass
EOF

  # Stub blitz.conf.sh — mimics real behavior: writes key=value to raspiblitz.conf
  cat > /home/admin/config.scripts/blitz.conf.sh <<'STUB'
#!/bin/bash
if [ "$1" = "set" ]; then
  key="$2"; val="$3"
  sed -i "/^${key}=/d" /mnt/hdd/app-data/raspiblitz.conf
  echo "${key}=${val}" >> /mnt/hdd/app-data/raspiblitz.conf
fi
STUB
  chmod +x /home/admin/config.scripts/blitz.conf.sh

  # Stub network.wallet.sh -- the real script toggles 'disablewallet' in
  # bitcoin.conf and restarts bitcoind via systemctl, neither of which is
  # available in the bats test environment. The bonus.joinmarket-ng.sh
  # installer just needs the call to succeed. We additionally normalize
  # disablewallet=0 in the mock bitcoin.conf so tests can later assert
  # the installer requested wallet support.
  cat > /home/admin/config.scripts/network.wallet.sh <<'STUB'
#!/bin/bash
# Mock: ensure disablewallet=0 is recorded, no bitcoind restart.
conf=/mnt/hdd/app-data/bitcoin/bitcoin.conf
if [ "$1" = "on" ]; then
  if grep -Eq "^disablewallet=" "${conf}"; then
    sed -i "s/^disablewallet=.*/disablewallet=0/" "${conf}"
  else
    echo "disablewallet=0" >> "${conf}"
  fi
fi
exit 0
STUB
  chmod +x /home/admin/config.scripts/network.wallet.sh

  # Install build dependencies the script expects (apt-get update + dev packages).
  # The bonus script runs apt-get install itself, but having build-essential
  # pre-installed speeds things up. We also need gpg for GPG verification.
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq sudo wget python3-dev python3-venv python3-pip \
    build-essential libffi-dev libgmp-dev pkg-config gpg curl > /dev/null 2>&1
}

teardown_file() {
  # Final cleanup: remove the joinmarket user and all mock files.
  # The bonus script's "off" should have cleaned most things, but be thorough.
  if id "${USER_JM}" &>/dev/null; then
    userdel -rf "${USER_JM}" 2>/dev/null || true
  fi
  rm -rf "${DATA_DIR}" 2>/dev/null || true
  rm -f "${SERVICE_FILE}" 2>/dev/null || true
  rm -f "${SUDOERS_FILE}" 2>/dev/null || true
  # Clean up mock environment
  rm -f /mnt/hdd/app-data/raspiblitz.conf 2>/dev/null || true
  rm -f /mnt/hdd/app-data/bitcoin/bitcoin.conf 2>/dev/null || true
  rm -f /home/admin/config.scripts/blitz.conf.sh 2>/dev/null || true
  rm -f /home/admin/config.scripts/network.wallet.sh 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 1. Pre-install: status should show isInstalled=0
# ---------------------------------------------------------------------------
@test "status before install shows isInstalled=0" {
  run bash "${SCRIPT}" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "isInstalled=0"
}

@test "verify-release accepts local-first signatures" {
  run bash "${SCRIPT}" verify-release "0.26.1"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "GPG verification passed:"
  echo "$output" | grep -q "VALID signature (local manifest commit matches release manifest)"
}

# ---------------------------------------------------------------------------
# 2. Install joinmarket-ng (real install from GitHub)
# ---------------------------------------------------------------------------
@test "install joinmarket-ng (on)" {
  run bash "${SCRIPT}" on
  [ "$status" -eq 0 ]

  # User was created
  id "${USER_JM}"

  # Venv exists with pip-installed packages
  [ -d "/home/${USER_JM}/venv" ]
  "/home/${USER_JM}/venv/bin/pip" show jmcore

  # Config template was downloaded
  [ -f "${CONFIG_TOML}" ]

  # Systemd service file was written
  [ -f "${SERVICE_FILE}" ]

  # Sudoers file was created
  [ -f "${SUDOERS_FILE}" ]

  # jm-ng entry point was installed in the venv (menu script bundled in jmcore)
  [ -x "/home/${USER_JM}/venv/bin/jm-ng" ]
}

# ---------------------------------------------------------------------------
# 2a. Installer enables Bitcoin Core wallet support (regression for
# RaspiBlitz default 'disablewallet=1', which makes every wallet RPC fail
# with '-32601 Method not found').
# ---------------------------------------------------------------------------
@test "install enables Bitcoin Core wallet support" {
  # The stubbed network.wallet.sh writes disablewallet=0 into bitcoin.conf
  # when invoked with 'on'. After the install, the line must be present
  # and set to 0.
  grep -q '^disablewallet=0' /mnt/hdd/app-data/bitcoin/bitcoin.conf
}

@test "installer calls network.wallet.sh on" {
  # Static check that the bonus script wires the wallet-enablement step,
  # so a future refactor doesn't silently drop it.
  grep -q 'network.wallet.sh on' "${SCRIPT}"
}

# Regression: the template wget URL must point at the actual file location
# inside the repo and the resulting config.toml must contain the RPC creds
# read from bitcoin.conf. A previous version pointed at a non-existent path,
# silently produced an empty config.toml and broke prestart.
@test "install produces non-empty config.toml with RPC credentials" {
  [ -s "${CONFIG_TOML}" ]
  grep -q '^rpc_user = "testuser"' "${CONFIG_TOML}"
  grep -q '^rpc_password = "testpass"' "${CONFIG_TOML}"
}

# Systemd unit must declare a retry policy so the maker survives a slow
# bitcoind boot (RPC unavailable for several minutes during IBD/mempool
# rebuild) instead of going into 'failed' state after a few attempts.
@test "maker systemd unit has retry-on-failure with no rate limit" {
  [ -f "${SERVICE_FILE}" ]
  grep -q '^Restart=on-failure' "${SERVICE_FILE}"
  grep -q '^RestartSec=30' "${SERVICE_FILE}"
  grep -q '^StartLimitIntervalSec=0' "${SERVICE_FILE}"
  grep -q '^WantedBy=multi-user.target' "${SERVICE_FILE}"
}

# Without a permanently stored wallet password the maker cannot start
# unattended (systemd has no TTY to prompt). The installer must leave
# the unit disabled so the user explicitly opts in via store-password.
@test "install leaves maker disabled when no password is stored" {
  # systemctl is a python shim on minimal Ubuntu images, so we can't rely on
  # the multi-user.target.wants symlink being created/removed. Instead, just
  # assert that the installer did not unconditionally enable the unit while
  # config.toml has no [wallet] mnemonic_password set yet.
  ! grep -q '^mnemonic_password' "${CONFIG_TOML}"
}

# ---------------------------------------------------------------------------
# 2b. Menu script is bundled as package data in jmcore and is valid bash
# ---------------------------------------------------------------------------
@test "jm-ng entry point can locate the bundled menu script" {
  # The tui.py trampoline should find the script via importlib.resources
  local script_path
  script_path=$("/home/${USER_JM}/venv/bin/python" -c "
from importlib import resources
ref = resources.files('jmcore').joinpath('data/menu.joinmarket-ng.sh')
print(ref)
")
  [ -f "$script_path" ]
  run bash -n "$script_path"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 2c. Installer uses jm-ng from venv (no download needed)
# ---------------------------------------------------------------------------
@test "installer uses jm-ng entry point instead of downloading menu script" {
  # Bonus script should reference venv/bin/jm-ng for the menu command
  grep -q 'venv/bin/jm-ng' "${SCRIPT}"
  # Old download functions should NOT be present
  ! grep -q 'download_file()' "${SCRIPT}"
  ! grep -q 'install_menu_script()' "${SCRIPT}"
  ! grep -q 'MENU_FALLBACK_URL' "${SCRIPT}"
}

# ---------------------------------------------------------------------------
# 2d. Menu script contains expected main menu entries
# ---------------------------------------------------------------------------
@test "menu script has unified Send entry and no separate Taker entry" {
  # Locate the bundled menu script via package data
  local menu
  menu=$("/home/${USER_JM}/venv/bin/python" -c "
from importlib import resources
print(resources.files('jmcore').joinpath('data/menu.joinmarket-ng.sh'))
")
  # "S" "Send Bitcoin" should be in the main menu
  grep -q '"S".*"Send Bitcoin"' "$menu"
  # Old "T" "Taker" entry should not exist
  ! grep -q '"T".*"Taker' "$menu"
  # Wallet submenu should not have a SEND entry
  ! grep -q '"SEND".*"Send Bitcoin"' "$menu"
  # prompt_param helper should exist
  grep -q 'prompt_param()' "$menu"
  # show_summary helper should exist
  grep -q 'show_summary()' "$menu"
}

# ---------------------------------------------------------------------------
# 3. Post-install: status should show isInstalled=1
# ---------------------------------------------------------------------------
@test "status after install shows isInstalled=1 and correct version" {
  run bash "${SCRIPT}" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "isInstalled=1"
  echo "$output" | grep -q "version="
}

# ---------------------------------------------------------------------------
# 4. CLI tools respond to --help (validates pip install actually works)
# ---------------------------------------------------------------------------
@test "jm-wallet --help works" {
  run "/home/${USER_JM}/venv/bin/jm-wallet" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "usage"
}

@test "jm-wallet subcommands respond to --help" {
  local subcommands=(generate import validate info send freeze history
                     list-bonds generate-bond-address)
  for sub in "${subcommands[@]}"; do
    run "/home/${USER_JM}/venv/bin/jm-wallet" "$sub" --help
    [ "$status" -eq 0 ]
  done
}

@test "jm-maker --help works" {
  run "/home/${USER_JM}/venv/bin/jm-maker" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "usage"
}

@test "jm-maker subcommands respond to --help" {
  local subcommands=(start generate-address config-init)
  for sub in "${subcommands[@]}"; do
    run "/home/${USER_JM}/venv/bin/jm-maker" "$sub" --help
    [ "$status" -eq 0 ]
  done
}

@test "jm-taker --help works" {
  run "/home/${USER_JM}/venv/bin/jm-taker" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "usage"
}

@test "jm-taker subcommands respond to --help" {
  local subcommands=(coinjoin tumble config-init)
  for sub in "${subcommands[@]}"; do
    run "/home/${USER_JM}/venv/bin/jm-taker" "$sub" --help
    [ "$status" -eq 0 ]
  done
}

# ---------------------------------------------------------------------------
# 5. store-password writes mnemonic_password to config.toml
# ---------------------------------------------------------------------------
@test "sudoers allows store-password command" {
  # The sudoers file should include store-password with wildcard arg
  grep -q 'store-password' "${SUDOERS_FILE}"
}

@test "sudoers allows update command without password" {
  # Without this rule the TUI, which runs as joinmarketng, prompts for a
  # system password on every update and then the update aborts.
  grep -q 'NOPASSWD:.* update$' "${SUDOERS_FILE}"
  grep -q 'NOPASSWD:.* update \*' "${SUDOERS_FILE}"
}

@test "store-password sets mnemonic_password in config.toml" {
  run bash "${SCRIPT}" store-password "hunter2"
  [ "$status" -eq 0 ]

  # Verify the active (uncommented) line is present
  grep -q '^mnemonic_password = "hunter2"' "${CONFIG_TOML}"
}

# Once the wallet password is permanently stored, the maker can survive a
# reboot unattended, so store-password must request boot auto-start. This is
# a static check on the script because the bats environment has no systemd
# proper and 'systemctl enable' may be a no-op.
@test "store-password block enables maker auto-start" {
  # Extract the store-password branch and assert it enables the unit.
  awk '/^if \[ "\$1" = "store-password" \];/,/^fi$/' "${SCRIPT}" \
    | grep -q 'systemctl enable .*-maker.service'
}

# Symmetric guarantee: the install path must enable the unit when a
# password is already permanently stored (reinstall case), and disable
# it otherwise.
@test "install block gates auto-start on stored password" {
  awk '/# 10. Reload systemd/,/Mark installed in raspiblitz config/' "${SCRIPT}" \
    | grep -q 'toml_has_wallet_password'
  awk '/# 10. Reload systemd/,/Mark installed in raspiblitz config/' "${SCRIPT}" \
    | grep -q 'systemctl enable'
  awk '/# 10. Reload systemd/,/Mark installed in raspiblitz config/' "${SCRIPT}" \
    | grep -q 'systemctl disable'
}

@test "store-password places mnemonic_password under [wallet] section (TOML-valid)" {
  # Verify Python tomllib can read it back under wallet.mnemonic_password
  python3 - "${CONFIG_TOML}" <<'PYEOF'
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
import pathlib
data = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
pwd = data.get("wallet", {}).get("mnemonic_password")
assert pwd == "hunter2", f"Expected 'hunter2', got {pwd!r}"
PYEOF
}

@test "store-password handles special characters safely" {
  # Test with a password containing sed metacharacters: & \ / | " $
  run bash "${SCRIPT}" store-password 'p@ss/w0rd&with\special|"chars'
  [ "$status" -eq 0 ]

  # Verify Python can round-trip the password correctly via TOML
  python3 - "${CONFIG_TOML}" <<'PYEOF'
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
import pathlib
data = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
pwd = data.get("wallet", {}).get("mnemonic_password")
assert pwd == 'p@ss/w0rd&with\\special|"chars', f"Got {pwd!r}"
PYEOF

  # Reset to the known value for subsequent tests
  run bash "${SCRIPT}" store-password "hunter2"
  [ "$status" -eq 0 ]
}

@test "mnemonic_password at top level (not under [wallet]) is not visible to Python settings" {
  # Write a config with mnemonic_password at top level only (not under [wallet])
  local tmp_cfg
  tmp_cfg=$(mktemp)
  cat > "${tmp_cfg}" <<'EOF'
mnemonic_password = "toplevelpwd"
EOF
  # Python should NOT see it under wallet.mnemonic_password
  python3 - "${tmp_cfg}" <<'PYEOF'
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
import pathlib
data = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
pwd = data.get("wallet", {}).get("mnemonic_password")
assert pwd is None, f"Expected None, got {pwd!r}"
PYEOF
  rm -f "${tmp_cfg}"
}

@test "mnemonic_password under [wallet] is visible to Python settings" {
  # CONFIG_TOML already has the key under [wallet] from store-password test
  python3 - "${CONFIG_TOML}" <<'PYEOF'
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib
import pathlib
data = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
pwd = data.get("wallet", {}).get("mnemonic_password")
assert pwd == "hunter2", f"Expected 'hunter2', got {pwd!r}"
PYEOF
}

# ---------------------------------------------------------------------------
# 6. wipe-password only removes injected passwords, not permanently stored ones
# ---------------------------------------------------------------------------
@test "wipe-password preserves permanently stored mnemonic_password" {
  # Ensure it's set first (from previous store-password test)
  grep -q '^mnemonic_password' "${CONFIG_TOML}"

  # No .password_injected flag exists, so wipe-password should be a no-op
  rm -f "/home/${USER_JM}/.joinmarket-ng/.password_injected"

  run bash "${SCRIPT}" wipe-password
  [ "$status" -eq 0 ]

  # Password should still be there (permanently stored)
  grep -q '^mnemonic_password = "hunter2"' "${CONFIG_TOML}"
}

@test "wipe-password removes injected mnemonic_password" {
  # Ensure it's set first
  grep -q '^mnemonic_password' "${CONFIG_TOML}"

  # Create the injection flag (simulating what prestart does)
  touch "/home/${USER_JM}/.joinmarket-ng/.password_injected"

  run bash "${SCRIPT}" wipe-password
  [ "$status" -eq 0 ]

  # Active (uncommented) line should be gone
  ! grep -q '^mnemonic_password' "${CONFIG_TOML}"
  # Injection flag should also be removed
  [ ! -f "/home/${USER_JM}/.joinmarket-ng/.password_injected" ]
}

# ---------------------------------------------------------------------------
# 7. prestart updates RPC credentials from bitcoin.conf
# ---------------------------------------------------------------------------
@test "prestart injects RPC credentials into config.toml" {
  run bash "${SCRIPT}" prestart
  # prestart may fail on mnemonic_file check, but RPC update happens first
  # Check that RPC credentials from bitcoin.conf were injected
  grep -q 'testuser' "${CONFIG_TOML}"
  grep -q 'testpass' "${CONFIG_TOML}"
}

@test "prestart handles special characters in RPC credentials" {
  # Write RPC credentials with sed metacharacters
  cat > /mnt/hdd/app-data/bitcoin/bitcoin.conf <<'EOF'
rpcuser=test&user
rpcpassword=pass/word\with|special
EOF
  run bash "${SCRIPT}" prestart
  # Verify credentials were written (prestart may fail on mnemonic check)
  grep -q 'rpc_user = "test&user"' "${CONFIG_TOML}"
  grep -q 'rpc_password = "pass/word\\with|special"' "${CONFIG_TOML}"

  # Restore original test credentials
  cat > /mnt/hdd/app-data/bitcoin/bitcoin.conf <<'EOF'
rpcuser=testuser
rpcpassword=testpass
EOF
}

# ---------------------------------------------------------------------------
# 8. Uninstall (off) — removes user, service, sudoers; keeps data
# ---------------------------------------------------------------------------
@test "uninstall joinmarket-ng (off)" {
  run bash "${SCRIPT}" off
  [ "$status" -eq 0 ]

  # User should be removed
  ! id "${USER_JM}" 2>/dev/null

  # Service file should be removed
  [ ! -f "${SERVICE_FILE}" ]

  # Sudoers should be removed
  [ ! -f "${SUDOERS_FILE}" ]

  # Data directory should be PRESERVED (deliberate design choice)
  [ -d "${DATA_DIR}" ]
  [ -f "${CONFIG_TOML}" ]
}

@test "status after uninstall shows isInstalled=0" {
  run bash "${SCRIPT}" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "isInstalled=0"
}

# ---------------------------------------------------------------------------
# 9. Reinstall preserves existing config.toml
# ---------------------------------------------------------------------------
@test "reinstall preserves existing config.toml" {
  # Mark the existing config so we can detect it survived reinstall
  echo '# MARKER_PRESERVED' >> "${CONFIG_TOML}"

  run bash "${SCRIPT}" on
  [ "$status" -eq 0 ]

  # The marker should still be in config.toml (template not overwritten)
  grep -q 'MARKER_PRESERVED' "${CONFIG_TOML}"

  # And the install should be functional again
  id "${USER_JM}"
  [ -f "${SERVICE_FILE}" ]
}

# ---------------------------------------------------------------------------
# 10. blitz.conf.sh integration — config flag was set on install
# ---------------------------------------------------------------------------
@test "raspiblitz.conf has joinmarketNG=on after install" {
  grep -q "joinmarketNG=on" /mnt/hdd/app-data/raspiblitz.conf
}

# ---------------------------------------------------------------------------
# 11. Unknown parameter exits with error
# ---------------------------------------------------------------------------
@test "unknown parameter exits with failure" {
  run bash "${SCRIPT}" nonexistent-command
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# 12. Final cleanup: uninstall to leave a clean state
# ---------------------------------------------------------------------------
@test "final cleanup uninstall" {
  run bash "${SCRIPT}" off
  [ "$status" -eq 0 ]
  ! id "${USER_JM}" 2>/dev/null
}
