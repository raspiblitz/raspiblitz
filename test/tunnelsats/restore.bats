#!/usr/bin/env bats
# fetch (pinned, signed, hashed), contract pass-through verbs, restore after an SD-card update and
# the tick timer (design 4.3, 5.2-5.4, 6.9). Real functions of internet.tunnelsats.sh; the network
# is a local file:// repository and the tool is a stub at the stored-copy path.

# Variables set here are read by the sourced production functions.
# shellcheck disable=SC2034

bats_require_minimum_version 1.5.0

load helpers

setup() {
    its_setup
    TS_RB_CUSTOM="$FX/app-data/custom-installs.sh"
    TS_RB_UNIT_DIR="$FX/units"
    TS_RB_LOGGER="$FX/bin/logger"
    mkdir -p "$TS_RB_UNIT_DIR" "$FX/admin/config.scripts" "$FX/answers"
    printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/journal"\n' "$FX" > "$FX/bin/logger"
    printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/systemctl.calls"\n[ "$1" = is-active ] && echo active\nexit 0\n' "$FX" > "$FX/bin/systemctl"
    chmod 0755 "$FX/bin/logger" "$FX/bin/systemctl"
    DIST="$FX/app-data/tunnelsats/dist/tunnelsats-${TS_PIN_VERSION}-${TS_PIN_COMMIT:0:12}.sh"
    CONF="$FX/app-data/tunnelsats/tunnelsats.conf"
}

teardown() {
    its_teardown
}

# The stored copy is a stub answering each verb with answers/<verb>.<n>.json (n-th call) or
# answers/<verb>.json, exiting with that document's exit_code; it records argv and environment.
dist_stub() {
    mkdir -p "$FX/app-data/tunnelsats/dist"
    chmod 0700 "$FX/app-data/tunnelsats" "$FX/app-data/tunnelsats/dist"
    cat > "$DIST" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> '$FX/dist.calls'
env > '$FX/dist.env'
verb="\$1"
n=\$(( \$(cat '$FX/count.'"\$verb" 2>/dev/null || echo 0) + 1 ))
echo "\$n" > '$FX/count.'"\$verb"
f='$FX/answers/'"\$verb.\$n"'.json'
[ -f "\$f" ] || f='$FX/answers/'"\$verb"'.json'
cat "\$f"
exit "\$(jq -r .exit_code "\$f")"
EOF
    chmod 0644 "$DIST"
    TS_PIN_SHA256="$(sha256sum "$DIST" | cut -d' ' -f1)"
    TS_ACCEPTED_SHA256=("$TS_PIN_SHA256")
}

answer() {   # answer <verb>[.<n>] <fixture path below fixtures/>
    cp "${FIXTURES}/$2" "$FX/answers/$1.json"
}

stored_conf() {
    mkdir -p "$FX/app-data/tunnelsats"
    chmod 0700 "$FX/app-data/tunnelsats"
    printf '%s\n' '# Port Forwarding: 24556' '[Interface]' 'PrivateKey = fixturefixturefixturefixturefixturefixture0E=' \
        'Address = 10.9.0.42/32' '[Peer]' 'PublicKey = serverserverserverserverserverserverserv0E=' \
        'Endpoint = de2.tunnelsats.com:51820' 'AllowedIPs = 0.0.0.0/0' > "$CONF"
    chmod 0600 "$CONF"
}

active_node() {   # $1 impl
    conf "runBehindTor=on" "tunnelsats=on" "tunnelsatsImpl='${1:-lnd}'"
    stored_conf
    dist_stub
}

# A local upstream repository with scripts/tunnelsats.sh at one commit; pins point at it.
upstream_repo() {   # $1 = TS_CONTRACT value in the file (default 1)
    local u="$FX/upstream"
    git init -q "$u"
    mkdir -p "$u/scripts" "$u/docs"
    printf '#!/bin/bash\nVERSION="%s"\nTS_CONTRACT=%s\necho tool\n' "$TS_PIN_VERSION" "${1:-1}" > "$u/scripts/tunnelsats.sh"
    echo "other content" > "$u/docs/other.md"
    git -C "$u" add -A
    git -C "$u" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false \
        -c core.hooksPath=/dev/null commit -q -m fixture
    git -C "$u" config uploadpack.allowFilter true
    git -C "$u" config uploadpack.allowAnySHA1InWant true
    TS_REPO_URL="file://$u"
    TS_PIN_COMMIT="$(git -C "$u" rev-parse HEAD)"
    TS_PIN_SHA256="$(sha256sum "$u/scripts/tunnelsats.sh" | cut -d' ' -f1)"
    DIST="$FX/app-data/tunnelsats/dist/tunnelsats-${TS_PIN_VERSION}-${TS_PIN_COMMIT:0:12}.sh"
    printf '#!/bin/bash\necho "$(pwd) $* $(git log --format=%%H -1)" >> "%s/gitverify.log"\nexit "${GITVERIFY_RC:-0}"\n' "$FX" \
        > "$FX/admin/config.scripts/blitz.git-verify.sh"
    chmod 0755 "$FX/admin/config.scripts/blitz.git-verify.sh"
}

# ---------------------------------------------------------------------------------------------
# fetch
# ---------------------------------------------------------------------------------------------

@test "fetch online: exactly the pinned commit, signature checked in it, hash and contract lines, stored 0644" {
    upstream_repo
    mkdir -p "$FX/app-data/tunnelsats/dist"
    chmod 0700 "$FX/app-data/tunnelsats" "$FX/app-data/tunnelsats/dist"
    echo old > "$FX/app-data/tunnelsats/dist/tunnelsats-3.1-0123456789ab.sh"
    run --separate-stderr call its_cmd_fetch --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.signature.result, .source, .actual_sha256 == .pinned_sha256, .path' <<< "$output" | tr '\n' ' ')" = \
        "good network true ${DIST} " ]
    cmp "$FX/upstream/scripts/tunnelsats.sh" "$DIST"
    [ "$(stat -c %a "$DIST")" = 644 ]
    [ ! -e "$FX/app-data/tunnelsats/dist/tunnelsats-3.1-0123456789ab.sh" ]
    [[ "$(cat "$FX/gitverify.log")" == *" web-flow https://github.com/web-flow.gpg B5690EEEBB952194 ${TS_PIN_COMMIT}" ]]
    [ -z "$(find "$TS_RB_TOOL_TMP" -mindepth 1 -maxdepth 1 -name '.tunnelsats-*')" ]
}

@test "fetch online: a bad signature, another sha256 or other contract lines store nothing" {
    upstream_repo
    GITVERIFY_RC=1 run --separate-stderr call its_cmd_fetch --json
    [ "$status" -eq 1 ]
    [ "$(jq -r '.error, .signature.result' <<< "$output" | tr '\n' ' ')" = "E_SIGNATURE bad " ]
    [ ! -e "$DIST" ]
    TS_PIN_SHA256="0000000000000000000000000000000000000000000000000000000000000000"
    run --separate-stderr call its_cmd_fetch --json
    [ "$status" -eq 1 ]
    [ "$(jq -r .error <<< "$output")" = E_HASH_MISMATCH ]
    [ ! -e "$DIST" ]
    setup
    upstream_repo 2
    run --separate-stderr call its_cmd_fetch --json
    [ "$status" -eq 1 ]
    [ "$(jq -r .error <<< "$output")" = E_CONTRACT ]
    TS_REPO_URL="file://$FX/nowhere"
    run --separate-stderr call its_cmd_fetch --json
    [ "$status" -eq 1 ]
    [ "$(jq -r .error <<< "$output")" = E_DOWNLOAD_FAILED ]
}

@test "fetch online: all network steps share one time budget (a remote that never answers)" {
    local pid port
    upstream_repo
    # a git:// server that accepts connections and never answers
    python3 -c 'import socket, sys
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(8)
open(sys.argv[1], "w").write(str(s.getsockname()[1]))
conns = []
while True:
    conns.append(s.accept()[0])' "$FX/port" 3>&- &
    pid=$!
    for _ in $(seq 50); do [ -s "$FX/port" ] && break; sleep 0.1; done
    port=$(cat "$FX/port")
    TS_REPO_URL="git://127.0.0.1:${port}/tunnelsats.git"
    TS_RB_FETCH_BUDGET=3
    SECONDS=0
    run --separate-stderr call its_cmd_fetch --json
    kill "$pid"
    [ "$status" -eq 1 ]
    [ "$SECONDS" -lt 15 ]
    [ "$(jq -r .error <<< "$output")" = E_DOWNLOAD_FAILED ]
    [[ "$(jq -r '.errors[0].message' <<< "$output")" == *"did not finish within 3 s"* ]]
    [ ! -e "$DIST" ]
    [ -z "$(find "$TS_RB_TOOL_TMP" -mindepth 1 -maxdepth 1 -name '.tunnelsats-*')" ]
}

@test "fetch --offline: no copy (exit 3), a copy with another hash is deleted (exit 1), a matching copy is used" {
    run --separate-stderr call its_cmd_fetch --offline --json
    [ "$status" -eq 3 ]
    [ "$(jq -r .error <<< "$output")" = E_NOT_FETCHED ]
    dist_stub
    run --separate-stderr call its_cmd_fetch --offline --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.signature.result, .source' <<< "$output" | tr '\n' ' ')" = "stored stored " ]
    echo "# changed" >> "$DIST"
    run --separate-stderr call its_cmd_fetch --offline --json
    [ "$status" -eq 1 ]
    [ "$(jq -r .error <<< "$output")" = E_HASH_MISMATCH ]
    [ ! -e "$DIST" ]
}

@test "fetch --dev-override: root-owned file with the given sha256; the guard accepts it for this boot only" {
    printf '#!/bin/bash\necho dev\n' > "$FX/dev.sh"
    chmod 0644 "$FX/dev.sh"
    local h
    h=$(sha256sum "$FX/dev.sh" | cut -d' ' -f1)
    run --separate-stderr call its_cmd_fetch --dev-override "$FX/dev.sh" --dev-sha256 0000000000000000000000000000000000000000000000000000000000000000 --json
    [ "$status" -eq 1 ]
    [ "$(jq -r .error <<< "$output")" = E_HASH_MISMATCH ]
    chmod 0664 "$FX/dev.sh"
    run --separate-stderr call its_cmd_fetch --dev-override "$FX/dev.sh" --dev-sha256 "$h" --json
    [ "$status" -eq 1 ]
    [ "$(jq -r .error <<< "$output")" = E_DEV_OVERRIDE ]
    chmod 0644 "$FX/dev.sh"
    run --separate-stderr call its_cmd_fetch --dev-override "$FX/dev.sh" --dev-sha256 "$h" --json
    [ "$status" -eq 0 ]
    [ "$(jq -r .source <<< "$output")" = dev_override ]
    [ "$(cat "${TS_RB_RUN_DIR}/dev-override.sha256")" = "$h" ]
    cmp "$FX/dev.sh" "$FX/app-data/tunnelsats/dist/dev-override.sh"
    grep -q 'DEV OVERRIDE' "$FX/journal"
    [ "$(call its_dev_override_sha)" = "$h" ]
}

@test "fetch, install, adopt, uninstall, verify, detect need root" {
    TS_RB_ROOT_UID=99999
    local verb
    for verb in its_cmd_fetch its_cmd_uninstall its_cmd_verify its_cmd_detect; do
        run --separate-stderr call "$verb" --json
        [ "$status" -eq 2 ]
        [ "$(jq -r '.errors[0].code' <<< "$output")" = E_NOT_ROOT ]
    done
    run --separate-stderr call its_cmd_install --impl lnd --json
    [ "$status" -eq 2 ]
    run --separate-stderr call its_cmd_adopt --impl lnd --json
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------------------------
# Contract calls
# ---------------------------------------------------------------------------------------------

@test "install: needs the stored config; runs the stored copy with the exact arguments; cl becomes cln" {
    dist_stub
    answer install tool/install_ok.json
    run --separate-stderr call its_cmd_install --impl lnd --json
    [ "$status" -eq 3 ]
    [ "$(jq -r '.errors[0].code' <<< "$output")" = E_NOT_CONFIGURED ]
    stored_conf
    run --separate-stderr call its_cmd_install --impl lnd --json
    [ "$status" -eq 0 ]
    [ "$output" = "$(cat "${FIXTURES}/tool/install_ok.json")" ]
    [ "$(tail -n 1 "$FX/dist.calls")" = "install --managed raspiblitz --impl lnd --network mainnet --config ${CONF} --non-interactive --yes --json" ]
    run --separate-stderr call its_cmd_install --impl cl --json
    [ "$(tail -n 1 "$FX/dist.calls")" = "install --managed raspiblitz --impl cln --network mainnet --config ${CONF} --non-interactive --yes --json" ]
    answer install tool/install_capability.json
    run --separate-stderr call its_cmd_install --impl lnd --json
    [ "$status" -eq 6 ]
    [ "$(jq -r '.errors[0].code' <<< "$output")" = E_CAPABILITY_MISSING ]
    chmod 0644 "$CONF"
    run --separate-stderr call its_cmd_install --impl lnd --json
    [ "$status" -eq 3 ]
}

@test "adopt: needs the stored config; runs the stored copy with adopt --managed raspiblitz; cl becomes cln" {
    dist_stub
    answer adopt tool/install_ok.json
    run --separate-stderr call its_cmd_adopt --impl lnd --json
    [ "$status" -eq 3 ]
    [ "$(jq -r '.errors[0].code' <<< "$output")" = E_NOT_CONFIGURED ]
    stored_conf
    run --separate-stderr call its_cmd_adopt --impl lnd --json
    [ "$status" -eq 0 ]
    [ "$output" = "$(cat "${FIXTURES}/tool/install_ok.json")" ]
    [ "$(tail -n 1 "$FX/dist.calls")" = "adopt --managed raspiblitz --impl lnd --network mainnet --config ${CONF} --non-interactive --yes --json" ]
    run --separate-stderr call its_cmd_adopt --impl cl --json
    [ "$(tail -n 1 "$FX/dist.calls")" = "adopt --managed raspiblitz --impl cln --network mainnet --config ${CONF} --non-interactive --yes --json" ]
}

@test "pass-through: contract 2 becomes E_CONTRACT, no document becomes E_TOOL_OUTPUT, env is clean" {
    dist_stub
    stored_conf
    jq -c '.contract = 2' "${FIXTURES}/tool/install_ok.json" > "$FX/answers/install.json"
    export SYSTEMCTL_BIN=/tmp/x TS_FS_ROOT=/tmp/fs tunnelsats=on
    run --separate-stderr call its_cmd_install --impl lnd --json
    unset SYSTEMCTL_BIN TS_FS_ROOT tunnelsats
    [ "$status" -eq 1 ]
    [ "$(jq -r '.command, .errors[0].code' <<< "$output" | tr '\n' ' ')" = "its.install E_CONTRACT " ]
    refute grep -Eq '^(SYSTEMCTL_BIN|TS_FS_ROOT|tunnelsats|TS_RB_[A-Z_]*)=' "$FX/dist.env"
    printf '{"exit_code":0}\nnot json\n' > "$FX/answers/install.json"
    run --separate-stderr call its_cmd_install --impl lnd --json
    [ "$status" -eq 1 ]
    [ "$(jq -r '.errors[0].code' <<< "$output")" = E_TOOL_OUTPUT ]
}

@test "uninstall: the installed tool when trusted, else the stored copy" {
    dist_stub
    answer uninstall tool/uninstall_disabled.json
    stub_tool ../tool/uninstall_disabled.json
    TS_ACCEPTED_SHA256+=("$TS_PIN_SHA256")
    run --separate-stderr call its_cmd_uninstall --json
    [ "$status" -eq 0 ]
    [ "$(cat "$FX/tool.calls")" = "uninstall --managed --non-interactive --yes --json" ]
    [ ! -e "$FX/dist.calls" ]
    chmod 0777 "$TS_RB_TOOL"
    run --separate-stderr call its_cmd_uninstall --json
    [ "$status" -eq 0 ]
    [ "$(jq -r .ln_disabled <<< "$output")" = true ]
    [ "$(cat "$FX/dist.calls")" = "uninstall --managed --non-interactive --yes --json" ]
}

@test "tool runs: a tool that clears /run/tunnelsats (uninstall --managed, a failed install's rollback) keeps its document" {
    local doc="${FIXTURES}/tool/uninstall_disabled.json" sha
    mkdir -m 0755 "$TS_RB_RUN_DIR"
    printf 'TUNNELSATS_LND_ARGS=\n' > "${TS_RB_RUN_DIR}/hybrid-lnd.env"
    printf '#!/bin/bash\nrm -rf -- %q\ncat %q\nexit 0\n' "$TS_RB_RUN_DIR" "$doc" > "$FX/clearing-tool.sh"
    sha=$(sha256sum "$FX/clearing-tool.sh" | cut -d' ' -f1)
    run --separate-stderr call its_tool_out 1 uninstall "$FX/clearing-tool.sh" "$sha" 30 uninstall --managed --non-interactive --yes
    [ "$status" -eq 0 ]
    [ "$output" = "$(cat "$doc")" ]
    [ ! -e "$TS_RB_RUN_DIR" ]
    [ -z "$(find "$TS_RB_TOOL_TMP" -mindepth 1 -maxdepth 1 -name '.tunnelsats-*')" ]
}

@test "verify: an untrusted installed tool is refused; without an install the stored copy answers" {
    dist_stub
    answer verify verify/not_installed.json
    stub_tool activating_tunnel_up.json
    TS_ACCEPTED_SHA256=("$TS_PIN_SHA256")
    run --separate-stderr call its_cmd_verify --no-probe --json
    [ "$status" -eq 1 ]
    [ "$(jq -r '.errors[0].code' <<< "$output")" = E_TOOL_UNTRUSTED ]
    rm "$TS_RB_TOOL"
    run --separate-stderr call its_cmd_verify --no-probe --json
    [ "$status" -eq 3 ]
    [ "$(jq -r '.errors[0].code' <<< "$output")" = E_NOT_INSTALLED ]
    [ "$(cat "$FX/dist.calls")" = "verify --no-probe --json" ]
}

@test "detect: the stored copy answers, read-only" {
    dist_stub
    answer detect tool/detect_legacy.json
    run --separate-stderr call its_cmd_detect --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.install.kind, .config.path' <<< "$output" | tr '\n' ' ')" = "legacy_v3_post_204 /etc/wireguard/tunnelsatsv2.conf " ]
    [ "$(cat "$FX/dist.calls")" = "detect --json" ]
}

# ---------------------------------------------------------------------------------------------
# restore
# ---------------------------------------------------------------------------------------------

@test "restore: TunnelSats off does nothing (a block left by a failed REMOVE stays inert)" {
    conf "runBehindTor=on" "tunnelsats=off"
    dist_stub
    run call its_cmd_restore
    [ "$status" -eq 0 ]
    [ "$output" = "# TunnelSats: not active, nothing to restore" ]
    [ ! -e "$FX/dist.calls" ]
    grep -q 'tunnelsats-restore' "$FX/journal"
}

@test "restore: Tor off refuses before anything is installed, with the reason logged and recorded" {
    active_node lnd
    conf "runBehindTor=off" "tunnelsats=on" "tunnelsatsImpl='lnd'"
    run --separate-stderr call its_cmd_restore --json
    [ "$status" -eq 1 ]
    [ "$(jq -r '.result, .errors[0].code, .errors[0].class' <<< "$output" | tr '\n' ' ')" = "refused E_TOR_REQUIRED refused " ]
    [[ "$stderr" == *"Tor is off and TunnelSats needs it"* ]]
    [ ! -e "$FX/dist.calls" ]
    [ -z "$(find "$TS_RB_UNIT_DIR" -mindepth 1)" ]
    [ "$(jq -r '.result, .error' "$FX/app-data/tunnelsats/last-restore.json" | tr '\n' ' ')" = "refused E_TOR_REQUIRED " ]
    grep -q 'Tor is off' "$FX/journal"
}

@test "restore: stored config missing or not root 0600: exit 3, Lightning stays Tor-only" {
    conf "runBehindTor=on" "tunnelsats=on" "tunnelsatsImpl='lnd'"
    dist_stub
    run call its_cmd_restore
    [ "$status" -eq 3 ]
    [[ "$output" == *"stored config missing"* ]]
    [ "$(jq -r '.result, .error' "$FX/app-data/tunnelsats/last-restore.json" | tr '\n' ' ')" = "not_configured E_NOT_CONFIGURED " ]
    stored_conf
    chmod 0640 "$CONF"
    run call its_cmd_restore
    [ "$status" -eq 3 ]
    [ ! -e "$FX/dist.calls" ]
}

@test "restore: installs managed mode from the stored copy, sets up the tick timer, records the result" {
    active_node lnd
    answer verify verify/not_installed.json
    answer install tool/install_ok.json
    export INVOCATION_ID=0123456789abcdef0123456789abcdef SYSTEMCTL_BIN=/tmp/x
    run call its_cmd_restore
    unset INVOCATION_ID SYSTEMCTL_BIN
    [ "$status" -eq 0 ]
    [[ "$output" == *"# TunnelSats: managed mode restored; Lightning restarted"* ]]
    [ "$(sed -n 1p "$FX/dist.calls")" = "verify --json --no-probe" ]
    [ "$(sed -n 2p "$FX/dist.calls")" = "install --managed raspiblitz --impl lnd --network mainnet --config ${CONF} --non-interactive --yes --json" ]
    refute grep -Eq '^(SYSTEMCTL_BIN|INVOCATION_ID|TS_RB_[A-Z_]*)=' "$FX/dist.env"
    [ -f "$TS_RB_UNIT_DIR/tunnelsats-tick.timer" ]
    grep -qx 'enable --now tunnelsats-tick.timer' "$FX/systemctl.calls"
    [ "$(jq -r '.result, .error, .tool_version, .ln_restarted' "$FX/app-data/tunnelsats/last-restore.json" | tr '\n' ' ')" = \
        "ok null ${TS_PIN_VERSION} true " ]
    [ "$(stat -c %a "$FX/app-data/tunnelsats/last-restore.json")" = 644 ]
    [ -z "$(find "$TS_RB_TOOL_TMP" -mindepth 1 -maxdepth 1 -name '.tunnelsats-*')" ]
}

@test "restore: CLN maps to --impl cln; an existing managed install is not installed again" {
    active_node cl
    answer verify verify/not_installed.json
    answer install tool/install_ok_stopped.json
    run call its_cmd_restore
    [ "$status" -eq 0 ]
    [[ "$(sed -n 2p "$FX/dist.calls")" == "install --managed raspiblitz --impl cln "* ]]
    [ "$(jq -r .ln_restarted "$FX/app-data/tunnelsats/last-restore.json")" = false ]
    setup
    active_node lnd
    answer verify verify/activating_tunnel_up.json
    run call its_cmd_restore
    [ "$status" -eq 0 ]
    [[ "$output" == *"already in place for lnd.service"* ]]
    [ "$(cat "$FX/dist.calls")" = "verify --json --no-probe" ]
}

@test "restore: a failed install is reported and recorded; E_MANAGED_PRESENT with managed mode in place counts as restored" {
    active_node lnd
    answer verify verify/not_installed.json
    answer install tool/install_capability.json
    run call its_cmd_restore
    [ "$status" -eq 1 ]
    [[ "$output" == *"install failed (E_CAPABILITY_MISSING); Lightning stays Tor-only"* ]]
    [ "$(jq -r '.result, .error' "$FX/app-data/tunnelsats/last-restore.json" | tr '\n' ' ')" = "failed E_CAPABILITY_MISSING " ]
    [ ! -e "$TS_RB_UNIT_DIR/tunnelsats-tick.timer" ]
    rm -f "$FX"/count.*
    answer verify.1 verify/not_installed.json
    answer verify.2 verify/activating_tunnel_up.json
    answer install tool/install_managed_present.json
    run call its_cmd_restore
    [ "$status" -eq 0 ]
    [ "$(jq -r .result "$FX/app-data/tunnelsats/last-restore.json")" = ok ]
}

@test "restore: no stored copy and the download fails: exit 1, nothing installed, no unpinned fallback" {
    conf "runBehindTor=on" "tunnelsats=on" "tunnelsatsImpl='lnd'"
    stored_conf
    TS_REPO_URL="file://$FX/nowhere"
    run --separate-stderr call its_cmd_restore --json
    [ "$status" -eq 1 ]
    [ "$(jq -r '.command, .result, .errors[0].code' <<< "$output" | tr '\n' ' ')" = "its.restore failed E_DOWNLOAD_FAILED " ]
    [ "$(jq -r .error "$FX/app-data/tunnelsats/last-restore.json")" = E_DOWNLOAD_FAILED ]
    [ ! -d "$FX/app-data/tunnelsats/dist" ] || [ -z "$(ls -A "$FX/app-data/tunnelsats/dist")" ]
}

@test "restore: downloads the pinned copy when none is stored, then installs" {
    conf "runBehindTor=on" "tunnelsats=on" "tunnelsatsImpl='lnd'"
    stored_conf
    upstream_repo
    run call its_cmd_restore
    [ "$status" -eq 1 ]
    [[ "$output" == *"downloading the pinned one"* ]]
    [[ "$output" == *"install failed (E_TOOL_OUTPUT)"* ]]
    [ -f "$DIST" ]
    [ -s "$FX/gitverify.log" ]
}

# ---------------------------------------------------------------------------------------------
# tick timer and status
# ---------------------------------------------------------------------------------------------

@test "tick-timer: on renders and enables the units, status reads them, off removes them" {
    run call its_cmd_tick_timer status
    [ "$output" = absent ]
    run call its_cmd_tick_timer on
    [ "$status" -eq 0 ]
    printf '%s\n' "[Unit]" "Description=TunnelSats RaspiBlitz tick (restart notice)" "[Service]" "Type=oneshot" \
        "ExecStart=/home/admin/config.scripts/blitz.subscriptions.tunnelsats.py tick --json" > "$FX/svc"
    printf '%s\n' "[Unit]" "Description=TunnelSats RaspiBlitz tick every 5 minutes" "[Timer]" "OnBootSec=5min" \
        "OnUnitActiveSec=5min" "[Install]" "WantedBy=timers.target" > "$FX/tmr"
    cmp "$FX/svc" "$TS_RB_UNIT_DIR/tunnelsats-tick.service"
    cmp "$FX/tmr" "$TS_RB_UNIT_DIR/tunnelsats-tick.timer"
    [ "$(stat -c %a "$TS_RB_UNIT_DIR/tunnelsats-tick.timer")" = 644 ]
    [ "$(cat "$FX/systemctl.calls")" = $'daemon-reload\nenable --now tunnelsats-tick.timer' ]
    run call its_cmd_tick_timer status
    [ "$output" = active ]
    run call its_cmd_tick_timer off
    [ "$status" -eq 0 ]
    [ ! -e "$TS_RB_UNIT_DIR/tunnelsats-tick.timer" ] && [ ! -e "$TS_RB_UNIT_DIR/tunnelsats-tick.service" ]
    grep -qx 'disable --now tunnelsats-tick.timer' "$FX/systemctl.calls"
}

@test "status: no secrets, no network; verify fields from the trusted tool, the restore result" {
    active_node lnd
    answer verify verify/not_installed.json
    answer install tool/install_ok.json
    run call its_cmd_restore
    stub_tool activating_tunnel_up.json
    TS_ACCEPTED_SHA256+=("$TS_PIN_SHA256")
    run call its_cmd_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"tunnelsats=on tunnelsatsImpl=lnd runBehindTor=on"* ]]
    [[ "$output" == *"managed=yes verify_rc=5 verdict=degraded emergency_block=false unit=lnd.service"* ]]
    [[ "$output" == *"endpoint_host=de2.tunnelsats.com vpn_port=24556"* ]]
    [[ "$output" == *"restore_block=absent last_restore=ok@"* ]]
    [[ "$output" != *"PrivateKey"* ]] && [[ "$output" != *"fixturefixture"* ]] && [[ "$output" != *"1.2.3.4"* ]]
    run --separate-stderr call its_cmd_status --json
    [ "$(jq -r '.command, .managed, .tool_hash' <<< "$output" | tr '\n' ' ')" = "its.status yes accepted_older " ]
    [[ "$(jq -r .last_restore <<< "$output")" == ok@* ]]
    TS_RB_ROOT_UID=99999
    run call its_cmd_status
    [[ "$output" == *"managed=n/a verify_rc=n/a"* ]]
    [[ "$output" == *"last_restore=n/a"* ]]
}
