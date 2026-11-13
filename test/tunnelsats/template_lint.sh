#!/bin/bash
#
# Template lint for the TunnelSats hooks (tests 7.5): the literal unit template lines (design
# 2.1-2.3) and the Tor-off refusal lines (2.4, 2.5) are present, each exactly once as a whole line
# and in the given order, so an unrelated edit cannot drop or reorder them silently. The order is
# part of the design: the hybrid env file comes after raspiblitz.conf (a later EnvironmentFile=
# wins) and the guard runs after the prestart check that rewrites the config.
#
# Usage: test/tunnelsats/template_lint.sh (from any directory). Exit 0: all present, 1: not.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FAILED=0
CHECKED=0

# check_seq <file relative to the repo root>: reads the expected lines from stdin; each one must
# occur exactly once as a whole line, and each after the previous one.
check_seq() {
    local rel="$1" file="$ROOT/$1" prev=0 line count n
    local -a lines
    mapfile -t lines
    if [[ ! -f "$file" ]]; then
        echo "FAIL ${rel}: file missing"
        FAILED=1
        return
    fi
    for line in "${lines[@]}"; do
        CHECKED=$((CHECKED + 1))
        count=$(grep -c -x -F -e "$line" -- "$file")
        if [[ "$count" -ne 1 ]]; then
            echo "FAIL ${rel}: expected once, found ${count}: ${line}"
            FAILED=1
            continue
        fi
        n=$(grep -n -x -F -e "$line" -- "$file")
        n="${n%%:*}"
        if [[ "$n" -le "$prev" ]]; then
            echo "FAIL ${rel}: out of order (line ${n}): ${line}"
            FAILED=1
        fi
        prev="$n"
    done
    echo "checked ${rel}: ${#lines[@]} lines"
}

# 2.1: LND unit text written by lnd.install.sh (escaped as in the echo block)
check_seq home.admin/config.scripts/lnd.install.sh <<'EOF'
EnvironmentFile=/mnt/hdd/app-data/raspiblitz.conf
# TunnelSats start guard (no-op unless TunnelSats is on): clearnet flags for this start only
# (without internet.tunnelsats.sh, for example older code after a PATCH, Lightning starts Tor-only)
Environment=TUNNELSATS_LND_ARGS=
EnvironmentFile=-/run/tunnelsats/hybrid-${netprefix}lnd.env
ExecStartPre=-/home/admin/config.scripts/lnd.check.sh prestart ${CHAIN}
ExecStartPre=+/bin/sh -c 'if [ -x /home/admin/config.scripts/internet.tunnelsats.sh ]; then exec /home/admin/config.scripts/internet.tunnelsats.sh guard lnd ${CHAIN}; fi; echo tunnelsats-guard: internet.tunnelsats.sh is missing, Lightning starts Tor-only >&2; mkdir -p /run/tunnelsats && echo TUNNELSATS_LND_ARGS= > /run/tunnelsats/hybrid-${netprefix}lnd.env'
ExecStart=/usr/local/bin/lnd --configfile=/mnt/hdd/app-data/lnd/${netprefix}lnd.conf \$TUNNELSATS_LND_ARGS
EOF

# 2.2: static LND unit used on SD-card updates
check_seq home.admin/assets/lnd.service <<'EOF'
# TunnelSats start guard (no-op unless TunnelSats is on): clearnet flags for this start only
# (without internet.tunnelsats.sh, for example older code after a PATCH, Lightning starts Tor-only)
Environment=TUNNELSATS_LND_ARGS=
EnvironmentFile=-/run/tunnelsats/hybrid-lnd.env
ExecStartPre=-/home/admin/config.scripts/lnd.check.sh prestart mainnet
ExecStartPre=+/bin/sh -c 'if [ -x /home/admin/config.scripts/internet.tunnelsats.sh ]; then exec /home/admin/config.scripts/internet.tunnelsats.sh guard lnd mainnet; fi; echo tunnelsats-guard: internet.tunnelsats.sh is missing, Lightning starts Tor-only >&2; mkdir -p /run/tunnelsats && echo TUNNELSATS_LND_ARGS= > /run/tunnelsats/hybrid-lnd.env'
ExecStart=/usr/local/bin/lnd --configfile=/mnt/hdd/app-data/lnd/lnd.conf $TUNNELSATS_LND_ARGS
EOF

# 2.3: CLN unit text written by cl.install-service.sh (escaped as in the echo block)
check_seq home.admin/config.scripts/cl.install-service.sh <<'EOF'
# TunnelSats start guard (no-op unless TunnelSats is on): clearnet flags for this start only
# (without internet.tunnelsats.sh, for example older code after a PATCH, Lightning starts Tor-only)
Environment=TUNNELSATS_CLN_ARGS=
EnvironmentFile=-/run/tunnelsats/hybrid-${netprefix}lightningd.env
ExecStartPre=-/home/admin/config.scripts/cl.check.sh prestart $CHAIN
ExecStartPre=+/bin/sh -c 'if [ -x /home/admin/config.scripts/internet.tunnelsats.sh ]; then exec /home/admin/config.scripts/internet.tunnelsats.sh guard cl $CHAIN; fi; echo tunnelsats-guard: internet.tunnelsats.sh is missing, Lightning starts Tor-only >&2; mkdir -p /run/tunnelsats && echo TUNNELSATS_CLN_ARGS= > /run/tunnelsats/hybrid-${netprefix}lightningd.env'
ExecStart=/bin/sh -c '${passwordInput}/usr/local/bin/lightningd --conf=${CLCONF} ${encryptedHSMoption} --rpc-file-mode 0660 \$\$TUNNELSATS_CLN_ARGS'
ExecStartPost=-/home/admin/config.scripts/cl.check.sh poststart $CHAIN
EOF

# render <file> <line prefix> <CHAIN> <netprefix>: that template line of <file> as the installer's
# echo "..." writes it (bash double-quote expansion of ${CHAIN}, ${netprefix} and \$)
render() {
    local line
    line=$(grep -m 1 -F -e "$2" -- "$ROOT/$1") || return 1
    # the variables are read by the expansion inside eval
    # shellcheck disable=SC2034
    local CHAIN="$3" netprefix="$4"
    eval "printf '%s\n' \"${line}\""
}

# check_render <description> <rendered> <expected>
check_render() {
    CHECKED=$((CHECKED + 1))
    if [[ "$2" != "$3" ]]; then
        echo "FAIL render: $1"
        echo "  rendered: $2"
        echo "  expected: $3"
        FAILED=1
    fi
}

# lnd.install.sh writes for mainnet exactly the TunnelSats lines of assets/lnd.service
for prefix in "# TunnelSats start guard" "# (without internet.tunnelsats.sh" "Environment=TUNNELSATS_LND_ARGS=" \
    "EnvironmentFile=-/run/tunnelsats/" "ExecStartPre=+" "ExecStart=/usr/local/bin/lnd "; do
    check_render "lnd.install.sh mainnet: ${prefix}" "$(render home.admin/config.scripts/lnd.install.sh "$prefix" mainnet "")" \
        "$(grep -m 1 -F -e "$prefix" -- "$ROOT/home.admin/assets/lnd.service")"
done
# testnet and CLN: the guard runs for the unit's chain and writes that unit's env file
check_render "lnd.install.sh testnet guard line" "$(render home.admin/config.scripts/lnd.install.sh "ExecStartPre=+" testnet t)" \
    "ExecStartPre=+/bin/sh -c 'if [ -x /home/admin/config.scripts/internet.tunnelsats.sh ]; then exec /home/admin/config.scripts/internet.tunnelsats.sh guard lnd testnet; fi; echo tunnelsats-guard: internet.tunnelsats.sh is missing, Lightning starts Tor-only >&2; mkdir -p /run/tunnelsats && echo TUNNELSATS_LND_ARGS= > /run/tunnelsats/hybrid-tlnd.env'"
check_render "cl.install-service.sh mainnet guard line" "$(render home.admin/config.scripts/cl.install-service.sh "ExecStartPre=+" mainnet "")" \
    "ExecStartPre=+/bin/sh -c 'if [ -x /home/admin/config.scripts/internet.tunnelsats.sh ]; then exec /home/admin/config.scripts/internet.tunnelsats.sh guard cl mainnet; fi; echo tunnelsats-guard: internet.tunnelsats.sh is missing, Lightning starts Tor-only >&2; mkdir -p /run/tunnelsats && echo TUNNELSATS_CLN_ARGS= > /run/tunnelsats/hybrid-lightningd.env'"
echo "checked the rendered unit lines"

# 2.4: tor.network.sh off refuses before it changes anything
check_seq home.admin/config.scripts/tor.network.sh <<'EOF'
  0|off)
    if [ "${tunnelsats}" = "on" ]; then
      echo "err='tunnelsats active'"
    /home/admin/config.scripts/blitz.conf.sh set runBehindTor "off"
EOF

# 2.5: the SETTINGS checklist keeps Tor on while TunnelSats is active
check_seq home.admin/00settingsMenuBasics.sh <<'EOF'
choice="off"; check=$(echo "${CHOICES}" | grep -c "t")
if [ "${choice}" = "off" ] && [ "${runBehindTor}" = "on" ] && [ "${tunnelsats}" = "on" ]; then
  choice="on"
if [ "${runBehindTor}" != "${choice}" ]; then
EOF

if [[ "$FAILED" -ne 0 ]]; then
    echo "template lint: FAILED"
    exit 1
fi
echo "template lint: ok (${CHECKED} lines)"
