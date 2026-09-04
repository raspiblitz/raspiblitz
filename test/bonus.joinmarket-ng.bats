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
PASSWORD_SCRIPT="../home.admin/config.scripts/blitz.passwords.sh"
APPID="joinmarket-ng"
USER_JM="joinmarketng"
JM_VERSION="0.38.0"
DATA_DIR="/mnt/hdd/app-data/${APPID}"
CONFIG_TOML="${DATA_DIR}/config.toml"
SERVICE_FILE="/etc/systemd/system/${APPID}-maker.service"
SUDOERS_FILE="/etc/sudoers.d/${USER_JM}-maker"
SERVICE_HELPER="/usr/local/sbin/raspiblitz-joinmarket-ng-service"
SERVICE_HELPER_SOURCE="../home.admin/config.scripts/joinmarket-ng-service.sh"
TRUSTED_KEYRING="../home.admin/config.scripts/joinmarket-ng-trusted-keys.asc"

setup_file() {
  # Create the minimal mock environment that bonus.joinmarket-ng.sh expects.
  # The script sources raspiblitz.conf and calls blitz.conf.sh unconditionally.
  mkdir -p /mnt/hdd /mnt/disk_storage/app-data
  if [ ! -e /mnt/hdd/app-data ]; then
    ln -s /mnt/disk_storage/app-data /mnt/hdd/app-data
  fi
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

  # CI containers do not run systemd as PID 1. Provide a disposable shim so
  # reconciliation can still require a successful daemon-reload operation.
  if ! systemctl show-environment >/dev/null 2>&1; then
    [ ! -e /usr/local/sbin/systemctl ]
    cat > /usr/local/sbin/systemctl <<'STUB'
#!/bin/bash
# raspiblitz-joinmarket-ng-bats-systemctl
case "$1" in
  status | is-active | is-enabled) exit 3 ;;
  *) exit 0 ;;
esac
STUB
    chmod +x /usr/local/sbin/systemctl
  fi
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
  rm -f "${SERVICE_HELPER}" 2>/dev/null || true
  rm -rf /run/joinmarket-ng 2>/dev/null || true
  # Clean up mock environment
  rm -f /mnt/hdd/app-data/raspiblitz.conf 2>/dev/null || true
  rm -f /mnt/hdd/app-data/bitcoin/bitcoin.conf 2>/dev/null || true
  rm -f /home/admin/config.scripts/blitz.conf.sh 2>/dev/null || true
  rm -f /home/admin/config.scripts/network.wallet.sh 2>/dev/null || true
  if [ "$(readlink /mnt/hdd/app-data 2>/dev/null)" = "/mnt/disk_storage/app-data" ]; then
    rm -f /mnt/hdd/app-data
    rmdir /mnt/disk_storage/app-data /mnt/disk_storage 2>/dev/null || true
  fi
  if grep -q 'raspiblitz-joinmarket-ng-bats-systemctl' /usr/local/sbin/systemctl 2>/dev/null; then
    rm -f /usr/local/sbin/systemctl
  fi
}

# ---------------------------------------------------------------------------
# 1. Pre-install: status should show isInstalled=0
# ---------------------------------------------------------------------------
@test "status before install shows isInstalled=0" {
  run bash "${SCRIPT}" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "isInstalled=0"
}

@test "install rejects a real JoinMarket-NG home directory" {
  mkdir -p "/home/${USER_JM}/.joinmarket-ng"

  run bash "${SCRIPT}" on
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Move its contents"

  rmdir "/home/${USER_JM}/.joinmarket-ng"
  rmdir "/home/${USER_JM}"
}

@test "verify-release accepts locally pinned signatures" {
  run bash "${SCRIPT}" verify-release "${JM_VERSION}"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "GPG verification passed: 2 valid trusted signature(s), 2 required."
  echo "$output" | grep -q "VALID signature"
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

  # The root service helper was installed with fixed permissions
  [ -x "${SERVICE_HELPER}" ]
  [ "$(stat -c '%a' "${SERVICE_HELPER}")" = "755" ]

  # The home path is the expected data-directory symlink
  [ "$(readlink -f "/home/${USER_JM}/.joinmarket-ng")" = "$(readlink -f "${DATA_DIR}")" ]

  # jm-ng entry point was installed in the venv (menu script bundled in jmcore)
  [ -x "/home/${USER_JM}/venv/bin/jm-ng" ]
}

@test "on reconciles a realistic legacy system integration without reinstalling JoinMarket-NG" {
  local menu installed_version config_marker helper_victim helper_victim_marker
  menu=$("/home/${USER_JM}/venv/bin/python" -c "
from importlib import resources
print(resources.files('jmcore').joinpath('data/menu.joinmarket-ng.sh'))
")
  installed_version=$("/home/${USER_JM}/venv/bin/pip" show jmcore | awk '/^Version:/{print $2}')
  config_marker="# RECONCILE_CONFIG_MARKER"
  printf '\n%s\n' "${config_marker}" >> "${CONFIG_TOML}"

  # This is the pre-hardening 0.38 TUI adapter. Reversing the current exact
  # patch models an installed package that was never repaired by an update.
  python3 - "${menu}" <<'PYEOF'
import pathlib
import sys

menu_path = pathlib.Path(sys.argv[1])
source = menu_path.read_text()
replacements = {
    'BONUS_SCRIPT="/home/admin/config.scripts/bonus.joinmarket-ng.sh"\n'
    'SERVICE_HELPER="/usr/local/sbin/raspiblitz-joinmarket-ng-service"\n'
    'if [ -f "$BONUS_SCRIPT" ] && [ -x "$SERVICE_HELPER" ]; then': (
        'BONUS_SCRIPT="/home/admin/config.scripts/bonus.joinmarket-ng.sh"\n'
        'if [ -f "$BONUS_SCRIPT" ]; then'
    ),
    'printf \'%s\\n\' "$password" | "$BONUS_SCRIPT" store-password': (
        'sudo "$BONUS_SCRIPT" store-password "$password"'
    ),
    'sudo "$SERVICE_HELPER" start': 'sudo "$BONUS_SCRIPT" maker-start',
    'sudo "$SERVICE_HELPER" stop': 'sudo "$BONUS_SCRIPT" maker-stop',
    'sudo "$SERVICE_HELPER" status': 'sudo "$BONUS_SCRIPT" maker-status',
    '"$BONUS_SCRIPT" update "$TARGET_VERSION"\n': 'sudo "$BONUS_SCRIPT" update "$TARGET_VERSION"\n',
    '"$BONUS_SCRIPT" update main\n': 'sudo "$BONUS_SCRIPT" update main\n',
    '"$BONUS_SCRIPT" update\n': 'sudo "$BONUS_SCRIPT" update\n',
}

for current, legacy in replacements.items():
    assert source.count(current) == 1, current
    source = source.replace(current, legacy)

menu_path.write_text(source)
PYEOF

  helper_victim="/tmp/${APPID}-helper-victim"
  helper_victim_marker="# HELPER_VICTIM_MARKER"
  printf '%s\n' "${helper_victim_marker}" > "${helper_victim}"
  rm -f "${SERVICE_HELPER}"
  ln -s "${helper_victim}" "${SERVICE_HELPER}"
  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=JoinMarket-NG Maker Bot

[Service]
User=${USER_JM}
EnvironmentFile=-/home/${USER_JM}/.joinmarket-ng/.maker.env
ExecStartPre=+/home/admin/config.scripts/bonus.${APPID}.sh prestart
ExecStart=/bin/bash -c 'exec jm-maker start'
ExecStopPost=+/bin/bash -c 'rm -f /home/${USER_JM}/.joinmarket-ng/.maker.env'
EOF
  cat > "${SUDOERS_FILE}" <<EOF
${USER_JM} ALL=(ALL) NOPASSWD: /home/admin/config.scripts/bonus.${APPID}.sh maker-start
${USER_JM} ALL=(ALL) NOPASSWD: /home/admin/config.scripts/bonus.${APPID}.sh maker-stop
${USER_JM} ALL=(ALL) NOPASSWD: /home/admin/config.scripts/bonus.${APPID}.sh maker-status
${USER_JM} ALL=(ALL) NOPASSWD: /home/admin/config.scripts/bonus.${APPID}.sh store-password *
${USER_JM} ALL=(ALL) NOPASSWD: /home/admin/config.scripts/bonus.${APPID}.sh update *
EOF
  chmod 440 "${SUDOERS_FILE}"

  run bash "${SCRIPT}" on
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'already installed, reconciling system integration'

  [ "$(stat -c '%U:%G %a' "${SERVICE_HELPER}")" = "root:root 755" ]
  [ ! -L "${SERVICE_HELPER}" ]
  cmp -s "${SERVICE_HELPER_SOURCE}" "${SERVICE_HELPER}"
  grep -Fx "${helper_victim_marker}" "${helper_victim}"
  rm -f "${helper_victim}"
  [ "$(wc -l < "${SUDOERS_FILE}")" -eq 5 ]
  grep -Fx "${USER_JM} ALL=(root) NOPASSWD: ${SERVICE_HELPER} start" "${SUDOERS_FILE}"
  grep -Fx "${USER_JM} ALL=(root) NOPASSWD: ${SERVICE_HELPER} stop" "${SUDOERS_FILE}"
  grep -Fx "${USER_JM} ALL=(root) NOPASSWD: ${SERVICE_HELPER} status" "${SUDOERS_FILE}"
  grep -Fx "${USER_JM} ALL=(root) NOPASSWD: ${SERVICE_HELPER} enable" "${SUDOERS_FILE}"
  ! grep -q 'bonus.joinmarket-ng.sh' "${SUDOERS_FILE}"
  grep -q "^ExecStartPre=+${SERVICE_HELPER} prepare" "${SERVICE_FILE}"
  grep -q '^EnvironmentFile=-/run/joinmarket-ng/rpc.env' "${SERVICE_FILE}"
  ! grep -q '^ExecStartPre=+/home/admin/config.scripts/bonus.joinmarket-ng.sh' "${SERVICE_FILE}"
  grep -q '^SERVICE_HELPER="/usr/local/sbin/raspiblitz-joinmarket-ng-service"' "${menu}"
  grep -Fq "printf '%s\\n' \"\$password\" | \"\$BONUS_SCRIPT\" store-password" "${menu}"
  grep -q 'sudo "\$SERVICE_HELPER" start' "${menu}"
  ! grep -q 'sudo "\$BONUS_SCRIPT"' "${menu}"
  [ "$("/home/${USER_JM}/venv/bin/pip" show jmcore | awk '/^Version:/{print $2}')" = "${installed_version}" ]
  grep -Fx "${config_marker}" "${CONFIG_TOML}"

  local reconcile_block
  reconcile_block=$(awk '/^reconcile_system_integration\(\)/ { capture=1 } capture { print } capture && /^}$/ { exit }' "${SCRIPT}")
  ! echo "${reconcile_block}" | grep -q 'install_system_dependencies\|/bin/pip'
}

@test "on reconciles an installed application when its systemd unit is missing" {
  local installed_version config_marker
  installed_version=$("/home/${USER_JM}/venv/bin/pip" show jmcore | awk '/^Version:/{print $2}')
  config_marker="# MISSING_UNIT_CONFIG_MARKER"
  printf '\n%s\n' "${config_marker}" >> "${CONFIG_TOML}"
  rm -f "${SERVICE_FILE}"

  run bash "${SCRIPT}" on
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'already installed, reconciling system integration'
  [ -f "${SERVICE_FILE}" ]
  [ "$("/home/${USER_JM}/venv/bin/pip" show jmcore | awk '/^Version:/{print $2}')" = "${installed_version}" ]
  grep -Fx "${config_marker}" "${CONFIG_TOML}"
}

@test "menu reconciles an installed application when its systemd unit is missing" {
  local jm_ng_entrypoint jm_ng_backup
  jm_ng_entrypoint="/home/${USER_JM}/venv/bin/jm-ng"
  jm_ng_backup="/tmp/${APPID}-jm-ng-entrypoint"
  cp "${jm_ng_entrypoint}" "${jm_ng_backup}"
  cat > "${jm_ng_entrypoint}" <<'STUB'
#!/bin/bash
echo "JM_NG_MENU_LAUNCHED"
STUB
  chown "${USER_JM}:${USER_JM}" "${jm_ng_entrypoint}"
  chmod 0755 "${jm_ng_entrypoint}"
  rm -f "${SERVICE_FILE}"

  run bash "${SCRIPT}" menu
  local menu_status="$status"
  local menu_output="$output"

  install -o "${USER_JM}" -g "${USER_JM}" -m 0755 "${jm_ng_backup}" "${jm_ng_entrypoint}"
  rm -f "${jm_ng_backup}"

  [ "${menu_status}" -eq 0 ]
  echo "${menu_output}" | grep -q 'JoinMarket-NG system integration reconciled'
  echo "${menu_output}" | grep -q 'JM_NG_MENU_LAUNCHED'
  [ -f "${SERVICE_FILE}" ]
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

@test "install provides the native secp256k1 library" {
  dpkg -s libsecp256k1-dev
  run "/home/${USER_JM}/venv/bin/python" -c '
from bitcointx.core.secp256k1 import get_secp256k1

get_secp256k1()
'
  [ "$status" -eq 0 ]
}

@test "update reconciles system dependencies before version checks" {
  local update_prefix
  update_prefix=$(awk '/^if \[ "\$1" = "update" \];/,/# Determine target version/' "${SCRIPT}")
  echo "${update_prefix}" | grep -q 'install_system_dependencies'
  grep -q 'Missing system dependencies require an administrator update' "${SCRIPT}"
}

@test "installer calls network.wallet.sh on" {
  # Static check that the bonus script wires the wallet-enablement step,
  # so a future refactor doesn't silently drop it.
  grep -q 'network.wallet.sh on' "${SCRIPT}"
}

# Regression: the template wget URL must point at the actual file location.
# Bitcoin RPC credentials are supplied separately by the root service helper.
@test "install produces non-empty config.toml and runtime RPC credentials" {
  [ -s "${CONFIG_TOML}" ]
  ! grep -q '^rpc_user = "testuser"' "${CONFIG_TOML}"
  ! grep -q '^rpc_password = "testpass"' "${CONFIG_TOML}"

  run bash "${SERVICE_HELPER}" prepare
  [ "$status" -eq 0 ]
  [ "$(stat -c '%U:%G %a' /run/joinmarket-ng/rpc.env)" = "root:root 600" ]
  grep -q '^BITCOIN__RPC_USER="testuser"$' /run/joinmarket-ng/rpc.env
  grep -q '^BITCOIN__RPC_PASSWORD="testpass"$' /run/joinmarket-ng/rpc.env
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
  grep -q '^EnvironmentFile=-/run/joinmarket-ng/rpc.env' "${SERVICE_FILE}"
  grep -q "^ExecStartPre=+${SERVICE_HELPER} prepare" "${SERVICE_FILE}"
  grep -q '^ExecStartPre=/home/admin/config.scripts/bonus.joinmarket-ng.sh prestart' "${SERVICE_FILE}"
  ! grep -q '^ExecStartPre=+/home/admin/config.scripts/bonus.joinmarket-ng.sh' "${SERVICE_FILE}"
  ! grep -q '^ExecStopPost=+' "${SERVICE_FILE}"
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

@test "menu reconciles integration before launching jm-ng" {
  local menu_block
  menu_block=$(awk '
    /^if \[ "\$1" = "menu" \];/ { capture=1 }
    capture && /^# STORE-PASSWORD/ { exit }
    capture { print }
  ' "${SCRIPT}")

  echo "${menu_block}" | grep -q 'reconcile_system_integration'
  [ "$(echo "${menu_block}" | grep -n 'reconcile_system_integration' | cut -d : -f 1)" -lt \
    "$(echo "${menu_block}" | grep -n 'venv/bin/jm-ng' | cut -d : -f 1)" ]
}

@test "reconcile is an admin or root operation" {
  run sudo -u "${USER_JM}" bash "${SCRIPT}" reconcile
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "reconcile must run as admin or root, not ${USER_JM}"
}

@test "reconciliation only reloads systemd and does not transition maker state" {
  local reconciliation_code
  reconciliation_code=$(awk '
    /^install_root_service_helper\(\)/ { capture=1 }
    capture { print }
    /^system_integration_is_current\(\)/ { exit }
  ' "${SCRIPT}")

  echo "${reconciliation_code}" | grep -q 'systemctl daemon-reload'
  ! echo "${reconciliation_code}" \
    | grep -Eq '(^|[[:space:]])(sudo[[:space:]]+)?systemctl[[:space:]]+(start|stop|enable|disable)([[:space:]]|$)'
  ! echo "${reconciliation_code}" \
    | grep -Eq '(^|[[:space:]])sudo[[:space:]]+"\$\{SERVICE_HELPER\}"[[:space:]]+(start|stop|enable|disable)([[:space:]]|$)'
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
  echo "$output" | grep -q "version='${JM_VERSION}'"
}

@test "app-user update fails early when the root helper is stale" {
  rm -f "${SERVICE_HELPER}"

  run sudo -u "${USER_JM}" bash "${SCRIPT}" update "${JM_VERSION}"
  local update_status="$status"
  local update_output="$output"

  # Restore the shared fixture before making assertions so later update tests
  # cannot inherit the intentionally stale integration.
  run bash "${SCRIPT}" reconcile
  local reconcile_status="$status"

  [ "${reconcile_status}" -eq 0 ]
  [ "${update_status}" -eq 1 ]
  echo "${update_output}" | grep -q 'RaspiBlitz main menu'
  ! echo "${update_output}" | grep -q 'Installing system dependencies'
  ! echo "${update_output}" | grep -q 'sudo:.*password'
}

@test "app-user update fails early when the packaged TUI adapter is stale" {
  local menu
  menu=$("/home/${USER_JM}/venv/bin/python" -c "
from importlib import resources
print(resources.files('jmcore').joinpath('data/menu.joinmarket-ng.sh'))
")
  sed -i 's|sudo "$SERVICE_HELPER" status|sudo "$BONUS_SCRIPT" maker-status|' "${menu}"

  run sudo -u "${USER_JM}" bash "${SCRIPT}" update "${JM_VERSION}"
  local update_status="$status"
  local update_output="$output"

  run bash "${SCRIPT}" reconcile
  local reconcile_status="$status"

  [ "${reconcile_status}" -eq 0 ]
  [ "${update_status}" -eq 1 ]
  echo "${update_output}" | grep -q 'RaspiBlitz main menu'
  ! echo "${update_output}" | grep -q 'Installing system dependencies'
}

@test "app-user update fails early when wildcard helper sudo access remains" {
  printf '%s\n' \
    "${USER_JM} ALL=(root) NOPASSWD: ${SERVICE_HELPER} *" \
    >> "${SUDOERS_FILE}"

  run sudo -u "${USER_JM}" bash "${SCRIPT}" update "${JM_VERSION}"
  local update_status="$status"
  local update_output="$output"

  run bash "${SCRIPT}" reconcile
  local reconcile_status="$status"

  [ "${reconcile_status}" -eq 0 ]
  [ "${update_status}" -eq 1 ]
  echo "${update_output}" | grep -q 'RaspiBlitz main menu'
  ! grep -q 'bonus.joinmarket-ng.sh' "${SUDOERS_FILE}"
}

# ---------------------------------------------------------------------------
# 3a. Updates compare immutable source commits, not package versions
# ---------------------------------------------------------------------------
@test "update skips an exact verified release commit" {
  run bash "${SCRIPT}" update "${JM_VERSION}"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Already on release ${JM_VERSION} at commit"
}

@test "update detects same-version packages from a different commit" {
  local expected_commit
  expected_commit=$("/home/${USER_JM}/venv/bin/python" - <<'PYEOF'
import json
from importlib.metadata import distribution

direct_url_text = distribution("jmcore").read_text("direct_url.json")
assert direct_url_text is not None
print(json.loads(direct_url_text)["vcs_info"]["commit_id"])
PYEOF
)

  # Development commits after a release keep that release's package version.
  # Change only jmcore's recorded PEP 610 commit to reproduce that identity
  # mismatch without downloading and rebuilding a moving main branch.
  "/home/${USER_JM}/venv/bin/python" - <<'PYEOF'
import json
from importlib.metadata import distribution

metadata = distribution("jmcore")
direct_url_path = next(
    path.locate()
    for path in metadata.files or ()
    if str(path).endswith(".dist-info/direct_url.json")
)
direct_url = json.loads(direct_url_path.read_text())
direct_url["vcs_info"]["commit_id"] = "0" * 40
direct_url_path.write_text(json.dumps(direct_url))
PYEOF

  # Load the production helper without executing the script's command router.
  run_as_joinmarketng() {
    "$@"
  }
  eval "$(awk '
    /^installed_release_matches\(\)/ { capture=1 }
    capture && /^# BASIC COMMANDLINE OPTIONS/ { exit }
    capture { print }
  ' "${SCRIPT}")"
  run installed_release_matches "${expected_commit}"
  local match_status="$status"
  local match_output="$output"

  # Restore the fixture before assertions so a failed test cannot poison the
  # remaining stateful integration tests.
  "/home/${USER_JM}/venv/bin/python" - "${expected_commit}" <<'PYEOF'
import json
import sys
from importlib.metadata import distribution

metadata = distribution("jmcore")
direct_url_path = next(
    path.locate()
    for path in metadata.files or ()
    if str(path).endswith(".dist-info/direct_url.json")
)
direct_url = json.loads(direct_url_path.read_text())
direct_url["vcs_info"]["commit_id"] = sys.argv[1]
direct_url_path.write_text(json.dumps(direct_url))
PYEOF

  [ "${match_status}" -eq 1 ]
  echo "${match_output}" | grep -q "does not match release commit"
  "/home/${USER_JM}/venv/bin/pip" show jmcore | grep -q "Version: ${JM_VERSION}"

  # The mismatch path must force-install the selected source even when pip
  # considers its package version current, then validate dependencies.
  grep -q -- '--upgrade --force-reinstall --no-deps' "${SCRIPT}"
  grep -q 'bin/pip check' "${SCRIPT}"
}

@test "release verification requires two pinned VALIDSIG fingerprints" {
  [ -f "${TRUSTED_KEYRING}" ]
  gpg --batch --with-colons --show-keys "${TRUSTED_KEYRING}" \
    | grep -q '1C53A412D11EF3051704419C44912E1E03005B31'
  gpg --batch --with-colons --show-keys "${TRUSTED_KEYRING}" \
    | grep -q '9253062A4F92D63459085CA62D230520212A5901'
  grep -q -- '--status-fd 1 --verify' "${SCRIPT}"
  grep -q '\$2 == "VALIDSIG" && \$3 == expected' "${SCRIPT}"
  grep -q '^REQUIRED_SIGNATURES=2$' "${SCRIPT}"
  grep -q 'VALID_SIGS.*-lt.*REQUIRED_SIGNATURES' "${SCRIPT}"
  ! grep -q 'trusted-keys.txt\|signatures/pubkeys' "${SCRIPT}"
}

@test "installer uses the verified commit for the config template" {
  grep -q 'raw.githubusercontent.com/joinmarket-ng/joinmarket-ng/\${VERIFIED_COMMIT}/jmcore/src/jmcore/data/config.toml.template' "${SCRIPT}"
  ! grep -q 'raw.githubusercontent.com/joinmarket-ng/joinmarket-ng/\${GITHUB_TAG}/jmcore/src/jmcore/data/config.toml.template' "${SCRIPT}"
}

@test "update preserves stored temporary and password-free maker modes" {
  update_block=$(awk '/^if \[ "\$1" = "update" \];/,/^fi$/' "${SCRIPT}")
  echo "${update_block}" | grep -q 'MAKER_PASSWORD_MODE="stored"'
  echo "${update_block}" | grep -q 'MAKER_PASSWORD_MODE="temporary"'
  echo "${update_block}" | grep -q 'MAKER_PASSWORD_MODE="none"'
  echo "${update_block}" | grep -q 'TEMP_ENV_BACKUP=.*mktemp'
  echo "${update_block}" | grep -q 'restore_temporary_maker_environment'
  echo "${update_block}" | grep -q 'restore_maker_after_update_failure'
  echo "${update_block}" | grep -q 'sudo "\${SERVICE_HELPER}" stop'
  echo "${update_block}" | grep -q 'sudo "\${SERVICE_HELPER}" start'
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
  local subcommands=(coinjoin clear-ignored-makers config-init)
  for sub in "${subcommands[@]}"; do
    run "/home/${USER_JM}/venv/bin/jm-taker" "$sub" --help
    [ "$status" -eq 0 ]
  done
}

# ---------------------------------------------------------------------------
# 5. Password storage is unprivileged and stdin-only
# ---------------------------------------------------------------------------
@test "sudoers exposes only fixed root service actions" {
  [ "$(wc -l < "${SUDOERS_FILE}")" -eq 5 ]
  grep -Fx "${USER_JM} ALL=(root) NOPASSWD: ${SERVICE_HELPER} start" "${SUDOERS_FILE}"
  grep -Fx "${USER_JM} ALL=(root) NOPASSWD: ${SERVICE_HELPER} stop" "${SUDOERS_FILE}"
  grep -Fx "${USER_JM} ALL=(root) NOPASSWD: ${SERVICE_HELPER} status" "${SUDOERS_FILE}"
  grep -Fx "${USER_JM} ALL=(root) NOPASSWD: ${SERVICE_HELPER} enable" "${SUDOERS_FILE}"
  ! grep -q 'bonus.joinmarket-ng.sh' "${SUDOERS_FILE}"
  ! grep -q '\*' "${SUDOERS_FILE}"
}

@test "store-password rejects root execution and password arguments" {
  run bash "${SCRIPT}" store-password "hunter2"
  [ "$status" -eq 1 ]
  ! echo "$output" | grep -q 'hunter2'
  echo "$output" | grep -q 'Password must be provided on standard input'

  run bash -c 'printf "%s\n" "hunter2" | bash "$1" store-password' \
    _ "${SCRIPT}"
  [ "$status" -eq 1 ]
  ! echo "$output" | grep -q 'hunter2'
  echo "$output" | grep -q "store-password must run as ${USER_JM}"
}

@test "store-password reads the secret from a private descriptor" {
  store_block=$(awk '/^if \[ "\$1" = "store-password" \];/,/^fi$/' "${SCRIPT}")
  echo "${store_block}" | grep -q 'IFS= read -r -s PASSWORD'
  echo "${store_block}" | grep -q 'python3 - "\${CONFIG_FILE}" 3<&3'
  ! echo "${store_block}" | grep -q 'PASSWORD="\${2}"'
  ! echo "${store_block}" | grep -q 'store-password <password>'
}

@test "store-password sets mnemonic_password from joinmarketng stdin" {
  run bash -c 'printf "%s\n" "$3" | sudo -u "$1" bash "$2" store-password' \
    _ "${USER_JM}" "${SCRIPT}" "hunter2"
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
    | grep -q '"\${SERVICE_HELPER}" enable'
}

# Symmetric guarantee: the install path must enable the unit when a
# password is already permanently stored (reinstall case), and disable
# it otherwise.
@test "install block gates auto-start on stored password" {
  awk '/# 8. Enable auto-start/,/Mark installed in raspiblitz config/' "${SCRIPT}" \
    | grep -q 'toml_has_wallet_password'
  awk '/# 8. Enable auto-start/,/Mark installed in raspiblitz config/' "${SCRIPT}" \
    | grep -q '"\${SERVICE_HELPER}" enable'
  awk '/# 8. Enable auto-start/,/Mark installed in raspiblitz config/' "${SCRIPT}" \
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
  run bash -c 'printf "%s\n" "$3" | sudo -u "$1" bash "$2" store-password' \
    _ "${USER_JM}" "${SCRIPT}" 'p@ss/w0rd&with\special|"chars'
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
  run bash -c 'printf "%s\n" "$3" | sudo -u "$1" bash "$2" store-password' \
    _ "${USER_JM}" "${SCRIPT}" "hunter2"
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
# 6. The temporary (declined) password is delivered via the systemd
#    EnvironmentFile (.maker.env) and is NEVER written to config.toml.
#    Regression: a previous version injected mnemonic_password into config.toml
#    at prestart, leaving the secret in cleartext on disk (and reappearing
#    after a user deleted it). The injection and the wipe-password command
#    have been removed; only the explicit 'store-password' opt-in writes it.
# ---------------------------------------------------------------------------
@test "wipe-password command and injection flag are removed" {
  ! grep -q 'wipe-password' "${SCRIPT}"
  ! grep -q 'password_injected' "${SCRIPT}"
}

@test "prestart never injects mnemonic_password into config.toml" {
  # Extract the prestart branch and assert it does not write the password.
  prestart_block=$(awk '/^if \[ "\$1" = "prestart" \];/,/^fi$/' "${SCRIPT}")
  [ -n "${prestart_block}" ]
  ! echo "${prestart_block}" | grep -q 'mnemonic_password'
}

@test "maker unit delivers the password via EnvironmentFile (.maker.env)" {
  [ -f "${SERVICE_FILE}" ]
  grep -q 'EnvironmentFile=.*\.maker\.env' "${SERVICE_FILE}"
  # ExecStopPost must no longer call wipe-password (command removed).
  ! grep -q 'wipe-password' "${SERVICE_FILE}"
}

@test "TUI compatibility patch uses stdin and the fixed service helper" {
  local menu
  menu=$("/home/${USER_JM}/venv/bin/python" -c "
from importlib import resources
print(resources.files('jmcore').joinpath('data/menu.joinmarket-ng.sh'))
")

  grep -q '^SERVICE_HELPER="/usr/local/sbin/raspiblitz-joinmarket-ng-service"' "${menu}"
  grep -Fq "printf '%s\\n' \"\$password\" | \"\$BONUS_SCRIPT\" store-password" "${menu}"
  grep -q 'sudo "\$SERVICE_HELPER" start' "${menu}"
  grep -q 'sudo "\$SERVICE_HELPER" stop' "${menu}"
  grep -q 'sudo "\$SERVICE_HELPER" status' "${menu}"
  ! grep -q 'sudo "\$BONUS_SCRIPT"' "${menu}"
  grep -q '^                "\$BONUS_SCRIPT" update' "${menu}"
}

@test "prestart does not write mnemonic_password when .maker.env is present" {
  # Configure a wallet so prestart passes the wallet-present check.
  wallet_dir="/home/${USER_JM}/.joinmarket-ng/wallets"
  mkdir -p "${wallet_dir}"
  echo "dummy mnemonic" > "${wallet_dir}/regtest.mnemonic"
  chown -R "${USER_JM}:${USER_JM}" "${wallet_dir}"
  if grep -q '^mnemonic_file' "${CONFIG_TOML}"; then
    sed -i "s|^mnemonic_file.*|mnemonic_file = \"${wallet_dir}/regtest.mnemonic\"|" "${CONFIG_TOML}"
  else
    printf '\n[wallet]\nmnemonic_file = "%s"\n' "${wallet_dir}/regtest.mnemonic" >> "${CONFIG_TOML}"
  fi
  # Remove any permanently stored password and stage a temporary one.
  sed -i '/^mnemonic_password/d' "${CONFIG_TOML}"
  printf 'MNEMONIC_PASSWORD="secret"\n' > "/home/${USER_JM}/.joinmarket-ng/.maker.env"

  run sudo -u "${USER_JM}" bash "${SCRIPT}" prestart
  [ "$status" -eq 0 ]

  # The cleartext password must NOT have been written into config.toml.
  ! grep -q '^mnemonic_password' "${CONFIG_TOML}"

  # Cleanup so later tests see a clean state.
  rm -f "/home/${USER_JM}/.joinmarket-ng/.maker.env"
}

# ---------------------------------------------------------------------------
# 7. Root helper supplies RPC credentials without changing app config
# ---------------------------------------------------------------------------
@test "runtime RPC environment handles special characters" {
  # Write RPC credentials with sed metacharacters
  cat > /mnt/hdd/app-data/bitcoin/bitcoin.conf <<'EOF'
rpcuser=test&user
rpcpassword=pass/word\with|special
EOF
  run bash "${SERVICE_HELPER}" prepare
  [ "$status" -eq 0 ]
  grep -q '^BITCOIN__RPC_USER="test&user"$' /run/joinmarket-ng/rpc.env
  grep -q '^BITCOIN__RPC_PASSWORD="pass/word\\\\with|special"$' /run/joinmarket-ng/rpc.env
  ! grep -q 'test&user\|pass/word' "${CONFIG_TOML}"

  # Restore original test credentials
  cat > /mnt/hdd/app-data/bitcoin/bitcoin.conf <<'EOF'
rpcuser=testuser
rpcpassword=testpass
EOF
}

@test "root service helper has an exact command boundary" {
  grep -q '^if \[ "\${EUID}" -ne 0 \]; then' "${SERVICE_HELPER_SOURCE}"
  grep -q '^if \[ "\$#" -ne 1 \]; then' "${SERVICE_HELPER_SOURCE}"
  grep -q '^    exec systemctl stop "\${SERVICE_NAME}"$' "${SERVICE_HELPER_SOURCE}"
  grep -q '^    exec systemctl start "\${SERVICE_NAME}"$' "${SERVICE_HELPER_SOURCE}"
  grep -q '^    exec systemctl enable "\${SERVICE_NAME}"$' "${SERVICE_HELPER_SOURCE}"
  ! grep -q '\.maker\.env\|config\.toml' "${SERVICE_HELPER_SOURCE}"
}

@test "Password B rotation reloads root-owned RPC credentials for an active maker" {
  local joinmarket_password_block
  joinmarket_password_block=$(awk '
    /# JoinMarket-NG/ { capture=1 }
    capture { print }
    capture && /^  fi$/ { exit }
  ' "${PASSWORD_SCRIPT}")

  echo "${joinmarket_password_block}" \
    | grep -q 'systemctl try-restart joinmarket-ng-maker.service'
  ! echo "${joinmarket_password_block}" | grep -q 'config.toml\|rpc_password'
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
  [ ! -e /run/joinmarket-ng ]

  # Data directory should be PRESERVED (deliberate design choice)
  [ -d "${DATA_DIR}" ]
  [ -f "${CONFIG_TOML}" ]
}

@test "status after uninstall shows isInstalled=0" {
  run bash "${SCRIPT}" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "isInstalled=0"
}

@test "reinstall fails closed on a symlinked persisted config" {
  local target_owner
  target_owner=$(stat -c '%U:%G' /etc/passwd)
  mv "${CONFIG_TOML}" "${CONFIG_TOML}.saved"
  ln -s /etc/passwd "${CONFIG_TOML}"

  run bash "${SCRIPT}" on
  local install_status="${status}"
  local install_output="${output}"

  rm -f "${CONFIG_TOML}"
  mv "${CONFIG_TOML}.saved" "${CONFIG_TOML}"

  [ "${install_status}" -eq 1 ]
  echo "${install_output}" | grep -q 'config.toml must not be a symlink'
  [ "$(stat -c '%U:%G' /etc/passwd)" = "${target_owner}" ]
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
