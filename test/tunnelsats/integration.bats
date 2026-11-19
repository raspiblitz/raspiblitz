#!/usr/bin/env bats
# Integration tests for RaspiBlitz shell hooks changed for TunnelSats:
# - home.admin/config.scripts/tor.network.sh (Tor-off refusal while TunnelSats is active)
# - home.admin/00settingsMenuBasics.sh (SETTINGS UI Tor-off guard)
# - home.admin/config.scripts/blitz.debug.sh (TUNNELSATS debug section)
# - home.admin/config.scripts/internet.tunnelsats.sh (CLI dispatch and status subcommand)

# Variables set here are read by the sourced production functions.
# shellcheck disable=SC2034

bats_require_minimum_version 1.5.0

load helpers

setup() {
    its_setup
    TS_RB_CUSTOM="$FX/app-data/custom-installs.sh"
    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    TOR_NETWORK="${REPO_ROOT}/home.admin/config.scripts/tor.network.sh"
    SETTINGS_MENU="${REPO_ROOT}/home.admin/00settingsMenuBasics.sh"
    BLITZ_DEBUG="${REPO_ROOT}/home.admin/config.scripts/blitz.debug.sh"
}

teardown() {
    its_teardown
}

# Builds an isolated copy of tor.network.sh with RaspiBlitz config and helper paths redirected
# inside $FX and stub binaries on PATH so no system files or network endpoints are touched.
prepare_tor_network_fixture() {
    mkdir -p "$FX/stubbin" "$FX/home.admin/config.scripts"
    : > "$FX/raspiblitz.info"

    printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/blitz.conf.calls"\nexit 0\n' "$FX" \
        > "$FX/home.admin/config.scripts/blitz.conf.sh"
    printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/sudo.calls"\nexit 0\n' "$FX" \
        > "$FX/stubbin/sudo"
    printf '#!/bin/bash\necho inactive\nexit 0\n' > "$FX/stubbin/systemctl"
    printf '#!/bin/bash\nexit 1\n' > "$FX/stubbin/curl"
    chmod 0755 \
        "$FX/home.admin/config.scripts/blitz.conf.sh" \
        "$FX/stubbin/sudo" \
        "$FX/stubbin/systemctl" \
        "$FX/stubbin/curl"

    sed \
        -e "s|/home/admin/raspiblitz.info|${FX}/raspiblitz.info|g" \
        -e "s|/mnt/hdd/app-data/raspiblitz.conf|${FX}/conf/raspiblitz.conf|g" \
        -e "s|/home/admin/config.scripts/blitz.conf.sh|${FX}/home.admin/config.scripts/blitz.conf.sh|g" \
        "$TOR_NETWORK" > "$FX/tor.network.sh"
    chmod 0755 "$FX/tor.network.sh"
}

# Extracts the Tor choice and TunnelSats guard block directly from 00settingsMenuBasics.sh.
extract_settings_tor_guard() {
    sed -n '/^# Tor process choice$/,/^if \[ "\${runBehindTor}" != "\${choice}" \]; then$/{
        /^if \[ "\${runBehindTor}" != "\${choice}" \]; then$/d
        p
    }' "$SETTINGS_MENU" > "$FX/settings_tor_guard.sh"
    grep -qF 'whiptail --title " TunnelSats is active "' "$FX/settings_tor_guard.sh"
    mkdir -p "$FX/stubbin"
    printf '#!/bin/bash\nprintf "%%s\\n" "$@" >> "%s/whiptail.calls"\nexit 0\n' "$FX" \
        > "$FX/stubbin/whiptail"
    chmod 0755 "$FX/stubbin/whiptail"
}

# Extracts the *** TUNNELSATS *** section directly from blitz.debug.sh.
extract_debug_tunnelsats_section() {
    sed -n '/^echo "\*\*\* TUNNELSATS \*\*\*"$/,/^echo$/p' "$BLITZ_DEBUG" > "$FX/debug_tunnelsats.sh"
    grep -qF '/home/admin/config.scripts/internet.tunnelsats.sh status' "$FX/debug_tunnelsats.sh"
    mkdir -p "$FX/stubbin"
    printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/sudo.calls"\necho "tunnelsats=on tunnelsatsImpl=lnd runBehindTor=on"\nexit 0\n' "$FX" \
        > "$FX/stubbin/sudo"
    chmod 0755 "$FX/stubbin/sudo"
}

# ---------------------------------------------------------------------------------------------
# 1. tor.network.sh Tor-off guard
# ---------------------------------------------------------------------------------------------

@test "tor.network.sh off refuses when tunnelsats=on and does not invoke blitz.conf.sh" {
    prepare_tor_network_fixture
    conf "network=bitcoin" "runBehindTor=on" "tunnelsats=on"

    run env PATH="$FX/stubbin:$PATH" bash "$FX/tor.network.sh" off
    [ "$status" -eq 1 ]
    [[ "$output" == *"# FAIL: TunnelSats is active"* ]]
    [[ "$output" == *"err='tunnelsats active'"* ]]
    [ ! -e "$FX/blitz.conf.calls" ]
}

@test "tor.network.sh 0 alias also refuses when tunnelsats=on" {
    prepare_tor_network_fixture
    conf "network=bitcoin" "runBehindTor=on" "tunnelsats=on"

    run env PATH="$FX/stubbin:$PATH" bash "$FX/tor.network.sh" 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"# FAIL: TunnelSats is active"* ]]
    [[ "$output" == *"err='tunnelsats active'"* ]]
    [ ! -e "$FX/blitz.conf.calls" ]
}

@test "tor.network.sh off proceeds when tunnelsats=off and invokes blitz.conf.sh set runBehindTor off" {
    prepare_tor_network_fixture
    conf "network=bitcoin" "runBehindTor=on" "tunnelsats=off"

    run env PATH="$FX/stubbin:$PATH" bash "$FX/tor.network.sh" off
    [ "$status" -eq 0 ]
    [[ "$output" != *"err='tunnelsats active'"* ]]
    [ -f "$FX/blitz.conf.calls" ]
    grep -qx 'set runBehindTor off' "$FX/blitz.conf.calls"
}

# ---------------------------------------------------------------------------------------------
# 2. 00settingsMenuBasics.sh Tor-off UI guard
# ---------------------------------------------------------------------------------------------

@test "00settingsMenuBasics.sh Tor-off guard shows whiptail msgbox and resets choice to on when tunnelsats=on" {
    extract_settings_tor_guard

    run env PATH="$FX/stubbin:$PATH" CHOICES="" runBehindTor="on" tunnelsats="on" \
        bash -c 'source "$1"; printf "choice=%s\n" "${choice}"' _ "$FX/settings_tor_guard.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "choice=on" ]
    [ -f "$FX/whiptail.calls" ]
    grep -qF ' TunnelSats is active ' "$FX/whiptail.calls"
    grep -qF 'SUBSCRIBE > TunnelSats > REMOVE' "$FX/whiptail.calls"
}

@test "00settingsMenuBasics.sh Tor-off guard leaves choice=off untouched when tunnelsats=off" {
    extract_settings_tor_guard

    run env PATH="$FX/stubbin:$PATH" CHOICES="" runBehindTor="on" tunnelsats="off" \
        bash -c 'source "$1"; printf "choice=%s\n" "${choice}"' _ "$FX/settings_tor_guard.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "choice=off" ]
    [ ! -e "$FX/whiptail.calls" ]
}

@test "00settingsMenuBasics.sh Tor-off guard does not warn when Tor remains checked" {
    extract_settings_tor_guard

    run env PATH="$FX/stubbin:$PATH" CHOICES="t" runBehindTor="on" tunnelsats="on" \
        bash -c 'source "$1"; printf "choice=%s\n" "${choice}"' _ "$FX/settings_tor_guard.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "choice=on" ]
    [ ! -e "$FX/whiptail.calls" ]
}

# ---------------------------------------------------------------------------------------------
# 3. blitz.debug.sh TUNNELSATS diagnostic section
# ---------------------------------------------------------------------------------------------

@test "blitz.debug.sh TUNNELSATS section calls internet.tunnelsats.sh status when tunnelsats=on" {
    extract_debug_tunnelsats_section

    run env PATH="$FX/stubbin:$PATH" tunnelsats="on" bash "$FX/debug_tunnelsats.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"*** TUNNELSATS ***"* ]]
    [[ "$output" == *"tunnelsats=on tunnelsatsImpl=lnd runBehindTor=on"* ]]
    [[ "$output" != *"- not activated -"* ]]
    [ -f "$FX/sudo.calls" ]
    grep -qx '/home/admin/config.scripts/internet.tunnelsats.sh status' "$FX/sudo.calls"
}

@test "blitz.debug.sh TUNNELSATS section prints not activated when tunnelsats is off or unset" {
    extract_debug_tunnelsats_section

    run env PATH="$FX/stubbin:$PATH" tunnelsats="off" bash "$FX/debug_tunnelsats.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"*** TUNNELSATS ***"* ]]
    [[ "$output" == *"- not activated -"* ]]
    [ ! -e "$FX/sudo.calls" ]

    run env -u tunnelsats PATH="$FX/stubbin:$PATH" bash "$FX/debug_tunnelsats.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"*** TUNNELSATS ***"* ]]
    [[ "$output" == *"- not activated -"* ]]
    [ ! -e "$FX/sudo.calls" ]
}

# ---------------------------------------------------------------------------------------------
# 4. internet.tunnelsats.sh CLI dispatch and status subcommand
# ---------------------------------------------------------------------------------------------

@test "internet.tunnelsats.sh CLI exits 2 on unknown or missing verb and 0 on --help" {
    run bash "$ITS" no-such-verb
    [ "$status" -eq 2 ]
    [[ "$output" == *"internet.tunnelsats.sh"* ]]

    run bash "$ITS"
    [ "$status" -eq 2 ]
    [[ "$output" == *"internet.tunnelsats.sh"* ]]

    run bash "$ITS" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"internet.tunnelsats.sh"* ]]
}

@test "internet.tunnelsats.sh status rejects unknown options with exit 2" {
    run call its_cmd_status --bogus
    [ "$status" -eq 2 ]
}

@test "internet.tunnelsats.sh status reports unconfigured node in plain text and JSON" {
    run call its_cmd_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"tunnelsats=off tunnelsatsImpl=- runBehindTor=off"* ]]
    [[ "$output" == *"tool_installed=no tool_hash=n/a"* ]]
    [[ "$output" == *"guard_lnd=none guard_lightningd=none"* ]]
    [[ "$output" == *"env_lnd=absent env_lightningd=absent stray_definitions=none"* ]]

    run call its_cmd_status --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.command, .ok, .tunnelsats, .tunnelsatsImpl, .runBehindTor, .tool_installed, .tool_hash, .guard_lnd, .guard_lightningd, .env_lnd, .env_lightningd, .stray_definitions' <<< "$output" | tr '\n' ' ')" = \
      "its.status true off - off no n/a none none absent absent none " ]
}

@test "internet.tunnelsats.sh status reports configured node, verify result, guard records, env files, and strays" {
    conf \
        "tunnelsats=on" \
        "tunnelsatsImpl='lnd'" \
        "runBehindTor=on" \
        "TUNNELSATS_LND_ARGS=--bad"
    stub_tool protected.json
    TS_PIN_SHA256="${TS_ACCEPTED_SHA256[0]}"

    mkdir -p "$TS_RB_RUN_DIR"
    printf '{"schema":"raspiblitz.tunnelsats.guard/1","decision":"hybrid","reason":"ok","decided_at":"2026-10-20T12:00:00Z"}\n' \
        > "${TS_RB_RUN_DIR}/guard-lnd.json"
    printf 'not-valid-json\n' > "${TS_RB_RUN_DIR}/guard-lightningd.json"
    printf 'TUNNELSATS_LND_ARGS=%s\n' "$LND_FLAGS" > "${TS_RB_RUN_DIR}/hybrid-lnd.env"
    printf 'TUNNELSATS_CLN_ARGS=\n' > "${TS_RB_RUN_DIR}/hybrid-lightningd.env"

    run call its_cmd_status --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.tunnelsats, .tunnelsatsImpl, .runBehindTor, .tool_installed, .tool_hash' <<< "$output" | tr '\n' ' ')" = \
      "on lnd on yes current " ]
    [ "$(jq -r '.managed, .verify_rc, .verdict, .emergency_block, .unit, .endpoint_host, .vpn_port' <<< "$output" | tr '\n' ' ')" = \
      "yes 0 protected false lnd.service de2.tunnelsats.com 24556 " ]
    [ "$(jq -r '.guard_lnd, .guard_lightningd, .env_lnd, .env_lightningd, .stray_definitions' <<< "$output" | tr '\n' ' ')" = \
      "hybrid:ok@2026-10-20T12:00:00Z invalid flags empty TUNNELSATS_LND_ARGS " ]
}

@test "internet.tunnelsats.sh status reports invalid env file and unknown tool hash" {
    conf "tunnelsats=on" "tunnelsatsImpl='lnd'" "runBehindTor=on"
    stub_tool protected.json
    TS_ACCEPTED_SHA256=()

    mkdir -p "$TS_RB_RUN_DIR"
    printf 'TUNNELSATS_LND_ARGS=$(evil)\n' > "${TS_RB_RUN_DIR}/hybrid-lnd.env"

    run call its_cmd_status --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.tool_installed, .tool_hash, .managed, .env_lnd' <<< "$output" | tr '\n' ' ')" = \
      "yes unknown n/a invalid " ]
}
