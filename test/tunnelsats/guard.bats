#!/usr/bin/env bats
# Start guard decision matrix (design sections 3.3-3.9, maintainer answers 11.1). Every test runs
# the real guard functions of internet.tunnelsats.sh against a fixture tree; the tool is a stub
# printing real verify documents of the pinned tunnelsats.sh (fixtures/verify/README.md).

# Variables set here are read by the sourced production functions.
# shellcheck disable=SC2034

bats_require_minimum_version 1.5.0

load helpers

setup() {
    its_setup
}

teardown() {
    its_teardown
}

lnd_node() {
    conf "lightning=lnd" "chain=main" "runBehindTor=on" "tunnelsats=on" "tunnelsatsImpl='lnd'"
    lnd_conf lnd.conf
    stub_tool "${1:-activating_tunnel_up.json}"
}

cln_node() {
    conf "lightning=cl" "chain=main" "runBehindTor=on" "tunnelsats=on" "tunnelsatsImpl='cl'"
    cln_conf cl-config
    stub_tool "${1:-cln_activating_tunnel_up.json}"
}

skip_if_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        skip "needs file permissions that root ignores"
    fi
}

# ---------------------------------------------------------------------------------------------
# Hybrid rows
# ---------------------------------------------------------------------------------------------

@test "H1: LND, rc 5 while activating: hybrid with the exact flags, one line, root 0644" {
    lnd_node
    run call its_cmd_guard lnd mainnet
    [ "$status" -eq 0 ]
    assert_decision hybrid ok
    [[ "$output" == *"verify_rc=5 verdict=degraded emergency_block=false announce=de2.tunnelsats.com:24556 repaired=- duration_ms="* ]]
    run cat -A "${TS_RB_RUN_DIR}/hybrid-lnd.env"
    [ "$output" = "TUNNELSATS_LND_ARGS=${LND_FLAGS}\$" ]
    [ "$(stat -c %a "${TS_RB_RUN_DIR}/hybrid-lnd.env")" = 644 ]
    [ "$(stat -c %a "${TS_RB_RUN_DIR}")" = 755 ]
    [ "$(record_field lnd .decision)" = hybrid ]
    [ "$(record_field lnd .flags)" = "$LND_FLAGS" ]
    [ "$(record_field lnd .announce.host)" = de2.tunnelsats.com ]
    [ "$(record_field lnd .announce.port)" = 24556 ]
    [ "$(record_field lnd .announce.ipv4)" = 1.2.3.4 ]
    [ "$(record_field lnd .verify.rc)" = 5 ]
    [ "$(record_field lnd .verify.tool_sha256)" = "${TS_ACCEPTED_SHA256[0]}" ]
    [ "$(record_field lnd .boot_id)" = 0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0 ]
    [ "$(stat -c %a "${TS_RB_RUN_DIR}/guard-lnd.json")" = 644 ]
    assert_schema "${TS_RB_RUN_DIR}/guard-lnd.json"
    cmp -s "${TS_RB_RUN_DIR}/guard-lnd.verify.json" "${FIXTURES}/verify/activating_tunnel_up.json"
    [ "$(tool_calls)" -eq 1 ]
    [ "$(cat "$FX/tool.calls")" = "verify --json --no-probe" ]
}

@test "H2: CLN, rc 5, address confirmed by handshake: flags with the announce address" {
    cln_node
    run call its_cmd_guard cl mainnet
    [ "$status" -eq 0 ]
    assert_decision hybrid ok
    [ "$(env_of lightningd)" = "TUNNELSATS_CLN_ARGS=${CLN_FLAGS_ANNOUNCE}" ]
    [ "$(record_field lightningd .announce.ipv4)" = 1.2.3.4 ]
    [[ "$output" == *"announce=1.2.3.4:24556"* ]]
    assert_schema "${TS_RB_RUN_DIR}/guard-lightningd.json"
    [ "$(tool_calls)" -eq 1 ]
}

@test "H3: CLN, address not confirmed (DNS failed): hybrid without --announce-addr, no wait" {
    cln_node cln_activating_dns_unresolved.json
    run call its_cmd_guard cl mainnet
    [ "$status" -eq 0 ]
    assert_decision hybrid announce_unconfirmed
    [[ "$output" == *"detail=dns_unresolved"* ]]
    [ "$(env_of lightningd)" = "TUNNELSATS_CLN_ARGS=${CLN_FLAGS_PLAIN}" ]
    [ "$(record_field lightningd .detail)" = dns_unresolved ]
    [ "$(tool_calls)" -eq 1 ]
}

@test "H4: rc 0 (outside ExecStartPre) is hybrid for LND and CLN" {
    lnd_node protected.json
    run call its_cmd_guard lnd mainnet
    [ "$status" -eq 0 ]
    assert_decision hybrid ok
    its_setup
    cln_node cln_protected.json
    run call its_cmd_guard cl mainnet
    [ "$status" -eq 0 ]
    assert_decision hybrid ok
    [ "$(env_of lightningd)" = "TUNNELSATS_CLN_ARGS=${CLN_FLAGS_ANNOUNCE}" ]
}

@test "H5: LND announces what it resolves: the record keeps a public endpoint IPv4 only, the flags never change" {
    lnd_node activating_dns_unresolved.json
    run call its_cmd_guard lnd mainnet
    [ "$status" -eq 0 ]
    assert_decision hybrid ok
    [ "$(env_of lnd)" = "TUNNELSATS_LND_ARGS=${LND_FLAGS}" ]
    [ "$(record_field lnd .announce.ipv4)" = null ]
    [[ "$output" == *"announce=de2.tunnelsats.com:24556 "* ]]
    its_setup
    lnd_node
    jq -c '.endpoint.ipv4 = "10.9.0.1"' "${FIXTURES}/verify/activating_tunnel_up.json" > "$FX/private.json"
    printf '#!/bin/bash\ncat %q\nexit 5\n' "$FX/private.json" > "$TS_RB_TOOL"
    chmod 0755 "$TS_RB_TOOL"
    TS_ACCEPTED_SHA256=("$(sha256sum "$TS_RB_TOOL" | cut -d' ' -f1)")
    run call its_cmd_guard lnd mainnet
    [ "$status" -eq 0 ]
    assert_decision hybrid ok
    [ "$(env_of lnd)" = "TUNNELSATS_LND_ARGS=${LND_FLAGS}" ]
    [ "$(record_field lnd .announce.ipv4)" = null ]
    assert_schema "${TS_RB_RUN_DIR}/guard-lnd.json"
}

# ---------------------------------------------------------------------------------------------
# Every verify document
# ---------------------------------------------------------------------------------------------

# Runs the guard for implementation $1 against each row "doc[:rc] decision reason env detail".
doc_table() {
    local impl="$1" doc decision reason envw detail base fails="" want
    if [[ "$impl" == lnd ]]; then base=lnd; else base=lightningd; fi
    while read -r doc decision reason envw detail; do
        [[ -z "$doc" || "$doc" == \#* ]] && continue
        its_setup
        if [[ "$impl" == lnd ]]; then lnd_node; else cln_node; fi
        if [[ "$doc" == *:* ]]; then
            stub_tool -r "${doc#*:}" "${doc%%:*}"
        else
            stub_tool "$doc"
        fi
        run call its_cmd_guard "$impl" mainnet
        case "$envw" in
            empty) want="TUNNELSATS_${impl^^}_ARGS=" ;;
            lnd) want="TUNNELSATS_LND_ARGS=${LND_FLAGS}" ;;
            announce) want="TUNNELSATS_CLN_ARGS=${CLN_FLAGS_ANNOUNCE}" ;;
            plain) want="TUNNELSATS_CLN_ARGS=${CLN_FLAGS_PLAIN}" ;;
        esac
        want="${want/TUNNELSATS_CL_ARGS/TUNNELSATS_CLN_ARGS}"
        [[ "$detail" == "-" ]] && detail=""
        if [[ "$status" -ne 0 ]] || [[ "$output" != *"decision=${decision} reason=${reason}"* ]] || \
            [[ "$(env_of "$base")" != "$want" ]] || [[ "$(record_field "$base" .detail)" != "$detail" ]] || \
            ! assert_schema "${TS_RB_RUN_DIR}/guard-${base}.json" >/dev/null; then
            fails+="${doc}: status=${status} env=$(env_of "$base") out=${output}"$'\n'
        fi
    done
    if [[ -n "$fails" ]]; then
        printf '%s' "$fails" >&2
        return 1
    fi
}

@test "T6-T14, H1: every verify document for LND" {
    doc_table lnd <<'EOF'
protected.json                      hybrid   ok                  lnd    -
activating_tunnel_up.json           hybrid   ok                  lnd    -
activating_tunnel_down.json         hybrid   ok                  lnd    -
activating_dns_unresolved.json      hybrid   ok                  lnd    -
activating_dns_timeout.json         hybrid   ok                  lnd    -
activating_endpoint_mismatch.json   hybrid   ok                  lnd    -
activating_no_handshake.json        hybrid   ok                  lnd    -
activating_endpoint_none.json       hybrid   ok                  lnd    -
activating_route_missing.json       hybrid   ok                  lnd    -
activating_emergency_leftover.json  hybrid   ok                  lnd    -
activating_emergency_block.json     tor-only emergency_block     empty  -
damaged_record.json                 tor-only unit_mismatch       empty  -
dropin_missing.json                 tor-only verify_unsafe       empty  -
state_removing.json                 tor-only verify_unsafe       empty  -
not_installed.json                  tor-only not_installed       empty  -
unmanaged.json                      tor-only unmanaged           empty  -
unit_tlnd.json                      tor-only unit_mismatch       empty  -
impl_mismatch.json                  tor-only unit_mismatch       empty  -
cln_activating_tunnel_up.json       tor-only unit_mismatch       empty  -
vpn_port_null.json                  tor-only announce_invalid    empty  -
vpn_port_string.json                tor-only announce_invalid    empty  -
vpn_port_range.json                 tor-only announce_invalid    empty  -
host_foreign.json                   tor-only announce_invalid    empty  -
host_injection.json                 tor-only announce_invalid    empty  -
host_uppercase.json                 tor-only announce_invalid    empty  -
contract2.json                      tor-only verify_invalid      empty  -
malformed.json:5                    tor-only verify_invalid      empty  -
two_documents.json:5                tor-only verify_invalid      empty  -
probes_run.json                     tor-only verify_invalid      empty  -
activating_tunnel_up.json:0         tor-only verify_invalid      empty  -
not_installed.json:5                tor-only verify_invalid      empty  -
verdict_mismatch.json               tor-only verify_inconsistent empty  -
unsafe_fail_rc5.json                tor-only verify_inconsistent empty  -
missing_check.json                  tor-only verify_inconsistent empty  -
failed_rc6.json                     tor-only verify_failed       empty  -
EOF
}

@test "T6-T14, H2, H3: every verify document for CLN" {
    doc_table cl <<'EOF'
cln_protected.json                    hybrid   ok                   announce -
cln_activating_tunnel_up.json         hybrid   ok                   announce -
cln_activating_dns_unresolved.json    hybrid   announce_unconfirmed plain    dns_unresolved
cln_activating_dns_timeout.json       hybrid   announce_unconfirmed plain    dns_unresolved
cln_activating_endpoint_mismatch.json hybrid   announce_unconfirmed plain    endpoint_mismatch
cln_activating_tunnel_down.json       hybrid   announce_unconfirmed plain    tunnel_down
cln_activating_no_handshake.json      hybrid   announce_unconfirmed plain    no_handshake
cln_activating_endpoint_none.json     hybrid   announce_unconfirmed plain    no_handshake
cln_ipv4_private.json                 hybrid   announce_unconfirmed plain    ipv4_invalid
cln_activating_emergency_block.json   tor-only emergency_block      empty    -
activating_tunnel_up.json             tor-only unit_mismatch        empty    -
damaged_record.json                   tor-only unit_mismatch        empty    -
dropin_missing.json                   tor-only verify_unsafe        empty    -
not_installed.json                    tor-only not_installed        empty    -
unmanaged.json                        tor-only unmanaged            empty    -
malformed.json:5                      tor-only verify_invalid       empty    -
failed_rc6.json                       tor-only verify_failed        empty    -
EOF
}

# ---------------------------------------------------------------------------------------------
# Decision table axes: chain x tunnelsats x Tor x selected implementation x at rest x eligibility
# ---------------------------------------------------------------------------------------------

# Builds the fixture of one row and runs the guard. $1 impl, $2 chain (main|test|sig), $3 tunnelsats,
# $4 runBehindTor, $5 selected (yes|no), $6 at rest (clean|drift|ro|toroff|incl|inclhyb), $7 eligibility.
matrix_run() {
    local impl="$1" chain="$2" ts="$3" tor="$4" sel="$5" rest="$6" elig="$7" tsimpl lndport=""
    local cfg chainname
    its_setup
    tsimpl="$impl"
    if [[ "$sel" == no ]]; then
        if [[ "$impl" == lnd ]]; then tsimpl=cl; else tsimpl=lnd; fi
    fi
    [[ "$elig" == port ]] && lndport="lndPort=9736"
    conf "chain=main" "runBehindTor=${tor}" "tunnelsats=${ts}" "tunnelsatsImpl='${tsimpl}'" $lndport
    if [[ "$impl" == lnd ]]; then
        cfg="$FX/app-data/lnd/lnd.conf"
        case "$rest" in
            clean) lnd_conf lnd.conf ;;
            drift | ro) lnd_conf lnd-legacy-v3.conf ;;
            toroff) lnd_conf lnd.conf; sed -i '/^tor.active=/d' "$cfg" ;;
        esac
        case "$elig" in
            nat) sed -i 's/^nat=false$/nat=true/' "$cfg" ;;
            iso) echo "tor.streamisolation=true" >> "$cfg" ;;
            listen) sed -i 's/^listen=0.0.0.0:9735$/listen=localhost:9735/' "$cfg" ;;
        esac
        [[ "$rest" == ro ]] && chmod 0555 "$FX/app-data/lnd"
        stub_tool activating_tunnel_up.json
    else
        cfg="$FX/app-data/.lightning/config"
        case "$rest" in
            clean) cln_conf cl-config ;;
            drift | ro) cln_conf cl-config-hybrid ;;
            incl) cln_conf cl-config; echo "include /nonexistent/tunnelsats-test.conf" >> "$cfg" ;;
            inclhyb)
                cln_conf cl-config
                echo "always-use-proxy=false" > "$FX/app-data/.lightning/extra.conf"
                echo "include extra.conf" >> "$cfg"
                ;;
        esac
        case "$elig" in
            proxy) sed -i '/^proxy=/d' "$cfg" ;;
            torbind) sed -i '/^bind-addr=127.0.0.1:9736$/d' "$cfg" ;;
        esac
        [[ "$rest" == ro ]] && chmod 0555 "$FX/app-data/.lightning"
        stub_tool cln_activating_tunnel_up.json
    fi
    case "$chain" in
        main) chainname=mainnet ;;
        test) chainname=testnet ;;
        sig) chainname=signet ;;
    esac
    run call its_cmd_guard "$impl" "$chainname"
}

matrix_table() {
    local impl chain ts tor sel rest elig xrc xenv xdec xreason base prefix fails="" want got
    while read -r impl chain ts tor sel rest elig xrc xenv xdec xreason; do
        [[ -z "$impl" || "$impl" == \#* ]] && continue
        if [[ "$rest" == ro ]] && [[ "$(id -u)" -eq 0 ]]; then
            continue
        fi
        matrix_run "$impl" "$chain" "$ts" "$tor" "$sel" "$rest" "$elig"
        prefix=""
        [[ "$chain" == test ]] && prefix=t
        [[ "$chain" == sig ]] && prefix=s
        if [[ "$impl" == lnd ]]; then base="${prefix}lnd"; else base="${prefix}lightningd"; fi
        case "$xenv" in
            none) want="<absent>" ;;
            empty) want="TUNNELSATS_${impl^^}_ARGS=" ;;
            flags) want="TUNNELSATS_LND_ARGS=${LND_FLAGS}" ;;
            announce) want="TUNNELSATS_CLN_ARGS=${CLN_FLAGS_ANNOUNCE}" ;;
        esac
        want="${want/TUNNELSATS_CL_ARGS/TUNNELSATS_CLN_ARGS}"
        got="$(env_of "$base")"
        if [[ "$status" -ne "$xrc" ]] || [[ "$got" != "$want" ]] || \
            [[ "$output" != *"decision=${xdec} reason=${xreason}"* ]]; then
            fails+="${impl} ${chain} ${ts} ${tor} ${sel} ${rest} ${elig}: status=${status} env=${got} out=${output}"$'\n'
        fi
        if [[ "$xenv" != none ]] && ! assert_schema "${TS_RB_RUN_DIR}/guard-${base}.json" >/dev/null; then
            fails+="${impl} ${chain} ${rest}: record does not match the schema"$'\n'
        fi
    done
    if [[ -n "$fails" ]]; then
        printf '%s' "$fails" >&2
        return 1
    fi
}

@test "matrix: LND rows of the decision table (N, B1-B3, T1, T2, H1 and their precedence)" {
    matrix_table <<'EOF'
# impl chain ts  tor sel rest   elig   rc env   decision reason
lnd    main  on  on  yes clean  ok     0  flags hybrid   ok
lnd    test  on  on  yes clean  ok     0  none  noop     not_mainnet
lnd    sig   on  on  yes clean  ok     0  none  noop     not_mainnet
lnd    main  off on  yes clean  ok     0  none  noop     tunnelsats_off
lnd    main  off off no  ro     nat    0  none  noop     tunnelsats_off
lnd    test  on  off no  ro     nat    0  none  noop     not_mainnet
lnd    test  on  on  yes drift  ok     0  none  noop     not_mainnet
lnd    sig   off on  yes toroff iso    0  none  noop     not_mainnet
lnd    main  on  off yes clean  ok     1  empty blocked  tor_off
lnd    main  on  off no  clean  ok     1  empty blocked  tor_off
lnd    main  on  off yes ro     nat    1  empty blocked  tor_off
lnd    main  on  on  yes drift  ok     0  flags hybrid   ok
lnd    main  on  on  yes ro     ok     1  empty blocked  at_rest_unrepairable:replace_failed
lnd    main  on  on  yes toroff ok     1  empty blocked  at_rest_unrepairable:tor_inactive
lnd    main  on  on  yes ro     nat    1  empty blocked  at_rest_unrepairable:replace_failed
lnd    main  on  on  yes toroff listen 1  empty blocked  at_rest_unrepairable:tor_inactive
lnd    main  on  on  no  clean  ok     0  empty tor-only other_impl
lnd    main  on  on  no  drift  ok     0  empty tor-only other_impl
lnd    main  on  on  no  ro     ok     1  empty blocked  at_rest_unrepairable:replace_failed
lnd    main  on  on  no  clean  nat    0  empty tor-only other_impl
lnd    main  on  on  yes clean  nat    0  empty tor-only not_eligible:nat
lnd    main  on  on  yes clean  iso    0  empty tor-only not_eligible:streamisolation
lnd    main  on  on  yes clean  listen 0  empty tor-only not_eligible:listen
lnd    main  on  on  yes clean  port   0  empty tor-only not_eligible:lndport
lnd    main  on  on  yes drift  nat    0  empty tor-only not_eligible:nat
EOF
}

@test "matrix: CLN rows of the decision table (N, B1-B3, T1, T2, H2 and their precedence)" {
    matrix_table <<'EOF'
# impl chain ts  tor sel rest    elig    rc env      decision reason
cl     main  on  on  yes clean   ok      0  announce hybrid   ok
cl     test  on  on  yes clean   ok      0  none     noop     not_mainnet
cl     sig   on  on  yes clean   ok      0  none     noop     not_mainnet
cl     main  off on  yes clean   ok      0  none     noop     tunnelsats_off
cl     test  on  on  yes drift   ok      0  none     noop     not_mainnet
cl     main  on  off yes clean   ok      1  empty    blocked  tor_off
cl     main  on  off no  incl    proxy   1  empty    blocked  tor_off
cl     main  on  on  yes drift   ok      0  announce hybrid   ok
cl     main  on  on  yes ro      ok      1  empty    blocked  at_rest_unrepairable:replace_failed
cl     main  on  on  yes incl    ok      1  empty    blocked  at_rest_unrepairable:include_unreadable
cl     main  on  on  yes inclhyb ok      1  empty    blocked  at_rest_unrepairable:include_hybrid
cl     main  on  on  no  clean   ok      0  empty    tor-only other_impl
cl     main  on  on  no  drift   ok      0  empty    tor-only other_impl
cl     main  on  on  no  incl    ok      1  empty    blocked  at_rest_unrepairable:include_unreadable
cl     main  on  on  yes clean   proxy   0  empty    tor-only not_eligible:proxy
cl     main  on  on  yes clean   torbind 0  empty    tor-only not_eligible:torbind
cl     main  on  on  yes drift   torbind 0  empty    tor-only not_eligible:torbind
cl     main  on  on  no  clean   proxy   0  empty    tor-only other_impl
EOF
}

# ---------------------------------------------------------------------------------------------
# Tool trust (T3, T4), timeout (T5), write failures (B1, N5, W)
# ---------------------------------------------------------------------------------------------

@test "T3: tool missing (fresh SD card before restore): tor-only, empty value" {
    lnd_node
    rm -f "$TS_RB_TOOL"
    run call its_cmd_guard lnd mainnet
    [ "$status" -eq 0 ]
    assert_decision tor-only tool_missing
    [ "$(env_of lnd)" = "TUNNELSATS_LND_ARGS=" ]
}

@test "T4: tool hash not in the allowlist, a symlink, or writable by group or others: tor-only" {
    lnd_node
    TS_ACCEPTED_SHA256=("0000000000000000000000000000000000000000000000000000000000000000")
    run call its_cmd_guard lnd mainnet
    assert_decision tor-only tool_untrusted
    [ "$(tool_calls)" -eq 0 ]
    lnd_node
    chmod 0775 "$TS_RB_TOOL"
    run call its_cmd_guard lnd mainnet
    assert_decision tor-only tool_untrusted
    chmod 0757 "$TS_RB_TOOL"
    run call its_cmd_guard lnd mainnet
    assert_decision tor-only tool_untrusted
    chmod 0755 "$TS_RB_TOOL"
    mv "$TS_RB_TOOL" "$FX/bin/real-tool"
    ln -s "$FX/bin/real-tool" "$TS_RB_TOOL"
    run call its_cmd_guard lnd mainnet
    assert_decision tor-only tool_untrusted
    [ "$(tool_calls)" -eq 0 ]
    [ "$(env_of lnd)" = "TUNNELSATS_LND_ARGS=" ]
}

@test "T4: an earlier accepted pin still runs (allowlist, not only the current pin)" {
    lnd_node
    TS_ACCEPTED_SHA256=("$TS_PIN_SHA256" "${TS_ACCEPTED_SHA256[0]}")
    run call its_cmd_guard lnd mainnet
    assert_decision hybrid ok
}

@test "T5: verify hangs: timeout ends it, tor-only verify_timeout within 7 s" {
    lnd_node
    stub_tool -s 5 activating_tunnel_up.json
    TS_RB_VERIFY_TIMEOUT=1
    SECONDS=0
    run call its_cmd_guard lnd mainnet
    [ "$SECONDS" -lt 7 ]
    [ "$status" -eq 0 ]
    assert_decision tor-only verify_timeout
    [ "$(env_of lnd)" = "TUNNELSATS_LND_ARGS=" ]
}

@test "B1: read-only /run/tunnelsats blocks the start (exit 1)" {
    skip_if_root
    lnd_node
    mkdir -m 0555 "$TS_RB_RUN_DIR"
    run call its_cmd_guard lnd mainnet
    [ "$status" -eq 1 ]
    assert_decision blocked env_write_failed
    [ "$(tool_calls)" -eq 0 ]
}

@test "B1: /run/tunnelsats as a symlink or writable by others blocks the start; nothing is written through it" {
    lnd_node
    mkdir "$FX/elsewhere"
    ln -s "$FX/elsewhere" "$TS_RB_RUN_DIR"
    run call its_cmd_guard lnd mainnet
    [ "$status" -eq 1 ]
    assert_decision blocked env_write_failed
    [ -z "$(ls -A "$FX/elsewhere")" ]
    rm "$TS_RB_RUN_DIR"
    mkdir -m 0777 "$TS_RB_RUN_DIR"
    chmod 0777 "$TS_RB_RUN_DIR"
    run call its_cmd_guard lnd mainnet
    [ "$status" -eq 1 ]
    assert_decision blocked env_write_failed
}

@test "N5: TunnelSats off, stale flags file, write fails: blocked, the start never reads the flags" {
    skip_if_root
    conf "runBehindTor=on" "tunnelsats=off"
    mkdir -m 0755 "$TS_RB_RUN_DIR"
    printf 'TUNNELSATS_LND_ARGS=%s\n' "$LND_FLAGS" > "${TS_RB_RUN_DIR}/hybrid-lnd.env"
    chmod 0555 "$TS_RB_RUN_DIR"
    export TUNNELSATS_LND_ARGS="$LND_FLAGS"
    run call its_cmd_guard lnd mainnet
    unset TUNNELSATS_LND_ARGS
    [ "$status" -eq 1 ]
    assert_decision blocked env_write_failed
}

@test "W: the final flags write fails: blocked, the empty value stays" {
    skip_if_root
    lnd_node
    stub_tool -c "chmod 0555 '${TS_RB_RUN_DIR}'" activating_tunnel_up.json
    run call its_cmd_guard lnd mainnet
    [ "$status" -eq 1 ]
    assert_decision blocked env_write_failed
    [ "$(env_of lnd)" = "TUNNELSATS_LND_ARGS=" ]
}

# ---------------------------------------------------------------------------------------------
# Stray values and no-op paths (3.6, N1-N4)
# ---------------------------------------------------------------------------------------------

@test "3.6: a stray value in raspiblitz.conf never reaches ExecStart, on two consecutive starts" {
    local stray="--externalhosts=203.0.113.9:9735" ts
    for ts in off on; do
        its_setup
        conf "runBehindTor=on" "tunnelsats=${ts}" "tunnelsatsImpl='lnd'" "TUNNELSATS_LND_ARGS=${stray}"
        lnd_conf lnd.conf
        stub_tool not_installed.json
        # start 1: no env file yet, so the unit environment carries the value of raspiblitz.conf
        export TUNNELSATS_LND_ARGS="$stray"
        run call its_cmd_guard lnd mainnet
        [ "$status" -eq 0 ]
        [[ "$output" == *"stray TUNNELSATS_LND_ARGS ignored"* ]]
        [ "$(env_of lnd)" = "TUNNELSATS_LND_ARGS=" ]
        # start 2: the empty env file (read after raspiblitz.conf) masks the value: inherited empty
        export TUNNELSATS_LND_ARGS=""
        run call its_cmd_guard lnd mainnet
        [ "$status" -eq 0 ]
        [[ "$output" == *"stray TUNNELSATS_LND_ARGS ignored"* ]]
        [ "$(env_of lnd)" = "TUNNELSATS_LND_ARGS=" ]
        [ "$(record_field lnd .stray)" = true ]
        unset TUNNELSATS_LND_ARGS
    done
}

@test "N4: TunnelSats off, a flags file left by a failed REMOVE: rewritten empty, noop" {
    conf "runBehindTor=on" "tunnelsats=off"
    mkdir -m 0755 "$TS_RB_RUN_DIR"
    printf 'TUNNELSATS_LND_ARGS=%s\n' "$LND_FLAGS" > "${TS_RB_RUN_DIR}/hybrid-lnd.env"
    export TUNNELSATS_LND_ARGS="$LND_FLAGS"
    run call its_cmd_guard lnd mainnet
    unset TUNNELSATS_LND_ARGS
    [ "$status" -eq 0 ]
    assert_decision noop tunnelsats_off
    [ "$(env_of lnd)" = "TUNNELSATS_LND_ARGS=" ]
    [ "$(record_field lnd .decision)" = noop ]
}

@test "N2: test chain with a stale flags file: rewritten empty, never flags" {
    conf "runBehindTor=on" "tunnelsats=on" "tunnelsatsImpl='lnd'"
    stub_tool activating_tunnel_up.json
    mkdir -m 0755 "$TS_RB_RUN_DIR"
    printf 'TUNNELSATS_LND_ARGS=%s\n' "$LND_FLAGS" > "${TS_RB_RUN_DIR}/hybrid-tlnd.env"
    run call its_cmd_guard lnd testnet
    [ "$status" -eq 0 ]
    assert_decision noop not_mainnet
    [ "$(env_of tlnd)" = "TUNNELSATS_LND_ARGS=" ]
    [ "$(tool_calls)" -eq 0 ]
}

@test "N1, N3: a no-op run on a node without TunnelSats creates and changes nothing" {
    conf "lightning=lnd" "chain=main" "runBehindTor=on"
    lnd_conf lnd.conf
    local before after
    before=$(tree_state)
    run call its_cmd_guard lnd mainnet
    [ "$status" -eq 0 ]
    assert_decision noop tunnelsats_off
    run call its_cmd_guard lnd signet
    [ "$status" -eq 0 ]
    run call its_cmd_guard cl testnet
    [ "$status" -eq 0 ]
    after=$(tree_state)
    [ "$before" = "$after" ]
    [ ! -e "$TS_RB_RUN_DIR" ]
}

@test "usage: unknown implementation, chain or option exits 2 (blocks the start)" {
    run call its_cmd_guard lightning mainnet
    [ "$status" -eq 2 ]
    run call its_cmd_guard lnd regtest
    [ "$status" -eq 2 ]
    run call its_cmd_guard lnd mainnet --bogus
    [ "$status" -eq 2 ]
    run call its_cmd_guard
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------------------------
# Isolation of the decision from the unit environment (3.2, 5.1)
# ---------------------------------------------------------------------------------------------

@test "env -i: no injection variable and no raspiblitz.conf key reaches the tool" {
    lnd_node
    export SYSTEMCTL_BIN=/tmp/x NFT_BIN=/tmp/x GETENT_BIN=/tmp/x TS_FS_ROOT=/tmp/fs \
        TS_VERIFY_ECHO_URLS="http://a http://b" tunnelsats=on runBehindTor=on lightning=lnd
    run call its_cmd_guard lnd mainnet
    unset SYSTEMCTL_BIN NFT_BIN GETENT_BIN TS_FS_ROOT TS_VERIFY_ECHO_URLS tunnelsats runBehindTor lightning
    assert_decision hybrid ok
    refute grep -Eq '^(SYSTEMCTL_BIN|NFT_BIN|GETENT_BIN|TS_FS_ROOT|TS_VERIFY_ECHO_URLS|tunnelsats|runBehindTor|lightning|TS_RB_[A-Z_]*)=' "$FX/tool.env"
    grep -qx "PATH=${ITS_SAFE_PATH}" "$FX/tool.env"
    grep -qx "LC_ALL=C.UTF-8" "$FX/tool.env"
}

@test "executed as a process, the script ignores TS_RB_* from its environment" {
    if [[ -e /mnt/hdd/app-data/raspiblitz.conf ]] || [[ -e /run/tunnelsats ]]; then
        skip "the host has a RaspiBlitz or TunnelSats state"
    fi
    lnd_node
    run env TS_RB_TOOL="$TS_RB_TOOL" TS_RB_CONF="$TS_RB_CONF" TS_RB_RUN_DIR="$TS_RB_RUN_DIR" \
        TS_RB_ROOT_UID="$(id -u)" TS_RB_APPDATA="$TS_RB_APPDATA" bash "$ITS" guard lnd mainnet
    [ "$status" -eq 0 ]
    assert_decision noop tunnelsats_off
    [ "$(tool_calls)" -eq 0 ]
    [ ! -e "$TS_RB_RUN_DIR" ]
}

@test "--dry-run --json: same decision, writes no env file, record, repair or backup" {
    conf "runBehindTor=on" "tunnelsats=on" "tunnelsatsImpl='lnd'"
    lnd_conf lnd-legacy-v3.conf
    stub_tool activating_tunnel_up.json
    mkdir -m 0755 "$TS_RB_RUN_DIR"
    printf 'TUNNELSATS_LND_ARGS=--stale\n' > "${TS_RB_RUN_DIR}/hybrid-lnd.env"
    local before after
    before=$(tree_state)
    run call its_cmd_guard lnd mainnet --dry-run --json
    [ "$status" -eq 0 ]
    after=$(tree_state)
    [ "$before" = "$after" ]
    [ "$(env_of lnd)" = "TUNNELSATS_LND_ARGS=--stale" ]
    cmp -s "$FX/app-data/lnd/lnd.conf" "${FIXTURES}/conf/lnd-legacy-v3.conf"
    local doc
    doc=$(printf '%s\n' "$output" | grep '^{')
    [ "$(jq -r .decision <<< "$doc")" = hybrid ]
    [ "$(jq -r .at_rest.status <<< "$doc")" = drift ]
    [[ "$output" == *"dry_run=1"* ]]
}

@test "INVOCATION_ID of the start is kept in the record" {
    lnd_node
    export INVOCATION_ID=0123456789abcdef0123456789abcdef
    run call its_cmd_guard lnd mainnet
    unset INVOCATION_ID
    [ "$(record_field lnd .invocation_id)" = 0123456789abcdef0123456789abcdef ]
}

@test "logs name repaired keys, never config lines or values" {
    conf "runBehindTor=on" "tunnelsats=on" "tunnelsatsImpl='lnd'"
    lnd_conf lnd-legacy-v3.conf
    stub_tool activating_tunnel_up.json
    run call its_cmd_guard lnd mainnet
    assert_decision hybrid ok
    [[ "$output" == *"at-rest repair: externalhosts removed"* ]]
    [[ "$output" == *"repaired=externalhosts,tor.skip-proxy-for-clearnet-targets"* ]]
    [[ "$output" != *"externalhosts=de2"* ]]
    [[ "$output" != *"rpcpass"* ]]
    [[ "$output" != *"fixture-rpc-password"* ]]
    [ "$(record_field lnd '.at_rest.status')" = repaired ]
    [ "$(record_field lnd '.at_rest.repaired_keys | join(",")')" = "externalhosts,tor.skip-proxy-for-clearnet-targets" ]
}

# ---------------------------------------------------------------------------------------------
# CLN: bounded wait for the first handshake (maintainer answer 11.1 item 2)
# ---------------------------------------------------------------------------------------------

@test "CLN wait: the handshake arrives within the wait: announce" {
    cln_node
    stub_tool cln_activating_no_handshake.json cln_activating_tunnel_up.json
    run call its_cmd_guard cl mainnet
    [ "$status" -eq 0 ]
    assert_decision hybrid ok
    [ "$(env_of lightningd)" = "TUNNELSATS_CLN_ARGS=${CLN_FLAGS_ANNOUNCE}" ]
    [ "$(tool_calls)" -eq 2 ]
    [ "$(record_field lightningd .verify.attempts)" = 2 ]
}

@test "CLN wait: no handshake within the limit: H3 after the limit, no announce" {
    cln_node
    stub_tool cln_activating_no_handshake.json
    SECONDS=0
    run call its_cmd_guard cl mainnet
    # the wait never starts a poll with less than a second left: between WAIT - 1 and WAIT seconds
    [ "$SECONDS" -ge 2 ]
    [ "$SECONDS" -lt 8 ]
    [ "$status" -eq 0 ]
    assert_decision hybrid announce_unconfirmed
    [ "$(record_field lightningd .detail)" = no_handshake ]
    [ "$(env_of lightningd)" = "TUNNELSATS_CLN_ARGS=${CLN_FLAGS_PLAIN}" ]
    [ "$(tool_calls)" -ge 2 ]
}

@test "CLN wait: no live endpoint yet counts as waitable" {
    cln_node
    stub_tool cln_activating_endpoint_none.json cln_activating_tunnel_up.json
    run call its_cmd_guard cl mainnet
    assert_decision hybrid ok
    [ "$(tool_calls)" -eq 2 ]
}

@test "CLN wait: skipped on a mismatch, an unresolved name, an unanswered lookup, a down tunnel or an unusable address" {
    local doc
    for doc in cln_activating_endpoint_mismatch.json cln_activating_dns_unresolved.json cln_activating_dns_timeout.json \
        cln_activating_tunnel_down.json cln_ipv4_private.json; do
        its_setup
        cln_node "$doc"
        run call its_cmd_guard cl mainnet
        assert_decision hybrid announce_unconfirmed
        [ "$(tool_calls)" -eq 1 ]
    done
}

@test "CLN wait: a poll that turns unsafe decides (tor-only), a poll that times out keeps the last result" {
    cln_node
    stub_tool cln_activating_no_handshake.json cln_activating_emergency_block.json
    run call its_cmd_guard cl mainnet
    [ "$status" -eq 0 ]
    assert_decision tor-only emergency_block
    [ "$(env_of lightningd)" = "TUNNELSATS_CLN_ARGS=" ]
    its_setup
    cln_node
    stub_tool -c '[ "$n" -ge 2 ] && sleep 20' cln_activating_no_handshake.json
    SECONDS=0
    run call its_cmd_guard cl mainnet
    [ "$SECONDS" -lt 12 ]
    assert_decision hybrid announce_unconfirmed
    [ "$(env_of lightningd)" = "TUNNELSATS_CLN_ARGS=${CLN_FLAGS_PLAIN}" ]
}

@test "CLN wait: never for LND, never in --dry-run" {
    lnd_node activating_no_handshake.json
    run call its_cmd_guard lnd mainnet
    assert_decision hybrid ok
    [ "$(tool_calls)" -eq 1 ]
    its_setup
    cln_node cln_activating_no_handshake.json
    run call its_cmd_guard cl mainnet --dry-run
    assert_decision hybrid announce_unconfirmed
    [ "$(tool_calls)" -eq 1 ]
}

@test "development override: the guard accepts its hash only from a root-owned run file" {
    lnd_node
    local h="${TS_ACCEPTED_SHA256[0]}"
    TS_ACCEPTED_SHA256=("$TS_PIN_SHA256")
    run call its_cmd_guard lnd mainnet
    assert_decision tor-only tool_untrusted
    printf '%s\n' "$h" > "${TS_RB_RUN_DIR}/dev-override.sha256"
    chmod 0644 "${TS_RB_RUN_DIR}/dev-override.sha256"
    run call its_cmd_guard lnd mainnet
    assert_decision hybrid ok
    chmod 0666 "${TS_RB_RUN_DIR}/dev-override.sha256"
    run call its_cmd_guard lnd mainnet
    assert_decision tor-only tool_untrusted
}

# The sh code of the template guard line (assets/lnd.service), with the run directory and the script
# path moved into the fixture tree. $1 = path the code checks for the script.
template_guard_code() {
    local line code
    line=$(grep -m 1 -F -e 'ExecStartPre=+/bin/sh -c ' -- "${BATS_TEST_DIRNAME}/../../home.admin/assets/lnd.service")
    code="${line#*-c \'}"
    code="${code%\'}"
    # systemd passes the quoted code to sh unchanged only without $, % and backslash
    [[ "$code" != *[\$%\\]* ]] || return 1
    code="${code//\/home\/admin\/config.scripts\/internet.tunnelsats.sh/$1}"
    printf '%s' "${code//\/run\/tunnelsats/${FX}/runts}"
}

@test "template guard line: the script runs if present; without it the empty value is written and the start goes on" {
    local code
    printf '#!/bin/bash\nprintf "%%s\\n" "$*" > %q\nexit 7\n' "$FX/guard.args" > "$FX/its-stub"
    chmod 0755 "$FX/its-stub"
    code=$(template_guard_code "$FX/its-stub")
    run sh -c "$code"
    [ "$status" -eq 7 ]
    [ "$(cat "$FX/guard.args")" = "guard lnd mainnet" ]
    [ ! -e "$FX/runts" ]
    code=$(template_guard_code "$FX/its-missing")
    run --separate-stderr sh -c "$code"
    [ "$status" -eq 0 ]
    [ "$stderr" = "tunnelsats-guard: internet.tunnelsats.sh is missing, Lightning starts Tor-only" ]
    [ "$(cat "$FX/runts/hybrid-lnd.env")" = "TUNNELSATS_LND_ARGS=" ]
    printf 'TUNNELSATS_LND_ARGS=--stale-flag\n' > "$FX/runts/hybrid-lnd.env"
    run sh -c "$code"
    [ "$status" -eq 0 ]
    [ "$(cat "$FX/runts/hybrid-lnd.env")" = "TUNNELSATS_LND_ARGS=" ]
    skip_if_root
    chmod 0444 "$FX/runts/hybrid-lnd.env"
    chmod 0555 "$FX/runts"
    run sh -c "$code"
    [ "$status" -ne 0 ]
}
