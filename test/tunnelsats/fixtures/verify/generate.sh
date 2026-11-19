#!/bin/bash
# Regenerates the verify documents in this directory with TunnelSats' own unprivileged test harness
# at the pinned commit: scripts/test_managed_dataplane.sh runs the production functions of
# tunnelsats.sh against a fixture tree with stateful stubs (ip, nft, systemctl, getent, wg, ...).
# Every *.json written here is the exact document the pinned tool's cmd_verify printed for that
# state with --no-probe; the derived documents (derived.sh) are one documented jq edit each.
#
# Usage: generate.sh <tunnelsats checkout at the pinned commit>
# The pin is read from home.admin/config.scripts/internet.tunnelsats.sh; a checkout whose
# scripts/tunnelsats.sh has another sha256 is refused.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../../../.." && pwd)"
SRC="$(cd "${1:?usage: generate.sh <tunnelsats checkout at the pinned commit>}" && pwd)"
ITS="${REPO}/home.admin/config.scripts/internet.tunnelsats.sh"

pin=$(sed -nE 's/^TS_PIN_SHA256="([0-9a-f]{64})"$/\1/p' "$ITS")
actual=$(sha256sum "${SRC}/scripts/tunnelsats.sh" | cut -d' ' -f1)
if [[ "$pin" != "$actual" ]]; then
    echo "scripts/tunnelsats.sh has sha256 ${actual}, the pin is ${pin}" >&2
    exit 1
fi

# The harness preamble (stubs, new_fixture, run_snippet) ends before its first test group
preamble=$(mktemp)
trap 'rm -f "$preamble"' EXIT
sed -n '1,/^echo "=== Running Managed Dataplane Tests ==="$/p' "${SRC}/scripts/test_managed_dataplane.sh" | sed '$d' > "$preamble"
# shellcheck source=/dev/null
source "$preamble"
# read by the harness' run_snippet
# shellcheck disable=SC2034
SCRIPT_UNDER_TEST="${SRC}/scripts/tunnelsats.sh"

WG_CONF_TEMPLATE='[Interface]
# Port Forwarding: 24556
PrivateKey = dHVubmVsc2F0cy10ZXN0LXByaXZhdGUta2V5LTAwMDE=
Address = 10.9.0.42/32
[Peer]
PublicKey = dHVubmVsc2F0cy10ZXN0LXNlcnZlci1rZXktMDAwMDE=
Endpoint = de2.tunnelsats.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25'

# wg stub: $1 = up (fresh handshake, live endpoint equals the resolved one), nohs (no handshake
# yet), none (no live endpoint yet), other (live endpoint differs), down (interface missing)
wg_state() {
    local hs="" ep=""
    case "$1" in
        up) hs='$(( $(date +%s) - 20 ))'; ep='1.2.3.4:51820' ;;
        nohs) hs='0'; ep='1.2.3.4:51820' ;;
        none) hs='0'; ep='(none)' ;;
        other) hs='$(( $(date +%s) - 20 ))'; ep='5.6.7.8:51820' ;;
        down) printf '#!/bin/bash\nexit 1\n' > "$STUB_BIN/wg"; chmod +x "$STUB_BIN/wg"; return 0 ;;
    esac
    cat > "$STUB_BIN/wg" <<EOF
#!/bin/bash
case "\$3" in
    latest-handshakes) echo "c2VydmVyLXB1YmxpYy1rZXktZm9yLXRlc3RzLTAwMDA9	${hs}" ;;
    endpoints) echo "c2VydmVyLXB1YmxpYy1rZXktZm9yLXRlc3RzLTAwMDA9	${ep}" ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$STUB_BIN/wg"
}

# A managed raspiblitz install for unit $3 (implementation $2), kill switch armed, tunnel up,
# Lightning in ExecStartPre (ActiveState activating). $1 = fixture name, $4 = inventory state.
managed_fixture() {
    local name="$1" impl="$2" unit="$3" state="${4:-installed}"
    fx=$(new_fixture "$name")
    mkdir -p "$fx/fs/etc/tunnelsats" "$fx/fs/sys/fs/cgroup/tunnelsats.slice/${unit}" "$fx/fs/proc/4242"
    run_snippet "$fx" "TS_M_INV_STATE=${state} TS_M_INV_PROFILE=raspiblitz TS_M_INV_IMPL=${impl} TS_M_INV_UNIT=${unit} TS_M_INV_USER=bitcoin TS_M_INV_UID=1001 TS_M_INV_BACKSTOP=0
TS_M_FILES=() TS_M_FILE_SHA=() TS_M_CREATED_DIRS=() TS_M_ENABLED_UNITS=()
ts_m_inventory_write"
    [[ "$SN_RC" -eq 0 ]] || { echo "inventory: $SN_OUT" >&2; exit 1; }
    run_snippet "$fx" "ts_m_killswitch_apply raspiblitz ${impl} ${unit} 1001 0 >/dev/null"
    [[ "$SN_RC" -eq 0 ]] || { echo "arm: $SN_OUT" >&2; exit 1; }
    printf '%s\n' "$WG_CONF_TEMPLATE" > "$fx/fs/etc/wireguard/tunnelsatsv2.conf"
    echo "1.2.3.4" > "$fx/state/resolve_de2.tunnelsats.com"
    echo "activating" > "$fx/state/unit_${unit}_ActiveState"
    echo "/tunnelsats.slice/${unit}" > "$fx/state/unit_${unit}_ControlGroup"
    echo "tunnelsats.slice" > "$fx/state/unit_${unit}_Slice"
    echo "/etc/systemd/system/${unit}.d/tunnelsats-managed.conf" > "$fx/state/unit_${unit}_DropInPaths"
    echo "4242" > "$fx/fs/sys/fs/cgroup/tunnelsats.slice/${unit}/cgroup.procs"
    echo "0::/tunnelsats.slice/${unit}" > "$fx/fs/proc/4242/cgroup"
    touch "$fx/state/link_tunnelsatsv2"
    printf 'default dev tunnelsatsv2 scope link \n' >> "$fx/state/routes4"
    wg_state up
}

tunnel_down() {
    rm -f "$fx/state/link_tunnelsatsv2"
    sed -i '/tunnelsatsv2/d' "$fx/state/routes4"
    wg_state down
}

# Writes the document cmd_verify --json --no-probe prints for the current fixture to $1.json and
# checks that its exit code is $2. $3 (optional) is run before cmd_verify in the same snippet.
gen() {
    local out="${HERE}/$1.json" want="$2" pre="${3:-}" doc
    run_snippet "$fx" "WG_BIN='${STUB_BIN}/wg'; ${pre} TS_JSON=1; TS_COMMAND=verify; TS_OUT_FD=1; TS_OPT_NO_PROBE=1; cmd_verify"
    doc=$(printf '%s\n' "$SN_OUT" | grep '^{"contract"' || true)
    if [[ "$SN_RC" -ne "$want" ]] || [[ -z "$doc" ]]; then
        echo "$1: exit ${SN_RC} (want ${want})" >&2
        printf '%s\n' "$SN_OUT" >&2
        exit 1
    fi
    printf '%s\n' "$doc" > "$out"
    echo "wrote $1.json (exit ${SN_RC})"
}

# getent whose host lookups get no answer (a silent name server); everything else as the stub
cat > "${TMP_ROOT}/getent-silent" <<EOF
#!/bin/bash
if [[ "\$1" == "ahostsv4" ]]; then sleep 20; fi
exec "${STUB_BIN}/getent" "\$@"
EOF
chmod +x "${TMP_ROOT}/getent-silent"
# verify bounds the endpoint lookup (5 s by default); 1 s keeps the generation short
silent_dns="GETENT_BIN='${TMP_ROOT}/getent-silent'; export TS_VERIFY_RESOLVE_TIMEOUT=1;"

for impl in lnd cln; do
    if [[ "$impl" == lnd ]]; then unit="lnd.service"; p=""; else unit="lightningd.service"; p="cln_"; fi

    managed_fixture "${p}up" "$impl" "$unit"
    gen "${p}activating_tunnel_up" 5
    echo "active" > "$fx/state/unit_${unit}_ActiveState"
    gen "${p}protected" 0

    managed_fixture "${p}nohs" "$impl" "$unit"
    wg_state nohs
    gen "${p}activating_no_handshake" 5
    wg_state none
    gen "${p}activating_endpoint_none" 5

    managed_fixture "${p}down" "$impl" "$unit"
    tunnel_down
    gen "${p}activating_tunnel_down" 5

    managed_fixture "${p}dns" "$impl" "$unit"
    rm -f "$fx/state/resolve_de2.tunnelsats.com"
    gen "${p}activating_dns_unresolved" 5

    # The name server does not answer: the lookup is cut off and reported as such (ipv4 null)
    managed_fixture "${p}dnstimeout" "$impl" "$unit"
    gen "${p}activating_dns_timeout" 5 "$silent_dns"

    managed_fixture "${p}mismatch" "$impl" "$unit"
    wg_state other
    gen "${p}activating_endpoint_mismatch" 5

    # Kill switch table gone, emergency block in effect for the Lightning uid (Q3)
    managed_fixture "${p}emergency" "$impl" "$unit"
    run_snippet "$fx" 'ts_m_emergency_arm 1001 >/dev/null'
    rm -f "$fx/state/nft_table"
    gen "${p}activating_emergency_block" 5
done

# LND only: the remaining states of the guard matrix
managed_fixture route lnd lnd.service
sed -i '/tunnelsatsv2/d' "$fx/state/routes4"
gen activating_route_missing 5

# Emergency rules left beside an armed kill switch (only the IPv6 blackhole is left): degraded,
# emergency_block false, the kill switch holds
managed_fixture leftover lnd lnd.service
run_snippet "$fx" 'ts_m_emergency_arm 1001 >/dev/null'
sed -i '/^2181[789]:.*1001-1001/d' "$fx/state/rules4"
sed -i '/^21817:.*1001-1001/d' "$fx/state/rules6"
gen activating_emergency_leftover 5

managed_fixture dropin lnd lnd.service
echo "/lib/systemd/system/lnd.service.d/other.conf" > "$fx/state/unit_lnd.service_DropInPaths"
gen dropin_missing 4

managed_fixture removing lnd lnd.service removing
gen state_removing 4

managed_fixture tlnd lnd tlnd.service
gen unit_tlnd 5

managed_fixture noport lnd lnd.service
sed -i '/^# Port Forwarding:/d' "$fx/fs/etc/wireguard/tunnelsatsv2.conf"
gen vpn_port_null 5

managed_fixture foreign lnd lnd.service
sed -i 's/de2\.tunnelsats\.com:51820/vpn.example.com:51820/' "$fx/fs/etc/wireguard/tunnelsatsv2.conf"
echo "1.2.3.4" > "$fx/state/resolve_vpn.example.com"
gen host_foreign 5

# Install record gone: the kill switch unit still carries the Lightning uid, the emergency block
# holds for it (unit null)
managed_fixture damaged lnd lnd.service
run_snippet "$fx" 'ts_m_emergency_arm 1001 >/dev/null'
rm -f "$fx/fs/etc/tunnelsats/managed.json"
echo "{ path=/usr/local/sbin/tunnelsats ; argv[]=/usr/local/sbin/tunnelsats managed-arm --fallback-uid 1001 ; ignore_errors=no }" \
    > "$fx/state/unit_tunnelsats-killswitch.service_ExecStart"
gen damaged_record 5

fx=$(new_fixture notinstalled)
gen not_installed 3

# A standard (legacy) install: route guard script and config of a v3 install after #204
fx=$(new_fixture legacy)
printf '%s\n' "$WG_CONF_TEMPLATE" > "$fx/fs/etc/wireguard/tunnelsatsv2.conf"
printf '#!/bin/bash\n' > "$fx/fs/etc/wireguard/tunnelsats-route-guard.sh"
wg_state up
gen unmanaged 9

"${HERE}/derived.sh"
