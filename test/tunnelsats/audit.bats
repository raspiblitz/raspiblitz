#!/usr/bin/env bats
# At-rest audit and repair toward Tor-only (design 3.7, tests 7.2). Runs the real audit functions
# and the audit verb of internet.tunnelsats.sh on fixture configs.

load helpers

setup() {
    its_setup
    conf "runBehindTor=on" "tunnelsats=on" "tunnelsatsImpl='lnd'"
    LND="$FX/app-data/lnd/lnd.conf"
    CLN="$FX/app-data/.lightning/config"
}

teardown() {
    its_teardown
}

@test "LND legacy v3 lines: externalhosts and skip-proxy go, streamisolation=false stays, nothing else changes" {
    lnd_conf lnd-legacy-v3.conf
    here its_audit lnd "$LND" repair lnd
    [ "$A_STATUS" = repaired ]
    [ "${A_REPAIRED[*]}" = "externalhosts tor.skip-proxy-for-clearnet-targets" ]
    grep -v -e '^externalhosts=' -e '^tor.skip-proxy-for-clearnet-targets=' "${FIXTURES}/conf/lnd-legacy-v3.conf" > "$FX/expected"
    cmp "$FX/expected" "$LND"
    grep -qx 'tor.streamisolation=false' "$LND"
    cmp "${FIXTURES}/conf/lnd-legacy-v3.conf" "$FX/app-data/tunnelsats/backup/lnd.lnd.conf.pre-repair"
    [ "$(stat -c %a "$FX/app-data/tunnelsats/backup/lnd.lnd.conf.pre-repair")" = 600 ]
    [ "$(stat -c %a "$FX/app-data/tunnelsats/backup")" = 700 ]
    [ "$(stat -c %a "$FX/app-data/tunnelsats")" = 700 ]
}

@test "LND: keys compared case-insensitively, with or without the tor. prefix; false is not a clearnet setting" {
    lnd_conf lnd.conf
    printf '%s\n' '[Tor]' 'Skip-Proxy-For-Clearnet-Targets' '  externalIP=203.0.113.7:9735' \
        'tor.skip-proxy-for-clearnet-targets=false' '# externalhosts=commented.example' '; externalhosts=x' >> "$LND"
    here its_audit lnd "$LND" check lnd
    [ "$A_STATUS" = drift ]
    [ "${A_KEYS[*]}" = "skip-proxy-for-clearnet-targets externalip" ]
    here its_audit lnd "$LND" repair lnd
    [ "$A_STATUS" = repaired ]
    refute grep -qi 'externalip' "$LND"
    grep -qx 'tor.skip-proxy-for-clearnet-targets=false' "$LND"
    grep -qx '# externalhosts=commented.example' "$LND"
}

@test "LND: tor.active missing or false is unrepairable, the file stays unchanged" {
    lnd_conf lnd-legacy-v3.conf
    sed -i '/^tor.active=/d' "$LND"
    cp "$LND" "$FX/before"
    here its_audit lnd "$LND" repair lnd
    [ "$A_STATUS" = unrepairable ]
    [ "$A_WHY" = tor_inactive ]
    cmp "$FX/before" "$LND"
    echo "tor.active=false" >> "$LND"
    here its_audit lnd "$LND" check lnd
    [ "$A_WHY" = tor_inactive ]
}

@test "LND eligibility: nat, streamisolation, listen without 9735 on all interfaces, lndPort" {
    lnd_conf lnd.conf
    here its_audit lnd "$LND" check lnd
    [ "$A_ELIGIBLE" -eq 1 ]
    sed -i 's/^nat=false$/nat=true/' "$LND"
    here its_audit lnd "$LND" check lnd
    [ "$A_ELIGIBLE" -eq 0 ] && [ "$A_NE_REASON" = nat ]
    lnd_conf lnd.conf
    echo "tor.streamisolation=1" >> "$LND"
    here its_audit lnd "$LND" check lnd
    [ "$A_NE_REASON" = streamisolation ]
    lnd_conf lnd.conf
    sed -i 's/^listen=0.0.0.0:9735$/listen=127.0.0.1:9735/' "$LND"
    here its_audit lnd "$LND" check lnd
    [ "$A_NE_REASON" = listen ]
    lnd_conf lnd.conf
    sed -i '/^listen=/d' "$LND"
    here its_audit lnd "$LND" check lnd
    [ "$A_ELIGIBLE" -eq 1 ]
    conf "runBehindTor=on" "lndPort='9736'"
    here its_audit lnd "$LND" check lnd
    [ "$A_NE_REASON" = lndport ]
}

@test "CLN: always-use-proxy=false becomes true, clearnet bind and announce go, Tor bind and onion stay" {
    cln_conf cl-config-hybrid
    here its_audit cl "$CLN" repair lightningd
    [ "$A_STATUS" = repaired ]
    [ "${A_REPAIRED[*]}" = "always-use-proxy bind-addr announce-addr" ]
    grep -qx 'always-use-proxy=true' "$CLN"
    refute grep -q '^always-use-proxy=false' "$CLN"
    refute grep -q '^bind-addr=0.0.0.0:9735' "$CLN"
    refute grep -q '^announce-addr=1.2.3.4' "$CLN"
    grep -qx 'bind-addr=127.0.0.1:9736' "$CLN"
    grep -qx 'addr=statictor:127.0.0.1:9051/torport=9736' "$CLN"
    grep -q '^announce-addr=.*\.onion:9735$' "$CLN"
    cmp "${FIXTURES}/conf/cl-config-hybrid" "$FX/app-data/tunnelsats/backup/lightningd.config.pre-repair"
}

@test "CLN: a missing always-use-proxy is appended (also after a last line without newline)" {
    cln_conf cl-config
    sed -i '/^always-use-proxy=/d' "$CLN"
    printf 'log-level=debug' >> "$CLN"
    here its_audit cl "$CLN" repair lightningd
    [ "$A_STATUS" = repaired ]
    [ "$(tail -n 2 "$CLN")" = $'log-level=debug\nalways-use-proxy=true' ]
    [ -z "$(tail -c 1 "$CLN")" ]
}

@test "CLN: clearnet addr goes, loopback, autotor and socket addr stay" {
    cln_conf cl-config
    printf '%s\n' 'addr=0.0.0.0:9735' 'addr=203.0.113.5:9735' 'addr=127.0.0.1:9737' 'addr=autotor:127.0.0.1:9051' \
        'addr=/run/lightningd/sock' 'addr=[::1]:9738' >> "$CLN"
    here its_audit cl "$CLN" repair lightningd
    [ "$A_STATUS" = repaired ]
    [ "${A_REPAIRED[*]}" = "addr addr" ]
    refute grep -q '^addr=0.0.0.0' "$CLN"
    refute grep -q '^addr=203.0.113.5' "$CLN"
    grep -qx 'addr=127.0.0.1:9737' "$CLN"
    grep -qx 'addr=autotor:127.0.0.1:9051' "$CLN"
    grep -qx 'addr=/run/lightningd/sock' "$CLN"
    grep -qxF 'addr=[::1]:9738' "$CLN"
}

@test "CLN eligibility: proxy and the Tor bind are required" {
    cln_conf cl-config
    here its_audit cl "$CLN" check lightningd
    [ "$A_STATUS" = clean ] && [ "$A_ELIGIBLE" -eq 1 ]
    sed -i '/^proxy=/d' "$CLN"
    here its_audit cl "$CLN" check lightningd
    [ "$A_NE_REASON" = proxy ]
    cln_conf cl-config
    sed -i '/^bind-addr=127.0.0.1:9736$/d' "$CLN"
    here its_audit cl "$CLN" check lightningd
    [ "$A_NE_REASON" = torbind ]
}

@test "CLN includes: unreadable or holding a clearnet setting is unrepairable; a clean include passes" {
    cln_conf cl-config
    echo "include extra.conf" >> "$CLN"
    here its_audit cl "$CLN" check lightningd
    [ "$A_STATUS" = unrepairable ] && [ "$A_WHY" = include_unreadable ]
    echo "log-prefix=x" > "$FX/app-data/.lightning/extra.conf"
    here its_audit cl "$CLN" check lightningd
    [ "$A_STATUS" = clean ]
    echo "include nested.conf" >> "$FX/app-data/.lightning/extra.conf"
    echo "announce-addr=203.0.113.5:9735" > "$FX/app-data/.lightning/nested.conf"
    cp "$CLN" "$FX/before"
    here its_audit cl "$CLN" repair lightningd
    [ "$A_STATUS" = unrepairable ] && [ "$A_WHY" = include_hybrid ]
    cmp "$FX/before" "$CLN"
}

@test "repair keeps owner, group and mode; the symlink stays and its target is replaced" {
    cln_conf cl-config-hybrid
    chmod 0640 "$CLN"
    local st_before
    st_before=$(stat -c '%u %g %a' "$CLN")
    here its_audit cl "$FX/bitcoin/.lightning/config" repair lightningd
    [ "$A_STATUS" = repaired ]
    [ "$A_CONF" = "$CLN" ]
    [ "$(stat -c '%u %g %a' "$CLN")" = "$st_before" ]
    [ -L "$FX/bitcoin/.lightning" ]
    [ "$(readlink "$FX/bitcoin/.lightning")" = "$FX/app-data/.lightning" ]
    ln -s "$CLN" "$FX/config-link"
    printf 'bind-addr=0.0.0.0:9735\n' >> "$CLN"
    here its_audit cl "$FX/config-link" repair lightningd
    [ "$A_STATUS" = repaired ]
    [ -L "$FX/config-link" ]
    [ -f "$CLN" ] && [ ! -L "$CLN" ]
    refute grep -q '^bind-addr=0.0.0.0:9735' "$CLN"
}

@test "one backup slot: it holds the state right before the latest repair" {
    lnd_conf lnd-legacy-v3.conf
    here its_audit lnd "$LND" repair lnd
    echo "externalip=203.0.113.7:9735" >> "$LND"
    cp "$LND" "$FX/second"
    here its_audit lnd "$LND" repair lnd
    [ "$A_STATUS" = repaired ]
    [ "$(ls "$FX/app-data/tunnelsats/backup" | wc -l)" -eq 1 ]
    cmp "$FX/second" "$FX/app-data/tunnelsats/backup/lnd.lnd.conf.pre-repair"
}

@test "CRLF lines: markers of unchanged lines are kept byte for byte, a replaced line keeps its CR" {
    printf 'proxy=127.0.0.1:9050\r\nbind-addr=127.0.0.1:9736\r\nalways-use-proxy=false\r\nalias=x\r\n' > "$CLN"
    here its_audit cl "$CLN" repair lightningd
    [ "$A_STATUS" = repaired ]
    printf 'proxy=127.0.0.1:9050\r\nbind-addr=127.0.0.1:9736\r\nalways-use-proxy=true\r\nalias=x\r\n' > "$FX/expected"
    cmp "$FX/expected" "$CLN"
}

@test "no backup, no edit; a failed replace leaves the file and no temp file" {
    if [[ "$(id -u)" -eq 0 ]]; then skip "needs file permissions that root ignores"; fi
    lnd_conf lnd-legacy-v3.conf
    mkdir -p "$FX/app-data/tunnelsats"
    chmod 0500 "$FX/app-data/tunnelsats"
    here its_audit lnd "$LND" repair lnd
    [ "$A_STATUS" = unrepairable ] && [ "$A_WHY" = backup_failed ]
    cmp "${FIXTURES}/conf/lnd-legacy-v3.conf" "$LND"
    chmod 0700 "$FX/app-data/tunnelsats"
    chmod 0555 "$FX/app-data/lnd"
    here its_audit lnd "$LND" repair lnd
    [ "$A_STATUS" = unrepairable ] && [ "$A_WHY" = replace_failed ]
    cmp "${FIXTURES}/conf/lnd-legacy-v3.conf" "$LND"
    [ "$(find "$FX/app-data/lnd" -mindepth 1 -printf '%f\n')" = "lnd.conf" ]
    [ -z "$(find "$FX/app-data/tunnelsats/backup" -mindepth 1 ! -name '*.pre-repair')" ]
}

@test "missing or unreadable config is unrepairable" {
    here its_audit lnd "$LND" check lnd
    [ "$A_STATUS" = unrepairable ] && [ "$A_WHY" = config_missing ]
    if [[ "$(id -u)" -ne 0 ]]; then
        lnd_conf lnd.conf
        chmod 0000 "$LND"
        here its_audit lnd "$LND" check lnd
        [ "$A_WHY" = config_unreadable ]
    fi
}

@test "audit verb: read-only exit codes 0 clean, 4 drift (file unchanged), 1 unrepairable; JSON fields" {
    lnd_conf lnd.conf
    run call its_cmd_audit lnd --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.command, .status, .eligible, .exit_code' <<< "$output" | tr '\n' ' ')" = "its.audit clean true 0 " ]
    lnd_conf lnd-legacy-v3.conf
    run call its_cmd_audit lnd --json
    [ "$status" -eq 4 ]
    [ "$(jq -r '.status, (.keys | join(","))' <<< "$output" | tr '\n' ' ')" = "drift externalhosts,tor.skip-proxy-for-clearnet-targets " ]
    cmp "${FIXTURES}/conf/lnd-legacy-v3.conf" "$LND"
    sed -i '/^tor.active=/d' "$LND"
    run call its_cmd_audit lnd --json
    [ "$status" -eq 1 ]
    [ "$(jq -r '.status, .reason, .errors[0].code' <<< "$output" | tr '\n' ' ')" = "unrepairable tor_inactive E_AT_REST_UNREPAIRABLE " ]
}

@test "audit --repair refuses while the unit runs, repairs while it is stopped" {
    lnd_conf lnd-legacy-v3.conf
    echo active > "$FX/unit_state"
    run call its_cmd_audit lnd --repair --json
    [ "$status" -eq 1 ]
    [ "$(jq -r '.errors[0].code' <<< "$output")" = E_UNIT_ACTIVE ]
    cmp "${FIXTURES}/conf/lnd-legacy-v3.conf" "$LND"
    echo inactive > "$FX/unit_state"
    run call its_cmd_audit lnd --repair --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.status, (.keys | join(",")), .backup' <<< "$output" | tr '\n' ' ')" = \
        "repaired externalhosts,tor.skip-proxy-for-clearnet-targets $FX/app-data/tunnelsats/backup/lnd.lnd.conf.pre-repair " ]
    run call its_cmd_audit cl --json
    [ "$status" -eq 1 ]
    [ "$(jq -r '.reason' <<< "$output")" = config_missing ]
}

@test "audit verb: lines names every clearnet line still at rest as file:line:setting, includes too" {
    local lnd cln_inc
    lnd_conf lnd-legacy-v3.conf
    lnd=$(readlink -f "$LND")
    run call its_cmd_audit lnd --json
    [ "$status" -eq 4 ]
    [ "$(jq -r '.lines | join("|")' <<< "$output")" = \
        "${lnd}:8:externalhosts=de2.tunnelsats.com:24556|${lnd}:27:tor.skip-proxy-for-clearnet-targets=true" ]
    echo inactive > "$FX/unit_state"
    run call its_cmd_audit lnd --repair --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '.lines' <<< "$output")" = "[]" ]
    cln_conf cl-config
    echo "include extra.conf" >> "$CLN"
    printf '%s\n' 'log-prefix=x' 'announce-addr=203.0.113.5:9735' '  bind-addr=0.0.0.0:9735' > "$FX/app-data/.lightning/extra.conf"
    cln_inc=$(readlink -f "$FX/app-data/.lightning/extra.conf")
    run call its_cmd_audit cl --repair --json
    [ "$status" -eq 1 ]
    [ "$(jq -r '.reason, (.lines | join("|"))' <<< "$output" | tr '\n' ' ')" = \
        "include_hybrid ${cln_inc}:2:announce-addr=203.0.113.5:9735|${cln_inc}:3:bind-addr=0.0.0.0:9735 " ]
}
