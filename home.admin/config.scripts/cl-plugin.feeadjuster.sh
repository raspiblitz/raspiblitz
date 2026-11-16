#!/bin/bash

# https://github.com/lightningd/plugins/tree/master/feeadjuster
plugin="feeadjuster"
pinnedVersion=""
norestart=0
network=""

fail() {
  echo "# ERROR: $*" >&2
  exit 1
}

if [ $# -eq 0 ] || [[ "$1" = -h || "$1" = -help || "$1" = --help ]]; then
  echo "Install the feeadjuster plugin for Core Lightning"
  echo "Usage:"
  echo "  cl-plugin.feeadjuster.sh on [mainnet|testnet|signet] [norestart] [--commit=<hash>]"
  echo "  cl-plugin.feeadjuster.sh off [mainnet|testnet|signet]"
  echo "Options may appear in either order; omit network to use the configured default."
  echo "--commit requires a 7-40 digit hexadecimal commit hash; default: origin/master."
  echo "Requires system-wide /usr/local/bin/uv >= 0.13.4 (stable), installed by cl.install.sh."
  echo "Configure feeadjuster-* options in CLN config before enabling."
  echo "https://github.com/lightningd/plugins/tree/master/feeadjuster"
  exit 1
fi

action=$1
shift
[[ "$action" = on || "$action" = off ]] || fail "Unknown action: $action"
for arg in "$@"; do
  case "$arg" in
    mainnet|testnet|signet)
      [ -z "$network" ] || fail "Duplicate network"
      network=$arg
      ;;
    norestart)
      [[ "$action" = on && "$norestart" = 0 ]] || fail "Invalid or duplicate norestart"
      norestart=1
      ;;
    --commit=*)
      [[ "$action" = on && -z "$pinnedVersion" ]] || fail "Invalid or duplicate --commit"
      pinnedVersion=${arg#--commit=}
      [[ "$pinnedVersion" =~ ^[[:xdigit:]]{7,40}$ ]] || fail "Invalid commit hash"
      ;;
    *) fail "Unknown argument: $arg" ;;
  esac
done

# Confirm before even probing the installed plugin or its runtime.
if [ "$action" = on ] && [ "$norestart" != 1 ]; then
  echo "# WARNING: feeadjuster will immediately recalculate and overwrite"
  echo "# the fees on ALL your channels upon startup based on current balances."
  echo "# Any manually set fees will be replaced."
  echo "# Make sure feeadjuster-* options are configured in cl.conf first."
  echo "# Press ENTER to continue or CTRL+C to abort."
  read -r _ || fail "Confirmation aborted"
fi

# Capture first: process substitution would hide a failed helper exit status.
networkArgs=(getvars cl)
[ -z "$network" ] || networkArgs+=("$network")
netprefix=invalid
aliases=$(/home/admin/config.scripts/network.aliases.sh "${networkArgs[@]}") || fail "Cannot resolve network"
eval "$aliases" || fail "Cannot load network aliases"
[[ "${netprefix}" = "" || "${netprefix}" = t || "${netprefix}" = s ]] || fail "Invalid network prefix"
[ -n "${lightningcli_alias}" ] || fail "Missing lightning-cli alias"

link="/home/bitcoin/${netprefix}cl-plugins-enabled/${plugin}.py"
key="${netprefix}feeadjuster"
conf=/home/admin/config.scripts/blitz.conf.sh
feeConfig=/home/admin/config.scripts/cl-plugin.feeadjuster-config.py
base=/home/bitcoin/cl-plugins-available
# Snapshot and mutate only while holding this network's lock. A stale lock
# requires an operator to verify no invocation is running before removing it.
sudo -u bitcoin mkdir -p "$base" || fail "Cannot create plugin source directory"
lock="$base/${netprefix}feeadjuster.lock"
sudo -u bitcoin mkdir -m 700 "$lock" || fail "Feeadjuster locked: $lock; if stale, verify no invocation is running before removing it"
trap 'sudo -u bitcoin rmdir -- "$lock" || echo "# ERROR: Cannot release lock: $lock" >&2' EXIT
transactionStarted=0
candidateStarted=0
trap 'if [ "$transactionStarted" = 1 ]; then rollback; fi; exit 130' INT
trap 'if [ "$transactionStarted" = 1 ]; then rollback; fi; exit 143' TERM
[ -n "$CLCONF" ] || fail "Missing CLN config path"
oldFeeConfig=$(sudo -u bitcoin python3 "$feeConfig" snapshot "$CLCONF") || fail "Cannot snapshot fee options"
stage=""
oldLink=""
if [ -L "$link" ]; then
  oldLink=$(sudo -u bitcoin readlink "$link") || fail "Cannot read old plugin link"
elif [ -e "$link" ]; then
  fail "Refusing to replace a non-symlink plugin: $link"
fi

# raspiblitz.conf is trusted shell configuration, as in network.aliases.sh.
# Snapshot only this marker; never copy or overwrite the whole config.
read_marker() (
  unset "$key"
  # shellcheck disable=SC1091
  source /mnt/hdd/app-data/raspiblitz.conf || exit 1
  if [ "${!key+x}" = x ]; then
    printf 'set:%s' "${!key}"
  else
    printf 'absent'
  fi
)
oldMarker=$(read_marker) || fail "Cannot snapshot configuration"

set_marker() {
  local actual
  "$conf" set "$key" "$1" || return 1
  actual=$(read_marker) || return 1
  [ "$actual" = "set:$1" ]
}

state=""
cache=$(/home/admin/_cache.sh get state) || fail "Cannot read node state"
eval "$cache" || fail "Cannot load node state"
manageRuntime=0
if [ "${state}" = ready ] && { [ "$action" = off ] || [ "$norestart" = 0 ]; }; then
  manageRuntime=1
fi

# CLN can report the resolved source path rather than the enabled symlink.
# Fail closed on RPC/JSON errors; do not treat an unknown runtime as stopped.
running_plugin() {
  local plugins
  plugins=$($lightningcli_alias plugin list) || return 1
  jq -er '
    if (.plugins | type) != "array" then error("Missing plugins array") else
      [.plugins[] | select(.active != false) | .name |
        select(. == "feeadjuster.py" or endswith("/feeadjuster.py"))] |
      if length > 1 then error("Multiple feeadjuster plugins")
      else .[0] // "" end
    end' <<< "$plugins"
}
oldRuntime=""
if [ "$manageRuntime" = 1 ]; then
  # jq -e returns 0 for an empty string, but rejects invalid JSON.
  oldRuntime=$(running_plugin) || fail "Cannot determine running feeadjuster"
fi

cleanup_stage() {
  if [ -n "$stage" ]; then
    sudo -u bitcoin rm -rf -- "$stage" || return 1
  fi
}

# Called after activation has begun. Leave sources in place if rollback fails:
# a still-running process may need them. Report every failed restoration.
rollback() {
  local failed=0 current="" runtimeKnown=0
  if [ "$manageRuntime" = 1 ]; then
    if current=$(running_plugin); then
      runtimeKnown=1
      if [ -n "$current" ] && { [ "$current" != "$oldRuntime" ] || [ "$candidateStarted" = 1 ]; }; then
        if ! $lightningcli_alias plugin stop "$current"; then
          echo "# ERROR: Rollback stop returned nonzero; rechecking runtime" >&2
        fi
        if current=$(running_plugin); then
          [ -z "$current" ] || failed=1
        else
          runtimeKnown=0
          failed=1
        fi
      fi
    else
      echo "# ERROR: Rollback runtime unknown" >&2
      failed=1
    fi
  fi
  if [ -n "$oldLink" ]; then
    sudo -u bitcoin ln -sfnT -- "$oldLink" "$link" || failed=1
  else
    sudo -u bitcoin rm -f -- "$link" || failed=1
  fi
  if [ "$oldMarker" = absent ]; then
    "$conf" delete "$key" || failed=1
  else
    "$conf" set "$key" "${oldMarker#set:}" || failed=1
  fi
  local restoredMarker
  restoredMarker=$(read_marker) && [ "$restoredMarker" = "$oldMarker" ] || failed=1
  printf '%s' "$oldFeeConfig" | sudo -u bitcoin python3 "$feeConfig" restore "$CLCONF" || failed=1
  # Restore runtime even when an independent restoration failed. Never claim
  # recovery from an RPC status alone: read back the exact running plugin.
  if [ "$manageRuntime" = 1 ] && [ -n "$oldRuntime" ]; then
    if [ "$runtimeKnown" = 1 ] && [ -z "$current" ]; then
      $lightningcli_alias plugin start "$oldRuntime" || echo "# ERROR: Old plugin restart returned nonzero" >&2
    fi
    if current=$(running_plugin); then
      [ "$current" = "$oldRuntime" ] || failed=1
    else
      failed=1
    fi
  fi
  if [ "$failed" = 0 ]; then
    cleanup_stage || echo "# ERROR: Failed to clean unused staging directory: $stage" >&2
  else
    echo "# ERROR: Rollback incomplete or runtime uncertain; retained sources: $stage. Check plugin runtime, $link, $key and fee options in $CLCONF." >&2
  fi
}

# A nonzero stop can still have stopped the process. Rollback re-queries and
# restarts the previous plugin when stopped; never report 'unchanged' blindly.
stop_old_plugin() {
  local current
  if [ -n "$oldRuntime" ]; then
    if ! $lightningcli_alias plugin stop "$oldRuntime"; then
      rollback
      fail "Plugin stop failed; restoration attempted (see diagnostics above)"
    fi
    if ! current=$(running_plugin) || [ -n "$current" ]; then
      rollback
      fail "Cannot verify plugin stopped; restoration attempted (see diagnostics above)"
    fi
  fi
}

if [ "$action" = on ]; then
  # Do not bootstrap uv here. Check the exact system-wide binary as bitcoin
  # before creating or changing source directories (same minimum as #5328).
  uvVersion=$(sudo -u bitcoin /usr/local/bin/uv --version) || fail "Install system-wide uv via cl.install.sh first"
  [[ "$uvVersion" =~ ^uv\ ([0-9]+)\.([0-9]+)\.([0-9]+)(\ \(.*\))?$ ]] || fail "uv must be a stable release >= 0.13.4"
  major=${BASH_REMATCH[1]}
  minor=${BASH_REMATCH[2]}
  patch=${BASH_REMATCH[3]}
  (( 10#$major > 0 || 10#$minor > 13 || (10#$minor == 13 && 10#$patch >= 4) )) || fail "uv >= 0.13.4 required"

  # Never reset the shared plugins checkout, or a previous working release.
  # Keep the full private checkout: uv run --script resolves upstream metadata.
  stage=$(sudo -u bitcoin mktemp -d "$base/${netprefix}feeadjuster.XXXXXXXX") || fail "Cannot stage plugin"
  if ! sudo -u bitcoin git clone --no-checkout https://github.com/lightningd/plugins.git "$stage/plugins" ||
     ! sudo -u bitcoin git -C "$stage/plugins" fetch origin ||
     ! sudo -u bitcoin git -C "$stage/plugins" checkout --detach "${pinnedVersion:-origin/master}" ||
     ! sudo -u bitcoin sh -c 'cd "$1" && exec /usr/local/bin/uv sync --all-extras' sh "$stage/plugins/$plugin" ||
     ! sudo -u bitcoin chmod +x "$stage/plugins/$plugin/$plugin.py"; then
    cleanup_stage || echo "# ERROR: Cannot clean failed staging directory: $stage" >&2
    fail "Plugin preparation failed; existing installation unchanged"
  fi

  transactionStarted=1
  stop_old_plugin
  if ! sudo -u bitcoin ln -sfnT -- "$stage/plugins/$plugin/$plugin.py" "$link" ||
     ! sudo -u bitcoin python3 "$feeConfig" unpark "$CLCONF" ||
     ! set_marker on; then
    rollback
    fail "Cannot enable plugin"
  fi
  if [ "$manageRuntime" = 1 ]; then
    candidateStarted=1
    if ! $lightningcli_alias plugin start "$link"; then
      rollback
      fail "Plugin activation failed"
    fi
    if ! current=$(running_plugin) || { [ "$current" != "$link" ] && [ "$current" != "$stage/plugins/$plugin/$plugin.py" ]; }; then
      rollback
      fail "Cannot verify activated plugin"
    fi
  fi
  transactionStarted=0
  echo "# The ${plugin} plugin is installed and enabled"
else
  # Keep options in the same config, but comments cannot break a CLN restart
  # while the plugin is absent. No uv prerequisite or source release deletion.
  transactionStarted=1
  stop_old_plugin
  if ! sudo -u bitcoin python3 "$feeConfig" park "$CLCONF" ||
     ! sudo -u bitcoin rm -f -- "$link" || ! set_marker off; then
    rollback
    fail "Cannot disable plugin"
  fi
  transactionStarted=0
  echo "# The ${plugin} plugin was disabled"
fi
