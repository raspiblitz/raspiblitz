#!/bin/bash
# Regenerates the detect documents in this directory with TunnelSats' own unprivileged harness at
# the pinned commit (see ../verify/README.md for the method). install_*.json and uninstall_*.json
# are written by hand with the exact field lists of cmd_install_managed and cmd_uninstall_managed
# at the pinned commit (README.md).
#
# Usage: generate.sh <tunnelsats checkout at the pinned commit>

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

preamble=$(mktemp)
trap 'rm -f "$preamble"' EXIT
sed -n '1,/^echo "=== Running Managed Dataplane Tests ==="$/p' "${SRC}/scripts/test_managed_dataplane.sh" | sed '$d' > "$preamble"
# shellcheck source=/dev/null
source "$preamble"
# read by the harness' run_snippet
# shellcheck disable=SC2034
SCRIPT_UNDER_TEST="${SRC}/scripts/tunnelsats.sh"

# Host-independent answers: the documents must not carry data of the machine that generated them
printf '#!/bin/bash\necho 6.12.25+rpt-rpi-v8\n' > "${STUB_BIN}/uname"
printf '#!/bin/bash\n[ "$1" = --version ] && echo "wireguard-tools v1.0.20210914 - https://git.zx2c4.com/wireguard-tools/"\nexit 0\n' > "${STUB_BIN}/wg"
chmod +x "${STUB_BIN}/uname" "${STUB_BIN}/wg"

WG_CONF='[Interface]
# Port Forwarding: 24556
PrivateKey = dHVubmVsc2F0cy10ZXN0LXByaXZhdGUta2V5LTAwMDE=
Address = 10.9.0.42/32
[Peer]
PublicKey = dHVubmVsc2F0cy10ZXN0LXNlcnZlci1rZXktMDAwMDE=
Endpoint = de2.tunnelsats.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25'

gen() {
    local doc
    run_snippet "$fx" "TS_JSON=1; TS_COMMAND=detect; TS_OUT_FD=1; cmd_detect"
    doc=$(printf '%s\n' "$SN_OUT" | grep '^{"contract"' || true)
    if [[ "$SN_RC" -ne 0 ]] || [[ -z "$doc" ]]; then
        echo "$1: exit ${SN_RC}" >&2
        printf '%s\n' "$SN_OUT" >&2
        exit 1
    fi
    printf '%s\n' "$doc" > "${HERE}/$1.json"
    echo "wrote $1.json"
}

fx=$(new_fixture detect-none)
gen detect_none

# A standard v3 install after #204: route guard script plus the tunnel config
fx=$(new_fixture detect-legacy)
printf '%s\n' "$WG_CONF" > "$fx/fs/etc/wireguard/tunnelsatsv2.conf"
printf '#!/bin/bash\n' > "$fx/fs/etc/wireguard/tunnelsats-route-guard.sh"
gen detect_legacy

# A managed install (inventory present)
fx=$(new_fixture detect-managed)
mkdir -p "$fx/fs/etc/tunnelsats"
run_snippet "$fx" 'TS_M_INV_STATE=installed TS_M_INV_PROFILE=raspiblitz TS_M_INV_IMPL=lnd TS_M_INV_UNIT=lnd.service TS_M_INV_USER=bitcoin TS_M_INV_UID=1001 TS_M_INV_BACKSTOP=0
TS_M_FILES=() TS_M_FILE_SHA=() TS_M_CREATED_DIRS=() TS_M_ENABLED_UNITS=()
ts_m_inventory_write'
printf '%s\n' "$WG_CONF" > "$fx/fs/etc/wireguard/tunnelsatsv2.conf"
gen detect_managed

# A managed install of CLN with the drop-in that puts lightningd.service into the slice
# (managed_ln_dropin present: REMOVE takes the managed unit from it)
fx=$(new_fixture detect-managed-cln)
mkdir -p "$fx/fs/etc/tunnelsats" "$fx/fs/etc/systemd/system/lightningd.service.d"
run_snippet "$fx" 'TS_M_INV_STATE=installed TS_M_INV_PROFILE=raspiblitz TS_M_INV_IMPL=cln TS_M_INV_UNIT=lightningd.service TS_M_INV_USER=bitcoin TS_M_INV_UID=1001 TS_M_INV_BACKSTOP=0
TS_M_FILES=() TS_M_FILE_SHA=() TS_M_CREATED_DIRS=() TS_M_ENABLED_UNITS=()
ts_m_inventory_write'
printf '[Service]\nSlice=tunnelsats.slice\n' > "$fx/fs/etc/systemd/system/lightningd.service.d/tunnelsats-managed.conf"
printf '%s\n' "$WG_CONF" > "$fx/fs/etc/wireguard/tunnelsatsv2.conf"
gen detect_managed_cln
